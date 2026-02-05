#!/bin/bash
# Post-installation script for Lyrah OS
set -e

echo "=== Lyrah OS Post-Installation ==="

# Enable required services
systemctl enable sddm
systemctl enable NetworkManager
systemctl enable lyrah-crash-monitor
systemctl enable lyrah-update.timer

# Create log directories
mkdir -p /var/log/lyrah/{luna-mode,desktop-mode}/{sessions,crashes}

# Set up first-boot flag
mkdir -p /var/lib/lyrah
systemctl enable lyrah-first-boot

echo "Post-installation complete."
