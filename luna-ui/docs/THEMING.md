# Luna UI Theming Guide

## Theme Format

Themes are JSON files stored in:
- System: `/usr/share/luna-ui/themes/`
- User: `~/.config/luna-ui/themes/`

## Theme Structure

    {
      "name": "Theme Name",
      "version": "1.0",
      "description": "Theme description",
      "colors": {
        "background": "#hex",
        "surface": "#hex",
        "primary": "#hex",
        "secondary": "#hex",
        "accent": "#hex",
        "textPrimary": "#hex",
        "textSecondary": "#hex",
        "focus": "#hex",
        "hover": "#hex",
        "cardBackground": "#hex"
      },
      "layout": {
        "sidebarWidth": 220,
        "gridColumns": 4,
        "fontSize": { "small": 14, "medium": 16, "large": 24, "xlarge": 32 }
      },
      "effects": {
        "animations": true,
        "blur": true,
        "glow": true,
        "transitionSpeed": 200
      },
      "fonts": {
        "heading": "Exo 2",
        "body": "Inter",
        "ui": "Inter"
      }
    }

## Built-in Themes
- Nebula Dark (default)
- Space Purple
- Cyber Neon
- AMOLED Black
- Forest Green
- Sunset Orange
