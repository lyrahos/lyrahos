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
        game.launchCommand = "steam steam://rungameid/" + game.appId;
        m_db->updateGame(game);
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
    return dirs;
}

QString GameManager::findSteamCmdBin() const {
    // 1. Check PATH (system-installed via pacman/AUR)
    QString inPath = QStandardPaths::findExecutable("steamcmd");
    if (!inPath.isEmpty()) return inPath;

    // 2. Check local download location (~/.steam/steamcmd/steamcmd.sh)
    QString localBin = QDir::homePath() + "/.steam/steamcmd/steamcmd.sh";
    if (QFile::exists(localBin)) return localBin;

    return QString();
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
    // +@sSteamCmdForcePlatformType linux  → ensure Linux depots
    // +force_install_dir <path>           → install into Steam's library
    // +login <user>                       → use cached credentials
    // +app_update <appid> validate        → download & verify game files
    // +quit                               → exit when done
    QProcess *proc = new QProcess(this);
    QStringList args;
    args << "+@sSteamCmdForcePlatformType" << "linux"
         << "+force_install_dir" << primarySteamApps + "/common"
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
    connect(proc, QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished),
            this, [this, proc, appId = game.appId, gameId, primarySteamApps](int exitCode, QProcess::ExitStatus status) {
        proc->deleteLater();
        m_steamCmdProcesses.remove(appId);
        m_downloadProgressCache.remove(appId);

        // SteamCMD exit codes are unreliable (often exits 5 on success).
        // Check for the app manifest file — its existence is the real proof
        // that the game was downloaded successfully.
        QString manifestPath = primarySteamApps + "/appmanifest_" + appId + ".acf";
        bool manifestExists = QFile::exists(manifestPath);

        if (manifestExists || (exitCode == 0 && status == QProcess::NormalExit)) {
            qDebug() << "SteamCMD finished for appId:" << appId
                     << "(exit code:" << exitCode << ", manifest:" << manifestExists << ")";

            // Update the database: mark as installed
            Game game = m_db->getGameById(gameId);
            game.isInstalled = true;
            game.launchCommand = "steam steam://rungameid/" + appId;

            // Read the install path from the manifest
            QFile manifest(manifestPath);
            if (manifest.open(QIODevice::ReadOnly)) {
                QTextStream in(&manifest);
                QString content = in.readAll();
                QRegularExpression installDirRe("\"installdir\"\\s+\"([^\"]+)\"");
                auto match = installDirRe.match(content);
                if (match.hasMatch()) {
                    game.installPath = primarySteamApps + "/common/" + match.captured(1);
                }
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

    // Fall back to reading .acf manifest files
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
                            game.launchCommand = "steam steam://rungameid/" + appId;
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
    // Open the Steam API key page in a real browser, full screen.
    // In gamescope, we need explicit full-screen flags since xdg-open
    // doesn't pass them through. Try known browsers with kiosk/fullscreen.
    QString url = "https://steamcommunity.com/dev/apikey";

    // Try browsers in order of preference with full-screen flags
    struct BrowserOption {
        QString bin;
        QStringList args;
    };
    QVector<BrowserOption> browsers = {
        {"firefox",        {"--kiosk", url}},
        {"chromium",       {"--start-fullscreen", "--no-first-run", url}},
        {"chromium-browser", {"--start-fullscreen", "--no-first-run", url}},
        {"google-chrome",  {"--start-fullscreen", "--no-first-run", url}},
    };

    for (const auto& b : browsers) {
        QString path = QStandardPaths::findExecutable(b.bin);
        if (!path.isEmpty()) {
            QProcess::startDetached(path, b.args);
            qDebug() << "Opened API key page with" << b.bin << "(full screen)";
            return;
        }
    }

    // Fallback: xdg-open without full-screen (better than nothing)
    QProcess::startDetached("xdg-open", QStringList() << url);
    qDebug() << "Opened API key page with xdg-open (no full-screen flag)";
}

void GameManager::scrapeApiKeyFromPage() {
    // Auto-detect the Steam API key by reading Steam client's CEF cookie
    // database and fetching the API key page directly.
    //
    // When the user logs into the Steam client (step 1), it stores web
    // session cookies in an SQLite DB at:
    //   ~/.local/share/Steam/config/htmlcache/Cookies
    //
    // On Linux, CEF encrypts cookie values using Chrome's standard
    // encryption: AES-128-CBC with a key derived from password "peanuts",
    // salt "saltysalt", 1 PBKDF2 iteration, IV = 16 spaces (0x20).
    //
    // We use Python3 (stdlib only + openssl CLI) to:
    //   1. Copy the cookie DB to /tmp (avoid lock issues)
    //   2. Read steamLoginSecure cookie (try plaintext, then decrypt)
    //   3. Fetch steamcommunity.com/dev/apikey with that cookie
    //   4. Parse the 32-char hex key from the HTML

    QProcess *proc = new QProcess(this);
    QString steamDir = QDir::homePath() + "/.local/share/Steam";

    QString script = QString(
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
        "# Copy to /tmp to avoid SQLite lock issues\n"
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
        "    # Decrypt Chrome/CEF Linux cookie (AES-128-CBC)\n"
        "    key = hashlib.pbkdf2_hmac(\"sha1\", b\"peanuts\", b\"saltysalt\", 1, dklen=16)\n"
        "    data = encrypted[3:]  # strip v10/v11 prefix\n"
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
        emit apiKeyScrapeError(errMsg);
    });

    proc->start("bash", QStringList() << "-c" << script);
    qDebug() << "Auto-detecting Steam API key via cookie decryption...";
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
    // Don't pass +quit on the command line. SteamCMD needs time to
    // save the login token after a successful auth. If +quit is queued
    // upfront, it fires before the token is persisted and exits with
    // code 5. Instead, we write "quit" to stdin after login succeeds.
    QStringList args;
    args << "+login" << username;

    // Track whether we saw a successful login in stdout, because
    // SteamCMD's exit codes are unreliable (often exits 5 even on success).
    auto loginOk = std::make_shared<bool>(false);

    connect(m_steamCmdSetupProc, &QProcess::readyReadStandardOutput, this, [this, loginOk]() {
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
            // Successful login — SteamCMD prints these on a valid session.
            // Now tell it to quit so it exits cleanly after saving the token.
            if (trimmed.contains("Logged in OK", Qt::CaseInsensitive) ||
                trimmed.contains("Waiting for user info", Qt::CaseInsensitive)) {
                *loginOk = true;
                if (m_steamCmdSetupProc && m_steamCmdSetupProc->state() == QProcess::Running) {
                    m_steamCmdSetupProc->write("quit\n");
                }
            }
            // Login failure messages from SteamCMD itself
            if (trimmed.contains("FAILED login", Qt::CaseInsensitive) ||
                trimmed.contains("Invalid Password", Qt::CaseInsensitive) ||
                trimmed.contains("Login Failure", Qt::CaseInsensitive)) {
                *loginOk = false;
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
