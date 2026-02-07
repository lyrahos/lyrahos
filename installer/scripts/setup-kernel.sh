#!/bin/bash
# Set up kernel for booting on the installed system.
#
# The ISO build installs kernel-core with dnf --installroot, which
# places modules under /lib/modules/<version>/ but the kernel-install
# scriptlet often fails in that context. This leaves /boot/ without
# vmlinuz or initramfs, so grub2-mkconfig (run by Calamares's
# bootloader module) generates entries pointing to files that don't
# exist — causing "file not found" at boot.
#
# This script runs inside the Calamares chroot (target system) BEFORE
# the bootloader module to ensure /boot/ is properly populated.
set -e

echo "=== Lyrah OS Kernel Setup ==="

# Find the installed kernel version
KVER=$(ls /lib/modules/ 2>/dev/null | sort -V | tail -1)
if [ -z "$KVER" ]; then
    echo "FATAL: No kernel modules found in /lib/modules/"
    exit 1
fi
echo "Found kernel version: $KVER"

VMLINUZ_SRC="/lib/modules/$KVER/vmlinuz"
VMLINUZ_DST="/boot/vmlinuz-$KVER"
INITRAMFS_DST="/boot/initramfs-$KVER.img"

# --- vmlinuz ---
if [ -f "$VMLINUZ_DST" ]; then
    echo "vmlinuz already present at $VMLINUZ_DST"
else
    if [ -f "$VMLINUZ_SRC" ]; then
        cp "$VMLINUZ_SRC" "$VMLINUZ_DST"
        echo "Copied vmlinuz to $VMLINUZ_DST"
    else
        echo "FATAL: vmlinuz not found at $VMLINUZ_SRC"
        ls -la /lib/modules/"$KVER"/ 2>/dev/null || true
        exit 1
    fi
fi

# --- initramfs ---
if [ -f "$INITRAMFS_DST" ]; then
    echo "initramfs already present at $INITRAMFS_DST"
else
    echo "Generating initramfs with dracut..."
    dracut --force --kver "$KVER" "$INITRAMFS_DST"
    echo "Generated initramfs at $INITRAMFS_DST"
fi

# --- BLS entry (Boot Loader Specification) ---
# Fedora's grub2-mkconfig uses BLS entries from /boot/loader/entries/.
# Without one, the GRUB menu will have no entry for this kernel.
MACHINE_ID=""
if [ -f /etc/machine-id ]; then
    MACHINE_ID=$(cat /etc/machine-id)
fi

BLS_DIR="/boot/loader/entries"
mkdir -p "$BLS_DIR"

# Check if a BLS entry already exists for this kernel
EXISTING_BLS=$(ls "$BLS_DIR"/*"$KVER"* 2>/dev/null | head -1)
if [ -n "$EXISTING_BLS" ]; then
    echo "BLS entry already exists: $EXISTING_BLS"
else
    BLS_ID="${MACHINE_ID:-lyrahos}-$KVER"
    BLS_FILE="$BLS_DIR/$BLS_ID.conf"

    PRETTY_NAME="Lyrah OS"

    cat > "$BLS_FILE" << EOF
title $PRETTY_NAME ($KVER)
version $KVER
linux /vmlinuz-$KVER
initrd /initramfs-$KVER.img
options root=UUID=@@ROOT_UUID@@ ro quiet rhgb
grub_users \$grub_users
grub_arg --unrestricted
grub_class lyrah
EOF
    echo "Created BLS entry: $BLS_FILE"

    # Fill in the root UUID. Try findmnt first, fall back to fstab
    # (which Calamares's fstab module generates before this step).
    ROOT_UUID=$(findmnt -no UUID / 2>/dev/null || true)
    if [ -z "$ROOT_UUID" ] && [ -f /etc/fstab ]; then
        ROOT_UUID=$(awk '$2 == "/" && $1 ~ /^UUID=/ {sub(/UUID=/, "", $1); print $1}' /etc/fstab)
    fi
    if [ -n "$ROOT_UUID" ]; then
        sed -i "s/@@ROOT_UUID@@/$ROOT_UUID/" "$BLS_FILE"
        echo "Root UUID: $ROOT_UUID"
    else
        echo "WARNING: Could not determine root UUID — bootloader module will set it"
    fi
fi

echo "Kernel setup complete. Contents of /boot/:"
ls -lh /boot/vmlinuz-* /boot/initramfs-*.img 2>/dev/null || echo "(no kernel files found)"
ls "$BLS_DIR"/ 2>/dev/null || echo "(no BLS entries)"
