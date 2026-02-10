#!/bin/bash
# Detect the best GPU for Wayland compositing on hybrid GPU laptops.
#
# On hybrid GPU systems, the internal display may be wired through
# EITHER GPU depending on the laptop model:
#   - Most ultrabooks: eDP on the iGPU (AMD/Intel)
#   - Many gaming laptops (ASUS ROG/TUF): eDP on the dGPU (NVIDIA)
#
# Strategy:
#   1. Find which DRM card has a physically connected display
#   2. Fall back to integrated GPU (amdgpu/i915/xe) if detection fails
#   3. Last resort: /dev/dri/card0
#
# The result is used as KWIN_DRM_DEVICES so kwin_wayland composites
# on the GPU that actually drives the screen.
#
# Usage:
#   export KWIN_DRM_DEVICES=$(detect-primary-gpu.sh)

# --- Strategy 1: Find the card with a connected display ---
for card in /dev/dri/card*; do
    cardname=$(basename "$card")
    for connector in /sys/class/drm/"$cardname"-*/status; do
        if [ -f "$connector" ] && [ "$(cat "$connector" 2>/dev/null)" = "connected" ]; then
            echo "$card"
            exit 0
        fi
    done
done

# --- Strategy 2: Prefer integrated GPU (best power efficiency) ---
for card in /dev/dri/card*; do
    cardname=$(basename "$card")
    drmdir="/sys/class/drm/$cardname/device/driver"
    if [ -L "$drmdir" ]; then
        drv=$(basename "$(readlink "$drmdir")")
        case "$drv" in
            amdgpu|i915|xe)
                echo "$card"
                exit 0
                ;;
        esac
    fi
done

# --- Strategy 3: Accept NVIDIA proprietary driver ---
# After first-boot installs nvidia drivers and blacklists nouveau,
# the nvidia module provides a proper DRM device for compositing.
for card in /dev/dri/card*; do
    cardname=$(basename "$card")
    drmdir="/sys/class/drm/$cardname/device/driver"
    if [ -L "$drmdir" ]; then
        drv=$(basename "$(readlink "$drmdir")")
        case "$drv" in
            nvidia)
                echo "$card"
                exit 0
                ;;
        esac
    fi
done

# --- Last resort: first card (works with simpledrm/nomodeset) ---
if [ -e /dev/dri/card0 ]; then
    echo "/dev/dri/card0"
fi
