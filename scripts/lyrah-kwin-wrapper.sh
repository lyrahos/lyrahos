#!/bin/bash
# Wrapper for kwin_wayland that detects the correct GPU before starting.
# Used by SDDM as CompositorCommand so the greeter doesn't fall back
# to llvmpipe on hybrid GPU laptops.
#
# If kwin crashes (e.g. bad DRM device, driver bug), retries once with
# software rendering so the login screen always appears.

PRIMARY_GPU=$(/usr/share/lyrah/setup/detect-primary-gpu.sh 2>/dev/null)
if [ -n "$PRIMARY_GPU" ]; then
    export KWIN_DRM_DEVICES="$PRIMARY_GPU"
fi

# Try hardware rendering first
kwin_wayland "$@"
EXIT_CODE=$?

# If kwin exited abnormally, retry with software rendering
if [ $EXIT_CODE -ne 0 ]; then
    echo "lyrah-kwin-wrapper: kwin_wayland exited $EXIT_CODE, retrying with software rendering" \
        >> /var/log/lyrah-kwin-wrapper.log 2>/dev/null
    unset KWIN_DRM_DEVICES
    export LIBGL_ALWAYS_SOFTWARE=1
    exec kwin_wayland "$@"
fi
