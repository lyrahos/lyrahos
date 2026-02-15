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

    // Unique index on store_source + app_id to prevent duplicate entries
    query.exec("CREATE UNIQUE INDEX IF NOT EXISTS idx_games_store_app "
               "ON games(store_source, app_id)");

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

    // Migration: clear stale steam://install/ launch commands.
    // These were set by the old install flow; installation is now handled
    // by steamcmd via GameManager::installGame(), not via launch_command.
    query.exec("UPDATE games SET launch_command = '' "
               "WHERE store_source = 'steam' AND is_installed = 0 "
               "AND launch_command LIKE 'steam steam://install/%'");

    // Migration: fix games hidden by uninitialized isHidden garbage values.
    // The Game struct previously had uninitialized bool members, so games
    // added via the Steam API could have random non-zero is_hidden values.
    // There is no UI to hide games, so all hidden games are from this bug.
    query.exec("UPDATE games SET is_hidden = 0 WHERE is_hidden != 0");

    // Migration: add -silent flag to Steam launch commands so the Steam
    // client UI doesn't show when launching games.
    query.exec("UPDATE games SET launch_command = REPLACE(launch_command, "
               "'steam steam://rungameid/', 'steam -silent steam://rungameid/') "
               "WHERE launch_command LIKE 'steam steam://rungameid/%'");

    // Migration: add -nofriendsui -nochatui flags to suppress friends list
    // and chat windows that appear alongside game launches.
    query.exec("UPDATE games SET launch_command = REPLACE(launch_command, "
               "'steam -silent steam://rungameid/', "
               "'steam -silent -nofriendsui -nochatui steam://rungameid/') "
               "WHERE launch_command LIKE 'steam -silent steam://rungameid/%' "
               "AND launch_command NOT LIKE '%nofriendsui%'");

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

Game Database::getGameByStoreAndAppId(const QString& storeSource, const QString& appId) {
    QSqlQuery query;
    query.prepare("SELECT * FROM games WHERE store_source = ? AND app_id = ?");
    query.addBindValue(storeSource);
    query.addBindValue(appId);
    if (query.exec() && query.next()) {
        return gameFromQuery(query);
    }
    return Game{};
}

int Database::addOrUpdateGame(const Game& game) {
    Game existing = getGameByStoreAndAppId(game.storeSource, game.appId);
    if (existing.id > 0) {
        // Update existing game, but preserve user data (favorites, hidden, last_played)
        Game updated = game;
        updated.id = existing.id;
        updated.isFavorite = existing.isFavorite;
        updated.isHidden = existing.isHidden;
        if (existing.lastPlayed > 0) {
            updated.lastPlayed = existing.lastPlayed;
        }
        if (existing.playTimeHours > game.playTimeHours) {
            updated.playTimeHours = existing.playTimeHours;
        }
        updateGame(updated);
        return existing.id;
    }
    return addGame(game);
}

QVector<Game> Database::getAllGames() {
    // Show all owned games: installed first, then uninstalled, alphabetical within each group
    QSqlQuery query("SELECT * FROM games WHERE is_hidden = 0 ORDER BY is_installed DESC, title ASC");
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
