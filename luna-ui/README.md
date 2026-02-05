# Luna UI

Custom store-agnostic gaming frontend for Lyrah OS Luna Mode.

## Building

    mkdir build && cd build
    cmake ..
    make
    sudo make install

## Dependencies

- Qt 6 (Core, Gui, Quick, Sql)
- SDL2
- SQLite

## Features

- Unified game library from Steam, Epic, GOG, Lutris
- Controller-first navigation with SDL2
- JSON-based theme system with 6 built-in themes
- SQLite database with FTS5 full-text search
- Cover art caching
