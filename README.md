# Lyrah OS

A Fedora 42-based gaming Linux distribution with dual session modes.

## Features

- **Luna Mode** - Console-like gaming experience powered by gamescope + Luna UI
- **Desktop Mode** - Full KDE Plasma 6 desktop environment
- **Store Agnostic** - Play games from Steam, Epic, GOG, Lutris, and more
- **Windows Game Support** - Via Proton/Wine (same technology as Steam Deck)
- **Automatic Updates** - Three update channels: stable, testing, dev

## Architecture

Lyrah OS provides two completely separate session types:

- **Luna Mode**: gamescope compositor + Luna UI (no desktop environment)
- **Desktop Mode**: Full KDE Plasma 6 with KWin compositor

Only one session runs at a time. Switch between them with:

    lyrah-switch-mode luna
    lyrah-switch-mode desktop

## Building

### Build Luna UI locally

    cd luna-ui
    mkdir build && cd build
    cmake ..
    make
    sudo make install

### Build ISO via GitHub Actions
Push to the main/testing/dev branch to trigger an automatic ISO build.

## Update Channels

- **stable** (main branch) - Tested, production-ready releases
- **testing** - Beta features, pre-release testing
- **dev** - Latest development, may be unstable

Switch channels:

    lyrah-update --channel testing
    lyrah-update

## License

MIT License - See LICENSE file for details.
