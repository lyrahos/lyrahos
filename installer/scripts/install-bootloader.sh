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
#
# NOTE: We intentionally do NOT use "set -e" here. Every failure is
# handled manually so the script never exits silently. Instead we
# track errors and always attempt the fallback BOOTX64.EFI path.

set -uo pipefail

# ---------------------------------------------------------------
# Logging — write everything to a file AND stdout (for Calamares)
# ---------------------------------------------------------------
LOGFILE="/var/log/lyrah-bootloader-install.log"
exec > >(tee "$LOGFILE") 2>&1

echo "=== Lyrah OS Bootloader Installation ==="
echo "Date: $(date)"
echo "Running as: $(whoami)"
echo "Script: $0"
echo ""

ESP="/boot/efi"
GRUB_CFG="/boot/grub2/grub.cfg"
BOOTLOADER_ID="lyrah"
ERRORS=0

# ---------------------------------------------------------------
# Pre-flight diagnostics
# ---------------------------------------------------------------
echo "=== Pre-flight Diagnostics ==="

echo "--- Mount info ---"
mount | grep -E '(efi|boot|vfat|fat32)' || echo "  (no EFI/vfat mounts found)"
echo ""

echo "--- /boot/efi status ---"
if mountpoint -q "$ESP" 2>/dev/null; then
    echo "  $ESP is a mountpoint (GOOD)"
    findmnt "$ESP" 2>/dev/null || true
else
    echo "  $ESP is NOT a mountpoint (may be a problem)"
    if [ -d "$ESP" ]; then
        echo "  $ESP exists as a directory"
    else
        echo "  $ESP does not exist!"
    fi
fi
echo ""

echo "--- Block devices ---"
lsblk -o NAME,SIZE,FSTYPE,PARTTYPE,MOUNTPOINT 2>/dev/null || \
    lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINT 2>/dev/null || \
    echo "  (lsblk not available)"
echo ""

echo "--- Saved EFI binaries ---"
if [ -d /usr/share/lyrah/efi-binaries ]; then
    ls -la /usr/share/lyrah/efi-binaries/
else
    echo "  /usr/share/lyrah/efi-binaries/ does NOT exist!"
fi
echo ""

echo "--- GRUB tools ---"
echo "  grub2-install: $(command -v grub2-install 2>/dev/null || echo 'NOT FOUND')"
echo "  grub2-mkconfig: $(command -v grub2-mkconfig 2>/dev/null || echo 'NOT FOUND')"
echo "  efibootmgr: $(command -v efibootmgr 2>/dev/null || echo 'NOT FOUND')"
echo ""

echo "--- GRUB modules ---"
if [ -d /usr/lib/grub/x86_64-efi ]; then
    echo "  /usr/lib/grub/x86_64-efi/ exists ($(ls /usr/lib/grub/x86_64-efi/*.mod 2>/dev/null | wc -l) modules)"
else
    echo "  /usr/lib/grub/x86_64-efi/ does NOT exist!"
fi
echo ""

echo "--- Root filesystem ---"
echo "  Root UUID: $(findmnt -no UUID / 2>/dev/null || echo 'unknown')"
echo "  Root device: $(findmnt -no SOURCE / 2>/dev/null || echo 'unknown')"
echo "  fstab root: $(grep -E '^\S+\s+/\s' /etc/fstab 2>/dev/null || echo 'not found')"
echo ""

# ---------------------------------------------------------------
# Step 0: Verify ESP is mounted and writable
# ---------------------------------------------------------------
echo "=== Step 0: Verify ESP ==="
if ! mountpoint -q "$ESP" 2>/dev/null; then
    if [ ! -d "$ESP" ]; then
        echo "FATAL: ESP directory $ESP does not exist"
        echo "Cannot install bootloader without an ESP"
        exit 1
    fi
    echo "WARN: $ESP is not a separate mount — proceeding anyway"
fi

mkdir -p "$ESP/EFI/$BOOTLOADER_ID" || { echo "FATAL: Cannot create $ESP/EFI/$BOOTLOADER_ID"; exit 1; }
mkdir -p "$ESP/EFI/BOOT" || { echo "FATAL: Cannot create $ESP/EFI/BOOT"; exit 1; }

# Test write access
if touch "$ESP/.write-test" 2>/dev/null; then
    rm -f "$ESP/.write-test"
    echo "ESP is writable (GOOD)"
else
    echo "FATAL: ESP is not writable!"
    exit 1
fi

echo "ESP contents before installation:"
ls -laR "$ESP/EFI/" 2>/dev/null || echo "  (empty)"
echo ""

# ---------------------------------------------------------------
# Step 1: Run grub2-install (best effort)
# ---------------------------------------------------------------
echo "=== Step 1: grub2-install ==="
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
        ERRORS=$((ERRORS + 1))
    fi
else
    echo "WARN: grub2-install not found — will use RPM-installed GRUB"
    ERRORS=$((ERRORS + 1))
fi
echo ""

# ---------------------------------------------------------------
# Step 2: If grub2-install failed, copy RPM-installed GRUB files
# ---------------------------------------------------------------
echo "=== Step 2: Copy EFI binaries ==="
if [ "$GRUB_INSTALL_OK" = "false" ] || [ ! -f "$ESP/EFI/$BOOTLOADER_ID/grubx64.efi" ]; then
    echo "Copying RPM-installed EFI binaries to ESP..."

    # Find signed GRUB and shim binaries — check our saved copies first,
    # then RPM default locations, then the ESP itself
    FOUND_BINARIES=false
    for src_dir in /usr/share/lyrah/efi-binaries \
                   /boot/efi/EFI/fedora \
                   /boot/efi/EFI/lyrah; do
        echo "  Checking $src_dir for grubx64.efi..."
        if [ -f "$src_dir/grubx64.efi" ]; then
            cp -f "$src_dir/grubx64.efi" "$ESP/EFI/$BOOTLOADER_ID/"
            echo "  FOUND and copied grubx64.efi from $src_dir"
            [ -f "$src_dir/shimx64.efi" ] && cp -f "$src_dir/shimx64.efi" "$ESP/EFI/$BOOTLOADER_ID/" && echo "  Copied shimx64.efi"
            [ -f "$src_dir/shimx64-fedora.efi" ] && cp -f "$src_dir/shimx64-fedora.efi" "$ESP/EFI/$BOOTLOADER_ID/" && echo "  Copied shimx64-fedora.efi"
            FOUND_BINARIES=true
            break
        else
            echo "  Not found at $src_dir"
        fi
    done

    # If still no grubx64.efi, search more broadly
    if [ ! -f "$ESP/EFI/$BOOTLOADER_ID/grubx64.efi" ]; then
        echo "  Searching filesystem for grubx64.efi..."
        GRUB_BIN=$(find /usr/share/lyrah/efi-binaries /usr/lib/grub /boot -name "grubx64.efi" 2>/dev/null | head -1 || true)
        if [ -n "$GRUB_BIN" ]; then
            cp -f "$GRUB_BIN" "$ESP/EFI/$BOOTLOADER_ID/"
            echo "  Found and copied grubx64.efi from $GRUB_BIN"
        else
            echo "  WARN: Cannot find grubx64.efi anywhere on filesystem"
            ERRORS=$((ERRORS + 1))
        fi
    fi

    # Last resort: try to build grubx64.efi from modules using grub2-mkimage
    if [ ! -f "$ESP/EFI/$BOOTLOADER_ID/grubx64.efi" ]; then
        echo "  Attempting to build grubx64.efi with grub2-mkimage..."
        if command -v grub2-mkimage &>/dev/null && [ -d /usr/lib/grub/x86_64-efi ]; then
            grub2-mkimage \
                -o "$ESP/EFI/$BOOTLOADER_ID/grubx64.efi" \
                -p /EFI/$BOOTLOADER_ID \
                -O x86_64-efi \
                fat part_gpt part_msdos normal boot linux configfile \
                loopback chain efifwsetup efi_gop efi_uga ls search \
                search_label search_fs_uuid search_fs_file gfxterm \
                gfxterm_background gfxterm_menu test all_video loadenv \
                exfat ext2 btrfs 2>&1 && echo "  Built grubx64.efi successfully" || {
                echo "  WARN: grub2-mkimage failed"
                ERRORS=$((ERRORS + 1))
            }
        else
            echo "  grub2-mkimage not available or no GRUB modules"
            ERRORS=$((ERRORS + 1))
        fi
    fi
else
    echo "grub2-install succeeded and grubx64.efi exists — skipping binary copy"
fi

# Final check
if [ ! -f "$ESP/EFI/$BOOTLOADER_ID/grubx64.efi" ]; then
    echo "CRITICAL: Still no grubx64.efi after all attempts!"
    ERRORS=$((ERRORS + 1))
else
    echo "grubx64.efi is present at $ESP/EFI/$BOOTLOADER_ID/grubx64.efi"
    ls -la "$ESP/EFI/$BOOTLOADER_ID/grubx64.efi"
fi
echo ""

# ---------------------------------------------------------------
# Step 3: Create redirect grub.cfg on the ESP
# ---------------------------------------------------------------
echo "=== Step 3: Create ESP grub.cfg ==="
# Use fstab FIRST because findmnt in a Calamares chroot reads
# /proc/mounts which shows the HOST's mount table — returning
# the CI runner's UUID, not the target disk's UUID.
ROOT_UUID=""
if [ -f /etc/fstab ]; then
    ROOT_UUID=$(awk '$2 == "/" && $1 ~ /^UUID=/ {sub(/UUID=/, "", $1); print $1}' /etc/fstab)
fi
if [ -z "$ROOT_UUID" ]; then
    ROOT_UUID=$(findmnt -no UUID / 2>/dev/null || true)
fi

if [ -n "$ROOT_UUID" ]; then
    cat > "$ESP/EFI/$BOOTLOADER_ID/grub.cfg" << ESPGRUB
search --no-floppy --fs-uuid --set=dev $ROOT_UUID
set prefix=(\$dev)/boot/grub2
export prefix
configfile \$prefix/grub.cfg
ESPGRUB
    echo "Created redirect grub.cfg (root UUID: $ROOT_UUID)"
    echo "Contents:"
    cat "$ESP/EFI/$BOOTLOADER_ID/grub.cfg"
else
    echo "WARN: Could not determine root UUID for ESP grub.cfg"
    ERRORS=$((ERRORS + 1))
fi
echo ""

# ---------------------------------------------------------------
# Step 4: Install fallback bootloader at /EFI/BOOT/BOOTX64.EFI
# ---------------------------------------------------------------
echo "=== Step 4: Fallback BOOTX64.EFI ==="
# This is THE critical step. UEFI firmware ALWAYS checks this path
# when scanning for bootable devices. Without it, the drive may not
# appear in the firmware boot menu at all.

# Prefer shim (Secure Boot compatible), then GRUB directly
FALLBACK_SRC=""
for src in "$ESP/EFI/$BOOTLOADER_ID/shimx64.efi" \
           "$ESP/EFI/$BOOTLOADER_ID/grubx64.efi" \
           /usr/share/lyrah/efi-binaries/shimx64.efi \
           /usr/share/lyrah/efi-binaries/grubx64.efi; do
    if [ -f "$src" ]; then
        FALLBACK_SRC="$src"
        echo "Using $src as fallback BOOTX64.EFI source"
        break
    fi
done

if [ -n "$FALLBACK_SRC" ]; then
    cp -f "$FALLBACK_SRC" "$ESP/EFI/BOOT/BOOTX64.EFI"
    echo "Installed $FALLBACK_SRC -> /EFI/BOOT/BOOTX64.EFI"
    ls -la "$ESP/EFI/BOOT/BOOTX64.EFI"
else
    echo "CRITICAL: No EFI binary found to install as BOOTX64.EFI!"
    ERRORS=$((ERRORS + 1))
fi

# Copy the redirect grub.cfg to ALL potential prefix locations.
# Different grubx64.efi binaries have different compiled-in prefixes:
#   - grub2-install output: /EFI/lyrah/
#   - RPM-shipped (Fedora): /EFI/fedora/
#   - Fallback (same dir):  /EFI/BOOT/
# Without a grub.cfg at the binary's prefix, GRUB drops to command line.
if [ -f "$ESP/EFI/$BOOTLOADER_ID/grub.cfg" ]; then
    cp -f "$ESP/EFI/$BOOTLOADER_ID/grub.cfg" "$ESP/EFI/BOOT/grub.cfg"
    echo "Copied redirect grub.cfg to /EFI/BOOT/"

    # Also create at /EFI/fedora/ in case the RPM-shipped grubx64.efi
    # is used (its prefix is /EFI/fedora/, which setup-kernel.sh deletes)
    mkdir -p "$ESP/EFI/fedora"
    cp -f "$ESP/EFI/$BOOTLOADER_ID/grub.cfg" "$ESP/EFI/fedora/grub.cfg"
    echo "Copied redirect grub.cfg to /EFI/fedora/ (RPM prefix backup)"
fi

# If shim was installed as BOOTX64.EFI, also need grubx64.efi alongside it
# (shim loads grubx64.efi from the same directory)
if [ -n "$FALLBACK_SRC" ] && echo "$FALLBACK_SRC" | grep -q "shimx64"; then
    GRUB_FOR_SHIM=""
    for g in "$ESP/EFI/$BOOTLOADER_ID/grubx64.efi" /usr/share/lyrah/efi-binaries/grubx64.efi; do
        [ -f "$g" ] && GRUB_FOR_SHIM="$g" && break
    done
    if [ -n "$GRUB_FOR_SHIM" ]; then
        cp -f "$GRUB_FOR_SHIM" "$ESP/EFI/BOOT/grubx64.efi"
        echo "Copied grubx64.efi alongside shim in /EFI/BOOT/"
    fi
fi

# Create BOOTX64.CSV so the firmware shows "Lyrah OS" instead of "UEFI OS".
# The CSV file tells shim what name to register in the firmware boot menu.
# It MUST be in the same directory as BOOTX64.EFI (/EFI/BOOT/) to work.
cat > "$ESP/EFI/BOOT/BOOTX64.CSV" << 'CSVEOF'
shimx64.efi,Lyrah OS,,This is the boot entry for Lyrah OS
grubx64.efi,Lyrah OS,,This is the boot entry for Lyrah OS
CSVEOF
echo "Created BOOTX64.CSV in /EFI/BOOT/ for firmware boot entry naming"

# Also create it in the primary bootloader directory as a backup
cp "$ESP/EFI/BOOT/BOOTX64.CSV" "$ESP/EFI/$BOOTLOADER_ID/BOOTX64.CSV" 2>/dev/null || true
echo ""

# ---------------------------------------------------------------
# Step 5: Generate grub.cfg on the root partition
# ---------------------------------------------------------------
echo "=== Step 5: Generate grub.cfg ==="

# Ensure /etc/default/grub exists with sane defaults
# ALWAYS overwrite to ensure Lyrah-specific settings are applied
# (grub2-tools RPM may have created a default file)
mkdir -p /etc/default
cat > /etc/default/grub << 'GRUBDEFAULT'
GRUB_TIMEOUT=5
GRUB_DISTRIBUTOR="Lyrah OS"
GRUB_DEFAULT=saved
GRUB_DISABLE_SUBMENU=true
GRUB_TERMINAL_OUTPUT="console"
GRUB_CMDLINE_LINUX="quiet splash plymouth.enable=1 selinux=0"
GRUB_DISABLE_RECOVERY="true"
GRUB_DISABLE_OS_PROBER=true
GRUB_ENABLE_BLSCFG=true
GRUBDEFAULT
echo "Created /etc/default/grub with Lyrah OS settings"

# Run grub2-mkconfig to generate the actual boot menu
if command -v grub2-mkconfig &>/dev/null; then
    mkdir -p "$(dirname "$GRUB_CFG")"
    if grub2-mkconfig -o "$GRUB_CFG" 2>&1; then
        echo "Generated $GRUB_CFG"
    else
        echo "WARN: grub2-mkconfig failed"
        ERRORS=$((ERRORS + 1))
    fi
else
    echo "WARN: grub2-mkconfig not found"
    ERRORS=$((ERRORS + 1))
fi
echo ""

# ---------------------------------------------------------------
# Step 6: Try to create UEFI NVRAM boot entry (best effort)
# ---------------------------------------------------------------
echo "=== Step 6: NVRAM entry ==="
if command -v efibootmgr &>/dev/null && [ -d /sys/firmware/efi/efivars ]; then
    echo "Attempting to create UEFI NVRAM boot entry..."

    # Find the ESP disk and partition number
    ESP_DEV=$(findmnt -no SOURCE "$ESP" 2>/dev/null || true)
    if [ -n "$ESP_DEV" ]; then
        # Handle both SATA (/dev/sda1) and NVMe (/dev/nvme0n1p1)
        if echo "$ESP_DEV" | grep -q "nvme\|mmcblk"; then
            # NVMe/eMMC: /dev/nvme0n1p1 → disk=/dev/nvme0n1 part=1
            DISK=$(echo "$ESP_DEV" | sed 's/p[0-9]*$//')
            PART=$(echo "$ESP_DEV" | grep -o '[0-9]*$')
        else
            # SATA/USB: /dev/sda1 → disk=/dev/sda part=1
            DISK=$(echo "$ESP_DEV" | sed 's/[0-9]*$//')
            PART=$(echo "$ESP_DEV" | grep -o '[0-9]*$')
        fi

        echo "  ESP device: $ESP_DEV → disk=$DISK part=$PART"

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
                --loader "$LOADER" 2>&1 || echo "  WARN: efibootmgr failed (non-fatal)"

            echo "  NVRAM entry creation attempted"
        fi
    else
        echo "  WARN: Could not determine ESP device — skipping NVRAM entry"
    fi
else
    echo "  Skipping NVRAM entry (efibootmgr not available or no efivars)"
fi
echo ""

# ---------------------------------------------------------------
# Step 7: Verify ESP contents
# ---------------------------------------------------------------
echo "=== Step 7: Final Verification ==="
echo "Contents of $ESP/EFI/:"
ls -laR "$ESP/EFI/" 2>/dev/null || echo "  (empty!)"
echo ""

# Detailed checks
echo "--- Critical file checks ---"
PASS=true
for check_file in \
    "$ESP/EFI/BOOT/BOOTX64.EFI" \
    "$ESP/EFI/BOOT/grub.cfg" \
    "$ESP/EFI/$BOOTLOADER_ID/grubx64.efi" \
    "$ESP/EFI/$BOOTLOADER_ID/grub.cfg"; do
    if [ -f "$check_file" ]; then
        SIZE=$(stat -c%s "$check_file" 2>/dev/null || echo "?")
        echo "  OK: $check_file ($SIZE bytes)"
    else
        echo "  MISSING: $check_file"
        PASS=false
    fi
done

if [ -f "$GRUB_CFG" ]; then
    echo "  OK: $GRUB_CFG ($(stat -c%s "$GRUB_CFG" 2>/dev/null || echo '?') bytes)"
else
    echo "  MISSING: $GRUB_CFG"
    PASS=false
fi

echo ""
if [ "$PASS" = "true" ] && [ "$ERRORS" -eq 0 ]; then
    echo "RESULT: PASS — All bootloader files present, no errors"
elif [ "$PASS" = "true" ]; then
    echo "RESULT: PASS with $ERRORS warning(s) — All critical files present"
else
    echo "RESULT: FAIL — Some bootloader files are missing (see above)"
fi

echo ""
echo "Total errors/warnings: $ERRORS"
echo "Log saved to: $LOGFILE"
echo "=== Bootloader Installation Complete ==="
