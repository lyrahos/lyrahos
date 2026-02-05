# Luna UI API Documentation

## C++ Backend Classes

### Database
- `initialize()` - Open/create SQLite database
- `addGame(Game)` - Add game to library
- `updateGame(Game)` - Update game record
- `removeGame(id)` - Remove game
- `searchGames(query)` - Full-text search via FTS5

### GameManager (Q_INVOKABLE)
- `scanAllStores()` - Scan all store backends
- `launchGame(id)` - Launch game by ID
- `toggleFavorite(id)` - Toggle favorite status
- `getGames()` - Get all games as QVariantList
- `getRecentGames()` - Get recently played
- `getFavorites()` - Get favorites
- `search(query)` - Search games

### ThemeManager (Q_INVOKABLE)
- `loadTheme(name)` - Load theme by name
- `getColor(key)` - Get theme color
- `getFont(key)` - Get font family
- `getFontSize(key)` - Get font size
- `availableThemes()` - List all themes

### ControllerManager
- Emits signals for controller input (confirmPressed, backPressed, navigateUp, etc.)
- 200ms debounce on analog stick navigation
