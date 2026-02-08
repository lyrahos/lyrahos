#!/bin/bash
# Detect the best GPU for Wayland compositing on hybrid GPU laptops.
#
# On systems with multiple GPUs (e.g. AMD iGPU + NVIDIA dGPU),
# kwin_wayland often can't auto-detect the right DRM device and
# falls back to llvmpipe (CPU software rendering at 90%+ CPU).
#
# This script finds the integrated GPU (amdgpu/i915/xe) which has
# full mesa OpenGL/Vulkan support and outputs its /dev/dri/cardN path.
# The NVIDIA dGPU can still be used for gaming via DRI_PRIME offloading.
#
# Usage:
#   export KWIN_DRM_DEVICES=$(detect-primary-gpu.sh)

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

# No AMD/Intel GPU found — fall back to first card
if [ -e /dev/dri/card0 ]; then
    echo "/dev/dri/card0"
fi
