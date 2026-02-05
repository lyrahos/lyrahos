# Luna UI Architecture

## Overview

Luna UI is a Qt6/QML application that serves as the gaming frontend for Lyrah OS Luna Mode.

## Components

    main.cpp          - Entry point, initializes all managers
    Database          - SQLite with FTS5 for game library
    GameManager       - Game launching, scanning, session tracking
    ThemeManager      - JSON-based theme system with live reload
    ControllerManager - SDL2 gamepad input with debounce
    ArtworkManager    - Cover art caching and downloading
    StoreBackends/    - Plugin system for game stores
      SteamBackend    - Steam library via VDF parsing
      HeroicBackend   - Epic/GOG via Heroic JSON files
      LutrisBackend   - Lutris via SQLite database
      CustomBackend   - User-added standalone games

## QML Structure

    Main.qml          - Root window with NavBar + content loader
    views/
      GamesView.qml   - Game library grid
      StoreView.qml   - Store browser (placeholder)
      MediaView.qml   - Media player (placeholder)
      SettingsView.qml - Settings (placeholder)
    components/
      NavBar.qml       - Side navigation
      GameCard.qml     - Game cover card with OpacityMask
      HeroSection.qml  - Featured game banner
      SearchBar.qml    - Search input
      GameDetailView.qml - Game detail page
