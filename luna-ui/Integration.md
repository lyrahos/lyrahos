# Luna UI Controller Profile Integration Guide

This document explains how third-party installers, game clients, and games can read and utilize Luna's controller profile system to provide consistent controller mappings across the platform.

## Overview

Luna UI uses a layered controller profile system that maps physical controller inputs to semantic actions. Profiles are stored in an internal SQLite database and can be exported as JSON files for external consumption.

Exported profiles are written to:

```
~/.config/luna-ui/profiles/
```

Users can trigger an export from **Settings > Controller > Export All Profiles**, or profiles are exported automatically when modified.

## Exported File Structure

Each profile is a standalone JSON file. File naming follows this convention:

| Scope   | Filename Pattern                         | Example                        |
|---------|------------------------------------------|--------------------------------|
| Global  | `global.json`                            | `global.json`                  |
| Family  | `family_{controller_family}.json`        | `family_xbox.json`             |
| Client  | `client_{client_id}.json`                | `client_steam.json`            |
| Game    | `game_{client_id}_{game_id}.json`        | `game_steam_42.json`           |

## JSON Format

```json
{
  "version": 1,
  "name": "My Custom Profile",
  "scope": "game",
  "controller_family": "xbox",
  "client_id": "steam",
  "game_id": 42,
  "mappings": {
    "button_south": {
      "action": "confirm"
    },
    "button_east": {
      "action": "back"
    },
    "trigger_left": {
      "action": "filters",
      "parameters": {
        "deadzone": 8000,
        "threshold": 8000
      }
    }
  }
}
```

### Top-Level Fields

| Field               | Type    | Description                                                                 |
|---------------------|---------|-----------------------------------------------------------------------------|
| `version`           | int     | Schema version. Currently `1`.                                              |
| `name`              | string  | User-facing profile name.                                                   |
| `scope`             | string  | One of: `global`, `family`, `client`, `game`.                               |
| `controller_family` | string  | One of: `xbox`, `playstation`, `switch`, `luna`, `generic`, `any`.          |
| `client_id`         | string  | (Optional) Identifier for the game client. Present for `client` and `game` scopes. |
| `game_id`           | int     | (Optional) Luna's internal game ID. Present for `game` scope.               |

### Mapping Entries

The `mappings` object is keyed by **physical input name**. Each value contains:

| Field        | Type   | Description                                         |
|--------------|--------|-----------------------------------------------------|
| `action`     | string | The semantic action this input triggers.             |
| `parameters` | object | (Optional) Analog tuning parameters for the input.  |

## Physical Input Names

Luna uses **positional naming** rather than vendor-specific labels. This means `button_south` refers to the bottom face button regardless of whether it's labeled A (Xbox), X (PlayStation), or B (Switch).

### Buttons

| Physical Input      | Xbox  | PlayStation | Switch |
|---------------------|-------|-------------|--------|
| `button_south`      | A     | X (Cross)   | B      |
| `button_east`       | B     | O (Circle)  | A      |
| `button_west`       | X     | Square      | Y      |
| `button_north`      | Y     | Triangle    | X      |
| `button_start`      | Menu  | Options     | +      |
| `button_back`       | View  | Share       | -      |
| `button_guide`      | Xbox  | PS          | Home   |

### D-Pad

| Physical Input  |
|-----------------|
| `dpad_up`       |
| `dpad_down`     |
| `dpad_left`     |
| `dpad_right`    |

### Shoulders & Triggers

| Physical Input    | Xbox | PlayStation | Switch |
|-------------------|------|-------------|--------|
| `shoulder_left`   | LB   | L1          | L      |
| `shoulder_right`  | RB   | R1          | R      |
| `trigger_left`    | LT   | L2          | ZL     |
| `trigger_right`   | RT   | R2          | ZR     |

### Analog Sticks

| Physical Input       | Description                          |
|----------------------|--------------------------------------|
| `stick_left_up`      | Left stick pushed up                 |
| `stick_left_down`    | Left stick pushed down               |
| `stick_left_left`    | Left stick pushed left               |
| `stick_left_right`   | Left stick pushed right              |
| `stick_right_up`     | Right stick pushed up                |
| `stick_right_down`   | Right stick pushed down              |
| `stick_right_right`  | Right stick pushed right             |
| `stick_left_click`   | Left stick click (L3)                |
| `stick_right_click`  | Right stick click (R3)               |

### Raw Axis Names (for analog processing)

| Axis Name       | Description               |
|-----------------|---------------------------|
| `axis_leftx`    | Left stick horizontal     |
| `axis_lefty`    | Left stick vertical       |
| `axis_rightx`   | Right stick horizontal    |
| `axis_righty`   | Right stick vertical      |

## Action IDs

These are the semantic actions that Luna's UI understands:

| Action           | Description                    | Default Input      |
|------------------|--------------------------------|--------------------|
| `confirm`        | Confirm / Select               | `button_south`     |
| `back`           | Back / Cancel                  | `button_east`      |
| `quick_action`   | Quick Action menu              | `button_west`      |
| `search`         | Open search                    | `button_north`     |
| `settings`       | Open settings                  | `button_start`     |
| `system_menu`    | Open system menu               | `button_back`      |
| `navigate_up`    | Navigate up in lists/grids     | `dpad_up`          |
| `navigate_down`  | Navigate down in lists/grids   | `dpad_down`        |
| `navigate_left`  | Navigate left in lists/grids   | `dpad_left`        |
| `navigate_right` | Navigate right in lists/grids  | `dpad_right`       |
| `previous_tab`   | Switch to previous tab         | `shoulder_left`    |
| `next_tab`       | Switch to next tab             | `shoulder_right`   |
| `filters`        | Open filters panel             | `trigger_left`     |
| `sort`           | Open sort options              | `trigger_right`    |
| `scroll_up`      | Scroll content up              | `stick_right_up`   |
| `scroll_down`    | Scroll content down            | `stick_right_down` |

## Profile Cascade (Resolution Order)

When multiple profiles exist, Luna merges them in specificity order. More specific profiles override less specific ones on a per-input basis:

```
Global  →  Controller Family  →  Client  →  Game
(least specific)                      (most specific)
```

For example, if a user has:
- **Global**: `button_south` = `confirm`
- **Game profile for Game #42**: `button_south` = `back`

Then while playing Game #42, `button_south` will trigger `back`. All other inputs not overridden by the game profile will fall through to the global/family defaults.

Integrators should be aware of this cascade when reading profiles. To get the full resolved mapping for a specific game, you need to merge the applicable profiles yourself in the same order.

## Integration Scenarios

### 1. Game Client / Installer Reading User Preferences

If your installer or client wants to respect the user's Luna controller configuration:

```python
import json
import os

PROFILES_DIR = os.path.expanduser("~/.config/luna-ui/profiles")

def load_profile(filename):
    path = os.path.join(PROFILES_DIR, filename)
    if os.path.exists(path):
        with open(path) as f:
            return json.load(f)
    return None

def get_resolved_mappings(client_id=None, game_id=None, controller_family=None):
    """Build a merged mapping dict respecting Luna's cascade order."""
    merged = {}

    # Layer 1: Global
    profile = load_profile("global.json")
    if profile:
        merged.update(profile.get("mappings", {}))

    # Layer 2: Controller family
    if controller_family:
        profile = load_profile(f"family_{controller_family}.json")
        if profile:
            merged.update(profile.get("mappings", {}))

    # Layer 3: Client
    if client_id:
        profile = load_profile(f"client_{client_id}.json")
        if profile:
            merged.update(profile.get("mappings", {}))

    # Layer 4: Game
    if client_id and game_id:
        profile = load_profile(f"game_{client_id}_{game_id}.json")
        if profile:
            merged.update(profile.get("mappings", {}))

    return merged
```

### 2. Game Reading Controller Mappings at Launch

Games can read the exported profiles at startup to configure their own input system. A minimal C example:

```c
#include <stdio.h>
#include <json-c/json.h>  // or cJSON, jansson, etc.

// Read Luna's game-specific profile
const char *get_luna_action(const char *profile_path, const char *physical_input) {
    FILE *f = fopen(profile_path, "r");
    if (!f) return NULL;

    // Parse JSON, look up mappings[physical_input].action
    // ... standard JSON parsing ...

    fclose(f);
    return action;
}
```

### 3. Installer Creating a Client-Scoped Profile

If your installer wants to register a client-specific profile that Luna will pick up:

1. Write a JSON file following the format above to `~/.config/luna-ui/profiles/client_{your_client_id}.json`
2. Set `scope` to `"client"` and `client_id` to your identifier
3. Luna will detect and load the file on next profile reload

```json
{
  "version": 1,
  "name": "My Client Defaults",
  "scope": "client",
  "controller_family": "any",
  "client_id": "my_client",
  "mappings": {
    "button_north": {
      "action": "quick_action"
    },
    "button_west": {
      "action": "search"
    }
  }
}
```

**Note:** Only include the mappings you want to override. Unspecified inputs will fall through to the global and family defaults via the cascade.

### 4. Translating Luna's Positional Names to Your Input System

If your application uses vendor-specific button names (e.g., SDL's `SDL_CONTROLLER_BUTTON_A`), map them using the positional table:

```python
LUNA_TO_SDL = {
    "button_south":    "SDL_CONTROLLER_BUTTON_A",
    "button_east":     "SDL_CONTROLLER_BUTTON_B",
    "button_west":     "SDL_CONTROLLER_BUTTON_X",
    "button_north":    "SDL_CONTROLLER_BUTTON_Y",
    "dpad_up":         "SDL_CONTROLLER_BUTTON_DPAD_UP",
    "dpad_down":       "SDL_CONTROLLER_BUTTON_DPAD_DOWN",
    "dpad_left":       "SDL_CONTROLLER_BUTTON_DPAD_LEFT",
    "dpad_right":      "SDL_CONTROLLER_BUTTON_DPAD_RIGHT",
    "shoulder_left":   "SDL_CONTROLLER_BUTTON_LEFTSHOULDER",
    "shoulder_right":  "SDL_CONTROLLER_BUTTON_RIGHTSHOULDER",
    "button_start":    "SDL_CONTROLLER_BUTTON_START",
    "button_back":     "SDL_CONTROLLER_BUTTON_BACK",
    "button_guide":    "SDL_CONTROLLER_BUTTON_GUIDE",
    "stick_left_click": "SDL_CONTROLLER_BUTTON_LEFTSTICK",
    "stick_right_click": "SDL_CONTROLLER_BUTTON_RIGHTSTICK",
}
```

## Parameters

Analog inputs can have optional tuning parameters:

| Parameter   | Type  | Default | Description                                       |
|-------------|-------|---------|---------------------------------------------------|
| `deadzone`  | int   | 8000    | Minimum axis value before input is recognized (0-32767). |
| `threshold` | int   | 8000    | Trigger activation threshold (0-32767).           |
| `inverted`  | bool  | false   | Invert the axis direction.                        |

These values use SDL2's axis range (0 to 32767 for absolute value).

## Controller Family Detection

Luna automatically detects the connected controller's family using SDL2's `SDL_GameControllerGetType()` with a name-based fallback. The detected family determines which family-level profile is loaded.

Your application can determine the active family by reading the `controller_family` field from exported profiles, or by performing your own detection.

## Versioning

The `version` field in exported JSON is currently `1`. Future versions will maintain backward compatibility. If you encounter a version higher than what you support, you can still safely read the `mappings` object — new versions will only add fields, never change the meaning of existing ones.

## File Watching

If your application runs alongside Luna and you want to react to profile changes in real time, watch the `~/.config/luna-ui/profiles/` directory for file modifications using `inotify` (Linux), `FSEvents` (macOS), or equivalent.

## Summary

1. Profiles are exported to `~/.config/luna-ui/profiles/` as JSON files
2. Physical inputs use **positional names** (not vendor labels)
3. Profiles follow a 4-layer cascade: Global > Family > Client > Game
4. Only override what you need — the cascade handles the rest
5. The `version` field ensures forward compatibility
