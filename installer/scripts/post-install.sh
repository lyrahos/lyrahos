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

# Disable os-prober to prevent GRUB from detecting other operating systems
# (e.g., Fedora base system). We only want Lyrah OS entries in the boot menu.
if [ ! -f /etc/default/grub ]; then
    echo "WARN: /etc/default/grub not found, creating it"
    touch /etc/default/grub
fi

if ! grep -q "GRUB_DISABLE_OS_PROBER" /etc/default/grub; then
    echo "GRUB_DISABLE_OS_PROBER=true" >> /etc/default/grub
    echo "Disabled os-prober in GRUB configuration"

    # Regenerate GRUB config to apply the change
    if [ -f /boot/grub2/grub.cfg ]; then
        grub2-mkconfig -o /boot/grub2/grub.cfg 2>/dev/null || echo "WARN: Could not regenerate GRUB config"
        echo "Regenerated GRUB configuration"
    fi
else
    echo "os-prober already disabled in GRUB configuration"
fi

# Set up first-boot flag
mkdir -p /var/lib/lyrah
systemctl enable lyrah-first-boot

echo "Post-installation complete."
