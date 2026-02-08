#!/bin/bash
# /etc/profile.d/lyrah-gpu-env.sh
# On hybrid GPU laptops, tell kwin_wayland which DRM device to use
# for compositing. Without this, kwin can't auto-detect the right
# GPU and falls back to llvmpipe (CPU software rendering).

PRIMARY_GPU=$(/usr/share/lyrah/setup/detect-primary-gpu.sh 2>/dev/null)
if [ -n "$PRIMARY_GPU" ]; then
    export KWIN_DRM_DEVICES="$PRIMARY_GPU"
fi
