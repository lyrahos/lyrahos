#!/bin/bash
# Lyrah OS First Boot Setup Script
# Runs once on first boot to configure the system
#
# NOTE: We intentionally do NOT use "set -e" here. Individual steps
# can fail (e.g. no network for dnf, Plymouth theme not installed yet)
# but the remaining steps must still run so the system is usable.

echo "=== Lyrah OS First Boot Setup ==="

# Run GPU detection and driver installation
if [ -f /usr/share/lyrah/setup/configure-gpu.sh ]; then
    echo "Running GPU configuration..."
    bash /usr/share/lyrah/setup/configure-gpu.sh || echo "WARNING: GPU configuration had errors (non-fatal)"
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
    if command -v grub2-mkconfig &>/dev/null && [ -f /boot/grub2/grub.cfg ]; then
        grub2-mkconfig -o /boot/grub2/grub.cfg 2>/dev/null || true
    fi
fi

# Set Plymouth theme
if command -v plymouth-set-default-theme &> /dev/null; then
    plymouth-set-default-theme lyrah || echo "WARNING: Could not set Plymouth theme (non-fatal)"
    dracut -f 2>/dev/null || true
fi

# Enable system services
systemctl enable lyrah-crash-monitor.service 2>/dev/null || true
systemctl enable lyrah-update.timer 2>/dev/null || true

# Create log directories
mkdir -p /var/log/lyrah/{luna-mode,desktop-mode}/{sessions,crashes}

# Set proper permissions on log directories
chmod -R 755 /var/log/lyrah

# Mark first boot as done
mkdir -p /var/lib/lyrah
touch /var/lib/lyrah/.first-boot-done

echo "=== First Boot Setup Complete ==="
