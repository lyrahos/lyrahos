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
