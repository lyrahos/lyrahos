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
#include <QUrlQuery>
#include <QFileSystemWatcher>
#include <QTextStream>
#include <QRegularExpression>

GameManager::GameManager(Database *db, QObject *parent)
    : QObject(parent), m_db(db) {
    registerBackends();

    m_processMonitor = new QTimer(this);
    connect(m_processMonitor, &QTimer::timeout, this, &GameManager::monitorGameProcess);

    m_networkManager = new QNetworkAccessManager(this);

    // Download progress monitor — polls .acf manifests every 2s
    m_downloadMonitor = new QTimer(this);
    connect(m_downloadMonitor, &QTimer::timeout, this, &GameManager::checkDownloadProgress);

    m_acfWatcher = new QFileSystemWatcher(this);
    // Watch steamapps dirs so we detect new .acf files appearing
    for (const QString& dir : getSteamAppsDirs()) {
        m_acfWatcher->addPath(dir);
    }
    connect(m_acfWatcher, &QFileSystemWatcher::directoryChanged, this, [this]() {
        // A new file appeared in steamapps — check progress immediately
        checkDownloadProgress();
    });
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
                m_db->addOrUpdateGame(game);
                totalFound++;
            }
        }
    }
    emit scanComplete(totalFound);
    emit gamesUpdated();

    // If Steam API key is configured, also fetch all owned games
    if (hasSteamApiKey() && isSteamAvailable()) {
        fetchSteamOwnedGames();
    }
}

void GameManager::launchGame(int gameId) {
    Game game = m_db->getGameById(gameId);

    // If game is not installed, trigger a silent download instead of opening Steam UI
    if (!game.isInstalled) {
        installGame(gameId);
        return;
    }

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

QVariantList GameManager::getWifiNetworks() {
    QVariantList networks;
    QProcess proc;
    // Force a fresh scan, then list results
    proc.start("nmcli", {"-t", "-f", "SSID,SIGNAL,SECURITY", "device", "wifi", "list", "--rescan", "yes"});
    proc.waitForFinished(10000);

    QString output = proc.readAllStandardOutput();
    QSet<QString> seen;
    for (const QString& line : output.split('\n')) {
        if (line.trimmed().isEmpty()) continue;
        // nmcli -t uses ':' as delimiter; SSID can't contain ':'
        // but SECURITY can have multiple values like "WPA2 WPA3"
        int first = line.indexOf(':');
        int second = line.indexOf(':', first + 1);
        if (first < 1 || second < 0) continue;

        QString ssid = line.left(first);
        QString signal = line.mid(first + 1, second - first - 1);
        QString security = line.mid(second + 1);

        if (ssid.isEmpty() || seen.contains(ssid)) continue;
        seen.insert(ssid);

        QVariantMap network;
        network["ssid"] = ssid;
        network["signal"] = signal.toInt();
        network["security"] = security;
        networks.append(network);
    }
    return networks;
}

void GameManager::connectToWifi(const QString& ssid, const QString& password) {
    QProcess *proc = new QProcess(this);
    QStringList args = {"device", "wifi", "connect", ssid};
    if (!password.isEmpty()) {
        args << "password" << password;
    }
    connect(proc, QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished),
            this, [this, proc](int exitCode, QProcess::ExitStatus) {
        bool success = (exitCode == 0);
        QString msg = success
            ? "Connected"
            : QString(proc->readAllStandardError()).trimmed();
        emit wifiConnectResult(success, msg);
        proc->deleteLater();
    });
    proc->start("nmcli", args);
}

// ── Steam API key management ──

QString GameManager::steamApiKeyPath() const {
    return QDir::homePath() + "/.config/luna-ui/steam-api-key";
}

QString GameManager::getSteamApiKey() {
    QFile file(steamApiKeyPath());
    if (!file.open(QIODevice::ReadOnly)) return QString();
    return QString(file.readAll()).trimmed();
}

void GameManager::setSteamApiKey(const QString& key) {
    QString configDir = QDir::homePath() + "/.config/luna-ui";
    QDir().mkpath(configDir);
    QFile file(steamApiKeyPath());
    if (file.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        file.write(key.trimmed().toUtf8());
    }
}

bool GameManager::hasSteamApiKey() {
    return !getSteamApiKey().isEmpty();
}

QString GameManager::getDetectedSteamId() {
    for (StoreBackend* backend : m_backends) {
        if (backend->name() == "steam") {
            SteamBackend* steam = static_cast<SteamBackend*>(backend);
            return steam->getLoggedInSteamId();
        }
    }
    return QString();
}

void GameManager::fetchSteamOwnedGames() {
    QString apiKey = getSteamApiKey();
    QString steamId = getDetectedSteamId();

    if (apiKey.isEmpty()) {
        emit steamOwnedGamesFetchError("No Steam API key configured");
        return;
    }
    if (steamId.isEmpty()) {
        emit steamOwnedGamesFetchError("Could not detect Steam ID — please log in to Steam first");
        return;
    }

    QUrl url("https://api.steampowered.com/IPlayerService/GetOwnedGames/v0001/");
    QUrlQuery params;
    params.addQueryItem("key", apiKey);
    params.addQueryItem("steamid", steamId);
    params.addQueryItem("include_appinfo", "1");
    params.addQueryItem("include_played_free_games", "1");
    params.addQueryItem("format", "json");
    url.setQuery(params);

    QNetworkRequest request(url);
    QNetworkReply *reply = m_networkManager->get(request);

    connect(reply, &QNetworkReply::finished, this, [this, reply]() {
        reply->deleteLater();

        if (reply->error() != QNetworkReply::NoError) {
            emit steamOwnedGamesFetchError(reply->errorString());
            return;
        }

        QByteArray data = reply->readAll();

        // Find the Steam backend to parse the response
        SteamBackend* steam = nullptr;
        for (StoreBackend* backend : m_backends) {
            if (backend->name() == "steam") {
                steam = static_cast<SteamBackend*>(backend);
                break;
            }
        }
        if (!steam) {
            emit steamOwnedGamesFetchError("Steam backend not found");
            return;
        }

        QVector<Game> games = steam->parseOwnedGamesResponse(data);
        int count = 0;
        for (const Game& game : games) {
            m_db->addOrUpdateGame(game);
            count++;
        }

        qDebug() << "Fetched" << count << "owned Steam games via API";
        emit steamOwnedGamesFetched(count);
        emit gamesUpdated();
    });
}

void GameManager::openSteamApiKeyPage() {
    // Open the Steam API key registration page in Steam's built-in browser.
    // steam://openurl/ tells the Steam client to open the URL in its overlay browser,
    // which works inside gamescope without needing a desktop browser.
    QProcess::startDetached("steam", QStringList() << "steam://openurl/https://steamcommunity.com/dev/apikey");
}

// ── Steam game download management ──

QStringList GameManager::getSteamAppsDirs() const {
    QStringList dirs;
    QString vdfPath = QDir::homePath() + "/.local/share/Steam/steamapps/libraryfolders.vdf";
    QFile file(vdfPath);
    if (!file.open(QIODevice::ReadOnly)) return dirs;

    QTextStream in(&file);
    QString content = in.readAll();
    QRegularExpression pathRe("\"path\"\\s+\"([^\"]+)\"");
    auto matches = pathRe.globalMatch(content);
    while (matches.hasNext()) {
        auto match = matches.next();
        QString steamapps = match.captured(1) + "/steamapps";
        if (QDir(steamapps).exists())
            dirs.append(steamapps);
    }
    return dirs;
}

void GameManager::installGame(int gameId) {
    Game game = m_db->getGameById(gameId);
    if (game.storeSource != "steam" || game.appId.isEmpty()) return;

    // Already downloading?
    if (m_activeDownloads.contains(game.appId)) return;

    m_activeDownloads.insert(game.appId, gameId);
    emit downloadStarted(game.appId, gameId);

    // Auto-accept Steam's install dialog by briefly minimizing Luna UI so
    // the dialog can receive focus. When Steam is already running, its
    // modal dialog opens behind Luna UI (the user sees Steam "grayed out"
    // because the dialog is hidden). We find Luna UI's window via PID,
    // minimize it so xdotool can activate the dialog, press Tab*4 + Enter
    // to accept, then restore Luna UI — takes ~2 s with no Steam restart.
    //
    // A lockfile serializes concurrent install requests so rapid clicks
    // don't race over dialog interactions.
    qint64 lunaUiPid = QCoreApplication::applicationPid();
    QString acceptScript = QString(
        "("
        "  flock -x 9 || exit 1; "
        "  LUNA_WID=$(xdotool search --pid %2 2>/dev/null | head -1); "
        "  EXISTING=$(xdotool search --name 'Install' 2>/dev/null | tr '\\n' ' '); "
        "  xdg-open 'steam://install/%1'; "
        "  for i in $(seq 1 40); do "
        "    for WID in $(xdotool search --name 'Install' 2>/dev/null); do "
        "      echo \"$EXISTING\" | grep -qw \"$WID\" && continue; "
        "      [ -n \"$LUNA_WID\" ] && xdotool windowminimize --sync \"$LUNA_WID\" 2>/dev/null; "
        "      xdotool windowactivate --sync \"$WID\"; "
        "      xdotool windowfocus --sync \"$WID\"; "
        "      xdotool windowraise \"$WID\"; "
        "      sleep 1; "
        "      xdotool key --window \"$WID\" Tab Tab Tab Tab Return; "
        "      sleep 0.5; "
        "      [ -n \"$LUNA_WID\" ] && xdotool windowactivate \"$LUNA_WID\" 2>/dev/null; "
        "      exit 0; "
        "    done; "
        "    sleep 1; "
        "  done; "
        ") 9>/tmp/luna-steam-install.lock"
    ).arg(game.appId).arg(lunaUiPid);
    QProcess::startDetached("sh", QStringList() << "-c" << acceptScript);

    // Start polling .acf manifests for download progress
    if (!m_downloadMonitor->isActive()) {
        m_downloadMonitor->start(2000);
    }

    qDebug() << "Started silent download for" << game.title << "(appId:" << game.appId << ")";
}

bool GameManager::isDownloading(const QString& appId) {
    return m_activeDownloads.contains(appId);
}

double GameManager::getDownloadProgress(const QString& appId) {
    if (!m_activeDownloads.contains(appId)) return -1.0;

    // Search all steamapps dirs for the appmanifest
    for (const QString& dir : getSteamAppsDirs()) {
        QString manifestPath = dir + "/appmanifest_" + appId + ".acf";
        QFile file(manifestPath);
        if (!file.open(QIODevice::ReadOnly)) continue;

        QTextStream in(&file);
        QString content = in.readAll();

        QRegularExpression dlRe("\"BytesDownloaded\"\\s+\"(\\d+)\"");
        QRegularExpression totalRe("\"BytesToDownload\"\\s+\"(\\d+)\"");
        auto dlMatch = dlRe.match(content);
        auto totalMatch = totalRe.match(content);

        if (dlMatch.hasMatch() && totalMatch.hasMatch()) {
            qint64 downloaded = dlMatch.captured(1).toLongLong();
            qint64 total = totalMatch.captured(1).toLongLong();
            if (total > 0) {
                return static_cast<double>(downloaded) / static_cast<double>(total);
            }
        }
        // Manifest exists but no progress fields yet — download queued
        return 0.0;
    }
    // No manifest yet — Steam is still starting up
    return 0.0;
}

void GameManager::checkDownloadProgress() {
    if (m_activeDownloads.isEmpty()) {
        m_downloadMonitor->stop();
        return;
    }

    QStringList dirs = getSteamAppsDirs();
    QList<QString> completed;

    for (auto it = m_activeDownloads.constBegin(); it != m_activeDownloads.constEnd(); ++it) {
        const QString& appId = it.key();
        int gameId = it.value();

        double progress = getDownloadProgress(appId);
        emit downloadProgressChanged(appId, progress);

        // Check if fully installed: StateFlags == 4 means fully installed
        for (const QString& dir : dirs) {
            QString manifestPath = dir + "/appmanifest_" + appId + ".acf";
            QFile file(manifestPath);
            if (!file.open(QIODevice::ReadOnly)) continue;

            QTextStream in(&file);
            QString content = in.readAll();

            QRegularExpression stateRe("\"StateFlags\"\\s+\"(\\d+)\"");
            auto stateMatch = stateRe.match(content);
            if (stateMatch.hasMatch()) {
                int stateFlags = stateMatch.captured(1).toInt();
                // StateFlags 4 = fully installed
                if (stateFlags == 4) {
                    completed.append(appId);

                    // Update the database
                    Game game = m_db->getGameById(gameId);
                    game.isInstalled = true;
                    game.launchCommand = "steam steam://rungameid/" + appId;
                    m_db->updateGame(game);

                    emit downloadComplete(appId, gameId);
                    qDebug() << "Download complete:" << game.title;
                }
            }
            break; // only check first matching dir
        }
    }

    for (const QString& appId : completed) {
        m_activeDownloads.remove(appId);
    }

    if (!completed.isEmpty()) {
        emit gamesUpdated();
    }

    if (m_activeDownloads.isEmpty()) {
        m_downloadMonitor->stop();
        // Shut down the background Steam instance used for downloading
        QProcess::startDetached("steam", QStringList() << "-shutdown");
        qDebug() << "All downloads finished, shutting down background Steam";
    }
}
