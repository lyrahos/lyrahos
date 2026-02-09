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
#
# NOTE: We intentionally do NOT use "set -e" here. In a Calamares
# chroot, commands like findmnt, ls with globs, and grep can fail
# unexpectedly, causing silent script exits. Every error is handled
# manually so we always complete the critical steps.

echo "=== Lyrah OS Kernel Setup ==="

# --- Clean up stale Fedora EFI files ---
# The grub2-efi-x64 and shim-x64 RPMs install their binaries and a
# redirect grub.cfg into /boot/efi/EFI/fedora/ inside the rootfs.
# When Calamares unpacks the rootfs, those files land on the real ESP
# and the firmware auto-discovers them as a second "Fedora" boot entry
# with stale UUIDs. Remove them BEFORE the bootloader module runs
# grub2-install, which creates the correct Lyrah entry from scratch.
if [ -d /boot/efi/EFI/fedora ]; then
    rm -rf /boot/efi/EFI/fedora
    echo "Removed stale Fedora EFI directory from ESP"
fi

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
# ALWAYS regenerate the initramfs for the installed system.
#
# Critical: Use --no-hostonly to include ALL kernel modules. The Calamares
# chroot may not have full access to the target hardware (especially for
# disk controllers, filesystems, and RAID), so --hostonly could create an
# incomplete initramfs that fails to boot. --no-hostonly is larger but
# guarantees the system boots on any hardware configuration.
#
# The installed system does NOT need dmsquash-live (that's only for live
# ISO boot from squashfs). Standard dracut boot modules suffice.
echo "Generating initramfs with dracut (--no-hostonly for maximum compatibility)..."
dracut --force --no-hostonly --kver "$KVER" "$INITRAMFS_DST"
if [ ! -f "$INITRAMFS_DST" ]; then
    echo "FATAL: dracut failed to generate initramfs at $INITRAMFS_DST"
    exit 1
fi
echo "Generated initramfs at $INITRAMFS_DST (size: $(du -h "$INITRAMFS_DST" | cut -f1))"

# --- Detect btrfs subvolume on root filesystem ---
# When Calamares formats root as btrfs, it may create subvolumes (e.g., @).
# The kernel needs rootflags=subvol=<name> to mount the correct subvolume,
# and GRUB needs the subvolume path to find kernel files if /boot is on btrfs.
ROOT_FSTYPE=$(findmnt -no FSTYPE / 2>/dev/null || true)
BTRFS_SUBVOL=""
ROOTFLAGS_OPT=""
if [ "$ROOT_FSTYPE" = "btrfs" ]; then
    BTRFS_SUBVOL=$(findmnt -no OPTIONS / 2>/dev/null | tr ',' '\n' | grep '^subvol=' | head -1 | cut -d= -f2)
    if [ -n "$BTRFS_SUBVOL" ] && [ "$BTRFS_SUBVOL" != "/" ]; then
        echo "Detected btrfs root subvolume: $BTRFS_SUBVOL"
        ROOTFLAGS_OPT="rootflags=subvol=$BTRFS_SUBVOL"
    else
        echo "Root is btrfs (no named subvolume or default subvolume)"
    fi
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

# Clean up any Fedora BLS entries to prevent duplicate boot menu entries.
# This is necessary because the ISO may be built from a Fedora base, and
# we only want Lyrah OS entries in the boot menu.
FEDORA_ENTRIES=$(ls "$BLS_DIR"/*fedora* "$BLS_DIR"/*Fedora* 2>/dev/null || true)
if [ -n "$FEDORA_ENTRIES" ]; then
    echo "Removing Fedora BLS entries to prevent duplicate boot entries..."
    rm -f "$BLS_DIR"/*fedora* "$BLS_DIR"/*Fedora* 2>/dev/null || true
    echo "Cleaned up Fedora entries"
fi

# Check if a BLS entry already exists for this kernel
EXISTING_BLS=$(ls "$BLS_DIR"/*"$KVER"* 2>/dev/null | head -1)
if [ -n "$EXISTING_BLS" ]; then
    echo "BLS entry already exists: $EXISTING_BLS"
else
    BLS_ID="${MACHINE_ID:-lyrahos}-$KVER"
    BLS_FILE="$BLS_DIR/$BLS_ID.conf"

    PRETTY_NAME="Lyrah OS"

    # BLS entry kernel command line options MUST match /etc/default/grub
    # (which install-bootloader.sh creates with plymouth.enable=1).
    # Remove rhgb (Fedora-specific Red Hat Graphical Boot) and use
    # plymouth.enable=1 instead for Lyrah branding.
    cat > "$BLS_FILE" << EOF
title $PRETTY_NAME ($KVER)
version $KVER
linux /vmlinuz-$KVER
initrd /initramfs-$KVER.img
options root=UUID=@@ROOT_UUID@@ $ROOTFLAGS_OPT ro quiet splash plymouth.enable=1
grub_users \$grub_users
grub_arg --unrestricted
grub_class lyrah
EOF
    echo "Created BLS entry: $BLS_FILE"

    # Fill in the root UUID. Use fstab FIRST because findmnt in a
    # Calamares chroot reads /proc/mounts which shows the HOST's
    # mount table — returning the CI runner's UUID, not the target's.
    # Calamares's fstab module writes the correct UUID before this step.
    ROOT_UUID=""
    if [ -f /etc/fstab ]; then
        ROOT_UUID=$(awk '$2 == "/" && $1 ~ /^UUID=/ {sub(/UUID=/, "", $1); print $1}' /etc/fstab)
    fi
    if [ -z "$ROOT_UUID" ]; then
        ROOT_UUID=$(findmnt -no UUID / 2>/dev/null || true)
    fi
    if [ -n "$ROOT_UUID" ]; then
        sed -i "s/@@ROOT_UUID@@/$ROOT_UUID/" "$BLS_FILE"
        echo "Root UUID: $ROOT_UUID"
    else
        echo "WARNING: Could not determine root UUID — bootloader module will set it"
    fi
fi

# --- GRUB defaults for btrfs ---
# When root is btrfs, ensure /etc/default/grub includes rootflags so
# grub2-mkconfig embeds the correct kernel command line.
if [ -n "$ROOTFLAGS_OPT" ]; then
    mkdir -p /etc/default
    if [ ! -f /etc/default/grub ]; then
        touch /etc/default/grub
    fi
    if ! grep -q "rootflags=subvol" /etc/default/grub; then
        if grep -q '^GRUB_CMDLINE_LINUX=' /etc/default/grub; then
            sed -i "s|^GRUB_CMDLINE_LINUX=\"|GRUB_CMDLINE_LINUX=\"$ROOTFLAGS_OPT |" /etc/default/grub
        else
            echo "GRUB_CMDLINE_LINUX=\"$ROOTFLAGS_OPT\"" >> /etc/default/grub
        fi
        echo "Added $ROOTFLAGS_OPT to GRUB_CMDLINE_LINUX"
    fi
fi

# --- GRUB btrfs subvolume boot script ---
# grub2-mkconfig may fail to detect the btrfs subvolume inside the
# Calamares chroot, generating a grub.cfg that looks for /boot at the
# top-level btrfs volume instead of inside the subvolume.  Add a GRUB
# config snippet (runs early, before 10_linux) that explicitly sets
# the boot path with the subvolume prefix.
if [ -n "$BTRFS_SUBVOL" ]; then
    BOOT_FSTYPE=$(findmnt -no FSTYPE /boot 2>/dev/null || true)
    # Only needed when /boot lives on the btrfs root (no separate ext4 /boot)
    if [ "$BOOT_FSTYPE" != "ext4" ] && [ "$BOOT_FSTYPE" != "xfs" ]; then
        mkdir -p /etc/grub.d
        cat > /etc/grub.d/01_lyrah_btrfs << GRUBEOF
#!/bin/bash
# Lyrah OS: override GRUB boot path for btrfs subvolume.
# Without this, GRUB looks at the top-level btrfs volume and cannot
# find kernel files that live inside the subvolume.
cat << 'INNEREOF'
insmod btrfs
if [ -z "\$boot" ]; then
  set boot=(\$root)${BTRFS_SUBVOL}/boot
fi
INNEREOF
GRUBEOF
        chmod +x /etc/grub.d/01_lyrah_btrfs
        echo "Created /etc/grub.d/01_lyrah_btrfs for subvolume: $BTRFS_SUBVOL"
    fi
fi

echo "=== Kernel setup complete ==="
echo "Contents of /boot/:"
ls -lh /boot/vmlinuz-* /boot/initramfs-*.img 2>/dev/null || echo "(no kernel files found)"
echo ""
echo "BLS entries:"
ls -la "$BLS_DIR"/ 2>/dev/null || echo "(no BLS entries)"
if [ -f "$BLS_FILE" ]; then
    echo ""
    echo "Active BLS entry contents:"
    cat "$BLS_FILE"
fi
echo ""
echo "Kernel setup complete."
