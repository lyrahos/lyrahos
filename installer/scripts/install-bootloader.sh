#!/bin/bash
# Install GRUB bootloader for UEFI systems.
#
# Replaces Calamares's built-in bootloader module for reliability:
# the C++ module depends on efibootmgr writing NVRAM entries (often
# fails in chroot) and doesn't always create the fallback BOOTX64.EFI.
#
# This script runs inside the Calamares chroot (target system) and
# guarantees the SSD is bootable by:
#   1. Running grub2-install to create /EFI/lyrah/
#   2. Copying the signed shim+GRUB to /EFI/BOOT/BOOTX64.EFI (fallback)
#   3. Generating grub.cfg via grub2-mkconfig
#   4. Attempting efibootmgr NVRAM entry (non-fatal if it fails)
#   5. Verifying the ESP has bootable files
set -euo pipefail

echo "=== Lyrah OS Bootloader Installation ==="

ESP="/boot/efi"
GRUB_CFG="/boot/grub2/grub.cfg"
BOOTLOADER_ID="lyrah"

# ---------------------------------------------------------------
# Step 0: Verify ESP is mounted and writable
# ---------------------------------------------------------------
if ! mountpoint -q "$ESP" 2>/dev/null; then
    # ESP might not be a separate mountpoint if Calamares merged it
    if [ ! -d "$ESP" ]; then
        echo "FATAL: ESP directory $ESP does not exist"
        exit 1
    fi
    echo "WARN: $ESP is not a separate mount — proceeding anyway"
fi

mkdir -p "$ESP/EFI/$BOOTLOADER_ID"
mkdir -p "$ESP/EFI/BOOT"

echo "ESP mounted at $ESP"
echo "ESP contents before installation:"
ls -laR "$ESP/EFI/" 2>/dev/null || echo "  (empty)"

# ---------------------------------------------------------------
# Step 1: Run grub2-install (best effort)
# ---------------------------------------------------------------
# grub2-install creates the GRUB EFI binary and a redirect grub.cfg
# in /EFI/<bootloader-id>/. It also tries efibootmgr internally.
GRUB_INSTALL_OK=false
if command -v grub2-install &>/dev/null; then
    echo "Running grub2-install..."
    if grub2-install \
        --target=x86_64-efi \
        --efi-directory="$ESP" \
        --bootloader-id="$BOOTLOADER_ID" \
        --no-nvram 2>&1; then
        echo "grub2-install succeeded"
        GRUB_INSTALL_OK=true
    else
        echo "WARN: grub2-install failed (exit $?) — will use RPM-installed GRUB"
    fi
else
    echo "WARN: grub2-install not found — will use RPM-installed GRUB"
fi

# ---------------------------------------------------------------
# Step 2: If grub2-install failed, copy RPM-installed GRUB files
# ---------------------------------------------------------------
# The grub2-efi-x64 and shim-x64 packages install signed EFI binaries.
# These are better than grub2-install's unsigned output for Secure Boot.
if [ "$GRUB_INSTALL_OK" = "false" ] || [ ! -f "$ESP/EFI/$BOOTLOADER_ID/grubx64.efi" ]; then
    echo "Copying RPM-installed EFI binaries to ESP..."

    # Find signed GRUB and shim binaries — check our saved copies first,
    # then RPM default locations, then the ESP itself
    for src_dir in /usr/share/lyrah/efi-binaries \
                   /boot/efi/EFI/fedora \
                   /boot/efi/EFI/lyrah; do
        if [ -f "$src_dir/grubx64.efi" ]; then
            cp -f "$src_dir/grubx64.efi" "$ESP/EFI/$BOOTLOADER_ID/"
            echo "  Copied grubx64.efi from $src_dir"
            [ -f "$src_dir/shimx64.efi" ] && cp -f "$src_dir/shimx64.efi" "$ESP/EFI/$BOOTLOADER_ID/"
            [ -f "$src_dir/shimx64-fedora.efi" ] && cp -f "$src_dir/shimx64-fedora.efi" "$ESP/EFI/$BOOTLOADER_ID/"
            break
        fi
    done

    # If still no grubx64.efi, search more broadly
    if [ ! -f "$ESP/EFI/$BOOTLOADER_ID/grubx64.efi" ]; then
        GRUB_BIN=$(find /usr/share/lyrah/efi-binaries /usr/lib/grub /boot -name "grubx64.efi" 2>/dev/null | head -1)
        if [ -n "$GRUB_BIN" ]; then
            cp -f "$GRUB_BIN" "$ESP/EFI/$BOOTLOADER_ID/"
            echo "  Copied grubx64.efi from $GRUB_BIN"
        else
            echo "FATAL: Cannot find grubx64.efi anywhere"
            exit 1
        fi
    fi
fi

# ---------------------------------------------------------------
# Step 3: Create redirect grub.cfg on the ESP
# ---------------------------------------------------------------
# The GRUB binary on the ESP needs a grub.cfg that tells it where
# to find the REAL grub.cfg on the root partition. This is Fedora's
# standard redirect mechanism.
ROOT_UUID=$(findmnt -no UUID / 2>/dev/null || true)
if [ -z "$ROOT_UUID" ] && [ -f /etc/fstab ]; then
    ROOT_UUID=$(awk '$2 == "/" && $1 ~ /^UUID=/ {sub(/UUID=/, "", $1); print $1}' /etc/fstab)
fi

if [ -n "$ROOT_UUID" ]; then
    cat > "$ESP/EFI/$BOOTLOADER_ID/grub.cfg" << ESPGRUB
search --no-floppy --fs-uuid --set=dev $ROOT_UUID
set prefix=(\$dev)/boot/grub2
export prefix
configfile \$prefix/grub.cfg
ESPGRUB
    echo "Created redirect grub.cfg (root UUID: $ROOT_UUID)"
else
    echo "WARN: Could not determine root UUID for ESP grub.cfg"
fi

# ---------------------------------------------------------------
# Step 4: Install fallback bootloader at /EFI/BOOT/BOOTX64.EFI
# ---------------------------------------------------------------
# This is THE critical step. UEFI firmware ALWAYS checks this path
# when scanning for bootable devices. Without it, the drive may not
# appear in the firmware boot menu at all.
echo "Installing fallback bootloader..."

# Prefer shim (Secure Boot compatible), then GRUB directly
FALLBACK_SRC=""
for src in "$ESP/EFI/$BOOTLOADER_ID/shimx64.efi" \
           "$ESP/EFI/$BOOTLOADER_ID/grubx64.efi"; do
    if [ -f "$src" ]; then
        FALLBACK_SRC="$src"
        break
    fi
done

if [ -n "$FALLBACK_SRC" ]; then
    cp -f "$FALLBACK_SRC" "$ESP/EFI/BOOT/BOOTX64.EFI"
    echo "  Installed $FALLBACK_SRC → /EFI/BOOT/BOOTX64.EFI"
else
    echo "FATAL: No EFI binary found to install as fallback"
    exit 1
fi

# Copy the redirect grub.cfg to the fallback location too
if [ -f "$ESP/EFI/$BOOTLOADER_ID/grub.cfg" ]; then
    cp -f "$ESP/EFI/$BOOTLOADER_ID/grub.cfg" "$ESP/EFI/BOOT/grub.cfg"
    echo "  Copied redirect grub.cfg to /EFI/BOOT/"
fi

# If shim was installed as BOOTX64.EFI, also need grubx64.efi alongside it
# (shim loads grubx64.efi from the same directory)
if echo "$FALLBACK_SRC" | grep -q "shimx64"; then
    if [ -f "$ESP/EFI/$BOOTLOADER_ID/grubx64.efi" ]; then
        cp -f "$ESP/EFI/$BOOTLOADER_ID/grubx64.efi" "$ESP/EFI/BOOT/grubx64.efi"
        echo "  Copied grubx64.efi alongside shim in /EFI/BOOT/"
    fi
fi

# ---------------------------------------------------------------
# Step 5: Generate grub.cfg on the root partition
# ---------------------------------------------------------------
echo "Generating GRUB configuration..."

# Ensure /etc/default/grub exists with sane defaults
mkdir -p /etc/default
if [ ! -f /etc/default/grub ]; then
    cat > /etc/default/grub << 'GRUBDEFAULT'
GRUB_TIMEOUT=5
GRUB_DISTRIBUTOR="Lyrah OS"
GRUB_DEFAULT=saved
GRUB_DISABLE_SUBMENU=true
GRUB_TERMINAL_OUTPUT="console"
GRUB_CMDLINE_LINUX="quiet splash rhgb plymouth.enable=1"
GRUB_DISABLE_RECOVERY="true"
GRUB_DISABLE_OS_PROBER=true
GRUBDEFAULT
    echo "Created /etc/default/grub"
fi

# Run grub2-mkconfig to generate the actual boot menu
if command -v grub2-mkconfig &>/dev/null; then
    mkdir -p "$(dirname "$GRUB_CFG")"
    grub2-mkconfig -o "$GRUB_CFG" 2>&1 || echo "WARN: grub2-mkconfig failed"
    echo "Generated $GRUB_CFG"
else
    echo "WARN: grub2-mkconfig not found"
fi

# ---------------------------------------------------------------
# Step 6: Try to create UEFI NVRAM boot entry (best effort)
# ---------------------------------------------------------------
# efibootmgr writes to /sys/firmware/efi/efivars. This often fails
# inside a chroot (efivars may be read-only or not mounted). That's
# OK — the fallback BOOTX64.EFI ensures bootability regardless.
if command -v efibootmgr &>/dev/null && [ -d /sys/firmware/efi/efivars ]; then
    echo "Attempting to create UEFI NVRAM boot entry..."

    # Find the ESP disk and partition number
    ESP_DEV=$(findmnt -no SOURCE "$ESP" 2>/dev/null || true)
    if [ -n "$ESP_DEV" ]; then
        # Extract disk and partition: /dev/sda1 → disk=/dev/sda part=1
        DISK=$(echo "$ESP_DEV" | sed 's/[0-9]*$//')
        PART=$(echo "$ESP_DEV" | grep -o '[0-9]*$')

        if [ -n "$DISK" ] && [ -n "$PART" ]; then
            # Determine which EFI binary to register
            if [ -f "$ESP/EFI/$BOOTLOADER_ID/shimx64.efi" ]; then
                LOADER="\\EFI\\$BOOTLOADER_ID\\shimx64.efi"
            else
                LOADER="\\EFI\\$BOOTLOADER_ID\\grubx64.efi"
            fi

            efibootmgr --create \
                --disk "$DISK" \
                --part "$PART" \
                --label "Lyrah OS" \
                --loader "$LOADER" 2>&1 || echo "  WARN: efibootmgr failed (non-fatal — fallback BOOTX64.EFI is in place)"

            echo "  NVRAM entry creation attempted"
        fi
    else
        echo "  WARN: Could not determine ESP device — skipping NVRAM entry"
    fi
else
    echo "  Skipping NVRAM entry (efibootmgr not available or no efivars)"
fi

# ---------------------------------------------------------------
# Step 7: Verify ESP contents
# ---------------------------------------------------------------
echo ""
echo "=== ESP Verification ==="
echo "Contents of $ESP/EFI/:"
ls -laR "$ESP/EFI/" 2>/dev/null || echo "  (empty!)"

# Critical checks
PASS=true
if [ ! -f "$ESP/EFI/BOOT/BOOTX64.EFI" ]; then
    echo "FAIL: /EFI/BOOT/BOOTX64.EFI missing"
    PASS=false
fi
if [ ! -f "$ESP/EFI/$BOOTLOADER_ID/grubx64.efi" ]; then
    echo "FAIL: /EFI/$BOOTLOADER_ID/grubx64.efi missing"
    PASS=false
fi
if [ ! -f "$GRUB_CFG" ]; then
    echo "FAIL: $GRUB_CFG missing"
    PASS=false
fi

if [ "$PASS" = "true" ]; then
    echo "PASS: All bootloader files present"
else
    echo "WARN: Some bootloader files are missing — boot may fail"
fi

echo "=== Bootloader Installation Complete ==="
