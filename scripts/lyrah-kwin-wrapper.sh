#!/bin/bash
# Wrapper for kwin_wayland that detects the correct GPU before starting.
# Used by SDDM as CompositorCommand so the greeter doesn't fall back
# to llvmpipe on hybrid GPU laptops.

PRIMARY_GPU=$(/usr/share/lyrah/setup/detect-primary-gpu.sh 2>/dev/null)
if [ -n "$PRIMARY_GPU" ]; then
    export KWIN_DRM_DEVICES="$PRIMARY_GPU"
fi

exec kwin_wayland "$@"
