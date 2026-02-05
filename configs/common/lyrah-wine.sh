#!/bin/bash
# Lyrah OS Wine/DXVK environment variables
# Applied system-wide for all Windows games

# FIX #37: Don't force FPS HUD system-wide. Users can enable per-game
# with: DXVK_HUD=fps mangohud %command%
export DXVK_LOG_LEVEL=none             # Reduce Wine/DXVK logging noise
export VKD3D_CONFIG=dxr                # Enable DirectX Raytracing support
