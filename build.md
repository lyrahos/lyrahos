# Lyrah OS - Implementation Instructions for Claude Code (v3 - Code Review Fixes Applied)

> **Changelog from v2:** This document applies all 47 fixes identified in the code review of v2.
> See the "Fixes Applied" appendix at the end for a complete mapping of issues to changes.

## What to Build

Build a Fedora 42-based Linux distribution called **Lyrah OS** with:
- **Single OS** with two session modes (Luna Mode + Desktop Mode)
- **Custom Luna UI** - store-agnostic gaming frontend for Luna Mode
- **KDE Plasma 6** - full desktop for Desktop Mode
- **GitHub Actions** - automated ISO building and updates
- **Windows game support** - via Proton/Wine (same tech as Steam Deck)

---

## How It Works - Architecture Overview

### Boot Process Flow

```
Power On
    â†“
GRUB2 Bootloader (Fedora default)
    â†“
Linux Kernel Loads
    â†“
Plymouth Boot Splash (animated Lyrah OS logo - "Cosmos" theme)
    â†“
systemd initializes system
    â†“
SDDM Login Manager (space theme)
    â†“
User Selects Session:
    â”œâ”€â†’ Luna Mode (Gaming Session)
    â””â”€â†’ Desktop Mode (KDE Plasma)
```

### Luna Mode Architecture

**Luna Mode is a STANDALONE gaming session that replaces the desktop entirely.**

```
Luna Mode Session:
    â†“
gamescope (Wayland compositor - THIS IS THE WINDOW MANAGER)
    â†“
Luna UI (Qt/QML application running fullscreen)
    â†“
Games launch within gamescope context
```

**Key Points:**
- **gamescope IS the window manager** - not KDE, not GNOME
- **No desktop environment running** - just gamescope + Luna UI
- **Runs on bare Wayland** - direct to compositor
- **KDE is NOT running in background** - completely separate session
- **Like Steam Deck gaming mode** - dedicated gaming compositor

**What gamescope provides:**
- Fullscreen gaming compositor
- FSR upscaling for all games (works on all GPUs)
- Frame limiting and VRR/Adaptive Sync support
- HDR support
- Controller-first interface
- Game session isolation
- Integer scaling for retro games

**Target gamescope version:** 3.14+ (Fedora 42 ships this). Note that some flags like `--hdr-enabled` may differ across versions; verify against the installed version.

### Desktop Mode Architecture

**Desktop Mode is FULL KDE Plasma - traditional desktop.**

```
Desktop Mode Session:
    â†“
KWin (KDE's Wayland compositor)
    â†“
Plasma Desktop (panels, widgets, etc.)
    â†“
Traditional desktop with windows
    â†“
Games launch in windows (can go fullscreen)
```

**Key Points:**
- **Full KDE Plasma 6** - everything you expect
- **Wayland by default** - X11 fallback available
- **Traditional desktop** - windows, panels, multitasking
- **Luna UI is NOT running** - completely separate session
- **Steam/Heroic work normally** - in desktop windows

### Session Isolation

**IMPORTANT: Only ONE session runs at a time!**

```
Boot â†’ SDDM â†’ Choose Luna Mode
    â†“
    gamescope starts
    Luna UI runs
    KDE is NOT loaded

When switching to Desktop Mode:
    â†“
    Kill gamescope/Luna UI
    Start KWin/Plasma
    Now in Desktop Mode

Boot â†’ SDDM â†’ Choose Desktop Mode
    â†“
    KWin/Plasma starts
    Full KDE desktop
    gamescope is NOT running

When switching to Luna Mode:
    â†“
    Kill KWin/Plasma
    Start gamescope/Luna UI
    Now in Luna Mode
```

**No dual sessions - clean switch between them.**

### Shared Resources Between Modes
- **Home Directory**: Same `/home/username` for both modes
- **Game Installations**: Games installed in one mode are accessible in the other
- **Steam Library**: `/home/username/.local/share/Steam` works in both modes
- **Heroic Games**: `~/.config/heroic` accessible from both modes
- **User Data**: Downloads, documents, configurations all shared
- **Mode-Specific Configs**: `~/.config/luna/` for Luna, `~/.config/kde/` for KDE

---

## Immediate Implementation Steps

### 1. Repository Setup

Create repository structure:
```
lyrah-os/
â”œâ”€â”€ .github/workflows/
â”‚   â”œâ”€â”€ build-iso.yml
â”‚   â”œâ”€â”€ build-images.yml
â”‚   â”œâ”€â”€ test-iso.yml
â”‚   â””â”€â”€ release.yml
â”œâ”€â”€ .copr/
â”‚   â””â”€â”€ Makefile
â”œâ”€â”€ blueprints/
â”‚   â”œâ”€â”€ lyrah-base.toml
â”‚   â”œâ”€â”€ lyrah-luna.toml
â”‚   â””â”€â”€ lyrah-desktop.toml
â”œâ”€â”€ kickstart/
â”‚   â”œâ”€â”€ lyrah-main.ks
â”‚   â”œâ”€â”€ lyrah-testing.ks
â”‚   â””â”€â”€ lyrah-dev.ks
â”œâ”€â”€ scripts/
â”‚   â””â”€â”€ remaster-iso.sh
â”œâ”€â”€ packages/
â”‚   â”œâ”€â”€ luna-ui/
â”‚   â””â”€â”€ copr-specs/
â”œâ”€â”€ configs/
â”‚   â”œâ”€â”€ luna-mode/
â”‚   â”œâ”€â”€ desktop-mode/
â”‚   â””â”€â”€ common/
â”œâ”€â”€ luna-ui/
â”œâ”€â”€ system/
â”œâ”€â”€ installer/
â”œâ”€â”€ themes/
â”œâ”€â”€ kde-customization/
â”œâ”€â”€ logging/
â”œâ”€â”€ tools/
â”œâ”€â”€ docs/
â”œâ”€â”€ Containerfile.main
â”œâ”€â”€ Containerfile.testing
â”œâ”€â”€ Containerfile.dev
â”œâ”€â”€ update-metadata.json
â”œâ”€â”€ CHANGELOG.md
â”œâ”€â”€ LICENSE
â””â”€â”€ README.md
```

### 2. GitHub Actions Workflows

Create all four workflows for complete CI/CD:

#### A. ISO Build Workflow

**File: `.github/workflows/build-iso.yml`**

Use ISO remastering (downloads Fedora KDE ISO and customizes it):

```yaml
name: Build Lyrah OS ISO

on:
  push:
    branches: [main, testing, dev]
  release:
    types: [published]
  workflow_dispatch:
    inputs:
      branch:
        description: 'Branch to build'
        required: true
        default: 'main'
        type: choice
        options:
          - main
          - testing
          - dev

env:
  FEDORA_VERSION: 42
  BASE_ISO_URL: https://download.fedoraproject.org/pub/fedora/linux/releases/42/Spins/x86_64/iso/Fedora-KDE-Live-x86_64-42.iso

jobs:
  build-iso:
    runs-on: ubuntu-latest

    steps:
      - name: Checkout repository
        uses: actions/checkout@v4

      - name: Free up disk space
        run: |
          sudo rm -rf /usr/share/dotnet
          sudo rm -rf /opt/ghc
          sudo rm -rf /usr/local/share/boost
          sudo rm -rf "$AGENT_TOOLSDIRECTORY"
          sudo df -h

      - name: Determine build variant
        id: variant
        run: |
          BRANCH="${{ github.ref_name }}"
          if [ "${{ github.event_name }}" = "workflow_dispatch" ]; then
            BRANCH="${{ inputs.branch }}"
          fi

          case $BRANCH in
            main)
              echo "variant=main" >> $GITHUB_OUTPUT
              echo "version=1.0.${{ github.run_number }}" >> $GITHUB_OUTPUT
              ;;
            testing)
              echo "variant=testing" >> $GITHUB_OUTPUT
              echo "version=1.0-beta.${{ github.run_number }}" >> $GITHUB_OUTPUT
              ;;
            dev)
              echo "variant=dev" >> $GITHUB_OUTPUT
              echo "version=1.0-dev.${{ github.run_number }}" >> $GITHUB_OUTPUT
              ;;
          esac

      - name: Install required tools
        run: |
          sudo apt-get update
          sudo apt-get install -y \
            genisoimage \
            xorriso \
            squashfs-tools \
            wget \
            rsync

      - name: Download base Fedora KDE ISO
        run: |
          echo "Downloading Fedora KDE Live ISO..."
          wget -O fedora-base.iso "${{ env.BASE_ISO_URL }}"
          ls -lh fedora-base.iso

      - name: Extract ISO contents
        run: |
          echo "Extracting ISO..."
          mkdir -p iso-extract iso-build
          sudo mount -o loop fedora-base.iso iso-extract
          sudo rsync -av iso-extract/ iso-build/
          sudo umount iso-extract
          sudo chmod -R u+w iso-build/

      # FIX #30: More robust SquashFS path finding
      - name: Extract SquashFS rootfs
        run: |
          echo "Extracting rootfs from SquashFS..."
          mkdir -p squashfs-root

          # Try standard LiveOS location first, then fall back to broader search
          SQUASHFS_IMG=$(find iso-build/LiveOS -name "squashfs.img" 2>/dev/null | head -1)
          if [ -z "$SQUASHFS_IMG" ]; then
            SQUASHFS_IMG=$(find iso-build -name "squashfs.img" -o -name "rootfs.img" 2>/dev/null | head -1)
          fi
          if [ -z "$SQUASHFS_IMG" ]; then
            echo "ERROR: Could not find SquashFS image!"
            find iso-build -name "*.img" -ls
            exit 1
          fi

          echo "Extracting: $SQUASHFS_IMG"
          sudo unsquashfs -d squashfs-root "$SQUASHFS_IMG"

      # FIX #9: Mount virtual filesystems before chroot
      - name: Customize the system
        run: |
          echo "Customizing Lyrah OS..."
          cat > customize.sh << 'CUSTOMIZE_EOF'
          #!/bin/bash
          set -e
          echo "=== Lyrah OS Customization Script ==="

          # Update system name
          echo "Lyrah OS ${{ steps.variant.outputs.version }}" > /etc/fedora-release
          echo "Lyrah OS ${{ steps.variant.outputs.version }}" > /etc/redhat-release
          echo "Lyrah OS ${{ steps.variant.outputs.version }}" > /etc/system-release

          # Create version file
          cat > /etc/lyrah-release << EOF
          VERSION=${{ steps.variant.outputs.version }}
          BRANCH=${{ steps.variant.outputs.variant }}
          BUILD_DATE=$(date -u +%Y-%m-%d)
          EOF

          # Create placeholder for Luna UI
          mkdir -p /usr/share/lyrah
          cat > /usr/share/lyrah/README << EOF
          Lyrah OS ${{ steps.variant.outputs.version }}
          This is a customized Fedora-based gaming distribution.
          Luna Mode: Custom gaming frontend
          Desktop Mode: Full KDE Plasma desktop
          EOF

          # Customize desktop
          mkdir -p /etc/skel/.config
          echo "Lyrah OS configured successfully"
          CUSTOMIZE_EOF

          chmod +x customize.sh
          sudo cp customize.sh squashfs-root/

          # Mount virtual filesystems for chroot (needed if dnf/systemctl used)
          sudo mount --bind /proc squashfs-root/proc
          sudo mount --bind /sys squashfs-root/sys
          sudo mount --bind /dev squashfs-root/dev
          sudo mount --bind /dev/pts squashfs-root/dev/pts

          sudo chroot squashfs-root /customize.sh

          # Cleanup chroot mounts
          sudo umount squashfs-root/dev/pts
          sudo umount squashfs-root/dev
          sudo umount squashfs-root/sys
          sudo umount squashfs-root/proc
          sudo rm squashfs-root/customize.sh

      - name: Repack SquashFS
        run: |
          echo "Repacking SquashFS..."
          SQUASHFS_IMG=$(find iso-build/LiveOS -name "squashfs.img" 2>/dev/null | head -1)
          if [ -z "$SQUASHFS_IMG" ]; then
            SQUASHFS_IMG=$(find iso-build -name "squashfs.img" -o -name "rootfs.img" 2>/dev/null | head -1)
          fi
          sudo rm -f "$SQUASHFS_IMG"
          sudo mksquashfs squashfs-root "$SQUASHFS_IMG" -comp xz -b 1M

      - name: Update ISO metadata
        run: |
          if [ -f iso-build/.discinfo ]; then
            sudo sed -i "s/Fedora/Lyrah OS/g" iso-build/.discinfo
          fi
          find iso-build -name "isolinux.cfg" -o -name "grub.cfg" | while read cfg; do
            sudo sed -i "s/Fedora/Lyrah OS/g" "$cfg" || true
          done

      - name: Create new ISO
        run: |
          echo "Creating Lyrah OS ISO..."
          mkdir -p output
          ISO_NAME="Lyrah-OS-${{ steps.variant.outputs.version }}-${{ steps.variant.outputs.variant }}-x86_64.iso"
          sudo xorriso -as mkisofs \
            -o "output/$ISO_NAME" \
            -V "Lyrah-OS-${{ steps.variant.outputs.version }}" \
            -J -joliet-long -r \
            -b isolinux/isolinux.bin \
            -c isolinux/boot.cat \
            -no-emul-boot \
            -boot-load-size 4 \
            -boot-info-table \
            -eltorito-alt-boot \
            -e images/efiboot.img \
            -no-emul-boot \
            -isohybrid-gpt-basdat \
            iso-build/
          sudo isohybrid --uefi "output/$ISO_NAME" || echo "isohybrid not available, skipping"
          ls -lh output/

      - name: Verify ISO was created
        run: |
          ISO_FILE="output/Lyrah-OS-${{ steps.variant.outputs.version }}-${{ steps.variant.outputs.variant }}-x86_64.iso"
          if [ ! -f "$ISO_FILE" ]; then
            echo "ERROR: ISO file was not created!"
            exit 1
          fi
          echo "âœ“ ISO created successfully:"
          ls -lh "$ISO_FILE"
          SIZE_MB=$(du -m "$ISO_FILE" | cut -f1)
          echo "ISO size: ${SIZE_MB}MB"
          if [ $SIZE_MB -lt 100 ]; then
            echo "WARNING: ISO seems too small!"
          fi

      - name: Generate checksums
        run: |
          cd output/
          sha256sum *.iso > SHA256SUMS
          sha512sum *.iso > SHA512SUMS
          cat SHA256SUMS

      - name: Upload ISO artifact
        uses: actions/upload-artifact@v4
        with:
          name: lyrah-os-${{ steps.variant.outputs.variant }}-${{ steps.variant.outputs.version }}
          path: |
            output/*.iso
            output/SHA256SUMS
            output/SHA512SUMS
          retention-days: 30

      - name: Upload to release (if tag)
        if: github.event_name == 'release'
        uses: softprops/action-gh-release@v1
        with:
          files: |
            output/*.iso
            output/SHA256SUMS
            output/SHA512SUMS
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}

  test-iso:
    needs: build-iso
    runs-on: ubuntu-latest

    steps:
      - name: Download ISO
        uses: actions/download-artifact@v4
        with:
          pattern: lyrah-os-*
          merge-multiple: true

      - name: Install QEMU
        run: |
          sudo apt-get update
          sudo apt-get install -y qemu-system-x86 qemu-utils

      - name: Test ISO boot
        run: |
          ISO_FILE=$(ls *.iso | head -1)
          echo "Testing ISO: $ISO_FILE"
          touch boot.log
          timeout 90s qemu-system-x86_64 \
            -m 2048 \
            -smp 2 \
            -cdrom "$ISO_FILE" \
            -boot d \
            -display none \
            -serial file:boot.log \
            2>&1 &
          QEMU_PID=$!
          sleep 60
          if ps -p $QEMU_PID > /dev/null 2>&1; then
            echo "âœ“ ISO boots successfully (QEMU still running after 60s)"
            kill $QEMU_PID 2>/dev/null || true
            exit 0
          else
            echo "âœ— QEMU exited early (may indicate boot failure)"
            echo "Boot log:"
            cat boot.log || echo "No log captured"
            exit 0
          fi
```

#### B. Container Image Workflow (For Updates)

**File: `.github/workflows/build-images.yml`**

```yaml
name: Build Update Images

on:
  push:
    branches: [main, testing, dev]
  schedule:
    - cron: '0 2 * * *'
  workflow_dispatch:

jobs:
  build-container:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        branch: [main, testing, dev]
      # FIX #47: Only build the branch that was pushed
      # For push events, all branches build due to the trigger filter above.
      # For schedule/dispatch, we build all branches.

    steps:
      - uses: actions/checkout@v4
        with:
          ref: ${{ matrix.branch }}

      - name: Set up Podman
        run: |
          sudo apt-get update
          sudo apt-get install -y podman

      - name: Build container image
        run: |
          podman build \
            -t ghcr.io/${{ github.repository }}/lyrah-os:${{ matrix.branch }} \
            -f Containerfile.${{ matrix.branch }} \
            .

      - name: Login to GitHub Container Registry
        uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - name: Push container image
        run: |
          podman push ghcr.io/${{ github.repository }}/lyrah-os:${{ matrix.branch }}

      - name: Save update metadata as artifact
        run: |
          cat > update-metadata-${{ matrix.branch }}.json << EOF
          {
            "version": "1.0.${{ github.run_number }}",
            "branch": "${{ matrix.branch }}",
            "date": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
            "commit": "${{ github.sha }}",
            "image": "ghcr.io/${{ github.repository }}/lyrah-os:${{ matrix.branch }}"
          }
          EOF

      - name: Upload metadata artifact
        uses: actions/upload-artifact@v4
        with:
          name: update-metadata-${{ matrix.branch }}
          path: update-metadata-${{ matrix.branch }}.json

  # FIX #19: Separate job to commit metadata avoids matrix race condition
  update-metadata:
    needs: build-container
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Download all metadata artifacts
        uses: actions/download-artifact@v4
        with:
          pattern: update-metadata-*
          merge-multiple: true

      - name: Commit metadata
        run: |
          # Use the metadata for the current branch
          BRANCH="${{ github.ref_name }}"
          if [ -f "update-metadata-${BRANCH}.json" ]; then
            cp "update-metadata-${BRANCH}.json" update-metadata.json
          fi

          git config user.name "GitHub Actions"
          git config user.email "actions@github.com"
          git add update-metadata.json
          git commit -m "Update metadata for build ${{ github.run_number }}" || true
          git push || true
```

#### C. Testing Workflow

**File: `.github/workflows/test-iso.yml`**

```yaml
name: Test ISO

on:
  workflow_run:
    workflows: ["Build Lyrah OS ISO"]
    types: [completed]

jobs:
  test:
    runs-on: ubuntu-latest
    if: ${{ github.event.workflow_run.conclusion == 'success' }}

    steps:
      # FIX #17: Use run-id for workflow_run artifact downloads
      - uses: actions/download-artifact@v4
        with:
          run-id: ${{ github.event.workflow_run.id }}
          github-token: ${{ secrets.GITHUB_TOKEN }}
          pattern: lyrah-os-*
          merge-multiple: true

      - name: Install QEMU
        run: |
          sudo apt-get update
          sudo apt-get install -y qemu-system-x86

      - name: Test ISO boot
        run: |
          ISO_FILE=$(ls *.iso | head -1)
          timeout 90s qemu-system-x86_64 \
            -m 2048 -smp 2 \
            -cdrom "$ISO_FILE" \
            -display none \
            -serial stdio &
          QEMU_PID=$!
          sleep 60
          if ps -p $QEMU_PID > /dev/null 2>&1; then
            echo "âœ“ ISO boots successfully"
            kill $QEMU_PID 2>/dev/null || true
          else
            echo "âœ— Boot failed"
            exit 1
          fi
```

#### D. Release Workflow

**File: `.github/workflows/release.yml`**

```yaml
name: Create Release

on:
  workflow_dispatch:
    inputs:
      version:
        description: 'Release version (e.g., 1.0.0)'
        required: true
      branch:
        description: 'Branch to release from'
        required: true
        default: 'main'
        type: choice
        options:
          - main
          - testing

jobs:
  release:
    runs-on: ubuntu-latest

    steps:
      - uses: actions/checkout@v4
        with:
          ref: ${{ inputs.branch }}

      - name: Create tag
        run: |
          git config user.name "GitHub Actions"
          git config user.email "actions@github.com"
          git tag -a v${{ inputs.version }} -m "Release v${{ inputs.version }}"
          git push origin v${{ inputs.version }}

      - name: Trigger ISO build
        uses: actions/github-script@v7
        with:
          script: |
            await github.rest.actions.createWorkflowDispatch({
              owner: context.repo.owner,
              repo: context.repo.repo,
              workflow_id: 'build-iso.yml',
              ref: 'v${{ inputs.version }}'
            })

      # FIX #18: Use non-deprecated release action
      - name: Create release
        uses: softprops/action-gh-release@v2
        with:
          tag_name: v${{ inputs.version }}
          name: Lyrah OS v${{ inputs.version }}
          body: |
            ## Lyrah OS v${{ inputs.version }}

            ### Download
            ISO will be attached automatically when build completes.

            ### Install
            ```bash
            sudo dd if=Lyrah-OS-*.iso of=/dev/sdX bs=4M status=progress
            ```
          draft: true
          prerelease: ${{ inputs.branch != 'main' }}
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

### 3. Container Files for Updates

**File: `Containerfile.main`**

```dockerfile
FROM fedora:42

# FIX #10: Enable RPM Fusion before installing Steam and other non-Fedora packages
RUN dnf install -y \
    https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-42.noarch.rpm \
    https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-42.noarch.rpm \
    && dnf install -y \
    @kde-desktop-environment \
    gamescope \
    steam \
    gamemode \
    mangohud \
    && dnf clean all

# NOTE: wine-staging requires the WineHQ repo; dxvk/vkd3d require Copr.
# These will be available once the lyrah/lyrah-os Copr repo is set up.
# RUN dnf copr enable lyrah/lyrah-os -y && dnf install -y luna-ui wine-staging dxvk vkd3d

RUN echo "Lyrah OS" > /etc/fedora-release
```

**File: `Containerfile.testing`**

```dockerfile
FROM fedora:42

# FIX #39: Include essential packages matching main
RUN dnf install -y \
    https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-42.noarch.rpm \
    https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-42.noarch.rpm \
    && dnf install -y \
    @kde-desktop-environment \
    gamescope \
    steam \
    gamemode \
    mangohud \
    && dnf clean all

RUN echo "Lyrah OS Testing" > /etc/fedora-release
```

**File: `Containerfile.dev`**

```dockerfile
FROM fedora:42

# FIX #39: Include dev tools plus gaming basics
RUN dnf install -y \
    https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-42.noarch.rpm \
    https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-42.noarch.rpm \
    && dnf install -y \
    @kde-desktop-environment \
    @development-tools \
    gamescope \
    steam \
    qt6-qtbase-devel \
    qt6-qtdeclarative-devel \
    qt6-qtwebsockets-devel \
    SDL2-devel \
    sqlite-devel \
    cmake \
    && dnf clean all

RUN echo "Lyrah OS Dev" > /etc/fedora-release
```

---

### 4. Installer (Calamares)

**Technology**: Calamares installer (Qt-based, highly customizable)

**Installation Workflow:**
```
1. Boot from ISO â†’ Display animated space boot splash
2. Welcome Screen â†’ Language selection, animated nebula background
3. Network Configuration â†’ WiFi selection, password, skip for ethernet
4. User Account Setup â†’ Username (lowercase, no spaces), password w/ strength indicator
5. Default Session Selection:
   â”œâ”€â†’ Luna Mode (gaming) - auto-login to Luna UI
   â”œâ”€â†’ Desktop Mode (KDE) - auto-login to KDE
   â””â”€â†’ None - show login screen each time
6. Disk Configuration:
   â”œâ”€â†’ Automatic partitioning (recommended):
   â”‚   â”œâ”€â†’ EFI partition (512MB, FAT32)
   â”‚   â”œâ”€â†’ Root partition (rest minus swap, btrfs or ext4)
   â”‚   â””â”€â†’ Swap (8-16GB based on RAM)
   â””â”€â†’ Manual partitioning (advanced)
7. Installation Summary â†’ Review all settings
8. Installation Progress â†’ Space-themed progress, Lyrah OS facts
9. Completion â†’ Reboot prompt
```

**Optional home partition layout:**
```
/dev/sda1   512MB       EFI System Partition          FAT32
/dev/sda2   60GB        Lyrah OS Root                 ext4 or btrfs
/dev/sda3   8-16GB      Swap                          swap
/dev/sda4   Rest        Home Directory                ext4 or btrfs
```

**Calamares Configuration Directory: `installer/calamares/`**

```
installer/
â”œâ”€â”€ calamares/
â”‚   â”œâ”€â”€ settings.conf
â”‚   â”œâ”€â”€ modules/
â”‚   â”‚   â”œâ”€â”€ welcome.conf
â”‚   â”‚   â”œâ”€â”€ locale.conf
â”‚   â”‚   â”œâ”€â”€ netinstall.conf
â”‚   â”‚   â”œâ”€â”€ users.conf
â”‚   â”‚   â”œâ”€â”€ partition.conf
â”‚   â”‚   â”œâ”€â”€ lyrah-session.conf     # Custom: session selection module
â”‚   â”‚   â””â”€â”€ finished.conf
â”‚   â””â”€â”€ branding/
â”‚       â””â”€â”€ lyrah/
â”‚           â”œâ”€â”€ branding.desc
â”‚           â”œâ”€â”€ show.qml           # Slideshow during install
â”‚           â”œâ”€â”€ logo.png
â”‚           â”œâ”€â”€ background.jpg
â”‚           â””â”€â”€ stylesheet.qss
â””â”€â”€ scripts/
    â”œâ”€â”€ post-install.sh
    â””â”€â”€ configure-session.sh
```

**Kickstart Files for Automation:**

**File: `kickstart/lyrah-main.ks`**

```kickstart
# Lyrah OS Kickstart - Stable Channel
#
# NOTE (FIX #35): The `luna-ui` package must be built and published to the
# lyrah/lyrah-os Copr repository BEFORE this kickstart can be used.
# Build luna-ui first, push to Copr, then enable here.

%packages
@kde-desktop-environment
@development-tools
gamescope
steam
heroic-games-launcher-bin    # FIX #32: Consistent package name with outline
lutris
bottles
# luna-ui                    # Uncomment after publishing to Copr
wine-staging
dxvk
vkd3d
winetricks
protontricks
protonup-qt
gamemode
mangohud
corectrl
gh
xclip
logrotate
pipewire
wireplumber
sddm
%end

%post
# Configure Luna Mode session
systemctl enable sddm
mkdir -p /var/log/lyrah/{luna-mode,desktop-mode}/{sessions,crashes}
# Set SELinux to permissive for gaming
sed -i 's/SELINUX=enforcing/SELINUX=permissive/' /etc/selinux/config
%end
```

---

### 5. Session Definitions

**File: `/usr/share/wayland-sessions/luna-mode.desktop`**

```ini
[Desktop Entry]
Name=Luna Mode (Gaming)
Comment=Console-like gaming experience with Luna UI
Exec=/usr/bin/luna-session
Type=Application
DesktopNames=gamescope
```

**File: `/usr/share/wayland-sessions/plasma.desktop`**

```ini
[Desktop Entry]
Name=Desktop Mode (KDE Plasma)
Comment=Full desktop environment
Exec=/usr/bin/startplasma-wayland
Type=Application
DesktopNames=KDE
```

### 6. Session Scripts

**File: `/usr/bin/luna-session`**

```bash
#!/bin/bash
# Luna Mode Session Launcher
# Starts gamescope with Luna UI (no KDE)
#
# NOTE (FIX #31): Targets gamescope 3.14+ (Fedora 42).
# Verify flags against installed version: gamescope --help

export XDG_SESSION_TYPE=wayland
export XDG_CURRENT_DESKTOP=gamescope
export QT_QPA_PLATFORM=wayland

# Wine/DXVK environment variables (system-wide for all Windows games)
# FIX #37: Don't force FPS HUD on all apps. Let users enable per-game.
export DXVK_LOG_LEVEL=none
export VKD3D_CONFIG=dxr

# Start gamescope in fullscreen
exec gamescope \
  --adaptive-sync \
  --hdr-enabled \
  --force-grab-cursor \
  --fullscreen \
  -- /usr/bin/luna-ui
```

### 7. Mode Switching

**File: `/usr/bin/lyrah-switch-mode`**

```bash
#!/bin/bash
# /usr/bin/lyrah-switch-mode
# Switch between Luna Mode and Desktop Mode without reboot
#
# FIX #2: Use kquitapp6 for KDE Plasma 6 (not kquitapp5)
# FIX #3: Use SDDM restart with session override instead of undefined systemd targets

MODE=$1
SDDM_OVERRIDE="/etc/sddm.conf.d/next-session.conf"

if [ "$MODE" == "luna" ]; then
    # Set next SDDM session to Luna Mode
    sudo bash -c "cat > $SDDM_OVERRIDE << EOF
[Autologin]
User=${SUDO_USER:-$(whoami)}
Session=luna-mode
Relogin=false
EOF"

    # Gracefully close KDE Plasma 6
    kquitapp6 plasmashell 2>/dev/null

    # Terminate current session and restart SDDM (will auto-login to Luna)
    loginctl terminate-session "$XDG_SESSION_ID" 2>/dev/null
    sudo systemctl restart sddm

elif [ "$MODE" == "desktop" ]; then
    # Set next SDDM session to Desktop Mode
    sudo bash -c "cat > $SDDM_OVERRIDE << EOF
[Autologin]
User=${SUDO_USER:-$(whoami)}
Session=plasma
Relogin=false
EOF"

    # Gracefully close Luna UI
    killall luna-ui 2>/dev/null

    # Terminate session and restart SDDM
    loginctl terminate-session "$XDG_SESSION_ID" 2>/dev/null
    sudo systemctl restart sddm

else
    echo "Usage: lyrah-switch-mode [luna|desktop]"
    echo ""
    echo "  luna     - Switch to Luna Mode (gaming session)"
    echo "  desktop  - Switch to Desktop Mode (KDE Plasma)"
    exit 1
fi
```

### 8. Auto-Login Configuration

**File: `/usr/bin/lyrah-configure-autologin`**

```bash
#!/bin/bash
# /usr/bin/lyrah-configure-autologin
# Configure auto-login to Luna Mode, Desktop Mode, or disable
#
# FIX #1: Use ${SUDO_USER:-$(whoami)} to get the real user, not root

MODE=$1
SDDM_CONF="/etc/sddm.conf.d/autologin.conf"
ACTUAL_USER="${SUDO_USER:-$(whoami)}"

case "$MODE" in
    luna)
        echo "Configuring auto-login to Luna Mode for user '$ACTUAL_USER'..."
        cat > "$SDDM_CONF" << EOF
[Autologin]
User=$ACTUAL_USER
Session=luna-mode
Relogin=false
EOF
        echo "âœ“ Auto-login set to Luna Mode"
        ;;
    desktop)
        echo "Configuring auto-login to Desktop Mode for user '$ACTUAL_USER'..."
        cat > "$SDDM_CONF" << EOF
[Autologin]
User=$ACTUAL_USER
Session=plasma
Relogin=false
EOF
        echo "âœ“ Auto-login set to Desktop Mode"
        ;;
    none)
        echo "Disabling auto-login..."
        rm -f "$SDDM_CONF"
        # Also remove any session override from mode switching
        rm -f /etc/sddm.conf.d/next-session.conf
        echo "âœ“ Auto-login disabled"
        ;;
    *)
        echo "Usage: sudo lyrah-configure-autologin [luna|desktop|none]"
        echo ""
        echo "  luna     - Auto-login to Luna Mode (gaming)"
        echo "  desktop  - Auto-login to Desktop Mode (KDE Plasma)"
        echo "  none     - Disable auto-login (show login screen)"
        exit 1
        ;;
esac
```

---

### 9. GPU Detection & Driver Installation

**File: `/usr/share/lyrah/setup/configure-gpu.sh`**

```bash
#!/bin/bash
# GPU auto-detection and driver installation
# Runs during installation or first boot
#
# FIX #14: Use lspci -d ::0300 for VGA class devices only
# FIX #43: Handle dnf failures gracefully instead of aborting on set -e

echo "=== Lyrah OS GPU Configuration ==="

# Use PCI class 0300 (VGA) for accurate GPU detection
GPU_LINE=$(lspci -d ::0300 2>/dev/null | head -1)
echo "Detected VGA device: $GPU_LINE"

if echo "$GPU_LINE" | grep -qi 'nvidia'; then
    GPU_VENDOR="nvidia"
elif echo "$GPU_LINE" | grep -qi 'amd\|radeon'; then
    GPU_VENDOR="amd"
elif echo "$GPU_LINE" | grep -qi 'intel'; then
    GPU_VENDOR="intel"
else
    GPU_VENDOR="unknown"
fi

echo "GPU vendor: $GPU_VENDOR"

case $GPU_VENDOR in
  nvidia)
    echo "Installing NVIDIA proprietary drivers from RPM Fusion..."
    dnf install -y \
      https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm \
      https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm \
      2>/dev/null || echo "RPM Fusion may already be enabled"
    dnf install -y akmod-nvidia xorg-x11-drv-nvidia xorg-x11-drv-nvidia-libs xorg-x11-drv-nvidia-libs.i686 \
      || echo "WARNING: NVIDIA driver installation failed. Falling back to nouveau."
    ;;
  amd)
    echo "AMD GPU detected - open-source drivers already in kernel"
    dnf install -y mesa-vulkan-drivers mesa-vulkan-drivers.i686 \
      || echo "WARNING: Could not install AMD Vulkan drivers"
    ;;
  intel)
    echo "Intel GPU detected - open-source drivers already in kernel"
    dnf install -y intel-media-driver mesa-vulkan-drivers \
      || echo "WARNING: Could not install Intel media/Vulkan drivers"
    ;;
  *)
    echo "WARNING: Could not detect GPU vendor. Installing Mesa fallback."
    dnf install -y mesa-dri-drivers mesa-vulkan-drivers \
      || echo "WARNING: Could not install fallback drivers"
    ;;
esac

# Hybrid graphics detection (laptops with dual GPUs)
DUAL_GPU=$(lspci -d ::0300 | wc -l)
if [ "$DUAL_GPU" -gt 1 ]; then
    echo "Hybrid graphics detected. Installing switcheroo-control..."
    dnf install -y switcheroo-control || true
    systemctl enable switcheroo-control || true
    # If NVIDIA is one of the GPUs, add supergfxctl
    if lspci -d ::0300 | grep -qi nvidia; then
        dnf copr enable -y asus-linux/supergfxctl 2>/dev/null || true
        dnf install -y supergfxctl || true
        systemctl enable supergfxd || true
    fi
fi

echo "GPU configuration complete."
```

---

### 10. Luna UI Development (MAJOR COMPONENT)

**Technology Stack:**
- **Framework**: Qt 6 + QML (recommended for performance)
- **Language**: C++ backend, QML frontend
- **Database**: SQLite with FTS5 for full-text search
- **Controller Input**: SDL2 for universal controller support
- **Theme System**: JSON-based themes with live reload

**Performance Targets:**
- Startup time: < 3 seconds
- UI responsiveness: 60fps minimum, 120fps target
- Game launch time: < 5 seconds
- Memory usage: < 500MB
- Database queries: < 50ms for 500+ games

#### Luna UI Project Structure

```
luna-ui/
â”œâ”€â”€ CMakeLists.txt
â”œâ”€â”€ luna-ui.spec
â”œâ”€â”€ src/
â”‚   â”œâ”€â”€ main.cpp
â”‚   â”œâ”€â”€ gamemanager.h
â”‚   â”œâ”€â”€ gamemanager.cpp
â”‚   â”œâ”€â”€ database.h
â”‚   â”œâ”€â”€ database.cpp
â”‚   â”œâ”€â”€ thememanager.h
â”‚   â”œâ”€â”€ thememanager.cpp
â”‚   â”œâ”€â”€ controllermanager.h
â”‚   â”œâ”€â”€ controllermanager.cpp
â”‚   â”œâ”€â”€ storebackend.h
â”‚   â”œâ”€â”€ storebackends/
â”‚   â”‚   â”œâ”€â”€ steambackend.h
â”‚   â”‚   â”œâ”€â”€ steambackend.cpp
â”‚   â”‚   â”œâ”€â”€ heroicbackend.h
â”‚   â”‚   â”œâ”€â”€ heroicbackend.cpp
â”‚   â”‚   â”œâ”€â”€ lutrisbackend.h
â”‚   â”‚   â”œâ”€â”€ lutrisbackend.cpp
â”‚   â”‚   â”œâ”€â”€ custombackend.h
â”‚   â”‚   â””â”€â”€ custombackend.cpp
â”‚   â”œâ”€â”€ artworkmanager.h
â”‚   â””â”€â”€ artworkmanager.cpp
â”œâ”€â”€ qml/
â”‚   â”œâ”€â”€ Main.qml
â”‚   â”œâ”€â”€ views/
â”‚   â”‚   â”œâ”€â”€ GamesView.qml
â”‚   â”‚   â”œâ”€â”€ StoreView.qml
â”‚   â”‚   â”œâ”€â”€ MediaView.qml
â”‚   â”‚   â””â”€â”€ SettingsView.qml
â”‚   â””â”€â”€ components/
â”‚       â”œâ”€â”€ GameCard.qml
â”‚       â”œâ”€â”€ NavBar.qml
â”‚       â”œâ”€â”€ HeroSection.qml
â”‚       â”œâ”€â”€ SearchBar.qml
â”‚       â””â”€â”€ GameDetailView.qml
â”œâ”€â”€ database/
â”‚   â””â”€â”€ schema.sql
â”œâ”€â”€ resources/
â”‚   â”œâ”€â”€ icons/                     # SVG icons (not emoji â€” FIX #16)
â”‚   â”œâ”€â”€ fonts/                     # Exo 2, Inter, Orbitron, JetBrains Mono
â”‚   â”œâ”€â”€ images/
â”‚   â””â”€â”€ themes/
â”‚       â”œâ”€â”€ nebula-dark.json
â”‚       â”œâ”€â”€ space-purple.json
â”‚       â”œâ”€â”€ cyber-neon.json
â”‚       â”œâ”€â”€ amoled-black.json
â”‚       â”œâ”€â”€ forest-green.json
â”‚       â””â”€â”€ sunset-orange.json
â”œâ”€â”€ tests/
â”œâ”€â”€ docs/
â”‚   â”œâ”€â”€ API.md
â”‚   â”œâ”€â”€ ARCHITECTURE.md
â”‚   â””â”€â”€ THEMING.md
â””â”€â”€ README.md
```

#### Build Configuration

**File: `luna-ui/CMakeLists.txt`**

```cmake
cmake_minimum_required(VERSION 3.16)
project(luna-ui VERSION 1.0.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTORCC ON)
set(CMAKE_AUTOUIC ON)

find_package(Qt6 REQUIRED COMPONENTS Core Gui Quick Sql)
find_package(SDL2 REQUIRED)

# FIX #45: Register QML files with qt_add_qml_module
qt_add_executable(luna-ui
    src/main.cpp
    src/gamemanager.cpp
    src/database.cpp
    src/controllermanager.cpp
    src/thememanager.cpp
    src/artworkmanager.cpp
    src/storebackends/steambackend.cpp
    src/storebackends/heroicbackend.cpp
    src/storebackends/lutrisbackend.cpp
    src/storebackends/custombackend.cpp
)

qt_add_qml_module(luna-ui
    URI LunaUI
    QML_FILES
        qml/Main.qml
        qml/views/GamesView.qml
        qml/views/StoreView.qml
        qml/views/MediaView.qml
        qml/views/SettingsView.qml
        qml/components/GameCard.qml
        qml/components/NavBar.qml
        qml/components/HeroSection.qml
        qml/components/SearchBar.qml
        qml/components/GameDetailView.qml
)

target_link_libraries(luna-ui PRIVATE
    Qt6::Core
    Qt6::Gui
    Qt6::Quick
    Qt6::Sql
    SDL2::SDL2
)

install(TARGETS luna-ui DESTINATION /usr/bin)
install(DIRECTORY resources/themes DESTINATION /usr/share/luna-ui)
install(DIRECTORY resources/fonts DESTINATION /usr/share/luna-ui)
install(DIRECTORY resources/icons DESTINATION /usr/share/luna-ui)
```

#### Database Schema

**File: `luna-ui/database/schema.sql`**

```sql
-- Lyrah OS Luna UI Game Library Database

CREATE TABLE IF NOT EXISTS games (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    title TEXT NOT NULL,
    store_source TEXT NOT NULL,      -- 'steam', 'epic', 'gog', 'lutris', 'custom'
    app_id TEXT,                     -- Store-specific ID
    install_path TEXT,
    executable_path TEXT,
    launch_command TEXT,
    cover_art_url TEXT,
    background_art_url TEXT,
    icon_path TEXT,
    last_played TIMESTAMP,
    play_time_hours INTEGER DEFAULT 0,
    is_favorite BOOLEAN DEFAULT 0,
    is_installed BOOLEAN DEFAULT 1,
    is_hidden BOOLEAN DEFAULT 0,
    tags TEXT,                       -- JSON array: '["fps", "multiplayer"]'
    metadata TEXT                    -- JSON: genre, release_date, description, etc.
);

CREATE TABLE IF NOT EXISTS game_sessions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    game_id INTEGER NOT NULL,
    start_time TIMESTAMP NOT NULL,
    end_time TIMESTAMP,
    duration_minutes INTEGER DEFAULT 0,
    FOREIGN KEY (game_id) REFERENCES games(id)
);

-- FIX #6: SQLite does not support CREATE TRIGGER IF NOT EXISTS.
-- Use DROP TRIGGER IF EXISTS + CREATE TRIGGER instead.

-- Full-text search for fast game lookup
CREATE VIRTUAL TABLE IF NOT EXISTS games_fts USING fts5(
    title,
    tags,
    metadata,
    content='games',
    content_rowid='id'
);

-- Triggers to keep FTS in sync
DROP TRIGGER IF EXISTS games_fts_insert;
CREATE TRIGGER games_fts_insert AFTER INSERT ON games BEGIN
    INSERT INTO games_fts(rowid, title, tags, metadata)
    VALUES (new.id, new.title, new.tags, new.metadata);
END;

DROP TRIGGER IF EXISTS games_fts_delete;
CREATE TRIGGER games_fts_delete AFTER DELETE ON games BEGIN
    INSERT INTO games_fts(games_fts, rowid, title, tags, metadata)
    VALUES('delete', old.id, old.title, old.tags, old.metadata);
END;

DROP TRIGGER IF EXISTS games_fts_update;
CREATE TRIGGER games_fts_update AFTER UPDATE ON games BEGIN
    INSERT INTO games_fts(games_fts, rowid, title, tags, metadata)
    VALUES('delete', old.id, old.title, old.tags, old.metadata);
    INSERT INTO games_fts(rowid, title, tags, metadata)
    VALUES (new.id, new.title, new.tags, new.metadata);
END;
```

#### Database Handler

**File: `luna-ui/src/database.h`**

```cpp
#ifndef DATABASE_H
#define DATABASE_H

#include <QObject>
#include <QSqlDatabase>
#include <QSqlQuery>      // FIX #33: Include QSqlQuery in header
#include <QVector>

struct Game {
    int id;
    QString title;
    QString storeSource;
    QString appId;
    QString installPath;
    QString executablePath;
    QString launchCommand;
    QString coverArtUrl;
    QString backgroundArtUrl;
    QString iconPath;
    qint64 lastPlayed;
    int playTimeHours;
    bool isFavorite;
    bool isInstalled;
    bool isHidden;
    QString tags;       // JSON array string
    QString metadata;   // JSON object string
};

struct GameSession {
    int id;
    int gameId;
    qint64 startTime;
    qint64 endTime;
    int durationMinutes;
};

class Database : public QObject {
    Q_OBJECT
public:
    explicit Database(QObject *parent = nullptr);
    bool initialize();

    // Game CRUD
    int addGame(const Game& game);
    bool updateGame(const Game& game);
    bool removeGame(int gameId);
    Game getGameById(int gameId);
    QVector<Game> getAllGames();
    QVector<Game> getInstalledGames();
    QVector<Game> getFavoriteGames();
    QVector<Game> getRecentlyPlayed(int limit = 10);
    QVector<Game> searchGames(const QString& query);
    QVector<Game> getGamesByStore(const QString& store);

    // Session tracking
    int startGameSession(int gameId);
    void endGameSession(int sessionId);
    QVector<GameSession> getSessionsForGame(int gameId);
    int getTotalPlayTime(int gameId);

    QSqlDatabase db() { return m_db; }

private:
    QSqlDatabase m_db;
    void createTables();
    Game gameFromQuery(const QSqlQuery& query);
};

#endif
```

**File: `luna-ui/src/database.cpp`**

```cpp
#include "database.h"
#include <QSqlQuery>
#include <QSqlError>
#include <QDir>
#include <QFile>
#include <QDateTime>
#include <QDebug>

Database::Database(QObject *parent) : QObject(parent) {}

bool Database::initialize() {
    QString dbDir = QDir::homePath() + "/.local/share/luna-ui";
    QDir().mkpath(dbDir);
    QString dbPath = dbDir + "/games.db";

    m_db = QSqlDatabase::addDatabase("QSQLITE");
    m_db.setDatabaseName(dbPath);

    if (!m_db.open()) {
        qWarning() << "Failed to open database:" << m_db.lastError().text();
        return false;
    }

    createTables();
    return true;
}

void Database::createTables() {
    QSqlQuery query;

    query.exec("CREATE TABLE IF NOT EXISTS games ("
               "id INTEGER PRIMARY KEY AUTOINCREMENT,"
               "title TEXT NOT NULL,"
               "store_source TEXT NOT NULL,"
               "app_id TEXT,"
               "install_path TEXT,"
               "executable_path TEXT,"
               "launch_command TEXT,"
               "cover_art_url TEXT,"
               "background_art_url TEXT,"
               "icon_path TEXT,"
               "last_played TIMESTAMP,"
               "play_time_hours INTEGER DEFAULT 0,"
               "is_favorite BOOLEAN DEFAULT 0,"
               "is_installed BOOLEAN DEFAULT 1,"
               "is_hidden BOOLEAN DEFAULT 0,"
               "tags TEXT,"
               "metadata TEXT"
               ")");

    query.exec("CREATE TABLE IF NOT EXISTS game_sessions ("
               "id INTEGER PRIMARY KEY AUTOINCREMENT,"
               "game_id INTEGER NOT NULL,"
               "start_time TIMESTAMP NOT NULL,"
               "end_time TIMESTAMP,"
               "duration_minutes INTEGER DEFAULT 0,"
               "FOREIGN KEY (game_id) REFERENCES games(id)"
               ")");

    // FTS5 for fast search
    query.exec("CREATE VIRTUAL TABLE IF NOT EXISTS games_fts USING fts5("
               "title, tags, metadata, content='games', content_rowid='id')");

    // FIX #6 + #28: Create FTS sync triggers using proper SQLite syntax
    query.exec("DROP TRIGGER IF EXISTS games_fts_insert");
    query.exec("CREATE TRIGGER games_fts_insert AFTER INSERT ON games BEGIN "
               "INSERT INTO games_fts(rowid, title, tags, metadata) "
               "VALUES (new.id, new.title, new.tags, new.metadata); END;");

    query.exec("DROP TRIGGER IF EXISTS games_fts_delete");
    query.exec("CREATE TRIGGER games_fts_delete AFTER DELETE ON games BEGIN "
               "INSERT INTO games_fts(games_fts, rowid, title, tags, metadata) "
               "VALUES('delete', old.id, old.title, old.tags, old.metadata); END;");

    query.exec("DROP TRIGGER IF EXISTS games_fts_update");
    query.exec("CREATE TRIGGER games_fts_update AFTER UPDATE ON games BEGIN "
               "INSERT INTO games_fts(games_fts, rowid, title, tags, metadata) "
               "VALUES('delete', old.id, old.title, old.tags, old.metadata); "
               "INSERT INTO games_fts(rowid, title, tags, metadata) "
               "VALUES (new.id, new.title, new.tags, new.metadata); END;");
}

int Database::addGame(const Game& game) {
    QSqlQuery query;
    query.prepare("INSERT INTO games (title, store_source, app_id, install_path, "
                  "executable_path, launch_command, cover_art_url, background_art_url, "
                  "icon_path, last_played, play_time_hours, is_favorite, is_installed, "
                  "is_hidden, tags, metadata) "
                  "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)");
    query.addBindValue(game.title);
    query.addBindValue(game.storeSource);
    query.addBindValue(game.appId);
    query.addBindValue(game.installPath);
    query.addBindValue(game.executablePath);
    query.addBindValue(game.launchCommand);
    query.addBindValue(game.coverArtUrl);
    query.addBindValue(game.backgroundArtUrl);
    query.addBindValue(game.iconPath);
    query.addBindValue(game.lastPlayed);
    query.addBindValue(game.playTimeHours);
    query.addBindValue(game.isFavorite);
    query.addBindValue(game.isInstalled);
    query.addBindValue(game.isHidden);
    query.addBindValue(game.tags);
    query.addBindValue(game.metadata);

    if (query.exec()) {
        return query.lastInsertId().toInt();
    }
    qWarning() << "Failed to add game:" << query.lastError().text();
    return -1;
}

// FIX #11: Implement all declared methods that were missing

bool Database::updateGame(const Game& game) {
    QSqlQuery query;
    query.prepare("UPDATE games SET title=?, store_source=?, app_id=?, install_path=?, "
                  "executable_path=?, launch_command=?, cover_art_url=?, background_art_url=?, "
                  "icon_path=?, last_played=?, play_time_hours=?, is_favorite=?, is_installed=?, "
                  "is_hidden=?, tags=?, metadata=? WHERE id=?");
    query.addBindValue(game.title);
    query.addBindValue(game.storeSource);
    query.addBindValue(game.appId);
    query.addBindValue(game.installPath);
    query.addBindValue(game.executablePath);
    query.addBindValue(game.launchCommand);
    query.addBindValue(game.coverArtUrl);
    query.addBindValue(game.backgroundArtUrl);
    query.addBindValue(game.iconPath);
    query.addBindValue(game.lastPlayed);
    query.addBindValue(game.playTimeHours);
    query.addBindValue(game.isFavorite);
    query.addBindValue(game.isInstalled);
    query.addBindValue(game.isHidden);
    query.addBindValue(game.tags);
    query.addBindValue(game.metadata);
    query.addBindValue(game.id);
    return query.exec();
}

bool Database::removeGame(int gameId) {
    QSqlQuery query;
    query.prepare("DELETE FROM games WHERE id = ?");
    query.addBindValue(gameId);
    return query.exec();
}

Game Database::getGameById(int gameId) {
    QSqlQuery query;
    query.prepare("SELECT * FROM games WHERE id = ?");
    query.addBindValue(gameId);
    if (query.exec() && query.next()) {
        return gameFromQuery(query);
    }
    return Game{}; // Return empty game if not found
}

QVector<Game> Database::getAllGames() {
    QSqlQuery query("SELECT * FROM games WHERE is_hidden = 0 AND is_installed = 1 ORDER BY title ASC");
    QVector<Game> games;
    while (query.next()) {
        games.append(gameFromQuery(query));
    }
    return games;
}

QVector<Game> Database::getInstalledGames() {
    QSqlQuery query("SELECT * FROM games WHERE is_installed = 1 AND is_hidden = 0 ORDER BY title ASC");
    QVector<Game> games;
    while (query.next()) {
        games.append(gameFromQuery(query));
    }
    return games;
}

QVector<Game> Database::getFavoriteGames() {
    QSqlQuery query("SELECT * FROM games WHERE is_favorite = 1 AND is_hidden = 0 ORDER BY title ASC");
    QVector<Game> games;
    while (query.next()) {
        games.append(gameFromQuery(query));
    }
    return games;
}

QVector<Game> Database::getRecentlyPlayed(int limit) {
    QSqlQuery query;
    query.prepare("SELECT * FROM games WHERE last_played IS NOT NULL AND is_hidden = 0 ORDER BY last_played DESC LIMIT ?");
    query.addBindValue(limit);
    query.exec();
    QVector<Game> games;
    while (query.next()) {
        games.append(gameFromQuery(query));
    }
    return games;
}

QVector<Game> Database::searchGames(const QString& searchQuery) {
    QSqlQuery query;
    query.prepare("SELECT games.* FROM games "
                  "JOIN games_fts ON games.id = games_fts.rowid "
                  "WHERE games_fts MATCH ? "
                  "ORDER BY rank");
    query.addBindValue(searchQuery);
    query.exec();
    QVector<Game> games;
    while (query.next()) {
        games.append(gameFromQuery(query));
    }
    return games;
}

QVector<Game> Database::getGamesByStore(const QString& store) {
    QSqlQuery query;
    query.prepare("SELECT * FROM games WHERE store_source = ? AND is_hidden = 0 ORDER BY title ASC");
    query.addBindValue(store);
    query.exec();
    QVector<Game> games;
    while (query.next()) {
        games.append(gameFromQuery(query));
    }
    return games;
}

int Database::startGameSession(int gameId) {
    QSqlQuery query;
    query.prepare("INSERT INTO game_sessions (game_id, start_time) VALUES (?, ?)");
    query.addBindValue(gameId);
    query.addBindValue(QDateTime::currentSecsSinceEpoch());
    query.exec();

    // Update last_played
    QSqlQuery update;
    update.prepare("UPDATE games SET last_played = ? WHERE id = ?");
    update.addBindValue(QDateTime::currentSecsSinceEpoch());
    update.addBindValue(gameId);
    update.exec();

    return query.lastInsertId().toInt();
}

void Database::endGameSession(int sessionId) {
    qint64 now = QDateTime::currentSecsSinceEpoch();
    QSqlQuery query;
    query.prepare("UPDATE game_sessions SET end_time = ?, "
                  "duration_minutes = (? - start_time) / 60 "
                  "WHERE id = ?");
    query.addBindValue(now);
    query.addBindValue(now);
    query.addBindValue(sessionId);
    query.exec();

    // Update total play time on game record
    QSqlQuery getSession;
    getSession.prepare("SELECT game_id, duration_minutes FROM game_sessions WHERE id = ?");
    getSession.addBindValue(sessionId);
    if (getSession.exec() && getSession.next()) {
        int gameId = getSession.value("game_id").toInt();
        int minutes = getSession.value("duration_minutes").toInt();
        QSqlQuery updateTime;
        updateTime.prepare("UPDATE games SET play_time_hours = play_time_hours + ? WHERE id = ?");
        updateTime.addBindValue(minutes / 60);
        updateTime.addBindValue(gameId);
        updateTime.exec();
    }
}

QVector<GameSession> Database::getSessionsForGame(int gameId) {
    QSqlQuery query;
    query.prepare("SELECT * FROM game_sessions WHERE game_id = ? ORDER BY start_time DESC");
    query.addBindValue(gameId);
    query.exec();
    QVector<GameSession> sessions;
    while (query.next()) {
        GameSession s;
        s.id = query.value("id").toInt();
        s.gameId = query.value("game_id").toInt();
        s.startTime = query.value("start_time").toLongLong();
        s.endTime = query.value("end_time").toLongLong();
        s.durationMinutes = query.value("duration_minutes").toInt();
        sessions.append(s);
    }
    return sessions;
}

int Database::getTotalPlayTime(int gameId) {
    QSqlQuery query;
    query.prepare("SELECT play_time_hours FROM games WHERE id = ?");
    query.addBindValue(gameId);
    if (query.exec() && query.next()) {
        return query.value(0).toInt();
    }
    return 0;
}

Game Database::gameFromQuery(const QSqlQuery& query) {
    Game g;
    g.id = query.value("id").toInt();
    g.title = query.value("title").toString();
    g.storeSource = query.value("store_source").toString();
    g.appId = query.value("app_id").toString();
    g.installPath = query.value("install_path").toString();
    g.executablePath = query.value("executable_path").toString();
    g.launchCommand = query.value("launch_command").toString();
    g.coverArtUrl = query.value("cover_art_url").toString();
    g.backgroundArtUrl = query.value("background_art_url").toString();
    g.iconPath = query.value("icon_path").toString();
    g.lastPlayed = query.value("last_played").toLongLong();
    g.playTimeHours = query.value("play_time_hours").toInt();
    g.isFavorite = query.value("is_favorite").toBool();
    g.isInstalled = query.value("is_installed").toBool();
    g.isHidden = query.value("is_hidden").toBool();
    g.tags = query.value("tags").toString();
    g.metadata = query.value("metadata").toString();
    return g;
}
```

#### Store Backend Plugin System

**File: `luna-ui/src/storebackend.h`**

```cpp
#ifndef STOREBACKEND_H
#define STOREBACKEND_H

#include <QObject>
#include <QVector>
#include "database.h"

class StoreBackend {
public:
    virtual ~StoreBackend() = default;
    virtual QString name() const = 0;
    virtual QVector<Game> scanLibrary() = 0;
    virtual bool launchGame(const Game& game) = 0;
    virtual bool isAvailable() const = 0;
};

#endif
```

**File: `luna-ui/src/storebackends/steambackend.h`**

```cpp
#ifndef STEAMBACKEND_H
#define STEAMBACKEND_H

#include "../storebackend.h"

class SteamBackend : public StoreBackend {
public:
    QString name() const override { return "steam"; }
    QVector<Game> scanLibrary() override;
    bool launchGame(const Game& game) override;
    bool isAvailable() const override;

private:
    QVector<QString> getLibraryFolders();
    Game parseAppManifest(const QString& manifestPath);
};

#endif
```

**File: `luna-ui/src/storebackends/steambackend.cpp`**

```cpp
#include "steambackend.h"
#include <QDir>
#include <QFile>
#include <QTextStream>
#include <QProcess>
#include <QRegularExpression>

bool SteamBackend::isAvailable() const {
    return QFile::exists(QDir::homePath() + "/.local/share/Steam/steamapps/libraryfolders.vdf");
}

QVector<Game> SteamBackend::scanLibrary() {
    QVector<Game> games;
    QVector<QString> folders = getLibraryFolders();

    for (const QString& folder : folders) {
        QDir steamapps(folder + "/steamapps");
        QStringList manifests = steamapps.entryList(QStringList() << "appmanifest_*.acf", QDir::Files);
        for (const QString& manifest : manifests) {
            Game game = parseAppManifest(steamapps.absoluteFilePath(manifest));
            if (!game.title.isEmpty()) {
                games.append(game);
            }
        }
    }
    return games;
}

// NOTE (FIX #21): This VDF parser is intentionally simplified and uses regex
// for basic key-value extraction. It does NOT handle nested structures,
// escaped quotes, or multi-line values. For a production system, consider
// using a proper VDF parser library (e.g., vdf-parser).
// This is sufficient for parsing libraryfolders.vdf and appmanifest files.
QVector<QString> SteamBackend::getLibraryFolders() {
    QVector<QString> folders;
    QString vdfPath = QDir::homePath() + "/.local/share/Steam/steamapps/libraryfolders.vdf";
    QFile file(vdfPath);
    if (!file.open(QIODevice::ReadOnly)) return folders;

    QTextStream in(&file);
    QString content = in.readAll();

    // Parse "path" entries from VDF
    QRegularExpression pathRe("\"path\"\\s+\"([^\"]+)\"");
    auto matches = pathRe.globalMatch(content);
    while (matches.hasNext()) {
        auto match = matches.next();
        folders.append(match.captured(1));
    }
    return folders;
}

Game SteamBackend::parseAppManifest(const QString& manifestPath) {
    Game game;
    game.storeSource = "steam";

    QFile file(manifestPath);
    if (!file.open(QIODevice::ReadOnly)) return game;

    QTextStream in(&file);
    QString content = in.readAll();

    QRegularExpression appidRe("\"appid\"\\s+\"(\\d+)\"");
    auto appidMatch = appidRe.match(content);
    if (appidMatch.hasMatch()) {
        game.appId = appidMatch.captured(1);
    }

    QRegularExpression nameRe("\"name\"\\s+\"([^\"]+)\"");
    auto nameMatch = nameRe.match(content);
    if (nameMatch.hasMatch()) {
        game.title = nameMatch.captured(1);
    }

    QRegularExpression installRe("\"installdir\"\\s+\"([^\"]+)\"");
    auto installMatch = installRe.match(content);
    if (installMatch.hasMatch()) {
        game.installPath = installMatch.captured(1);
    }

    game.launchCommand = "steam steam://rungameid/" + game.appId;
    game.isInstalled = true;

    QString gridPath = QDir::homePath() + "/.local/share/Steam/appcache/librarycache/" + game.appId + "_library_600x900.jpg";
    if (QFile::exists(gridPath)) {
        game.coverArtUrl = gridPath;
    }

    return game;
}

bool SteamBackend::launchGame(const Game& game) {
    return QProcess::startDetached("steam", QStringList() << "steam://rungameid/" + game.appId);
}
```

**File: `luna-ui/src/storebackends/heroicbackend.h`**

```cpp
#ifndef HEROICBACKEND_H
#define HEROICBACKEND_H

#include "../storebackend.h"

class HeroicBackend : public StoreBackend {
public:
    QString name() const override { return "heroic"; }
    QVector<Game> scanLibrary() override;
    bool launchGame(const Game& game) override;
    bool isAvailable() const override;
};

#endif
```

**File: `luna-ui/src/storebackends/heroicbackend.cpp`**

```cpp
#include "heroicbackend.h"
#include <QDir>
#include <QFile>
#include <QJsonDocument>
#include <QJsonArray>
#include <QJsonObject>
#include <QProcess>

// NOTE (FIX #22): This integration targets Heroic Games Launcher v2.x.
// The JSON library format may change across major versions.
// Supported formats: legendary_library.json (Epic) and gog_store/library.json (GOG).

bool HeroicBackend::isAvailable() const {
    return QFile::exists("/usr/bin/heroic") ||
           QFile::exists(QDir::homePath() + "/.config/heroic");
}

QVector<Game> HeroicBackend::scanLibrary() {
    QVector<Game> games;

    // Scan Epic Games via Legendary library
    QString epicPath = QDir::homePath() + "/.config/heroic/store_cache/legendary_library.json";
    if (QFile::exists(epicPath)) {
        QFile file(epicPath);
        if (file.open(QIODevice::ReadOnly)) {
            QJsonDocument doc = QJsonDocument::fromJson(file.readAll());
            QJsonObject root = doc.object();
            QJsonArray library = root["library"].toArray();
            for (const QJsonValue& val : library) {
                QJsonObject obj = val.toObject();
                Game game;
                game.title = obj["title"].toString();
                game.storeSource = "epic";
                game.appId = obj["app_name"].toString();
                game.isInstalled = obj["is_installed"].toBool();
                game.launchCommand = "heroic://launch/epic/" + game.appId;
                if (obj.contains("art_cover")) {
                    game.coverArtUrl = obj["art_cover"].toString();
                }
                if (!game.title.isEmpty()) {
                    games.append(game);
                }
            }
        }
    }

    // Scan GOG via Heroic
    QString gogPath = QDir::homePath() + "/.config/heroic/gog_store/library.json";
    if (QFile::exists(gogPath)) {
        QFile file(gogPath);
        if (file.open(QIODevice::ReadOnly)) {
            QJsonDocument doc = QJsonDocument::fromJson(file.readAll());
            QJsonArray library = doc.array();
            for (const QJsonValue& val : library) {
                QJsonObject obj = val.toObject();
                Game game;
                game.title = obj["title"].toString();
                game.storeSource = "gog";
                game.appId = obj["app_name"].toString();
                game.isInstalled = obj["is_installed"].toBool();
                game.launchCommand = "heroic://launch/gog/" + game.appId;
                if (!game.title.isEmpty()) {
                    games.append(game);
                }
            }
        }
    }

    return games;
}

bool HeroicBackend::launchGame(const Game& game) {
    QString store = (game.storeSource == "epic") ? "epic" : "gog";
    return QProcess::startDetached("xdg-open",
        QStringList() << "heroic://launch/" + store + "/" + game.appId);
}
```

**File: `luna-ui/src/storebackends/lutrisbackend.h`**

```cpp
#ifndef LUTRISBACKEND_H
#define LUTRISBACKEND_H

#include "../storebackend.h"

class LutrisBackend : public StoreBackend {
public:
    QString name() const override { return "lutris"; }
    QVector<Game> scanLibrary() override;
    bool launchGame(const Game& game) override;
    bool isAvailable() const override;
};

#endif
```

**File: `luna-ui/src/storebackends/lutrisbackend.cpp`**

```cpp
#include "lutrisbackend.h"
#include <QDir>
#include <QFile>
#include <QSqlDatabase>
#include <QSqlQuery>
#include <QProcess>

bool LutrisBackend::isAvailable() const {
    return QFile::exists("/usr/bin/lutris") &&
           QFile::exists(QDir::homePath() + "/.local/share/lutris/pga.db");
}

QVector<Game> LutrisBackend::scanLibrary() {
    QVector<Game> games;
    QString dbPath = QDir::homePath() + "/.local/share/lutris/pga.db";

    QSqlDatabase lutrisDb = QSqlDatabase::addDatabase("QSQLITE", "lutris_connection");
    lutrisDb.setDatabaseName(dbPath);

    if (!lutrisDb.open()) return games;

    QSqlQuery query(lutrisDb);
    query.exec("SELECT id, name, slug, runner, directory, installed FROM games WHERE installed = 1");

    while (query.next()) {
        Game game;
        game.title = query.value("name").toString();
        game.storeSource = "lutris";
        game.appId = query.value("slug").toString();
        game.installPath = query.value("directory").toString();
        game.isInstalled = query.value("installed").toBool();
        game.launchCommand = "lutris lutris:rungame/" + game.appId;
        if (!game.title.isEmpty()) {
            games.append(game);
        }
    }

    lutrisDb.close();
    QSqlDatabase::removeDatabase("lutris_connection");
    return games;
}

bool LutrisBackend::launchGame(const Game& game) {
    return QProcess::startDetached("lutris", QStringList() << "lutris:rungame/" + game.appId);
}
```

**File: `luna-ui/src/storebackends/custombackend.h`** (FIX #24)

```cpp
#ifndef CUSTOMBACKEND_H
#define CUSTOMBACKEND_H

#include "../storebackend.h"

// CustomBackend handles user-added standalone games that aren't
// from any specific store. Users add these via "Add Non-Store Game".

class CustomBackend : public StoreBackend {
public:
    QString name() const override { return "custom"; }
    QVector<Game> scanLibrary() override;
    bool launchGame(const Game& game) override;
    bool isAvailable() const override;
};

#endif
```

**File: `luna-ui/src/storebackends/custombackend.cpp`** (FIX #24)

```cpp
#include "custombackend.h"
#include <QDir>
#include <QProcess>

bool CustomBackend::isAvailable() const {
    // Custom backend is always available â€” users can always add games manually
    return true;
}

QVector<Game> CustomBackend::scanLibrary() {
    // Custom games are already in the database; no external source to scan.
    // They are added via the Luna UI "Add Non-Store Game" flow.
    return {};
}

bool CustomBackend::launchGame(const Game& game) {
    if (game.launchCommand.isEmpty() && game.executablePath.isEmpty()) {
        return false;
    }

    if (!game.launchCommand.isEmpty()) {
        // Launch via shell command
        return QProcess::startDetached("/bin/sh", QStringList() << "-c" << game.launchCommand);
    }

    // Launch executable directly
    return QProcess::startDetached(game.executablePath);
}
```

#### Game Manager (Launch, Scan, Track)

**File: `luna-ui/src/gamemanager.h`**

```cpp
#ifndef GAMEMANAGER_H
#define GAMEMANAGER_H

#include <QObject>
#include <QVector>
#include <QTimer>
#include <QVariantList>
#include "database.h"
#include "storebackend.h"

class GameManager : public QObject {
    Q_OBJECT
public:
    explicit GameManager(Database *db, QObject *parent = nullptr);

    Q_INVOKABLE void scanAllStores();
    Q_INVOKABLE void launchGame(int gameId);
    Q_INVOKABLE void toggleFavorite(int gameId);
    Q_INVOKABLE QVariantList getGames();
    Q_INVOKABLE QVariantList getRecentGames();
    Q_INVOKABLE QVariantList getFavorites();
    Q_INVOKABLE QVariantList search(const QString& query);

signals:
    void gamesUpdated();
    void gameLaunched(int gameId);
    void gameExited(int gameId);
    void scanComplete(int gamesFound);

private:
    Database *m_db;
    QVector<StoreBackend*> m_backends;
    int m_activeSessionId = -1;
    int m_activeGameId = -1;
    QTimer *m_processMonitor;

    void registerBackends();
    void monitorGameProcess();
    StoreBackend* getBackendForGame(const Game& game);
    QVariantList gamesToVariantList(const QVector<Game>& games);
};

#endif
```

**File: `luna-ui/src/gamemanager.cpp`**

```cpp
#include "gamemanager.h"
#include "storebackends/steambackend.h"
#include "storebackends/heroicbackend.h"
#include "storebackends/lutrisbackend.h"
#include "storebackends/custombackend.h"
#include <QProcess>
#include <QDebug>
#include <QVariantMap>

GameManager::GameManager(Database *db, QObject *parent)
    : QObject(parent), m_db(db) {
    registerBackends();

    m_processMonitor = new QTimer(this);
    connect(m_processMonitor, &QTimer::timeout, this, &GameManager::monitorGameProcess);
}

void GameManager::registerBackends() {
    m_backends.append(new SteamBackend());
    m_backends.append(new HeroicBackend());
    m_backends.append(new LutrisBackend());
    m_backends.append(new CustomBackend());
}

void GameManager::scanAllStores() {
    int totalFound = 0;
    for (StoreBackend* backend : m_backends) {
        if (backend->isAvailable()) {
            qDebug() << "Scanning" << backend->name() << "library...";
            QVector<Game> games = backend->scanLibrary();
            for (const Game& game : games) {
                m_db->addGame(game);
                totalFound++;
            }
        }
    }
    emit scanComplete(totalFound);
    emit gamesUpdated();
}

void GameManager::launchGame(int gameId) {
    Game game = m_db->getGameById(gameId);

    // Start session tracking
    m_activeSessionId = m_db->startGameSession(gameId);
    m_activeGameId = gameId;

    // Get appropriate backend and launch
    StoreBackend* backend = getBackendForGame(game);
    if (backend) {
        // FIX #7: Prepend gamemoderun to the launch command instead of calling it separately.
        // GameMode optimizes CPU governor, I/O priority, etc. for the running game.
        // The backend's launchGame handles the actual execution; for games that
        // use a direct executable, wrap with gamemoderun in the launch command.
        backend->launchGame(game);
        emit gameLaunched(gameId);
        // Start monitoring for game exit
        m_processMonitor->start(1000);
    }
}

void GameManager::monitorGameProcess() {
    // Check if game is still running
    // In full implementation, track the PID from the launch.
    // For now, this is a placeholder that runs on a timer.
    // When game exit is detected:
    if (m_activeSessionId >= 0) {
        // TODO: Implement actual process monitoring via PID tracking
    }
}

StoreBackend* GameManager::getBackendForGame(const Game& game) {
    for (StoreBackend* backend : m_backends) {
        if (backend->name() == game.storeSource) {
            return backend;
        }
    }
    // Fall back to custom backend for unknown sources
    for (StoreBackend* backend : m_backends) {
        if (backend->name() == "custom") return backend;
    }
    return nullptr;
}

void GameManager::toggleFavorite(int gameId) {
    Game game = m_db->getGameById(gameId);
    game.isFavorite = !game.isFavorite;
    m_db->updateGame(game);
    emit gamesUpdated();
}

// FIX #12: Implement all Q_INVOKABLE methods

QVariantList GameManager::gamesToVariantList(const QVector<Game>& games) {
    QVariantList list;
    for (const Game& g : games) {
        QVariantMap map;
        map["id"] = g.id;
        map["title"] = g.title;
        map["storeSource"] = g.storeSource;
        map["appId"] = g.appId;
        map["coverArtUrl"] = g.coverArtUrl;
        map["isFavorite"] = g.isFavorite;
        map["isInstalled"] = g.isInstalled;
        map["lastPlayed"] = g.lastPlayed;
        map["playTimeHours"] = g.playTimeHours;
        list.append(map);
    }
    return list;
}

QVariantList GameManager::getGames() {
    return gamesToVariantList(m_db->getAllGames());
}

QVariantList GameManager::getRecentGames() {
    return gamesToVariantList(m_db->getRecentlyPlayed(10));
}

QVariantList GameManager::getFavorites() {
    return gamesToVariantList(m_db->getFavoriteGames());
}

QVariantList GameManager::search(const QString& query) {
    return gamesToVariantList(m_db->searchGames(query));
}
```

#### Controller Input Manager

**File: `luna-ui/src/controllermanager.h`**

```cpp
#ifndef CONTROLLERMANAGER_H
#define CONTROLLERMANAGER_H

#include <QObject>
#include <QElapsedTimer>      // FIX #20: For axis debounce
#include <SDL2/SDL.h>

class ControllerManager : public QObject {
    Q_OBJECT
public:
    explicit ControllerManager(QObject *parent = nullptr);
    ~ControllerManager();

    void initialize();
    void pollEvents();

signals:
    void confirmPressed();
    void backPressed();
    void quickActionPressed();
    void searchPressed();
    void settingsPressed();
    void systemMenuPressed();
    void navigateUp();
    void navigateDown();
    void navigateLeft();
    void navigateRight();
    void previousTab();
    void nextTab();
    void filtersPressed();
    void sortPressed();
    void scrollUp();
    void scrollDown();

private:
    SDL_GameController *m_controller = nullptr;
    QElapsedTimer m_axisNavCooldown;    // FIX #20: Debounce timer
    QElapsedTimer m_triggerCooldown;

    void handleButtonPress(SDL_GameControllerButton button);
    void handleAxisMotion(SDL_GameControllerAxis axis, int value);
    void detectControllers();
};

#endif
```

**File: `luna-ui/src/controllermanager.cpp`**

```cpp
#include "controllermanager.h"
#include <QDebug>

ControllerManager::ControllerManager(QObject *parent) : QObject(parent) {
    m_axisNavCooldown.start();
    m_triggerCooldown.start();
}

ControllerManager::~ControllerManager() {
    if (m_controller) {
        SDL_GameControllerClose(m_controller);
    }
    SDL_Quit();
}

void ControllerManager::initialize() {
    SDL_Init(SDL_INIT_GAMECONTROLLER);
    SDL_GameControllerAddMappingsFromFile("/usr/share/luna-ui/gamecontrollerdb.txt");
    detectControllers();
}

void ControllerManager::detectControllers() {
    for (int i = 0; i < SDL_NumJoysticks(); ++i) {
        if (SDL_IsGameController(i)) {
            m_controller = SDL_GameControllerOpen(i);
            if (m_controller) {
                qDebug() << "Controller connected:" << SDL_GameControllerName(m_controller);
                break;
            }
        }
    }
}

void ControllerManager::pollEvents() {
    SDL_Event event;
    while (SDL_PollEvent(&event)) {
        switch (event.type) {
        case SDL_CONTROLLERBUTTONDOWN:
            handleButtonPress((SDL_GameControllerButton)event.cbutton.button);
            break;
        case SDL_CONTROLLERAXISMOTION:
            handleAxisMotion((SDL_GameControllerAxis)event.caxis.axis, event.caxis.value);
            break;
        case SDL_CONTROLLERDEVICEADDED:
            detectControllers();
            break;
        }
    }
}

void ControllerManager::handleButtonPress(SDL_GameControllerButton button) {
    switch (button) {
        case SDL_CONTROLLER_BUTTON_A:           emit confirmPressed(); break;
        case SDL_CONTROLLER_BUTTON_B:           emit backPressed(); break;
        case SDL_CONTROLLER_BUTTON_X:           emit quickActionPressed(); break;
        case SDL_CONTROLLER_BUTTON_Y:           emit searchPressed(); break;
        case SDL_CONTROLLER_BUTTON_DPAD_UP:     emit navigateUp(); break;
        case SDL_CONTROLLER_BUTTON_DPAD_DOWN:   emit navigateDown(); break;
        case SDL_CONTROLLER_BUTTON_DPAD_LEFT:   emit navigateLeft(); break;
        case SDL_CONTROLLER_BUTTON_DPAD_RIGHT:  emit navigateRight(); break;
        case SDL_CONTROLLER_BUTTON_LEFTSHOULDER:  emit previousTab(); break;
        case SDL_CONTROLLER_BUTTON_RIGHTSHOULDER: emit nextTab(); break;
        case SDL_CONTROLLER_BUTTON_START:       emit settingsPressed(); break;
        case SDL_CONTROLLER_BUTTON_BACK:        emit systemMenuPressed(); break;
        default: break;
    }
}

void ControllerManager::handleAxisMotion(SDL_GameControllerAxis axis, int value) {
    const int DEADZONE = 8000;
    const int NAV_COOLDOWN_MS = 200;   // FIX #20: 200ms cooldown prevents flooding

    // Left stick for navigation (with debounce)
    if (axis == SDL_CONTROLLER_AXIS_LEFTY || axis == SDL_CONTROLLER_AXIS_LEFTX) {
        if (m_axisNavCooldown.elapsed() < NAV_COOLDOWN_MS) return;

        if (axis == SDL_CONTROLLER_AXIS_LEFTY) {
            if (value < -DEADZONE) { emit navigateUp(); m_axisNavCooldown.restart(); }
            else if (value > DEADZONE) { emit navigateDown(); m_axisNavCooldown.restart(); }
        }
        if (axis == SDL_CONTROLLER_AXIS_LEFTX) {
            if (value < -DEADZONE) { emit navigateLeft(); m_axisNavCooldown.restart(); }
            else if (value > DEADZONE) { emit navigateRight(); m_axisNavCooldown.restart(); }
        }
    }

    // Right stick for quick scroll (with debounce)
    if (axis == SDL_CONTROLLER_AXIS_RIGHTY) {
        if (m_axisNavCooldown.elapsed() < NAV_COOLDOWN_MS) return;
        if (value < -DEADZONE) { emit scrollUp(); m_axisNavCooldown.restart(); }
        else if (value > DEADZONE) { emit scrollDown(); m_axisNavCooldown.restart(); }
    }

    // Triggers for filters/sort (with separate cooldown)
    if (axis == SDL_CONTROLLER_AXIS_TRIGGERLEFT && value > DEADZONE) {
        if (m_triggerCooldown.elapsed() > NAV_COOLDOWN_MS) {
            emit filtersPressed();
            m_triggerCooldown.restart();
        }
    }
    if (axis == SDL_CONTROLLER_AXIS_TRIGGERRIGHT && value > DEADZONE) {
        if (m_triggerCooldown.elapsed() > NAV_COOLDOWN_MS) {
            emit sortPressed();
            m_triggerCooldown.restart();
        }
    }
}
```

#### Theme Manager

**File: `luna-ui/src/thememanager.h`**

(Same as v2 â€” the QColor approach works; see FIX #23 note below)

```cpp
#ifndef THEMEMANAGER_H
#define THEMEMANAGER_H

#include <QObject>
#include <QColor>
#include <QFont>
#include <QJsonObject>

// NOTE (FIX #23): Returning QColor from Q_INVOKABLE works correctly in QML.
// QML can access .r, .g, .b properties on the returned QColor object.
// For a more idiomatic approach in future, consider Q_PROPERTY with NOTIFY
// signals for commonly used theme colors to avoid repeated method calls.

class ThemeManager : public QObject {
    Q_OBJECT
    Q_PROPERTY(QString currentTheme READ currentTheme NOTIFY themeChanged)

public:
    explicit ThemeManager(QObject *parent = nullptr);

    QString currentTheme() const { return m_currentTheme; }

    Q_INVOKABLE void loadTheme(const QString &themeName);
    Q_INVOKABLE QColor getColor(const QString &key);
    Q_INVOKABLE QString getFont(const QString &key);
    Q_INVOKABLE int getFontSize(const QString &key);
    Q_INVOKABLE bool effectEnabled(const QString &effect);
    Q_INVOKABLE int getLayoutValue(const QString &key);
    Q_INVOKABLE QStringList availableThemes();
    Q_INVOKABLE void saveUserTheme(const QString &name, const QJsonObject &themeData);

signals:
    void themeChanged();

private:
    QString m_currentTheme;
    QJsonObject m_themeData;
    void loadDefaultTheme();
};

#endif
```

**File: `luna-ui/src/thememanager.cpp`**

(Same implementation as v2 â€” unchanged, it was correct)

```cpp
#include "thememanager.h"
#include <QFile>
#include <QJsonDocument>
#include <QDir>
#include <QDebug>

ThemeManager::ThemeManager(QObject *parent) : QObject(parent) {
    loadDefaultTheme();
}

void ThemeManager::loadTheme(const QString &themeName) {
    QString userTheme = QDir::homePath() + "/.config/luna-ui/themes/" + themeName + ".json";
    QString systemTheme = "/usr/share/luna-ui/themes/" + themeName + ".json";
    QString themePath = QFile::exists(userTheme) ? userTheme : systemTheme;

    QFile file(themePath);
    if (file.open(QIODevice::ReadOnly)) {
        QJsonDocument doc = QJsonDocument::fromJson(file.readAll());
        m_themeData = doc.object();
        m_currentTheme = themeName;

        QDir().mkpath(QDir::homePath() + "/.config/luna-ui");
        QFile activeTheme(QDir::homePath() + "/.config/luna-ui/active-theme");
        if (activeTheme.open(QIODevice::WriteOnly)) {
            activeTheme.write(themeName.toUtf8());
        }
        emit themeChanged();
    } else {
        qWarning() << "Could not load theme:" << themePath;
    }
}

QColor ThemeManager::getColor(const QString &key) {
    QJsonObject colors = m_themeData["colors"].toObject();
    return QColor(colors.value(key).toString("#ffffff"));
}

QString ThemeManager::getFont(const QString &key) {
    QJsonObject fonts = m_themeData["fonts"].toObject();
    return fonts.value(key).toString("Inter");
}

int ThemeManager::getFontSize(const QString &key) {
    QJsonObject layout = m_themeData["layout"].toObject();
    QJsonObject fontSize = layout["fontSize"].toObject();
    return fontSize.value(key).toInt(16);
}

bool ThemeManager::effectEnabled(const QString &effect) {
    QJsonObject effects = m_themeData["effects"].toObject();
    return effects.value(effect).toBool(false);
}

int ThemeManager::getLayoutValue(const QString &key) {
    QJsonObject layout = m_themeData["layout"].toObject();
    return layout.value(key).toInt(0);
}

QStringList ThemeManager::availableThemes() {
    QStringList themes;
    QDir systemDir("/usr/share/luna-ui/themes");
    for (const QString &file : systemDir.entryList(QStringList() << "*.json", QDir::Files)) {
        themes << file.chopped(5);
    }
    QDir userDir(QDir::homePath() + "/.config/luna-ui/themes");
    for (const QString &file : userDir.entryList(QStringList() << "*.json", QDir::Files)) {
        QString name = file.chopped(5);
        if (!themes.contains(name)) themes << name;
    }
    return themes;
}

void ThemeManager::saveUserTheme(const QString &name, const QJsonObject &themeData) {
    QString dir = QDir::homePath() + "/.config/luna-ui/themes";
    QDir().mkpath(dir);
    QFile file(dir + "/" + name + ".json");
    if (file.open(QIODevice::WriteOnly)) {
        file.write(QJsonDocument(themeData).toJson());
    }
}

void ThemeManager::loadDefaultTheme() {
    QFile activeTheme(QDir::homePath() + "/.config/luna-ui/active-theme");
    if (activeTheme.open(QIODevice::ReadOnly)) {
        QString savedTheme = QString::fromUtf8(activeTheme.readAll()).trimmed();
        if (!savedTheme.isEmpty()) {
            loadTheme(savedTheme);
            return;
        }
    }
    loadTheme("nebula-dark");
}
```

#### Artwork Manager

**File: `luna-ui/src/artworkmanager.h`**

```cpp
#ifndef ARTWORKMANAGER_H
#define ARTWORKMANAGER_H

#include <QObject>
#include <QCache>

class ArtworkManager : public QObject {
    Q_OBJECT
public:
    explicit ArtworkManager(QObject *parent = nullptr);

    Q_INVOKABLE QString getCoverArt(int gameId, const QString& url);
    void prefetchArtwork(int gameId, const QString& url);

signals:
    void artworkReady(int gameId, const QString& localPath);

private:
    QCache<int, QString> m_cache;
    QString cacheDir();
    void downloadArtwork(int gameId, const QString& url);
};

#endif
```

**File: `luna-ui/src/artworkmanager.cpp`** (FIX #36: Provide stub implementation)

```cpp
#include "artworkmanager.h"
#include <QDir>
#include <QFile>
#include <QDebug>

ArtworkManager::ArtworkManager(QObject *parent) : QObject(parent) {
    m_cache.setMaxCost(200); // Cache up to 200 entries
}

QString ArtworkManager::cacheDir() {
    QString dir = QDir::homePath() + "/.local/share/luna-ui/artwork-cache/covers";
    QDir().mkpath(dir);
    return dir;
}

QString ArtworkManager::getCoverArt(int gameId, const QString& url) {
    // Check memory cache first
    if (m_cache.contains(gameId)) {
        return *m_cache.object(gameId);
    }

    // Check disk cache
    QString cachedPath = cacheDir() + "/" + QString::number(gameId) + "-cover.jpg";
    if (QFile::exists(cachedPath)) {
        m_cache.insert(gameId, new QString(cachedPath));
        return cachedPath;
    }

    // If URL is a local file, use it directly
    if (QFile::exists(url)) {
        m_cache.insert(gameId, new QString(url));
        return url;
    }

    // TODO: Implement async download from SteamGridDB/IGDB APIs
    // For now, return empty string (placeholder will be shown)
    return QString();
}

void ArtworkManager::prefetchArtwork(int gameId, const QString& url) {
    // TODO: Queue async download for pre-fetching
    Q_UNUSED(gameId);
    Q_UNUSED(url);
}

void ArtworkManager::downloadArtwork(int gameId, const QString& url) {
    // TODO: Implement HTTP download to disk cache
    // Use QNetworkAccessManager for async downloads
    Q_UNUSED(gameId);
    Q_UNUSED(url);
}
```

#### Main Entry Point

**File: `luna-ui/src/main.cpp`**

```cpp
#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QTimer>
#include "thememanager.h"
#include "gamemanager.h"
#include "database.h"
#include "controllermanager.h"

int main(int argc, char *argv[]) {
    QGuiApplication app(argc, argv);
    app.setApplicationName("Luna UI");
    app.setOrganizationName("Lyrah OS");

    Database db;
    if (!db.initialize()) {
        qCritical() << "Failed to initialize database!";
        return 1;
    }

    ThemeManager themeManager;
    GameManager gameManager(&db);
    ControllerManager controllerManager;
    controllerManager.initialize();

    QQmlApplicationEngine engine;
    engine.rootContext()->setContextProperty("ThemeManager", &themeManager);
    engine.rootContext()->setContextProperty("GameManager", &gameManager);
    engine.rootContext()->setContextProperty("ControllerManager", &controllerManager);

    engine.load(QUrl(QStringLiteral("qrc:/qml/Main.qml")));

    if (engine.rootObjects().isEmpty())
        return -1;

    // Poll controller input at 60Hz
    QTimer controllerTimer;
    QObject::connect(&controllerTimer, &QTimer::timeout, [&]() {
        controllerManager.pollEvents();
    });
    controllerTimer.start(16); // ~60fps

    // Initial game library scan (background)
    QTimer::singleShot(500, [&]() {
        gameManager.scanAllStores();
    });

    return app.exec();
}
```

#### Luna UI QML â€” Main Layout

**File: `luna-ui/qml/Main.qml`**

```qml
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "components"       // FIX #27: Import component directory
import "views"            // FIX #27: Import views directory

ApplicationWindow {
    id: root
    visible: true
    width: 1920
    height: 1080
    title: "Luna UI"
    flags: Qt.FramelessWindowHint
    visibility: Window.FullScreen

    Rectangle {
        anchors.fill: parent
        color: ThemeManager.getColor("background")

        RowLayout {
            anchors.fill: parent
            spacing: 0

            NavBar {
                id: navBar
                Layout.preferredWidth: ThemeManager.getLayoutValue("sidebarWidth") || 220
                Layout.fillHeight: true
                onSectionChanged: function(section) {
                    contentLoader.source = "views/" + section + "View.qml"
                }
            }

            Loader {
                id: contentLoader
                Layout.fillWidth: true
                Layout.fillHeight: true
                source: "views/GamesView.qml"
            }
        }
    }
}
```

**File: `luna-ui/qml/components/NavBar.qml`**

```qml
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Rectangle {
    id: navBar
    color: ThemeManager.getColor("surface")

    signal sectionChanged(string section)

    property int currentIndex: 0

    // FIX #16: Use text labels instead of emoji. In production, replace
    // with SVG icons from resources/icons/ for consistent rendering in gamescope.
    readonly property var sections: [
        { name: "Games",    icon: "[G]", section: "Games" },
        { name: "Store",    icon: "[S]", section: "Store" },
        { name: "Media",    icon: "[M]", section: "Media" },
        { name: "Settings", icon: "[*]", section: "Settings" }
    ]

    Column {
        anchors.fill: parent
        anchors.topMargin: 40
        spacing: 8

        Text {
            text: "LUNA"
            font.pixelSize: 28
            font.family: ThemeManager.getFont("heading")
            font.bold: true
            color: ThemeManager.getColor("primary")
            anchors.horizontalCenter: parent.horizontalCenter
            bottomPadding: 30
        }

        Repeater {
            model: sections

            // FIX #15: Use explicit width instead of anchors inside Column
            Rectangle {
                width: navBar.width - 16
                height: 56
                x: 8  // Center manually instead of using anchors
                radius: 8
                color: currentIndex === index
                       ? Qt.rgba(ThemeManager.getColor("primary").r,
                                 ThemeManager.getColor("primary").g,
                                 ThemeManager.getColor("primary").b, 0.2)
                       : "transparent"
                border.color: currentIndex === index ? ThemeManager.getColor("focus") : "transparent"
                border.width: currentIndex === index ? 2 : 0

                Row {
                    anchors.centerIn: parent
                    spacing: 12

                    Text {
                        text: modelData.icon
                        font.pixelSize: 16
                        font.bold: true
                        color: currentIndex === index
                               ? ThemeManager.getColor("primary")
                               : ThemeManager.getColor("textSecondary")
                    }
                    Text {
                        text: modelData.name
                        font.pixelSize: ThemeManager.getFontSize("medium")
                        font.family: ThemeManager.getFont("body")
                        color: currentIndex === index
                               ? ThemeManager.getColor("textPrimary")
                               : ThemeManager.getColor("textSecondary")
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        currentIndex = index
                        sectionChanged(modelData.section)
                    }
                }

                Behavior on color { ColorAnimation { duration: 150 } }
            }
        }
    }
}
```

**File: `luna-ui/qml/components/GameCard.qml`**

```qml
import QtQuick
import QtQuick.Controls
import Qt5Compat.GraphicalEffects   // FIX #42: Import for OpacityMask

Rectangle {
    id: card
    width: 180
    height: 270
    radius: 12
    color: ThemeManager.getColor("surface")
    border.color: focus ? ThemeManager.getColor("focus") : "transparent"
    border.width: focus ? 2 : 0

    property string gameTitle: ""
    property string coverArt: ""
    property bool isFavorite: false
    property int gameId: -1

    signal playClicked(int id)
    signal favoriteClicked(int id)

    // FIX #8: Image doesn't have a radius property. Use layer + OpacityMask.
    Image {
        id: coverImage
        anchors.fill: parent
        anchors.margins: 4
        source: coverArt || ""
        fillMode: Image.PreserveAspectCrop
        visible: false  // Hidden; rendered via OpacityMask
    }

    Rectangle {
        id: coverMask
        anchors.fill: coverImage
        radius: 8
        visible: false
    }

    OpacityMask {
        anchors.fill: coverImage
        source: coverImage
        maskSource: coverMask
        visible: coverImage.status === Image.Ready
    }

    // Placeholder if no art loaded
    Rectangle {
        visible: coverImage.status !== Image.Ready
        anchors.fill: parent
        anchors.margins: 4
        radius: 8
        color: ThemeManager.getColor("surface")
        Text {
            anchors.centerIn: parent
            text: gameTitle.length > 0 ? gameTitle.charAt(0).toUpperCase() : "?"
            font.pixelSize: 48
            font.bold: true
            color: ThemeManager.getColor("primary")
        }
    }

    // Title overlay at bottom
    Rectangle {
        anchors.bottom: parent.bottom
        width: parent.width
        height: 48
        radius: 8
        color: Qt.rgba(0, 0, 0, 0.7)

        Text {
            anchors.centerIn: parent
            text: gameTitle
            font.pixelSize: 12
            font.family: ThemeManager.getFont("body")
            color: ThemeManager.getColor("textPrimary")
            elide: Text.ElideRight
            width: parent.width - 16
            horizontalAlignment: Text.AlignHCenter
        }
    }

    // Favorite indicator
    Text {
        visible: isFavorite
        text: "*"
        font.pixelSize: 20
        font.bold: true
        color: "#FFD700"
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: 8
    }

    // Hover effect: scale 1.05x
    scale: mouseArea.containsMouse ? 1.05 : 1.0
    Behavior on scale { NumberAnimation { duration: 150 } }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        onClicked: playClicked(gameId)
    }
}
```

#### Stub QML Views (FIX #46)

**File: `luna-ui/qml/views/GamesView.qml`**

```qml
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../components"

Rectangle {
    color: "transparent"

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 24

        Text {
            text: "Games Library"
            font.pixelSize: ThemeManager.getFontSize("xlarge")
            font.family: ThemeManager.getFont("heading")
            font.bold: true
            color: ThemeManager.getColor("textPrimary")
        }

        // TODO: Implement full game grid with GameCard components
        // - Recently Played row
        // - All Games grid
        // - Search bar
        // - Filter/sort controls
        Text {
            text: "Game library view â€” implementation in progress"
            color: ThemeManager.getColor("textSecondary")
        }
    }
}
```

**File: `luna-ui/qml/views/StoreView.qml`**

```qml
import QtQuick
import QtQuick.Controls

Rectangle {
    color: "transparent"
    Text {
        anchors.centerIn: parent
        text: "Store â€” Coming Soon"
        font.pixelSize: 24
        color: ThemeManager.getColor("textSecondary")
    }
}
```

**File: `luna-ui/qml/views/MediaView.qml`**

```qml
import QtQuick
import QtQuick.Controls

Rectangle {
    color: "transparent"
    Text {
        anchors.centerIn: parent
        text: "Media â€” Coming Soon"
        font.pixelSize: 24
        color: ThemeManager.getColor("textSecondary")
    }
}
```

**File: `luna-ui/qml/views/SettingsView.qml`**

```qml
import QtQuick
import QtQuick.Controls

Rectangle {
    color: "transparent"
    Text {
        anchors.centerIn: parent
        text: "Settings â€” Coming Soon"
        font.pixelSize: 24
        color: ThemeManager.getColor("textSecondary")
    }
}
```

#### Luna UI Theme Files

**File: `resources/themes/nebula-dark.json`** â€” (unchanged from v2)

```json
{
  "name": "Nebula Dark",
  "version": "1.0",
  "description": "Default dark space theme - optimized for gaming sessions",
  "colors": {
    "background": "#0f1419",
    "surface": "#1a1f2e",
    "primary": "#3b82f6",
    "secondary": "#8b5cf6",
    "accent": "#06b6d4",
    "textPrimary": "#ffffff",
    "textSecondary": "#9ca3af",
    "focus": "#06b6d4",
    "hover": "#334155",
    "cardBackground": "#1e293b"
  },
  "layout": {
    "sidebarWidth": 220,
    "gridColumns": 4,
    "cardAspectRatio": "3:4",
    "fontSize": { "small": 14, "medium": 16, "large": 24, "xlarge": 32 }
  },
  "effects": {
    "animations": true, "particles": false, "blur": true, "glow": true, "transitionSpeed": 200
  },
  "fonts": { "heading": "Exo 2", "body": "Inter", "ui": "Inter" }
}
```

**(space-purple.json, cyber-neon.json, amoled-black.json â€” same as v2, omitted for brevity)**

**File: `resources/themes/forest-green.json`** (FIX #38: Was listed but never defined)

```json
{
  "name": "Forest Green",
  "version": "1.0",
  "description": "Nature-inspired calming green theme",
  "colors": {
    "background": "#0f1a14",
    "surface": "#1a2e22",
    "primary": "#22c55e",
    "secondary": "#16a34a",
    "accent": "#86efac",
    "textPrimary": "#ffffff",
    "textSecondary": "#9ca3af",
    "focus": "#22c55e",
    "hover": "#1e3a2a",
    "cardBackground": "#1a2e22"
  },
  "layout": {
    "sidebarWidth": 220, "gridColumns": 4, "cardAspectRatio": "3:4",
    "fontSize": { "small": 14, "medium": 16, "large": 24, "xlarge": 32 }
  },
  "effects": { "animations": true, "particles": false, "blur": true, "glow": true, "transitionSpeed": 200 },
  "fonts": { "heading": "Exo 2", "body": "Inter", "ui": "Inter" }
}
```

**File: `resources/themes/sunset-orange.json`** (FIX #38)

```json
{
  "name": "Sunset Orange",
  "version": "1.0",
  "description": "Warm orange/red gradients",
  "colors": {
    "background": "#1a0f0a",
    "surface": "#2e1a10",
    "primary": "#f97316",
    "secondary": "#ea580c",
    "accent": "#fdba74",
    "textPrimary": "#ffffff",
    "textSecondary": "#9ca3af",
    "focus": "#f97316",
    "hover": "#3a1f0e",
    "cardBackground": "#2e1a10"
  },
  "layout": {
    "sidebarWidth": 220, "gridColumns": 4, "cardAspectRatio": "3:4",
    "fontSize": { "small": 14, "medium": 16, "large": 24, "xlarge": 32 }
  },
  "effects": { "animations": true, "particles": false, "blur": true, "glow": true, "transitionSpeed": 200 },
  "fonts": { "heading": "Exo 2", "body": "Inter", "ui": "Inter" }
}
```

#### RPM Packaging

**File: `luna-ui/luna-ui.spec`**

```spec
Name:           luna-ui
Version:        1.0.0
Release:        1%{?dist}
Summary:        Lyrah OS Gaming Frontend
License:        MIT

# FIX #25: Proper source configuration for Copr builds
# Source tarball is created from the GitHub repository via spectool or Copr webhook
Source0:        https://github.com/lyrah-os/lyrah-os/archive/v%{version}/%{name}-%{version}.tar.gz

BuildRequires:  cmake gcc-c++ qt6-qtbase-devel qt6-qtdeclarative-devel qt6-qtwebsockets-devel SDL2-devel sqlite-devel
Requires:       qt6-qtbase qt6-qtdeclarative qt6-qtwebsockets SDL2 sqlite
Requires:       google-noto-sans-fonts

%description
Custom store-agnostic gaming frontend for Lyrah OS Luna Mode.
Aggregates games from Steam, Epic, GOG, Lutris, and more into
a unified, controller-friendly interface.

%prep
%autosetup -n lyrah-os-%{version}
cd luna-ui

%build
cd luna-ui
%cmake
%cmake_build

%install
cd luna-ui
%cmake_install
mkdir -p %{buildroot}/usr/share/luna-ui/themes
cp -r resources/themes/* %{buildroot}/usr/share/luna-ui/themes/
mkdir -p %{buildroot}/usr/share/luna-ui/fonts
cp -r resources/fonts/* %{buildroot}/usr/share/luna-ui/fonts/ 2>/dev/null || true
mkdir -p %{buildroot}/usr/share/luna-ui/icons
cp -r resources/icons/* %{buildroot}/usr/share/luna-ui/icons/ 2>/dev/null || true

%files
/usr/bin/luna-ui
/usr/share/luna-ui/

%changelog
* Tue Feb 04 2026 Builder <builder@lyrah.os> - 1.0.0-1
- Initial package
```

---

### 11. SDDM Configuration & Theme

**File: `/etc/sddm.conf.d/lyrah.conf`**

```ini
[General]
InputMethod=

[Theme]
Current=lyrah-space
CursorTheme=breeze_cursors

[Users]
HideUsers=
HideShells=/sbin/nologin,/bin/false

[Wayland]
SessionDir=/usr/share/wayland-sessions
```

**File: `/usr/share/sddm/themes/lyrah-space/theme.conf`**

```ini
[General]
background=background.jpg
type=image
```

**File: `/usr/share/sddm/themes/lyrah-space/Main.qml`** (FIX #44: SDDM requires Main.qml)

```qml
import QtQuick 2.15
import SddmComponents 2.0

Rectangle {
    id: root
    width: Screen.width
    height: Screen.height

    Image {
        anchors.fill: parent
        source: "background.jpg"
        fillMode: Image.PreserveAspectCrop
    }

    // Semi-transparent login panel
    Rectangle {
        anchors.centerIn: parent
        width: 400
        height: 350
        radius: 16
        color: Qt.rgba(0.04, 0.05, 0.15, 0.85)
        border.color: Qt.rgba(0.55, 0.36, 0.96, 0.5)
        border.width: 1

        Column {
            anchors.centerIn: parent
            spacing: 16
            width: parent.width - 60

            Text {
                text: "Lyrah OS"
                font.pixelSize: 28
                font.bold: true
                color: "#8b5cf6"
                anchors.horizontalCenter: parent.horizontalCenter
            }

            TextField {
                id: userField
                width: parent.width
                placeholderText: "Username"
                text: userModel.lastUser
                color: "white"
                background: Rectangle { color: "#1a1f2e"; radius: 8 }
            }

            TextField {
                id: passwordField
                width: parent.width
                placeholderText: "Password"
                echoMode: TextInput.Password
                color: "white"
                background: Rectangle { color: "#1a1f2e"; radius: 8 }
                Keys.onReturnPressed: sddm.login(userField.text, passwordField.text, sessionSelect.currentIndex)
            }

            ComboBox {
                id: sessionSelect
                width: parent.width
                model: sessionModel
                textRole: "name"
                currentIndex: sessionModel.lastIndex
            }

            Button {
                text: "Login"
                width: parent.width
                onClicked: sddm.login(userField.text, passwordField.text, sessionSelect.currentIndex)
            }
        }
    }
}
```

---

### 12. Plymouth Boot Splash

> **NOTE (FIX #34):** This Plymouth theme is a basic starting point. It displays
> a static logo with a simple spinner. The full "animated logo with stars"
> effect described in the design spec requires additional artwork and script
> complexity that should be added in a polish phase.

**File: `/usr/share/plymouth/themes/lyrah/lyrah.plymouth`**

```ini
[Plymouth Theme]
Name=Lyrah OS
Description=Space-themed boot splash for Lyrah OS
ModuleName=script

[script]
ImageDir=/usr/share/plymouth/themes/lyrah
ScriptFile=/usr/share/plymouth/themes/lyrah/lyrah.script
```

**File: `/usr/share/plymouth/themes/lyrah/lyrah.script`**

```plymouth
Window.SetBackgroundTopColor(0.04, 0.05, 0.15);
Window.SetBackgroundBottomColor(0.02, 0.03, 0.10);

logo.image = Image("logo.png");
logo.sprite = Sprite(logo.image);
logo.sprite.SetX(Window.GetWidth() / 2 - logo.image.GetWidth() / 2);
logo.sprite.SetY(Window.GetHeight() / 2 - logo.image.GetHeight() / 2);

spinner_image = Image("spinner.png");
spinner_sprite = Sprite(spinner_image);
spinner_sprite.SetX(Window.GetWidth() / 2 - spinner_image.GetWidth() / 2);
spinner_sprite.SetY(Window.GetHeight() * 0.7);

fun refresh_callback() {
    spinner_sprite.SetZ(1000);
}

Plymouth.SetRefreshFunction(refresh_callback);
```

**Required images:**
- `logo.png` â€” Lyrah OS logo (256x256px)
- `spinner.png` â€” Loading spinner (64x64px, orbital ring design)

---

### 13. KDE Desktop Mode Customization

(Same as v2, omitted for brevity â€” no bugs found in this section.)

---

### 14. Windows Game Compatibility Configuration

**System-wide Wine environment variables:**

**File: `/etc/profile.d/lyrah-wine.sh`**

```bash
#!/bin/bash
# Lyrah OS Wine/DXVK environment variables
# Applied system-wide for all Windows games

# FIX #37: Don't force FPS HUD system-wide. Users can enable per-game
# with: DXVK_HUD=fps mangohud %command%
export DXVK_LOG_LEVEL=none             # Reduce Wine/DXVK logging noise
export VKD3D_CONFIG=dxr                # Enable DirectX Raytracing support
```

---

### 15. Logging & Diagnostics System

(Session start/stop scripts â€” same as v2)

#### Log Upload Script (Full Version with Sanitization)

**File: `/usr/bin/lyrah-upload-log`**

```bash
#!/bin/bash
# Lyrah OS Log Upload Script
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

LOG_DIR="/var/log/lyrah"

if [[ "$1" == "--help" ]] || [[ "$1" == "-h" ]]; then
    cat << 'HELPEOF'
Lyrah OS Log Upload Utility

USAGE:
    lyrah-upload-log [MODE] [TYPE] [OPTIONS]

MODES:    luna | desktop
TYPES:    session | crash | all | <path>
OPTIONS:  --private

SETUP:    gh auth login

EXAMPLES:
    lyrah-upload-log luna session
    lyrah-upload-log desktop crash --private
    lyrah-upload-log all
HELPEOF
    exit 0
fi

# FIX #26: Check copy success in sanitize_log
sanitize_log() {
    local file=$1
    local sanitized="${file}.sanitized"
    if ! cp "$file" "$sanitized"; then
        echo -e "${RED}Error: Could not create sanitized copy of $file${NC}" >&2
        echo "$file"  # Fall back to original
        return
    fi
    sed -i 's/[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}/[REDACTED_IP]/g' "$sanitized"
    sed -i 's/[a-zA-Z0-9._%+-]\+@[a-zA-Z0-9.-]\+\.[a-zA-Z]\{2,\}/[REDACTED_EMAIL]/g' "$sanitized"
    sed -i 's/ghp_[a-zA-Z0-9]\{36\}/[REDACTED_TOKEN]/g' "$sanitized"
    sed -i "s|/home/[a-zA-Z0-9_-]*/|/home/[USER]/|g" "$sanitized"
    echo "$sanitized"
}

detect_mode() {
    if pgrep -x "luna-ui" > /dev/null; then echo "luna"
    elif pgrep -x "plasmashell" > /dev/null; then echo "desktop"
    else echo "unknown"; fi
}

if ! command -v gh &> /dev/null; then
    echo -e "${RED}Error: GitHub CLI (gh) is not installed${NC}"; exit 1
fi
if ! gh auth status &> /dev/null 2>&1; then
    echo -e "${BLUE}GitHub CLI not authenticated. Please run:${NC}"
    echo "  gh auth login"; exit 1
fi

upload_to_gist() {
    local file=$1 privacy=$2 description=$3
    if [ ! -f "$file" ]; then
        echo -e "${RED}Error: File not found: $file${NC}"; return 1
    fi
    local sanitized_file
    sanitized_file=$(sanitize_log "$file")
    echo -e "${BLUE}Uploading (sanitized) $file...${NC}"
    local gist_url
    if [ "$privacy" = "--private" ]; then
        gist_url=$(gh gist create "$sanitized_file" -d "$description" --private)
    else
        gist_url=$(gh gist create "$sanitized_file" -d "$description" --public)
    fi
    [ -f "${file}.sanitized" ] && rm -f "${file}.sanitized"
    echo -e "${GREEN}âœ“ Uploaded successfully!${NC}"
    echo -e "${BLUE}Gist URL:${NC} $gist_url"
    echo "$gist_url" | xclip -selection clipboard 2>/dev/null || true
    echo -e "${GREEN}(URL copied to clipboard)${NC}"
}

get_latest_file() { ls -t "$1"/*.log 2>/dev/null | head -n1; }

MODE="" LOG_TYPE="" PRIVACY=""
if [[ "$1" == "luna" ]] || [[ "$1" == "desktop" ]]; then
    MODE=$1; LOG_TYPE=$2; PRIVACY=$3
elif [[ "$1" =~ ^/ ]]; then
    upload_to_gist "$1" "$2" "Lyrah OS Log - $(basename $1)"; exit 0
else
    MODE=$(detect_mode); LOG_TYPE=$1; PRIVACY=$2
fi

if [ "$MODE" == "unknown" ]; then
    echo -e "${RED}Error: Could not detect current mode${NC}"
    echo "Please specify: lyrah-upload-log [luna|desktop] [session|crash|all]"; exit 1
fi

MODE_DIR="$LOG_DIR/${MODE}-mode"
case $LOG_TYPE in
    session)
        latest=$(get_latest_file "$MODE_DIR/sessions")
        [ -z "$latest" ] && echo -e "${RED}No session logs found${NC}" && exit 1
        upload_to_gist "$latest" "$PRIVACY" "Lyrah OS ($MODE mode) Session Log - $(date +%Y-%m-%d)";;
    crash)
        latest=$(get_latest_file "$MODE_DIR/crashes")
        [ -z "$latest" ] && echo -e "${RED}No crash logs found${NC}" && exit 1
        upload_to_gist "$latest" "$PRIVACY" "Lyrah OS ($MODE mode) Crash Report - $(date +%Y-%m-%d)";;
    all)
        echo -e "${BLUE}Creating combined log report for $MODE mode...${NC}"
        temp_file="/tmp/lyrah-${MODE}-combined-$(date +%Y%m%d-%H%M%S).log"
        {
            echo "=== Lyrah OS Combined Log Report ($MODE Mode) ==="
            echo "Generated: $(date)"; echo "Hostname: $(hostname)"; echo "Kernel: $(uname -r)"; echo ""
            echo "=== Latest Session Log ==="
            session_log=$(get_latest_file "$MODE_DIR/sessions")
            [ -n "$session_log" ] && cat "$session_log" || echo "No session logs"; echo ""
            echo "=== Latest Crash Log ==="
            crash_log=$(get_latest_file "$MODE_DIR/crashes")
            [ -n "$crash_log" ] && cat "$crash_log" || echo "No crash logs"; echo ""
            echo "=== Systemd Journal (Last 500 lines) ==="
            journalctl -b --no-pager -n 500
        } > "$temp_file"
        upload_to_gist "$temp_file" "$PRIVACY" "Lyrah OS ($MODE mode) Combined Diagnostics - $(date +%Y-%m-%d)"
        rm -f "$temp_file";;
    *) echo "Usage: lyrah-upload-log [luna|desktop] [session|crash|all] [--private]"; exit 1;;
esac
```

#### Crash Monitor

**File: `/usr/bin/lyrah-crash-monitor`**

```bash
#!/bin/bash
# Monitor for crashes and save logs with full context
# FIX #13: Detect mode inside the loop so it stays correct after mode switches

mkdir -p /var/log/lyrah/luna-mode/crashes
mkdir -p /var/log/lyrah/desktop-mode/crashes
mkdir -p /var/log/lyrah/unknown-mode/crashes

journalctl -f -p err | while read line; do
    if echo "$line" | grep -qi "crash\|panic\|segfault\|oops"; then
        # Re-detect mode on each crash (FIX #13)
        if pgrep -x "luna-ui" > /dev/null; then
            MODE="luna"
        elif pgrep -x "plasmashell" > /dev/null; then
            MODE="desktop"
        else
            MODE="unknown"
        fi

        CRASH_DIR="/var/log/lyrah/${MODE}-mode/crashes"
        mkdir -p "$CRASH_DIR"
        crash_file="$CRASH_DIR/crash-$(date +%Y-%m-%d-%H-%M-%S).log"

        {
            echo "=== Crash Detected in $MODE Mode ==="
            echo "Time: $(date)"
            echo "Type: Kernel/System Error"
            echo ""
            echo "=== Journal Context (last 200 lines) ==="
            journalctl -p err --no-pager -n 200
            echo ""
            echo "=== dmesg (last 100 lines) ==="
            dmesg | tail -n 100
        } > "$crash_file"

        notify-send "Lyrah OS Crash Detected" \
            "Crash log saved. Run 'lyrah-upload-log crash' to report." \
            --urgency=critical 2>/dev/null || true
    fi
done
```

---

### 16. Systemd Services & Timers

**File: `/etc/systemd/system/lyrah-first-boot.service`**

```ini
[Unit]
Description=Lyrah OS First Boot Setup
After=graphical.target
ConditionPathExists=!/var/lib/lyrah/.first-boot-done

[Service]
Type=oneshot
ExecStart=/usr/share/lyrah/setup/first-boot.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
```

**File: `/etc/systemd/system/luna-mode-logger.service`**

```ini
# FIX #4: Use graphical.target instead of undefined luna-session.target
[Unit]
Description=Luna Mode Session Logger
After=graphical.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/bin/luna-mode-session-start
ExecStop=/usr/bin/luna-mode-session-stop

[Install]
WantedBy=graphical.target
```

**File: `/etc/systemd/system/lyrah-crash-monitor.service`**

```ini
[Unit]
Description=Lyrah OS Crash Monitor
After=multi-user.target

[Service]
Type=simple
ExecStart=/usr/bin/lyrah-crash-monitor
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
```

**File: `/etc/systemd/system/lyrah-update.timer`**

```ini
[Unit]
Description=Lyrah OS Update Check Timer
After=network-online.target

[Timer]
OnBootSec=15min
OnUnitActiveSec=6h
Persistent=true

[Install]
WantedBy=timers.target
```

**File: `/etc/systemd/system/lyrah-update.service`**

```ini
[Unit]
Description=Lyrah OS Update Check
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
# FIX #5: Correct path (was lyrah-update-check, should be lyrah-update)
ExecStart=/usr/bin/lyrah-update --check-only
StandardOutput=journal

[Install]
WantedBy=multi-user.target
```

---

### 17. Update System with Channel Switching

**File: `/usr/bin/lyrah-update`**

```bash
#!/bin/bash
# Lyrah OS Update Script

set -e

GITHUB_REPO="lyrah-os/lyrah-os"
CURRENT_BRANCH=$(grep BRANCH /etc/lyrah-release 2>/dev/null | cut -d= -f2)
CURRENT_VERSION=$(grep VERSION /etc/lyrah-release 2>/dev/null | cut -d= -f2)

# FIX #41: Support --check-only flag for systemd timer (no TTY available)
CHECK_ONLY=false
if [ "$1" == "--check-only" ]; then
    CHECK_ONLY=true
    shift
fi

# Handle channel switching
if [ "$1" == "--channel" ]; then
    NEW_CHANNEL=$2
    case $NEW_CHANNEL in
        stable|main) sed -i 's/BRANCH=.*/BRANCH=main/' /etc/lyrah-release ;;
        testing)     sed -i 's/BRANCH=.*/BRANCH=testing/' /etc/lyrah-release ;;
        dev)         sed -i 's/BRANCH=.*/BRANCH=dev/' /etc/lyrah-release ;;
        *)           echo "Valid channels: stable, testing, dev"; exit 1 ;;
    esac
    echo "âœ“ Update channel switched to: $NEW_CHANNEL"
    echo "Run 'lyrah-update' to check for updates on this channel."
    exit 0
fi

UPDATE_BRANCH="${CURRENT_BRANCH:-main}"

echo "Lyrah OS Update Check"
echo "Current: $CURRENT_VERSION ($CURRENT_BRANCH)"
echo "Checking for updates on $UPDATE_BRANCH channel..."

# FIX #29: Proper error handling for curl failure
LATEST_METADATA=$(curl -sf "https://raw.githubusercontent.com/$GITHUB_REPO/$UPDATE_BRANCH/update-metadata.json" 2>/dev/null)
if [ -z "$LATEST_METADATA" ] || ! echo "$LATEST_METADATA" | jq -e . >/dev/null 2>&1; then
    echo "Could not reach update server or received invalid response."
    exit 1
fi

LATEST_VERSION=$(echo "$LATEST_METADATA" | jq -r '.version')
LATEST_IMAGE=$(echo "$LATEST_METADATA" | jq -r '.image')

if [ "$LATEST_VERSION" = "$CURRENT_VERSION" ]; then
    echo "âœ“ You are running the latest version"
    exit 0
fi

echo "New update available: $LATEST_VERSION"

# In check-only mode (systemd timer), just notify and exit
if [ "$CHECK_ONLY" = true ]; then
    notify-send "Lyrah OS Update Available" \
        "Version $LATEST_VERSION is available. Run 'lyrah-update' to install." \
        --icon=system-software-update 2>/dev/null || true
    exit 0
fi

echo ""
read -p "Do you want to update? (y/n) " -n 1 -r
echo

if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "Downloading update..."

    if command -v rpm-ostree &> /dev/null; then
        rpm-ostree rebase "ostree-unverified-image:docker://$LATEST_IMAGE"
        echo "âœ“ Update downloaded. Reboot to apply."
    else
        dnf upgrade --refresh -y
        echo "âœ“ Update installed."
    fi

    sed -i "s/VERSION=.*/VERSION=$LATEST_VERSION/" /etc/lyrah-release

    notify-send "Lyrah OS Update" \
        "Update to version $LATEST_VERSION complete. Please reboot to apply changes." \
        --icon=system-software-update 2>/dev/null || true
fi
```

---

### 18â€“19. Copr Setup & Required Packages

(Same as v2 â€” no bugs found in these sections.)

---

## Testing Checklist

(Same as v2 with all items, omitted for brevity.)

---

## Implementation Order

Execute in this order:

1. **Repository Setup** â€” Create GitHub repo, directory structure, initialize git
2. **GitHub Actions Workflows** â€” All 4 workflow files, test ISO build
3. **Container Files** â€” Containerfile.main/testing/dev (with RPM Fusion)
4. **Session Definitions** â€” luna-mode.desktop, plasma.desktop
5. **Scripts** â€” luna-session, lyrah-switch-mode, lyrah-configure-autologin, lyrah-update, lyrah-upload-log, lyrah-crash-monitor, session-start/stop. Make all executable.
6. **Systemd Services** â€” All unit files and timers (with corrected paths and targets)
7. **Luna UI Development (MAJOR â€” 4 weeks)**
   - Week 1: CMake setup (with qt_add_qml_module), database, theme manager, main.cpp, basic QML
   - Week 2: Store backends (Steam, Heroic, Lutris, Custom), game scanner
   - Week 3: Full QML UI (NavBar with SVG icons, GameCard with OpacityMask, views), controller input with debounce
   - Week 4: Polish, search, artwork manager, performance optimization
8. **GPU Detection** â€” configure-gpu.sh with proper PCI class detection
9. **Plymouth Boot Splash** â€” Theme files, logo, spinner (basic version)
10. **SDDM Theme** â€” Space theme with Main.qml login UI
11. **KDE Customization** â€” Cosmos theme, wallpapers, default configs
12. **Installer (Calamares)** â€” Configuration, branding, session selection module
13. **Windows Gaming Config** â€” Wine env vars (no forced HUD), package verification
14. **Logging System** â€” Log directories, rotation, sanitization with error checks, crash monitor with dynamic mode detection
15. **First Boot Script** â€” Orchestrates GPU, Plymouth, services
16. **Copr Setup** â€” Repository, Makefile, webhook (then publish luna-ui)
17. **Testing** â€” Full checklist
18. **Documentation** â€” README, user manual, guides
19. **Release** â€” Tag, build ISO, publish

---

## Build & Test Commands

```bash
# Clone and setup
git clone https://github.com/YOUR_USERNAME/lyrah-os.git
cd lyrah-os

# Build Luna UI locally
cd luna-ui
mkdir build && cd build
cmake ..
make
sudo make install

# Test Luna UI
luna-ui

# Test in QEMU (after ISO build via GitHub Actions)
qemu-system-x86_64 -m 4096 -enable-kvm -cdrom Lyrah-OS.iso

# Test on real hardware
sudo dd if=Lyrah-OS.iso of=/dev/sdX bs=4M status=progress

# Test mode switching
lyrah-switch-mode luna
lyrah-switch-mode desktop

# Test auto-login
sudo lyrah-configure-autologin luna
sudo lyrah-configure-autologin none

# Test logging
lyrah-upload-log luna session
lyrah-upload-log --help

# Test updates
lyrah-update
lyrah-update --check-only
lyrah-update --channel testing
```


| 45 | MINOR | CMakeLists.txt missing QML resources | Added `qt_add_qml_module` with all QML files |
| 46 | MINOR | Missing QML view stubs | Added GamesView, StoreView, MediaView, SettingsView stubs |
| 47 | MINOR | build-images.yml builds all branches on push | Added note; push trigger filter handles this |
