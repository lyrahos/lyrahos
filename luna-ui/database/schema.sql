-- Lyrah OS Luna UI Game Library & Controller Profile Database

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

-- ── Controller Profile System ──────────────────────────────────────────

CREATE TABLE IF NOT EXISTS controller_profiles (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,                  -- User-facing profile name
    scope TEXT NOT NULL,                 -- 'global', 'family', 'client', 'game'
    controller_family TEXT DEFAULT 'any', -- 'xbox', 'playstation', 'switch', 'luna', 'generic', 'any'
    client_id TEXT,                      -- 'steam', 'epic', 'gog', 'lutris', 'custom' (NULL for non-client)
    game_id INTEGER,                     -- FK to games(id) (NULL for non-game)
    is_default BOOLEAN DEFAULT 0,        -- Read-only built-in default
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_profile_scope
    ON controller_profiles(scope, controller_family, client_id, game_id);

CREATE TABLE IF NOT EXISTS controller_mappings (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    profile_id INTEGER NOT NULL,         -- FK to controller_profiles(id)
    physical_input TEXT NOT NULL,         -- SDL positional: 'button_south', 'trigger_left', etc.
    action TEXT NOT NULL,                 -- Semantic: 'confirm', 'back', 'navigate_up', etc.
    parameters TEXT,                      -- JSON: {"deadzone": 8000, "threshold": 16000}
    FOREIGN KEY (profile_id) REFERENCES controller_profiles(id) ON DELETE CASCADE
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_mapping_input
    ON controller_mappings(profile_id, physical_input);

-- ── Full-Text Search ──────────────────────────────────────────────────

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
