#!/bin/bash
# Lyrah OS First Boot Setup Script
# Runs once on first boot to configure the system
set -e

echo "=== Lyrah OS First Boot Setup ==="

# Run GPU detection and driver installation
if [ -f /usr/share/lyrah/setup/configure-gpu.sh ]; then
    echo "Running GPU configuration..."
    bash /usr/share/lyrah/setup/configure-gpu.sh
fi

# Set Plymouth theme
if command -v plymouth-set-default-theme &> /dev/null; then
    plymouth-set-default-theme lyrah
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
