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

# Install Noto fonts for full Unicode/internationalization support.
# These are skipped during the ISO build (weak deps disabled to save
# CI disk space) but are needed for proper text rendering.
dnf install -y --setopt=install_weak_deps=False \
  google-noto-sans-fonts \
  google-noto-serif-fonts \
  google-noto-emoji-color-fonts 2>/dev/null || echo "WARN: Noto fonts install skipped (no network?)"

# Set up first-boot flag
mkdir -p /var/lib/lyrah
systemctl enable lyrah-first-boot

echo "Post-installation complete."
