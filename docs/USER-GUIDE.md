# Lyrah OS User Guide

## Getting Started

### Installation
1. Download the ISO from GitHub Releases
2. Flash to USB: `sudo dd if=Lyrah-OS.iso of=/dev/sdX bs=4M status=progress`
3. Boot from USB and follow the Calamares installer

### First Boot
On first boot, Lyrah OS will:
- Detect your GPU and install appropriate drivers
- Set up the Plymouth boot splash
- Configure system services

## Using Luna Mode

Luna Mode provides a console-like gaming experience:
- Navigate with controller or keyboard
- Games from all stores appear in one unified library
- Games launch within gamescope for optimal performance

## Using Desktop Mode

Desktop Mode is a full KDE Plasma 6 desktop:
- Traditional desktop with windows, panels, and widgets
- Run games from Steam/Heroic/Lutris normally
- Full productivity environment

## Switching Modes

    # Switch to Luna Mode
    lyrah-switch-mode luna

    # Switch to Desktop Mode
    lyrah-switch-mode desktop

## Updating

    # Check for updates
    lyrah-update

    # Switch update channel
    lyrah-update --channel testing
    lyrah-update --channel stable

## Troubleshooting

### Upload logs for support

    lyrah-upload-log luna session
    lyrah-upload-log desktop crash
    lyrah-upload-log all
