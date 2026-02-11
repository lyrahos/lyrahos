#!/bin/bash
# Lyrah OS First Boot Setup Script
# Runs once on first boot to configure the system
#
# NOTE: We intentionally do NOT use "set -e" here. Individual steps
# can fail (e.g. no network for dnf, Plymouth theme not installed yet)
# but the remaining steps must still run so the system is usable.
#
# CRITICAL: This script blocks the graphical session (SDDM) from
# starting. Keep it fast — move slow operations (dracut, grub2-mkconfig)
# to a background task or defer to next boot.

LOG="/var/log/lyrah/first-boot.log"
mkdir -p /var/log/lyrah
exec > >(tee "$LOG") 2>&1

echo "=== Lyrah OS First Boot Setup ==="
echo "Started at: $(date)"

# Run GPU detection and driver configuration
# With pre-installed NVIDIA drivers, this just verifies the module
# is compiled for the running kernel — should be fast.
if [ -f /usr/share/lyrah/setup/configure-gpu.sh ]; then
    echo "Running GPU configuration..."
    timeout 60 bash /usr/share/lyrah/setup/configure-gpu.sh || echo "WARNING: GPU configuration had errors (non-fatal)"
fi

# Remove nomodeset from kernel command line.
# The installed system boots with nomodeset for a safe first boot
# (software rendering). Now that GPU drivers are configured, remove it
# so the next boot uses hardware-accelerated rendering.
if command -v grubby &>/dev/null; then
    echo "Removing nomodeset from kernel command line (GPU drivers now configured)..."
    grubby --update-kernel=ALL --remove-args="nomodeset" || echo "WARNING: grubby failed (non-fatal)"
fi
if [ -f /etc/default/grub ]; then
    sed -i 's/ nomodeset//' /etc/default/grub 2>/dev/null || true
fi

# Enable system services
systemctl enable lyrah-crash-monitor.service 2>/dev/null || true
systemctl enable lyrah-update.timer 2>/dev/null || true

# Create log directories
mkdir -p /var/log/lyrah/{luna-mode,desktop-mode}/{sessions,crashes}
chmod -R 755 /var/log/lyrah

# Mark first boot as done BEFORE slow tasks so we don't re-run on next boot
mkdir -p /var/lib/lyrah
touch /var/lib/lyrah/.first-boot-done

echo "=== First Boot Setup Complete ($(date)) ==="
echo "Slow tasks (dracut, grub2-mkconfig) will run in background..."

# Run slow tasks in background so they don't block SDDM from starting.
# These are important but not urgent — they improve the NEXT boot, not this one.
(
    echo "=== Background tasks starting ==="

    # Regenerate GRUB config (picks up nomodeset removal)
    if command -v grub2-mkconfig &>/dev/null && [ -f /boot/grub2/grub.cfg ]; then
        echo "Regenerating GRUB config..."
        grub2-mkconfig -o /boot/grub2/grub.cfg 2>/dev/null || true
    fi

    # Set Plymouth theme and rebuild initramfs
    if command -v plymouth-set-default-theme &>/dev/null; then
        echo "Setting Plymouth theme and rebuilding initramfs..."
        plymouth-set-default-theme lyrah 2>/dev/null || true
        dracut -f 2>/dev/null || true
    fi

    echo "=== Background tasks complete ($(date)) ==="
) >> "$LOG" 2>&1 &

exit 0
