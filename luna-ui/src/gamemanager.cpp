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
#include <memory>

GameManager::GameManager(Database *db, QObject *parent)
    : QObject(parent), m_db(db) {
    registerBackends();

    m_processMonitor = new QTimer(this);
    connect(m_processMonitor, &QTimer::timeout, this, &GameManager::monitorGameProcess);

    m_networkManager = new QNetworkAccessManager(this);

    // Download progress monitor — polls .acf manifests every 2s as backup
    // to steamcmd stdout parsing
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

    // If game is not installed, trigger steamcmd download
    if (!game.isInstalled) {
        installGame(gameId);
        return;
    }

    // Safety: if a stale steam://install/ command is in the database for a game
    // that's marked installed, fix it before launching.
    if (game.storeSource == "steam" && game.launchCommand.contains("steam://install/")) {
        game.launchCommand = "steam -silent steam://rungameid/" + game.appId;
        m_db->updateGame(game);
    }

    // Start session tracking
    m_activeSessionId = m_db->startGameSession(gameId);
    m_activeGameId = gameId;

    // Get appropriate backend and launch
    StoreBackend* backend = getBackendForGame(game);
    if (backend) {
        bool launched = backend->launchGame(game);
        if (launched) {
            emit gameLaunched(gameId, game.title);
            // Start monitoring for game exit
            m_processMonitor->start(1000);
        } else {
            emit gameLaunchError(gameId, game.title,
                "Failed to start the game. The executable may be missing or corrupted.");
        }
    } else {
        emit gameLaunchError(gameId, game.title,
            "No compatible launcher found for this game.");
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

void GameManager::ensureSteamRunning() {
    // Pre-start Steam silently in the background so that when the user
    // clicks Play, the steam:// protocol URL is handled by the
    // already-running process via xdg-open — no new windows appear.
    if (!isSteamInstalled() || !isSteamAvailable()) return;

    // Check if Steam is already running
    QProcess pgrep;
    pgrep.start("pgrep", QStringList() << "-x" << "steam");
    pgrep.waitForFinished(2000);
    if (pgrep.exitCode() == 0) {
        qDebug() << "Steam is already running";
        return;
    }

    // Mark the hardware survey as completed so it never pops up
    suppressSteamHardwareSurvey();

    qDebug() << "Pre-starting Steam silently in background...";
    // Suppress Steam's overlay drawing via environment variable.
    // NOTE: Do NOT set STEAM_NO_CEFHOST — it prevents Steam from fully
    // initializing its network stack, causing "no internet" errors.
    // NOTE: Do NOT use -nofriendsui/-nochatui — on modern Steam these
    // prevent the client backend (CM connection) from fully initializing,
    // causing "no internet" errors when launching games even though
    // the web store (CEF) works fine.
    qputenv("SteamNoOverlayUIDrawing", "1");
    QProcess::startDetached("steam", QStringList() << "-silent");
}

void GameManager::suppressSteamHardwareSurvey() {
    // Inject a future SurveyDate and high SurveyDateVersion into Steam's
    // registry.vdf so the hardware survey dialog never appears.
    // Steam checks this file on startup; if the date is in the future,
    // it skips the survey prompt entirely.
    //
    // IMPORTANT: We must modify the existing file, NOT truncate it.
    // After the user logs into Steam (step 1), Steam writes a full
    // registry.vdf with hundreds of settings. Truncating it would
    // destroy all of Steam's state and ironically trigger the survey.
    QString registryPath = QDir::homePath() + "/.steam/registry.vdf";

    QDir().mkpath(QDir::homePath() + "/.steam");
    QString content;

    QFile readFile(registryPath);
    if (readFile.open(QIODevice::ReadOnly)) {
        content = QString::fromUtf8(readFile.readAll());
        readFile.close();
    }

    // If the file already has our suppression values, nothing to do
    if (content.contains("\"SurveyDate\"\t\t\"2030-01-01\"") &&
        content.contains("\"SurveyDateVersion\"")) {
        return;
    }

    if (content.isEmpty()) {
        // No registry.vdf yet — write a minimal one (pre-first-login)
        content =
            "\"Registry\"\n"
            "{\n"
            "\t\"HKLM\"\n"
            "\t{\n"
            "\t\t\"Software\"\n"
            "\t\t{\n"
            "\t\t\t\"Valve\"\n"
            "\t\t\t{\n"
            "\t\t\t\t\"Steam\"\n"
            "\t\t\t\t{\n"
            "\t\t\t\t\t\"SurveyDate\"\t\t\"2030-01-01\"\n"
            "\t\t\t\t\t\"SurveyDateVersion\"\t\t\"999\"\n"
            "\t\t\t\t}\n"
            "\t\t\t}\n"
            "\t\t}\n"
            "\t}\n"
            "}\n";
    } else {
        // Existing file — update or inject entries without destroying it.
        // Replace existing SurveyDate value if present
        QRegularExpression dateRe("\"SurveyDate\"\\s+\"[^\"]*\"");
        if (content.contains(dateRe)) {
            content.replace(dateRe, "\"SurveyDate\"\t\t\"2030-01-01\"");
        }

        QRegularExpression verRe("\"SurveyDateVersion\"\\s+\"[^\"]*\"");
        if (content.contains(verRe)) {
            content.replace(verRe, "\"SurveyDateVersion\"\t\t\"999\"");
        }

        // If neither entry exists, inject them into the HKLM/Software/Valve/Steam block.
        // Find the "Steam" section under HKLM by looking for the pattern.
        if (!content.contains("\"SurveyDate\"")) {
            // Look for "Steam" block opening brace under Valve
            QRegularExpression steamBlockRe(
                "(\"Steam\"\\s*\\n\\s*\\{\\s*\\n)");
            auto match = steamBlockRe.match(content);
            if (match.hasMatch()) {
                int insertPos = match.capturedEnd();
                QString entries =
                    "\t\t\t\t\t\"SurveyDate\"\t\t\"2030-01-01\"\n"
                    "\t\t\t\t\t\"SurveyDateVersion\"\t\t\"999\"\n";
                content.insert(insertPos, entries);
            }
        }
    }

    QFile writeFile(registryPath);
    if (writeFile.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        writeFile.write(content.toUtf8());
        qDebug() << "Updated hardware survey suppression in" << registryPath;
    }
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
    // Fast path: check for any non-loopback interface with an IP address.
    // Accept both IPv4 and IPv6, and don't require the IsRunning flag —
    // many wireless drivers (especially on gaming handhelds) don't report
    // it correctly even when fully connected.
    const auto interfaces = QNetworkInterface::allInterfaces();
    for (const auto &iface : interfaces) {
        if (iface.flags().testFlag(QNetworkInterface::IsUp) &&
            !iface.flags().testFlag(QNetworkInterface::IsLoopBack)) {
            const auto entries = iface.addressEntries();
            for (const auto &entry : entries) {
                if (!entry.ip().isLoopback() && !entry.ip().isNull()) {
                    return true;
                }
            }
        }
    }

    // Fallback: ask NetworkManager directly (always present on Lyrah OS).
    // This catches edge cases where QNetworkInterface doesn't see
    // addresses yet (e.g. WiFi just connected, DHCP still pending).
    QProcess nmcli;
    nmcli.start("nmcli", QStringList() << "networking" << "connectivity" << "check");
    if (nmcli.waitForFinished(3000)) {
        QString state = QString::fromUtf8(nmcli.readAllStandardOutput()).trimmed();
        if (state == "full" || state == "limited" || state == "portal") {
            return true;
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

void GameManager::scanWifiNetworks() {
    QProcess *proc = new QProcess(this);
    connect(proc, QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished),
            this, [this, proc](int, QProcess::ExitStatus) {
        QVariantList networks;
        QString output = proc->readAllStandardOutput();
        QSet<QString> seen;
        for (const QString& line : output.split('\n')) {
            if (line.trimmed().isEmpty()) continue;
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
        emit wifiNetworksScanned(networks);
        proc->deleteLater();
    });
    proc->start("nmcli", {"-t", "-f", "SSID,SIGNAL,SECURITY", "device", "wifi", "list", "--rescan", "yes"});
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

QString GameManager::getConnectedWifi() {
    QProcess proc;
    // nmcli -t -f NAME connection show --active shows active connections
    proc.start("nmcli", {"-t", "-f", "NAME,TYPE", "connection", "show", "--active"});
    proc.waitForFinished(5000);

    QString output = proc.readAllStandardOutput();
    for (const QString& line : output.split('\n')) {
        if (line.trimmed().isEmpty()) continue;
        // Format: "ConnectionName:802-11-wireless"
        int sep = line.lastIndexOf(':');
        if (sep < 0) continue;
        QString name = line.left(sep);
        QString type = line.mid(sep + 1);
        if (type.contains("wireless")) {
            return name;
        }
    }
    return QString();
}

void GameManager::disconnectWifi() {
    QString ssid = getConnectedWifi();
    if (ssid.isEmpty()) {
        emit wifiDisconnectResult(false, "No Wi-Fi connection active");
        return;
    }

    QProcess *proc = new QProcess(this);
    connect(proc, QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished),
            this, [this, proc](int exitCode, QProcess::ExitStatus) {
        bool success = (exitCode == 0);
        QString msg = success
            ? "Disconnected"
            : QString(proc->readAllStandardError()).trimmed();
        emit wifiDisconnectResult(success, msg);
        proc->deleteLater();
    });
    proc->start("nmcli", {"connection", "down", ssid});
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
    QString key = getSteamApiKey();
    return !key.isEmpty() && key != "__setup_pending__";
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

// ── SteamCMD-based game download management ──

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

    // Include SteamCMD's steamapps (not in libraryfolders.vdf but has
    // manifests and game files from SteamCMD-installed games)
    QString steamCmdApps = QDir::homePath() + "/.steam/steamcmd/steamapps";
    if (QDir(steamCmdApps).exists() && !dirs.contains(steamCmdApps))
        dirs.append(steamCmdApps);

    return dirs;
}

QString GameManager::findSteamCmdBin() const {
    // 1. Prefer the local download (~/.steam/steamcmd/steamcmd.sh).
    //    steamcmd.sh sets STEAMROOT to its own directory, so login tokens
    //    are stored in ~/.steam/steamcmd/config/config.vdf — isolated
    //    from the Steam client which overwrites ~/.local/share/Steam/config/.
    //    This ensures credentials survive Steam client restarts.
    QString localBin = QDir::homePath() + "/.steam/steamcmd/steamcmd.sh";
    if (QFile::exists(localBin)) return localBin;

    // 2. Fall back to system-installed binary (pacman/AUR)
    QString inPath = QStandardPaths::findExecutable("steamcmd");
    if (!inPath.isEmpty()) return inPath;

    return QString();
}

QString GameManager::steamCmdDataDir() const {
    // Always use a consistent, writable directory for SteamCMD data.
    // SteamCMD stores login tokens in config/config.vdf relative to CWD.
    // If the binary is system-installed (e.g., /usr/bin/steamcmd), CWD
    // would be unwritable. Using ~/.steam/steamcmd/ ensures credentials
    // persist across reboots and session logouts.
    QString dir = QDir::homePath() + "/.steam/steamcmd";
    QDir().mkpath(dir);
    return dir;
}

bool GameManager::isSteamCmdAvailable() {
    return !findSteamCmdBin().isEmpty();
}

void GameManager::ensureSteamCmd(int gameId) {
    // Auto-download steamcmd from Valve's CDN if not found anywhere.
    // This runs a short script that downloads and extracts the tarball
    // into ~/.steam/steamcmd/, then retries the install.
    QString destDir = QDir::homePath() + "/.steam/steamcmd";

    QProcess *dlProc = new QProcess(this);
    QString script = QString(
        "mkdir -p '%1' && "
        "cd '%1' && "
        "curl -sqL 'https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz' | tar zxf - && "
        "echo 'STEAMCMD_READY'"
    ).arg(destDir);

    connect(dlProc, QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished),
            this, [this, dlProc, gameId, destDir](int exitCode, QProcess::ExitStatus) {
        dlProc->deleteLater();

        QString output = QString::fromUtf8(dlProc->readAllStandardOutput());
        if (exitCode == 0 && output.contains("STEAMCMD_READY")) {
            qDebug() << "SteamCMD auto-downloaded to" << destDir;
            // Retry the install now that steamcmd is available (skip if -1 = setup-only)
            if (gameId >= 0) installGame(gameId);
        } else {
            QString err = QString::fromUtf8(dlProc->readAllStandardError()).trimmed();
            if (gameId >= 0) {
                Game game = m_db->getGameById(gameId);
                emit installError(game.appId,
                    "Failed to download steamcmd: " + (err.isEmpty() ? "unknown error" : err));
            } else {
                emit steamCmdSetupLoginError(
                    "Failed to download steamcmd: " + (err.isEmpty() ? "unknown error" : err));
            }
        }
    });

    dlProc->start("sh", QStringList() << "-c" << script);
    qDebug() << "Auto-downloading steamcmd to" << destDir;
}

QString GameManager::getSteamUsername() {
    // Parse the AccountName from loginusers.vdf for the most-recent user
    QString loginUsersPath = QDir::homePath() + "/.local/share/Steam/config/loginusers.vdf";
    QFile file(loginUsersPath);
    if (!file.open(QIODevice::ReadOnly)) return QString();

    QTextStream in(&file);
    QString content = in.readAll();

    // Parse user blocks: "76561198..." { "AccountName" "user" "MostRecent" "1" }
    QRegularExpression userBlockRe(
        "\"(7656119\\d{10})\"\\s*\\{([^}]+)\\}");
    auto matches = userBlockRe.globalMatch(content);

    QString fallbackName;
    while (matches.hasNext()) {
        auto match = matches.next();
        QString block = match.captured(2);

        QRegularExpression nameRe("\"AccountName\"\\s+\"([^\"]+)\"");
        auto nameMatch = nameRe.match(block);
        QString accountName = nameMatch.hasMatch() ? nameMatch.captured(1) : QString();

        if (fallbackName.isEmpty() && !accountName.isEmpty()) {
            fallbackName = accountName;
        }

        if (block.contains("\"MostRecent\"") && block.contains("\"1\"")) {
            return accountName;
        }
    }
    return fallbackName;
}

void GameManager::installGame(int gameId) {
    Game game = m_db->getGameById(gameId);
    if (game.storeSource != "steam" || game.appId.isEmpty()) return;

    // Already downloading?
    if (m_activeDownloads.contains(game.appId)) return;

    // Find steamcmd (system PATH or local download)
    QString steamcmdBin = findSteamCmdBin();
    if (steamcmdBin.isEmpty()) {
        // Auto-download from Valve's CDN, then retry
        ensureSteamCmd(gameId);
        return;
    }

    // Get Steam username for login
    QString username = getSteamUsername();
    if (username.isEmpty()) {
        emit installError(game.appId, "No Steam account detected. Please log in to Steam first.");
        return;
    }

    // Get the primary Steam library path for installation
    QStringList steamAppsDirs = getSteamAppsDirs();
    QString primarySteamApps = steamAppsDirs.isEmpty()
        ? QDir::homePath() + "/.local/share/Steam/steamapps"
        : steamAppsDirs.first();

    m_activeDownloads.insert(game.appId, gameId);
    m_downloadProgressCache.insert(game.appId, 0.0);
    emit downloadStarted(game.appId, gameId);

    // Build steamcmd arguments:
    // steamcmd runs headlessly — no GUI dialogs, no window management needed.
    // Do NOT use +force_install_dir — it sets the exact dir for game files
    // (no subdirectory), which breaks manifest paths. Instead, let SteamCMD
    // install to its default location (steamcmd/steamapps/common/GameName/)
    // and we symlink the result into Steam's library afterward.
    // +@sSteamCmdForcePlatformType linux  → ensure Linux depots
    // +login <user>                       → use cached credentials
    // +app_update <appid> validate        → download & verify game files
    // +quit                               → exit when done
    QProcess *proc = new QProcess(this);
    // Always run from the consistent data directory so SteamCMD finds
    // cached login tokens saved during setup (survives reboots/logouts)
    proc->setWorkingDirectory(steamCmdDataDir());
    QStringList args;
    args << "+@sSteamCmdForcePlatformType" << "linux"
         << "+login" << username
         << "+app_update" << game.appId << "validate"
         << "+quit";

    // Parse steamcmd stdout for download progress and credential prompts
    connect(proc, &QProcess::readyReadStandardOutput, this, [this, proc, appId = game.appId]() {
        handleSteamCmdOutput(appId, proc);
    });

    // Also capture stderr (steamcmd sometimes writes progress there)
    connect(proc, &QProcess::readyReadStandardError, this, [this, proc, appId = game.appId]() {
        QString errOutput = QString::fromUtf8(proc->readAllStandardError());
        qDebug() << "[steamcmd stderr]" << appId << ":" << errOutput.trimmed();
    });

    // Handle process completion
    QString dataDir = steamCmdDataDir();
    connect(proc, QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished),
            this, [this, proc, appId = game.appId, gameId, primarySteamApps, dataDir](int exitCode, QProcess::ExitStatus status) {
        proc->deleteLater();
        m_steamCmdProcesses.remove(appId);
        m_downloadProgressCache.remove(appId);

        // SteamCMD exit codes are unreliable (often exits 5 on success).
        // Check for the app manifest file — its existence is the real proof
        // that the game was downloaded successfully.
        //
        // SteamCMD installs games to its own steamapps/ directory
        // (e.g. ~/.steam/steamcmd/steamapps/common/GameName/).
        // We need to:
        //   1. Find the manifest in SteamCMD's steamapps
        //   2. Read "installdir" to get the game folder name
        //   3. Symlink the game folder into Steam's steamapps/common/
        //   4. Copy the manifest to Steam's steamapps/
        // This lets "steam steam://rungameid/<appid>" find the game.
        QString manifestName = "appmanifest_" + appId + ".acf";

        // Search SteamCMD's data directory for the manifest
        QStringList searchDirs = {
            dataDir + "/steamapps",
        };
        QString steamcmdManifest;
        QString steamcmdSteamApps;
        for (const QString& dir : searchDirs) {
            QString path = dir + "/" + manifestName;
            if (QFile::exists(path)) {
                steamcmdManifest = path;
                steamcmdSteamApps = dir;
                qDebug() << "Found manifest in SteamCMD dir:" << path;
                break;
            }
        }

        // Also check if it's already in Steam's dir (unlikely but possible)
        QString clientManifest = primarySteamApps + "/" + manifestName;
        bool manifestExists = QFile::exists(clientManifest) || !steamcmdManifest.isEmpty();

        if (manifestExists || (exitCode == 0 && status == QProcess::NormalExit)) {
            qDebug() << "SteamCMD finished for appId:" << appId
                     << "(exit code:" << exitCode << ", manifest:" << manifestExists << ")";

            // Read the install directory name from the manifest
            QString manifestToRead = steamcmdManifest.isEmpty() ? clientManifest : steamcmdManifest;
            QString installDir;
            QFile manifest(manifestToRead);
            if (manifest.open(QIODevice::ReadOnly)) {
                QTextStream in(&manifest);
                QString content = in.readAll();
                QRegularExpression installDirRe("\"installdir\"\\s+\"([^\"]+)\"");
                auto match = installDirRe.match(content);
                if (match.hasMatch()) {
                    installDir = match.captured(1);
                }
            }

            // If the game was installed by SteamCMD (not already in Steam's dir),
            // symlink the game folder into Steam's library and copy the manifest.
            if (!steamcmdManifest.isEmpty() && !installDir.isEmpty()) {
                QString srcGameDir = steamcmdSteamApps + "/common/" + installDir;
                QString dstGameDir = primarySteamApps + "/common/" + installDir;

                // Create the common/ directory if it doesn't exist
                QDir().mkpath(primarySteamApps + "/common");

                // Symlink the game directory into Steam's library
                if (QFile::exists(srcGameDir) && !QFile::exists(dstGameDir)) {
                    if (QFile::link(srcGameDir, dstGameDir)) {
                        qDebug() << "Symlinked game into Steam library:" << srcGameDir << "->" << dstGameDir;
                    } else {
                        qDebug() << "Warning: could not symlink" << srcGameDir << "to" << dstGameDir;
                    }
                }

                // Copy the manifest to Steam's steamapps/
                if (!QFile::exists(clientManifest)) {
                    if (QFile::copy(steamcmdManifest, clientManifest)) {
                        qDebug() << "Copied manifest to Steam client dir:" << clientManifest;
                    } else {
                        qDebug() << "Warning: could not copy manifest to" << clientManifest;
                    }
                }
            }

            // Update the database: mark as installed
            Game game = m_db->getGameById(gameId);
            game.isInstalled = true;
            game.launchCommand = "steam -silent steam://rungameid/" + appId;
            if (!installDir.isEmpty()) {
                game.installPath = primarySteamApps + "/common/" + installDir;
            }

            m_db->updateGame(game);
            m_activeDownloads.remove(appId);
            emit downloadComplete(appId, gameId);
            emit gamesUpdated();
            qDebug() << "Download complete:" << game.title;
        } else {
            qDebug() << "SteamCMD failed for appId:" << appId
                     << "exit code:" << exitCode << "status:" << status;
            m_activeDownloads.remove(appId);
            emit installError(appId, "Installation failed — check your credentials and try again.");
            // Emit progress -1 to clear the UI progress bar
            emit downloadProgressChanged(appId, -1.0);
        }

        // Stop polling if no more active downloads
        if (m_activeDownloads.isEmpty()) {
            m_downloadMonitor->stop();
        }
    });

    m_steamCmdProcesses.insert(game.appId, proc);
    proc->start(steamcmdBin, args);

    // Start ACF polling as a backup progress source
    if (!m_downloadMonitor->isActive()) {
        m_downloadMonitor->start(2000);
    }

    qDebug() << "Started steamcmd download for" << game.title << "(appId:" << game.appId << ")";
}

void GameManager::handleSteamCmdOutput(const QString& appId, QProcess *proc) {
    QString output = QString::fromUtf8(proc->readAllStandardOutput());

    for (const QString& line : output.split('\n')) {
        QString trimmed = line.trimmed();
        if (trimmed.isEmpty()) continue;

        qDebug() << "[steamcmd]" << appId << ":" << trimmed;

        // Detect credential prompts — steamcmd needs interactive login
        // "password:" or "Steam Guard code:" or "Two-factor code:"
        if (trimmed.contains("password:", Qt::CaseInsensitive)) {
            emit steamCmdCredentialNeeded(appId, "password");
            continue;
        }
        if (trimmed.contains("Steam Guard", Qt::CaseInsensitive) ||
            trimmed.contains("Two-factor", Qt::CaseInsensitive)) {
            emit steamCmdCredentialNeeded(appId, "steamguard");
            continue;
        }

        // Parse download progress lines:
        // " Update state (0x61) downloading, progress: 45.23 (1234567890 / 2734567890)"
        // " Update state (0x5) verifying install, progress: 98.23 (...)"
        QRegularExpression progressRe("progress:\\s+(\\d+\\.?\\d*)\\s+\\((\\d+)\\s*/\\s*(\\d+)\\)");
        auto match = progressRe.match(trimmed);
        if (match.hasMatch()) {
            double pct = match.captured(1).toDouble() / 100.0;
            // Clamp to 0.0 - 1.0
            pct = qBound(0.0, pct, 1.0);
            m_downloadProgressCache.insert(appId, pct);
            emit downloadProgressChanged(appId, pct);
            continue;
        }

        // Detect success
        if (trimmed.contains("fully installed", Qt::CaseInsensitive)) {
            m_downloadProgressCache.insert(appId, 1.0);
            emit downloadProgressChanged(appId, 1.0);
        }

        // Detect errors
        if (trimmed.startsWith("ERROR!", Qt::CaseInsensitive) ||
            trimmed.contains("FAILED", Qt::CaseInsensitive)) {
            emit installError(appId, trimmed);
        }
    }
}

void GameManager::provideSteamCmdCredential(const QString& appId, const QString& credential) {
    if (!m_steamCmdProcesses.contains(appId)) return;
    QProcess *proc = m_steamCmdProcesses.value(appId);
    if (proc && proc->state() == QProcess::Running) {
        proc->write((credential + "\n").toUtf8());
    }
}

void GameManager::cancelDownload(const QString& appId) {
    if (m_steamCmdProcesses.contains(appId)) {
        QProcess *proc = m_steamCmdProcesses.value(appId);
        if (proc && proc->state() == QProcess::Running) {
            proc->terminate();
            // Give it a moment, then force-kill if needed
            if (!proc->waitForFinished(3000)) {
                proc->kill();
            }
        }
    }
    m_activeDownloads.remove(appId);
    m_downloadProgressCache.remove(appId);
    emit downloadProgressChanged(appId, -1.0);
    qDebug() << "Cancelled download for appId:" << appId;
}

bool GameManager::isDownloading(const QString& appId) {
    return m_activeDownloads.contains(appId);
}

double GameManager::getDownloadProgress(const QString& appId) {
    if (!m_activeDownloads.contains(appId)) return -1.0;

    // First check the steamcmd stdout progress cache
    if (m_downloadProgressCache.contains(appId) && m_downloadProgressCache.value(appId) > 0.0) {
        return m_downloadProgressCache.value(appId);
    }

    // Fall back to reading .acf manifest files from Steam + SteamCMD dirs
    QStringList progressDirs = getSteamAppsDirs();
    // Also check SteamCMD's steamapps for downloads in progress
    QString steamcmdBin = findSteamCmdBin();
    if (!steamcmdBin.isEmpty()) {
        QFileInfo cmdInfo(steamcmdBin);
        QString cmdApps = cmdInfo.absolutePath() + "/steamapps";
        if (QDir(cmdApps).exists() && !progressDirs.contains(cmdApps))
            progressDirs.append(cmdApps);
    }
    QString localCmdApps = QDir::homePath() + "/.steam/steamcmd/steamapps";
    if (QDir(localCmdApps).exists() && !progressDirs.contains(localCmdApps))
        progressDirs.append(localCmdApps);

    for (const QString& dir : progressDirs) {
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
    // No manifest yet — steamcmd is still starting up
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

        // Only use ACF polling if we don't have steamcmd stdout progress
        if (!m_downloadProgressCache.contains(appId) || m_downloadProgressCache.value(appId) <= 0.0) {
            double progress = getDownloadProgress(appId);
            if (progress > 0.0) {
                emit downloadProgressChanged(appId, progress);
            }
        }

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
                    // Only mark complete if steamcmd process has also finished
                    // (avoids race between ACF watcher and process exit handler)
                    if (!m_steamCmdProcesses.contains(appId)) {
                        completed.append(appId);

                        Game game = m_db->getGameById(gameId);
                        if (!game.isInstalled) {
                            game.isInstalled = true;
                            game.launchCommand = "steam -silent steam://rungameid/" + appId;
                            m_db->updateGame(game);
                            emit downloadComplete(appId, gameId);
                            qDebug() << "ACF watcher: download complete:" << game.title;
                        }
                    }
                }
            }
            break; // only check first matching dir
        }
    }

    for (const QString& appId : completed) {
        m_activeDownloads.remove(appId);
        m_downloadProgressCache.remove(appId);
    }

    if (!completed.isEmpty()) {
        emit gamesUpdated();
    }

    if (m_activeDownloads.isEmpty()) {
        m_downloadMonitor->stop();
    }
}

// ── Steam Setup Wizard backend ──

bool GameManager::isSteamSetupComplete() {
    // Setup is "complete" when: Steam is logged in, API key is saved, and steamcmd is available
    return isSteamAvailable() && hasSteamApiKey() && isSteamCmdAvailable();
}

void GameManager::openApiKeyInBrowser() {
    // Open the Steam API key page in a real browser, truly full screen.
    // In gamescope the window manager doesn't tile/maximize automatically,
    // so we must give explicit geometry that fills the entire screen.
    // We track the PID so closeApiKeyBrowser() can kill it later.
    QString url = "https://steamcommunity.com/dev/apikey";

    // Detect screen resolution from gamescope / Xrandr environment
    // Default to 1280x800 (Steam Deck) if detection fails.
    int screenW = 1280, screenH = 800;
    QProcess xrandr;
    xrandr.start("xrandr", QStringList() << "--current");
    if (xrandr.waitForFinished(2000)) {
        // Parse lines like "  1280x800     59.98*+"
        QRegularExpression re("(\\d+)x(\\d+)\\s+\\d+\\.\\d+\\*");
        auto m = re.match(QString::fromUtf8(xrandr.readAllStandardOutput()));
        if (m.hasMatch()) {
            screenW = m.captured(1).toInt();
            screenH = m.captured(2).toInt();
        }
    }
    QString geom = QString("%1x%2").arg(screenW).arg(screenH);
    qDebug() << "Browser target geometry:" << geom;

    struct BrowserOption {
        QString bin;
        QStringList args;
    };
    // Enable remote debugging so scrapeApiKeyFromPage() can read the DOM.
    m_apiKeyBrowserType = "";
    QVector<BrowserOption> browsers = {
        {"brave",            {"--kiosk", "--no-first-run",
                              "--window-size=" + geom, "--window-position=0,0",
                              "--remote-debugging-port=9222", url}},
        {"brave-browser",    {"--kiosk", "--no-first-run",
                              "--window-size=" + geom, "--window-position=0,0",
                              "--remote-debugging-port=9222", url}},
        {"chromium",         {"--kiosk", "--no-first-run",
                              "--window-size=" + geom, "--window-position=0,0",
                              "--remote-debugging-port=9222", url}},
        {"chromium-browser", {"--kiosk", "--no-first-run",
                              "--window-size=" + geom, "--window-position=0,0",
                              "--remote-debugging-port=9222", url}},
        {"google-chrome",    {"--kiosk", "--no-first-run",
                              "--window-size=" + geom, "--window-position=0,0",
                              "--remote-debugging-port=9222", url}},
        {"firefox",          {"--kiosk", "--width", QString::number(screenW),
                              "--height", QString::number(screenH), url}},
    };

    for (const auto& b : browsers) {
        QString path = QStandardPaths::findExecutable(b.bin);
        if (!path.isEmpty()) {
            qint64 pid = 0;
            QProcess::startDetached(path, b.args, QString(), &pid);
            m_apiKeyBrowserPid = pid;
            m_apiKeyBrowserType = b.bin;
            qDebug() << "Opened API key page with" << b.bin << "(kiosk" << geom << ", pid:" << pid << ")";
            return;
        }
    }

    // Fallback: xdg-open without full-screen
    qint64 pid = 0;
    QProcess::startDetached("xdg-open", QStringList() << url, QString(), &pid);
    m_apiKeyBrowserPid = pid;
    qDebug() << "Opened API key page with xdg-open (pid:" << pid << ")";
}

void GameManager::closeApiKeyBrowser() {
    // Delegate to the force-close implementation which uses SIGTERM,
    // falls back to SIGKILL, and waits for all browser processes to die.
    forceCloseApiKeyBrowser();
}

void GameManager::forceCloseApiKeyBrowser() {
    // Aggressively kill all browser processes and WAIT for them to die.
    // Called from QML after the user confirms or rejects the detected key.
    //
    // The script:
    //   1. SIGTERM the specific PID
    //   2. SIGTERM all matching browser processes
    //   3. Wait 0.5s for graceful shutdown
    //   4. SIGKILL everything that survived
    //   5. Poll until all matching processes are gone (up to 3 seconds)
    QString browserType = m_apiKeyBrowserType;
    qint64 browserPid = m_apiKeyBrowserPid;
    m_apiKeyBrowserPid = 0;

    if (browserPid <= 0 && browserType.isEmpty()) {
        return;
    }

    // Build a kill-and-wait script
    QString script;
    if (!browserType.isEmpty()) {
        script = QString(
            "kill -TERM %1 2>/dev/null; "
            "pkill -f '%2' 2>/dev/null; "
            "sleep 0.5; "
            "kill -9 %1 2>/dev/null; "
            "pkill -9 -f '%2' 2>/dev/null; "
            "for i in $(seq 1 10); do "
            "  pgrep -f '%2' >/dev/null 2>&1 || exit 0; "
            "  sleep 0.3; "
            "done"
        ).arg(browserPid).arg(browserType);
    } else {
        script = QString(
            "kill -9 %1 2>/dev/null; sleep 1"
        ).arg(browserPid);
    }

    qDebug() << "Force-closing browser (pid:" << browserPid
             << "type:" << browserType << ")";

    QProcess *killProc = new QProcess(this);
    connect(killProc, QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished),
            this, [killProc]() {
        killProc->deleteLater();
        qDebug() << "Browser confirmed dead";
    });
    killProc->start("bash", QStringList() << "-c" << script);
}

void GameManager::raiseLunaWindow() {
    // Bring Luna UI's window to the foreground above the browser.
    // In gamescope (Xwayland), xdotool can shift focus between
    // managed windows, making Luna UI visible over the browser.
    QProcess::execute("xdotool", QStringList()
        << "search" << "--name" << "Luna UI"
        << "windowactivate" << "--sync");
}

void GameManager::scrapeApiKeyFromPage() {
    // Scrape the Steam API key from the browser that openApiKeyInBrowser()
    // launched.  We connect to the browser's Chrome DevTools Protocol
    // (remote debugging on port 9222) and read the page's DOM text.
    //
    // The script polls every 2 seconds for up to 60 seconds, giving the
    // user time to log in / load the page.  Once "Key: <hex>" appears
    // in the page body, it prints the key and exits.
    //
    // For Firefox (no CDP), we fall back to cookie-based scraping.

    QProcess *proc = new QProcess(this);
    bool useCDP = (m_apiKeyBrowserType != "firefox" && !m_apiKeyBrowserType.isEmpty());
    QString steamDir = QDir::homePath() + "/.local/share/Steam";

    QString script;
    if (useCDP) {
        // Chromium-based: scrape via Chrome DevTools Protocol
        script = QString(
            "python3 -c '\n"
            "import json, re, sys, time\n"
            "try:\n"
            "    from urllib.request import Request, urlopen\n"
            "except:\n"
            "    print(\"ERROR:Python urllib not available\")\n"
            "    sys.exit(1)\n"
            "\n"
            "def get_page_text():\n"
            "    \"\"\"Connect to Chrome DevTools and get page body text.\"\"\"\n"
            "    try:\n"
            "        # Get the list of debuggable pages\n"
            "        tabs = json.loads(urlopen(\"http://127.0.0.1:9222/json\", timeout=3).read())\n"
            "        # Find the Steam API key tab\n"
            "        ws_url = None\n"
            "        for tab in tabs:\n"
            "            if \"steamcommunity.com/dev/apikey\" in tab.get(\"url\", \"\"):\n"
            "                ws_url = tab.get(\"id\")\n"
            "                break\n"
            "        if not ws_url and tabs:\n"
            "            ws_url = tabs[0].get(\"id\")\n"
            "        if not ws_url:\n"
            "            return None\n"
            "        # Use the /json/evaluate endpoint (no websocket needed)\n"
            "        # We send a Runtime.evaluate via HTTP by POSTing to a simpler endpoint\n"
            "        # Actually use the CDP HTTP fetch trick: navigate to javascript: won t work\n"
            "        # Simplest: just fetch the page URL from the tab info and grab the body\n"
            "        page_url = None\n"
            "        for tab in tabs:\n"
            "            if tab.get(\"id\") == ws_url:\n"
            "                page_url = tab.get(\"url\")\n"
            "                break\n"
            "        if not page_url or \"steamcommunity\" not in page_url:\n"
            "            return None\n"
            "        # Read cookies from the browser by fetching the page through CDP\n"
            "        # Use websocket to evaluate document.body.innerText\n"
            "        import socket, struct, hashlib, base64, os\n"
            "        ws_uri = None\n"
            "        for tab in tabs:\n"
            "            if tab.get(\"id\") == ws_url:\n"
            "                ws_uri = tab.get(\"webSocketDebuggerUrl\")\n"
            "                break\n"
            "        if not ws_uri:\n"
            "            return None\n"
            "        # Parse ws://host:port/path\n"
            "        ws_uri = ws_uri.replace(\"ws://\", \"\")\n"
            "        host_port, path = ws_uri.split(\"/\", 1) if \"/\" in ws_uri else (ws_uri, \"\")\n"
            "        host, port = host_port.split(\":\") if \":\" in host_port else (host_port, \"80\")\n"
            "        path = \"/\" + path\n"
            "        # WebSocket handshake\n"
            "        sock = socket.create_connection((host, int(port)), timeout=5)\n"
            "        ws_key = base64.b64encode(os.urandom(16)).decode()\n"
            "        handshake = (f\"GET {path} HTTP/1.1\\r\\n\"\n"
            "                     f\"Host: {host_port}\\r\\n\"\n"
            "                     f\"Upgrade: websocket\\r\\n\"\n"
            "                     f\"Connection: Upgrade\\r\\n\"\n"
            "                     f\"Sec-WebSocket-Key: {ws_key}\\r\\n\"\n"
            "                     f\"Sec-WebSocket-Version: 13\\r\\n\\r\\n\")\n"
            "        sock.sendall(handshake.encode())\n"
            "        resp = sock.recv(4096)\n"
            "        if b\"101\" not in resp:\n"
            "            sock.close()\n"
            "            return None\n"
            "        # Send CDP command: Runtime.evaluate\n"
            "        cmd = json.dumps({\"id\": 1, \"method\": \"Runtime.evaluate\",\n"
            "                          \"params\": {\"expression\": \"document.body.innerText\"}})\n"
            "        payload = cmd.encode()\n"
            "        mask = os.urandom(4)\n"
            "        # Build websocket frame (masked, text)\n"
            "        frame = bytearray([0x81])  # FIN + text opcode\n"
            "        length = len(payload)\n"
            "        if length < 126:\n"
            "            frame.append(0x80 | length)  # masked\n"
            "        elif length < 65536:\n"
            "            frame.append(0x80 | 126)\n"
            "            frame.extend(struct.pack(\">H\", length))\n"
            "        else:\n"
            "            frame.append(0x80 | 127)\n"
            "            frame.extend(struct.pack(\">Q\", length))\n"
            "        frame.extend(mask)\n"
            "        frame.extend(bytes(b ^ mask[i % 4] for i, b in enumerate(payload)))\n"
            "        sock.sendall(frame)\n"
            "        # Read response\n"
            "        data = b\"\"\n"
            "        sock.settimeout(5)\n"
            "        try:\n"
            "            while True:\n"
            "                chunk = sock.recv(65536)\n"
            "                if not chunk:\n"
            "                    break\n"
            "                data += chunk\n"
            "                # Check if we have a complete frame\n"
            "                try:\n"
            "                    json.loads(data[data.index(b\"{\"):])\n"
            "                    break\n"
            "                except:\n"
            "                    pass\n"
            "        except socket.timeout:\n"
            "            pass\n"
            "        sock.close()\n"
            "        # Parse the CDP response from the websocket frame\n"
            "        try:\n"
            "            json_start = data.index(b\"{\")\n"
            "            result = json.loads(data[json_start:])\n"
            "            return result.get(\"result\", {}).get(\"result\", {}).get(\"value\", \"\")\n"
            "        except:\n"
            "            return None\n"
            "    except Exception as e:\n"
            "        return None\n"
            "\n"
            "# Poll the browser page for up to 60 seconds\n"
            "for attempt in range(30):\n"
            "    text = get_page_text()\n"
            "    if text:\n"
            "        m = re.search(r\"Key:\\s*([A-Fa-f0-9]{32})\", text)\n"
            "        if m:\n"
            "            print(f\"APIKEY:{m.group(1)}\")\n"
            "            sys.exit(0)\n"
            "    time.sleep(2)\n"
            "\n"
            "print(\"ERROR:Could not find API key on the page. Copy it manually.\")\n"
            "sys.exit(1)\n"
            "'\n"
        );
    } else {
        // Firefox fallback: use cookie-based scraping
        script = QString(
            "python3 -c '\n"
            "import sqlite3, os, hashlib, subprocess, re, sys, shutil\n"
            "try:\n"
            "    from urllib.request import Request, urlopen\n"
            "except:\n"
            "    print(\"ERROR:Python urllib not available\")\n"
            "    sys.exit(1)\n"
            "\n"
            "db_src = \"%1/config/htmlcache/Cookies\"\n"
            "if not os.path.exists(db_src):\n"
            "    print(\"ERROR:Steam cookie database not found\")\n"
            "    sys.exit(1)\n"
            "\n"
            "db_tmp = \"/tmp/.luna_steam_cookies.db\"\n"
            "try:\n"
            "    shutil.copy2(db_src, db_tmp)\n"
            "except Exception as e:\n"
            "    print(f\"ERROR:Could not copy cookie DB: {e}\")\n"
            "    sys.exit(1)\n"
            "\n"
            "conn = sqlite3.connect(db_tmp)\n"
            "\n"
            "def get_cookie(name):\n"
            "    cur = conn.execute(\n"
            "        \"SELECT value, encrypted_value FROM cookies \"\n"
            "        \"WHERE host_key=\\'\\'.steamcommunity.com\\'\\' AND name=? LIMIT 1\", (name,))\n"
            "    row = cur.fetchone()\n"
            "    if not row:\n"
            "        return None\n"
            "    value, encrypted = row\n"
            "    if value:\n"
            "        return value\n"
            "    if not encrypted or len(encrypted) < 4:\n"
            "        return None\n"
            "    key = hashlib.pbkdf2_hmac(\"sha1\", b\"peanuts\", b\"saltysalt\", 1, dklen=16)\n"
            "    data = encrypted[3:]\n"
            "    iv = bytes([0x20] * 16)\n"
            "    r = subprocess.run(\n"
            "        [\"openssl\", \"enc\", \"-aes-128-cbc\", \"-d\",\n"
            "         \"-K\", key.hex(), \"-iv\", iv.hex()],\n"
            "        input=data, capture_output=True)\n"
            "    if r.returncode != 0:\n"
            "        return None\n"
            "    return r.stdout.decode(\"utf-8\", errors=\"ignore\")\n"
            "\n"
            "login = get_cookie(\"steamLoginSecure\")\n"
            "sessid = get_cookie(\"sessionid\") or \"\"\n"
            "conn.close()\n"
            "try:\n"
            "    os.remove(db_tmp)\n"
            "except:\n"
            "    pass\n"
            "\n"
            "if not login:\n"
            "    print(\"ERROR:Could not read Steam session cookie\")\n"
            "    sys.exit(1)\n"
            "\n"
            "try:\n"
            "    req = Request(\"https://steamcommunity.com/dev/apikey\",\n"
            "        headers={\"Cookie\": f\"steamLoginSecure={login}; sessionid={sessid}\",\n"
            "                 \"User-Agent\": \"Mozilla/5.0\"})\n"
            "    html = urlopen(req, timeout=10).read().decode(\"utf-8\", errors=\"ignore\")\n"
            "except Exception as e:\n"
            "    print(f\"ERROR:Failed to fetch page: {e}\")\n"
            "    sys.exit(1)\n"
            "\n"
            "m = re.search(r\"Key:\\s*([A-Fa-f0-9]{32})\", html)\n"
            "if m:\n"
            "    print(f\"APIKEY:{m.group(1)}\")\n"
            "else:\n"
            "    print(\"ERROR:No API key found on page\")\n"
            "    sys.exit(1)\n"
            "'\n"
        ).arg(steamDir);
    }

    connect(proc, QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished),
            this, [this, proc](int exitCode, QProcess::ExitStatus) {
        QString output = QString::fromUtf8(proc->readAllStandardOutput()).trimmed();
        QString errors = QString::fromUtf8(proc->readAllStandardError()).trimmed();
        proc->deleteLater();

        if (!errors.isEmpty()) {
            qDebug() << "API key scrape stderr:" << errors;
        }

        for (const QString& line : output.split('\n')) {
            qDebug() << "API key scrape:" << line;
            if (line.startsWith("APIKEY:")) {
                QString key = line.mid(7).trimmed().toUpper();
                if (!key.isEmpty()) {
                    qDebug() << "Auto-detected Steam API key:" << key.left(4) + "...";
                    // Raise Luna UI above the browser so the confirmation
                    // overlay is visible. The browser stays open behind —
                    // it gets killed only after the user confirms or
                    // rejects the key in the QML overlay.
                    raiseLunaWindow();
                    emit apiKeyScraped(key);
                    return;
                }
            }
        }

        // Extract error message for the user
        QString errMsg = "Could not auto-detect API key.";
        for (const QString& line : output.split('\n')) {
            if (line.startsWith("ERROR:")) {
                errMsg = line.mid(6);
                break;
            }
        }
        // On error, raise Luna UI and kill the browser (nothing to confirm)
        raiseLunaWindow();
        closeApiKeyBrowser();
        emit apiKeyScrapeError(errMsg);
    });

    proc->start("bash", QStringList() << "-c" << script);
    qDebug() << "Auto-detecting Steam API key via cookie decryption...";
}

void GameManager::downloadSteamCmd() {
    // Pre-download SteamCMD binary in the background if not already present.
    // Called early so it's ready by the time the user reaches the login step.
    if (isSteamCmdAvailable()) {
        qDebug() << "SteamCMD already available, skipping download";
        return;
    }
    qDebug() << "Pre-downloading SteamCMD in background...";
    ensureSteamCmd(-1);
}

void GameManager::loginSteamCmd() {
    // Run steamcmd with +login only (no game install) to cache credentials.
    // This is a standalone login process separate from game downloads.
    if (m_steamCmdSetupProc && m_steamCmdSetupProc->state() == QProcess::Running) {
        qDebug() << "SteamCMD setup login already running";
        return;
    }

    QString steamcmdBin = findSteamCmdBin();
    if (steamcmdBin.isEmpty()) {
        emit steamCmdSetupLoginError("SteamCMD not found. It will be downloaded first.");
        // Trigger auto-download, then the QML wizard can retry
        ensureSteamCmd(-1);  // -1 = no game, just download steamcmd
        return;
    }

    QString username = getSteamUsername();
    if (username.isEmpty()) {
        emit steamCmdSetupLoginError("No Steam account detected. Please complete Step 2 first.");
        return;
    }

    m_steamCmdSetupProc = new QProcess(this);
    // Always use the consistent data directory so login tokens are stored
    // where installGame() will find them — survives reboots and logouts.
    m_steamCmdSetupProc->setWorkingDirectory(steamCmdDataDir());
    // Don't pass +quit on the command line. SteamCMD needs time to
    // save the login token after a successful auth. If +quit is queued
    // upfront, it fires before the token is persisted and exits with
    // code 5. Instead, we write "quit" to stdin after login succeeds.
    QStringList args;
    args << "+login" << username;

    // Track whether we saw a successful login in stdout, because
    // SteamCMD's exit codes are unreliable (often exits 5 even on success).
    auto loginOk = std::make_shared<bool>(false);

    // Timer to send quit after the login token has been saved.
    // SteamCMD prints "Logged in OK" → "Waiting for user info" → "OK"
    // → "Steam>" — only at the Steam> prompt has the token been persisted.
    // We wait for the Steam> prompt, or fall back to a 5-second delay.
    auto quitTimer = new QTimer(this);
    quitTimer->setSingleShot(true);
    quitTimer->setInterval(5000);
    connect(quitTimer, &QTimer::timeout, this, [this, quitTimer]() {
        quitTimer->deleteLater();
        if (m_steamCmdSetupProc && m_steamCmdSetupProc->state() == QProcess::Running) {
            qDebug() << "[steamcmd-setup] quit timer fired, sending quit";
            m_steamCmdSetupProc->write("quit\n");
        }
    });

    connect(m_steamCmdSetupProc, &QProcess::readyReadStandardOutput, this, [this, loginOk, quitTimer]() {
        QString output = QString::fromUtf8(m_steamCmdSetupProc->readAllStandardOutput());
        for (const QString& line : output.split('\n')) {
            QString trimmed = line.trimmed();
            if (trimmed.isEmpty()) continue;
            qDebug() << "[steamcmd-setup]" << trimmed;

            // Password prompt
            if (trimmed.contains("password:", Qt::CaseInsensitive)) {
                emit steamCmdSetupCredentialNeeded("password");
                continue;
            }
            // Steam Guard / Two-factor / authenticator prompt
            if (trimmed.contains("Steam Guard", Qt::CaseInsensitive) ||
                trimmed.contains("Two-factor", Qt::CaseInsensitive)) {
                emit steamCmdSetupCredentialNeeded("steamguard");
                continue;
            }
            // Successful login detected — but do NOT quit yet.
            // SteamCMD needs to finish saving the login token to disk.
            // Start a timeout; if we see the "Steam>" prompt we'll
            // quit sooner.
            if (trimmed.contains("Logged in OK", Qt::CaseInsensitive)) {
                *loginOk = true;
                if (!quitTimer->isActive()) {
                    qDebug() << "[steamcmd-setup] login OK, waiting for token save...";
                    quitTimer->start();
                }
            }
            // The Steam> prompt means SteamCMD is idle and the token
            // has been fully written to config.vdf. Safe to quit now.
            if (*loginOk && trimmed.startsWith("Steam>")) {
                quitTimer->stop();
                if (m_steamCmdSetupProc && m_steamCmdSetupProc->state() == QProcess::Running) {
                    qDebug() << "[steamcmd-setup] Steam> prompt seen, sending quit";
                    m_steamCmdSetupProc->write("quit\n");
                }
            }
            // Login failure messages from SteamCMD itself
            if (trimmed.contains("FAILED login", Qt::CaseInsensitive) ||
                trimmed.contains("Invalid Password", Qt::CaseInsensitive) ||
                trimmed.contains("Login Failure", Qt::CaseInsensitive)) {
                *loginOk = false;
                quitTimer->stop();
                if (m_steamCmdSetupProc && m_steamCmdSetupProc->state() == QProcess::Running) {
                    m_steamCmdSetupProc->write("quit\n");
                }
            }
        }
    });

    connect(m_steamCmdSetupProc, QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished),
            this, [this, loginOk](int exitCode, QProcess::ExitStatus) {
        m_steamCmdSetupProc->deleteLater();
        m_steamCmdSetupProc = nullptr;

        // Trust the stdout "Logged in OK" over the exit code, because
        // SteamCMD frequently exits with code 5 even after a successful
        // login+quit sequence.
        if (*loginOk || exitCode == 0) {
            qDebug() << "SteamCMD setup login successful (exit code:" << exitCode << ")";
            emit steamCmdSetupLoginSuccess();
        } else {
            qDebug() << "SteamCMD setup login failed, exit code:" << exitCode;
            emit steamCmdSetupLoginError(
                "Login failed. Check your password or Steam Guard code and try again.");
        }
    });

    m_steamCmdSetupProc->start(steamcmdBin, args);
    qDebug() << "Started steamcmd setup login for user:" << username;
}

void GameManager::provideSteamCmdSetupCredential(const QString& credential) {
    if (m_steamCmdSetupProc && m_steamCmdSetupProc->state() == QProcess::Running) {
        m_steamCmdSetupProc->write((credential + "\n").toUtf8());
    }
}

void GameManager::cancelSteamCmdSetup() {
    if (m_steamCmdSetupProc && m_steamCmdSetupProc->state() == QProcess::Running) {
        m_steamCmdSetupProc->terminate();
        if (!m_steamCmdSetupProc->waitForFinished(3000)) {
            m_steamCmdSetupProc->kill();
        }
    }
}
