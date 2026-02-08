#!/bin/bash
# Post-installation script for Lyrah OS
set -e

echo "=== Lyrah OS Post-Installation ==="

# --- Remove live-session artifacts ---
# The installer shortcut is placed in /etc/skel/Desktop/ for the live
# session so users can launch Calamares.  After installation it must
# not appear on the installed user's desktop.
rm -f /etc/skel/Desktop/install-lyrah.desktop
for desktop_dir in /home/*/Desktop; do
    rm -f "$desktop_dir/install-lyrah.desktop" 2>/dev/null || true
done
echo "Removed installer shortcut from desktop"

# Remove the live-session SDDM autologin (liveuser → installer).
# Calamares's users module creates the real user; configure-session.sh
# writes the correct autologin for the chosen session.
rm -f /etc/sddm.conf.d/live-autologin.conf 2>/dev/null || true

# Remove the liveuser account.  It was created for the live/installer
# session and must not appear in SDDM on the installed system.
if id liveuser &>/dev/null; then
    userdel -rf liveuser 2>/dev/null || true
    rm -f /etc/sudoers.d/liveuser 2>/dev/null || true
    echo "Removed liveuser account"
fi

# Disable KDE Plasma Welcome Center — it shows generic Fedora/KDE
# branding that does not apply to Lyrah OS.
mkdir -p /etc/xdg/autostart
cat > /etc/xdg/autostart/org.kde.plasma-welcome.desktop << WELCOMEEOF
[Desktop Entry]
Hidden=true
WELCOMEEOF
echo "Disabled Plasma Welcome Center"

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

# --- Ensure EFI fallback bootloader exists ---
# UEFI firmware looks for /EFI/BOOT/BOOTX64.EFI when no NVRAM boot entry
# matches. If efibootmgr failed inside the Calamares chroot (efivars not
# writable), this is the ONLY way the firmware can find the bootloader.
# Belt-and-suspenders: even if Calamares's installEFIFallback worked,
# this is a no-op since the file already exists.
if [ -d /boot/efi/EFI ]; then
    mkdir -p /boot/efi/EFI/BOOT

    # Prefer shim (Secure Boot), fall back to raw GRUB
    GRUB_SRC=""
    for src in /boot/efi/EFI/lyrah/shimx64.efi \
               /boot/efi/EFI/lyrah/grubx64.efi \
               /boot/efi/EFI/fedora/shimx64.efi \
               /boot/efi/EFI/fedora/grubx64.efi; do
        if [ -f "$src" ]; then
            GRUB_SRC="$src"
            break
        fi
    done

    if [ -n "$GRUB_SRC" ]; then
        cp -f "$GRUB_SRC" /boot/efi/EFI/BOOT/BOOTX64.EFI
        echo "Installed fallback bootloader: $GRUB_SRC → /EFI/BOOT/BOOTX64.EFI"
    else
        echo "WARN: No EFI bootloader found to copy to fallback path"
        ls -laR /boot/efi/EFI/ 2>/dev/null || true
    fi

    # Also ensure grub.cfg exists at the fallback location.
    # BOOTX64.EFI (shim or GRUB) looks for grub.cfg in its own directory
    # or in the default Fedora/RHEL path. Create a redirect that points
    # to the real grub.cfg.
    if [ ! -f /boot/efi/EFI/BOOT/grub.cfg ] && [ -f /boot/grub2/grub.cfg ]; then
        cat > /boot/efi/EFI/BOOT/grub.cfg << 'GRUBCFG'
search --no-floppy --fs-uuid --set=dev @@ROOT_UUID@@
set prefix=($dev)/boot/grub2
export $prefix
configfile $prefix/grub.cfg
GRUBCFG
        # Fill in the root UUID
        ROOT_UUID=$(findmnt -no UUID / 2>/dev/null || true)
        if [ -z "$ROOT_UUID" ] && [ -f /etc/fstab ]; then
            ROOT_UUID=$(awk '$2 == "/" && $1 ~ /^UUID=/ {sub(/UUID=/, "", $1); print $1}' /etc/fstab)
        fi
        if [ -n "$ROOT_UUID" ]; then
            sed -i "s/@@ROOT_UUID@@/$ROOT_UUID/" /boot/efi/EFI/BOOT/grub.cfg
            echo "Created fallback grub.cfg (root UUID: $ROOT_UUID)"
        else
            echo "WARN: Could not determine root UUID for fallback grub.cfg"
        fi
    fi
else
    echo "WARN: /boot/efi/EFI not found — EFI fallback not installed"
fi

# Set up first-boot flag
mkdir -p /var/lib/lyrah
systemctl enable lyrah-first-boot

echo "Post-installation complete."
