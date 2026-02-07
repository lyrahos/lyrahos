#include "gamemanager.h"
#include "storebackends/steambackend.h"
#include "storebackends/heroicbackend.h"
#include "storebackends/lutrisbackend.h"
#include "storebackends/custombackend.h"
#include <QProcess>
#include <QDebug>
#include <QVariantMap>
#include <QDir>
#include <QFile>
#include <QStandardPaths>
#include <QCoreApplication>

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

void GameManager::executeCommand(const QString& program, const QStringList& args) {
    QProcess::startDetached(program, args);
}

bool GameManager::isSteamInstalled() {
    // Check if steam binary exists
    return !QStandardPaths::findExecutable("steam").isEmpty();
}

bool GameManager::isSteamAvailable() {
    // Steam is "available" if the user has logged in (library data exists)
    return QFile::exists(QDir::homePath() + "/.local/share/Steam/steamapps/libraryfolders.vdf");
}

void GameManager::launchSteam() {
    QProcess::startDetached("steam", QStringList());
}

void GameManager::launchSteamLogin() {
    // Launch Steam and poll for library data.
    // luna-ui's window will be hidden by QML so Steam is visible in gamescope.
    QProcess::startDetached("steam", QStringList());

    m_steamCheckCount = 0;
    if (m_steamCheckTimer) {
        m_steamCheckTimer->stop();
        m_steamCheckTimer->deleteLater();
    }
    m_steamCheckTimer = new QTimer(this);
    connect(m_steamCheckTimer, &QTimer::timeout, this, [this]() {
        m_steamCheckCount++;
        if (isSteamAvailable()) {
            m_steamCheckTimer->stop();
            m_steamCheckTimer->deleteLater();
            m_steamCheckTimer = nullptr;
            scanAllStores();
            emit steamLoginComplete(true);
        } else if (m_steamCheckCount > 90) {
            // 3s * 90 = ~4.5 min timeout — give up
            m_steamCheckTimer->stop();
            m_steamCheckTimer->deleteLater();
            m_steamCheckTimer = nullptr;
            emit steamLoginComplete(false);
        }
    });
    m_steamCheckTimer->start(3000);
}

void GameManager::switchToDesktop() {
    // Terminate the entire SDDM session so the login screen returns.
    // Qt.quit() alone isn't enough when running under kwin_wayland fallback
    // — kwin_wayland stays alive as an empty compositor (black screen + cursor).
    // loginctl terminate-session with XDG_SESSION_ID kills the whole chain.
    QByteArray sessionId = qgetenv("XDG_SESSION_ID");
    if (!sessionId.isEmpty()) {
        QProcess::startDetached("loginctl", {"terminate-session", QString::fromUtf8(sessionId)});
    } else {
        // Fallback: try killing by current session
        QProcess::startDetached("loginctl", {"terminate-session", ""});
    }
    // Also quit ourselves in case loginctl doesn't work
    QCoreApplication::quit();
}

int GameManager::getGameCount() {
    return m_db->getAllGames().size();
}
