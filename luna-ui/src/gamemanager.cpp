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
#include <QNetworkInterface>

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
    // Signal luna-session to launch Steam directly as gamescope's child.
    // We can't launch Steam from inside luna-ui because gamescope only
    // manages windows from its direct child process tree. By exiting
    // luna-ui and letting luna-session run "gamescope -- steam", Steam
    // gets full window management (just like SteamOS does it).
    // luna-session will restart luna-ui after Steam exits.
    QFile signal("/tmp/luna-launch-steam");
    signal.open(QIODevice::WriteOnly);
    signal.close();

    QCoreApplication::quit();
}

void GameManager::switchToDesktop() {
    // Write a signal file that luna-session checks after gamescope exits.
    // This tells the session script to exit immediately instead of retrying
    // gamescope (which would restart Luna Mode instead of returning to SDDM).
    // luna-session also handles killing kwin_wayland in the fallback case.
    QFile signal("/tmp/luna-switch-to-desktop");
    signal.open(QIODevice::WriteOnly);
    signal.close();

    QCoreApplication::quit();
}

int GameManager::getGameCount() {
    return m_db->getAllGames().size();
}

bool GameManager::isNetworkAvailable() {
    const auto interfaces = QNetworkInterface::allInterfaces();
    for (const auto &iface : interfaces) {
        if (iface.flags().testFlag(QNetworkInterface::IsUp) &&
            iface.flags().testFlag(QNetworkInterface::IsRunning) &&
            !iface.flags().testFlag(QNetworkInterface::IsLoopBack)) {
            const auto entries = iface.addressEntries();
            for (const auto &entry : entries) {
                if (entry.ip().protocol() == QAbstractSocket::IPv4Protocol &&
                    !entry.ip().isLoopback()) {
                    return true;
                }
            }
        }
    }
    return false;
}
