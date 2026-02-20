#include "gamemanager.h"
#include "storebackends/steambackend.h"
#include "storebackends/heroicbackend.h"
#include "storebackends/epicbackend.h"
#include "storebackends/lutrisbackend.h"
#include "storebackends/custombackend.h"
#include <QProcess>
#include <QDebug>
#include <QVariantMap>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QStandardPaths>
#include <QCoreApplication>
#include <QNetworkInterface>
#include <QUrlQuery>
#include <QFileSystemWatcher>
#include <QPointer>
#include <QTextStream>
#include <QDateTime>
#include <QRegularExpression>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <memory>
#include <unistd.h>

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
    m_backends.append(new EpicBackend());
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

    // If Epic is set up, refresh the library from Legendary metadata
    if (isEpicLoggedIn()) {
        fetchEpicLibrary();
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
    // Steam is "available" if the user has logged in (library data exists).
    // Check both common Linux Steam paths — the canonical data directory
    // and the ~/.steam/steam symlink/directory — because the layout varies
    // between distros and bootstrap methods.
    QString home = QDir::homePath();
    return QFile::exists(home + "/.local/share/Steam/steamapps/libraryfolders.vdf")
        || QFile::exists(home + "/.steam/steam/steamapps/libraryfolders.vdf");
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

    // Kill any straggling Steam sub-processes (steamwebhelper, etc.)
    // left over from a previous session. If any survive with the
    // hardware survey queued, they'll show it when we start a new
    // Steam instance that inherits the backend.
    QProcess::execute("pkill", QStringList() << "-f" << "steamwebhelper");

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

void GameManager::restartSteam() {
    // After initial setup, Steam's running instance may have stale config
    // and report "no internet". Kill it and relaunch silently so it picks
    // up the new configuration (login tokens, library paths, etc.).
    qDebug() << "Restarting Steam to pick up new configuration...";
    QProcess::execute("pkill", QStringList() << "-x" << "steam");
    QProcess::execute("pkill", QStringList() << "-f" << "steamwebhelper");

    // Give Steam a moment to fully shut down before relaunching.
    QTimer::singleShot(2000, this, [this]() {
        ensureSteamRunning();
    });
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
    //
    // Write to BOTH possible registry.vdf locations. On some distros
    // ~/.steam is a symlink to ~/.local/share/Steam (same file), but
    // on others they're separate directories. Steam reads from its
    // own data dir so we must cover both.
    QStringList registryPaths = {
        QDir::homePath() + "/.steam/registry.vdf",
        QDir::homePath() + "/.local/share/Steam/registry.vdf"
    };

    QDir().mkpath(QDir::homePath() + "/.steam");
    QDir().mkpath(QDir::homePath() + "/.local/share/Steam");

    for (const QString& registryPath : registryPaths) {
        QString content;

        QFile readFile(registryPath);
        if (readFile.open(QIODevice::ReadOnly)) {
            content = QString::fromUtf8(readFile.readAll());
            readFile.close();
        }

        // If the file already has our suppression values, skip it
        if (content.contains("\"SurveyDate\"\t\t\"2030-01-01\"") &&
            content.contains("\"SurveyDateVersion\"")) {
            continue;
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
            if (!content.contains("\"SurveyDate\"")) {
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
            writeFile.flush();
            writeFile.close();
            qDebug() << "Updated hardware survey suppression in" << registryPath;
        }
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

void GameManager::logout() {
    // Cancel all active downloads so SteamCMD processes don't linger.
    QStringList activeApps = m_activeDownloads.keys();
    for (const QString& appId : activeApps) {
        cancelDownload(appId);
    }

    // Write a logout signal file. luna-session will see this and exit
    // cleanly, which returns the display to SDDM (login screen).
    QFile signal("/tmp/luna-logout");
    signal.open(QIODevice::WriteOnly);
    signal.close();

    // Give WebEngine time to flush persistent cookies to disk.
    // ForcePersistentCookies writes are asynchronous; quitting
    // immediately can lose in-flight cookie data.
    qInfo() << "[logout] flushing WebEngine cookies before quit...";
    QTimer::singleShot(500, qApp, &QCoreApplication::quit);
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
    // Only delete a stale connection profile if we are NOT currently on this
    // network.  Deleting the active connection disrupts the WiFi adapter and
    // causes "network not found" on the subsequent connect attempt.
    QString currentSsid = getConnectedWifi();
    if (!currentSsid.isEmpty() && currentSsid != ssid) {
        // Switching networks — safe to clean up a stale profile for the target
        QProcess deleteProc;
        deleteProc.start("nmcli", {"connection", "delete", "id", ssid});
        deleteProc.waitForFinished(3000);
    } else if (currentSsid.isEmpty()) {
        // Not connected to anything — safe to clean up stale profile
        QProcess deleteProc;
        deleteProc.start("nmcli", {"connection", "delete", "id", ssid});
        deleteProc.waitForFinished(3000);
    }

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

// ── Bluetooth management ──

void GameManager::scanBluetoothDevices() {
    // Power on the adapter first, then scan for a few seconds
    QProcess *powerProc = new QProcess(this);
    connect(powerProc, QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished),
            this, [this, powerProc](int, QProcess::ExitStatus) {
        powerProc->deleteLater();

        // Start discovery
        QProcess::startDetached("bluetoothctl", {"scan", "on"});

        // After 6 seconds, collect discovered devices
        QTimer::singleShot(6000, this, [this]() {
            QProcess *listProc = new QProcess(this);
            connect(listProc, QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished),
                    this, [this, listProc](int, QProcess::ExitStatus) {
                QVariantList devices;
                QString output = listProc->readAllStandardOutput();
                // bluetoothctl devices output: "Device AA:BB:CC:DD:EE:FF DeviceName"
                for (const QString& line : output.split('\n')) {
                    QString trimmed = line.trimmed();
                    if (!trimmed.startsWith("Device ")) continue;
                    // "Device " is 7 chars, MAC is 17 chars
                    if (trimmed.length() < 25) continue;
                    QString address = trimmed.mid(7, 17);
                    QString name = trimmed.mid(25).trimmed();
                    if (name.isEmpty()) name = address;

                    QVariantMap dev;
                    dev["address"] = address;
                    dev["name"] = name;
                    devices.append(dev);
                }
                // Stop scanning
                QProcess::startDetached("bluetoothctl", {"scan", "off"});
                emit bluetoothDevicesScanned(devices);
                listProc->deleteLater();
            });
            listProc->start("bluetoothctl", {"devices"});
        });
    });
    powerProc->start("bluetoothctl", {"power", "on"});
}

void GameManager::connectBluetooth(const QString& address) {
    // Pair first (no-op if already paired), then connect
    QProcess *pairProc = new QProcess(this);
    connect(pairProc, QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished),
            this, [this, pairProc, address](int, QProcess::ExitStatus) {
        pairProc->deleteLater();
        // Trust the device so it auto-reconnects
        QProcess::startDetached("bluetoothctl", {"trust", address});

        QProcess *connProc = new QProcess(this);
        connect(connProc, QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished),
                this, [this, connProc](int exitCode, QProcess::ExitStatus) {
            bool success = (exitCode == 0);
            QString msg = success
                ? "Connected"
                : QString(connProc->readAllStandardError() + connProc->readAllStandardOutput()).trimmed();
            emit bluetoothConnectResult(success, msg);
            connProc->deleteLater();
        });
        connProc->start("bluetoothctl", {"connect", address});
    });
    pairProc->start("bluetoothctl", {"pair", address});
}

void GameManager::disconnectBluetooth(const QString& address) {
    QProcess *proc = new QProcess(this);
    connect(proc, QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished),
            this, [this, proc](int exitCode, QProcess::ExitStatus) {
        bool success = (exitCode == 0);
        QString msg = success
            ? "Disconnected"
            : QString(proc->readAllStandardError()).trimmed();
        emit bluetoothDisconnectResult(success, msg);
        proc->deleteLater();
    });
    proc->start("bluetoothctl", {"disconnect", address});
}

QVariantList GameManager::getConnectedBluetoothDevices() {
    QVariantList devices;
    // List all known devices, then check which are connected
    QProcess listProc;
    listProc.start("bluetoothctl", {"devices", "Connected"});
    listProc.waitForFinished(3000);

    QString output = listProc.readAllStandardOutput();
    for (const QString& line : output.split('\n')) {
        QString trimmed = line.trimmed();
        if (!trimmed.startsWith("Device ")) continue;
        if (trimmed.length() < 25) continue;
        QString address = trimmed.mid(7, 17);
        QString name = trimmed.mid(25).trimmed();
        if (name.isEmpty()) name = address;

        QVariantMap dev;
        dev["address"] = address;
        dev["name"] = name;
        devices.append(dev);
    }
    return devices;
}

// ── Audio device management ──

QVariantList GameManager::getAudioOutputDevices() {
    QVariantList devices;
    QProcess proc;
    // pactl list sinks gives detailed info; parse Name and Description
    proc.start("pactl", {"list", "sinks"});
    proc.waitForFinished(3000);

    QString output = proc.readAllStandardOutput();
    QVariantMap current;
    for (const QString& line : output.split('\n')) {
        QString trimmed = line.trimmed();
        if (trimmed.startsWith("Name:")) {
            current = QVariantMap();
            current["name"] = trimmed.mid(5).trimmed();
        } else if (trimmed.startsWith("Description:") && current.contains("name")) {
            current["description"] = trimmed.mid(12).trimmed();
            devices.append(current);
        }
    }
    return devices;
}

QVariantList GameManager::getAudioInputDevices() {
    QVariantList devices;
    QProcess proc;
    proc.start("pactl", {"list", "sources"});
    proc.waitForFinished(3000);

    QString output = proc.readAllStandardOutput();
    QVariantMap current;
    for (const QString& line : output.split('\n')) {
        QString trimmed = line.trimmed();
        if (trimmed.startsWith("Name:")) {
            current = QVariantMap();
            current["name"] = trimmed.mid(5).trimmed();
            // Skip monitor sources (they echo output audio, not real mics)
        } else if (trimmed.startsWith("Description:") && current.contains("name")) {
            QString name = current["name"].toString();
            // Filter out .monitor sources — they're not real inputs
            if (!name.contains(".monitor")) {
                current["description"] = trimmed.mid(12).trimmed();
                devices.append(current);
            }
        }
    }
    return devices;
}

QString GameManager::getDefaultAudioOutput() {
    QProcess proc;
    proc.start("pactl", {"get-default-sink"});
    proc.waitForFinished(3000);
    return QString(proc.readAllStandardOutput()).trimmed();
}

QString GameManager::getDefaultAudioInput() {
    QProcess proc;
    proc.start("pactl", {"get-default-source"});
    proc.waitForFinished(3000);
    return QString(proc.readAllStandardOutput()).trimmed();
}

void GameManager::setAudioOutputDevice(const QString& name) {
    QProcess *proc = new QProcess(this);
    connect(proc, QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished),
            this, [this, proc](int exitCode, QProcess::ExitStatus) {
        bool success = (exitCode == 0);
        emit audioOutputSet(success, success ? "Output changed" : QString(proc->readAllStandardError()).trimmed());
        proc->deleteLater();
    });
    proc->start("pactl", {"set-default-sink", name});
}

void GameManager::setAudioInputDevice(const QString& name) {
    QProcess *proc = new QProcess(this);
    connect(proc, QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished),
            this, [this, proc](int exitCode, QProcess::ExitStatus) {
        bool success = (exitCode == 0);
        emit audioInputSet(success, success ? "Input changed" : QString(proc->readAllStandardError()).trimmed());
        proc->deleteLater();
    });
    proc->start("pactl", {"set-default-source", name});
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
        // Ensure the key is flushed to disk immediately so it survives
        // unexpected session termination (e.g., SDDM logout).
        file.flush();
        fsync(file.handle());
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

    // Route Epic games to Epic-specific installer
    if (game.storeSource == "epic" && !game.appId.isEmpty()) {
        installEpicGame(gameId);
        return;
    }

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
        // Remove from hash BEFORE deleteLater so provideSteamCmdCredential
        // can never find a pointer that's scheduled for deletion.
        m_steamCmdProcesses.remove(appId);
        proc->deleteLater();
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
    // Setup is "complete" when: Steam is logged in, API key is saved,
    // steamcmd is available, AND a cached login token exists.
    // Without the token check we'd report "connected" even when
    // SteamCMD will just re-prompt for credentials on every game install.
    if (!isSteamAvailable() || !hasSteamApiKey() || !isSteamCmdAvailable())
        return false;

    // SteamCMD stores login tokens in config/config.vdf relative to its
    // data directory. If this file is missing or empty, the login never
    // completed (e.g. crash during token save) and we should not report
    // setup as complete.
    QString tokenFile = steamCmdDataDir() + "/config/config.vdf";
    QFileInfo fi(tokenFile);
    return fi.exists() && fi.size() > 0;
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
    // --remote-allow-origins=*  is REQUIRED for Chromium 111+ — without it
    // the CDP WebSocket handshake is rejected (403) and BrowserBridge can
    // never connect for controller navigation.
    m_apiKeyBrowserType = "";
    QStringList cdpFlags = {"--kiosk", "--no-first-run",
                            "--window-size=" + geom, "--window-position=0,0",
                            "--remote-debugging-port=9222",
                            "--remote-allow-origins=*"};
    QVector<BrowserOption> browsers = {
        {"brave",            cdpFlags + QStringList{url}},
        {"brave-browser",    cdpFlags + QStringList{url}},
        {"chromium",         cdpFlags + QStringList{url}},
        {"chromium-browser", cdpFlags + QStringList{url}},
        {"google-chrome",    cdpFlags + QStringList{url}},
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
            emit browserOpened();
            return;
        }
    }

    // Fallback: xdg-open without full-screen
    qint64 pid = 0;
    QProcess::startDetached("xdg-open", QStringList() << url, QString(), &pid);
    m_apiKeyBrowserPid = pid;
    qDebug() << "Opened API key page with xdg-open (pid:" << pid << ")";
    emit browserOpened();
}

void GameManager::closeApiKeyBrowser() {
    // Delegate to the force-close implementation which uses SIGTERM,
    // falls back to SIGKILL, and waits for all browser processes to die.
    forceCloseApiKeyBrowser();
    emit browserClosed();
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

    // ── Log file setup ──
    // Writes a timestamped log to ~/.config/luna-ui/steamcmd-setup.log
    // so users can inspect the full SteamCMD output after login attempts.
    QString logDir = QDir::homePath() + "/.config/luna-ui";
    QDir().mkpath(logDir);
    auto logFile = std::make_shared<QFile>(logDir + "/steamcmd-setup.log");
    logFile->open(QIODevice::WriteOnly | QIODevice::Append | QIODevice::Text);
    auto writeLog = [logFile](const QString& msg) {
        if (!logFile->isOpen()) return;
        QString ts = QDateTime::currentDateTime().toString("yyyy-MM-dd hh:mm:ss.zzz");
        QTextStream out(logFile.get());
        out << "[" << ts << "] " << msg << "\n";
        out.flush();
    };

    writeLog("═══════════════════════════════════════════════════════");
    writeLog("SteamCMD setup login started");

    QString steamcmdBin = findSteamCmdBin();
    if (steamcmdBin.isEmpty()) {
        writeLog("ERROR: SteamCMD binary not found");
        emit steamCmdSetupLoginError("SteamCMD not found. It will be downloaded first.");
        // Trigger auto-download, then the QML wizard can retry
        ensureSteamCmd(-1);  // -1 = no game, just download steamcmd
        return;
    }
    writeLog("Binary: " + steamcmdBin);

    QString username = getSteamUsername();
    if (username.isEmpty()) {
        writeLog("ERROR: No Steam username detected");
        emit steamCmdSetupLoginError("No Steam account detected. Please complete Step 2 first.");
        return;
    }
    writeLog("Username: " + username);

    // Clean up any previous process that finished but wasn't fully cleaned
    if (m_steamCmdSetupProc) {
        writeLog("Cleaning up previous process");
        m_steamCmdSetupProc->deleteLater();
        m_steamCmdSetupProc = nullptr;
    }

    m_steamCmdSetupProc = new QProcess(this);
    // Always use the consistent data directory so login tokens are stored
    // where installGame() will find them — survives reboots and logouts.
    QString dataDir = steamCmdDataDir();
    m_steamCmdSetupProc->setWorkingDirectory(dataDir);
    writeLog("Working directory: " + dataDir);

    // Check for existing token
    QString tokenFile = dataDir + "/config/config.vdf";
    QFileInfo tokenInfo(tokenFile);
    writeLog("Token file: " + tokenFile + " (exists=" +
             (tokenInfo.exists() ? "yes" : "no") +
             ", size=" + QString::number(tokenInfo.size()) + ")");

    // Don't pass +quit on the command line. SteamCMD needs time to
    // save the login token after a successful auth. If +quit is queued
    // upfront, it fires before the token is persisted and exits with
    // code 5. Instead, we write "quit" to stdin after login succeeds.
    QStringList args;
    args << "+login" << username;
    writeLog("Args: +login " + username);

    // Track whether we saw a successful login in stdout, because
    // SteamCMD's exit codes are unreliable (often exits 5 even on success).
    auto loginOk = std::make_shared<bool>(false);

    // Track whether we're waiting for a Steam Guard code.  SteamCMD
    // outputs bare "OK" lines during normal auth handshake (e.g.
    // "Connecting...OK"), so we must not treat those as login success
    // while a guard code prompt is outstanding.
    auto awaitingGuard = std::make_shared<bool>(false);

    // Use QPointer to safely reference the process from lambdas — if the
    // QProcess is destroyed (e.g. GameManager teardown, cancel) the
    // QPointer becomes null and we avoid use-after-free crashes.
    QPointer<QProcess> procGuard = m_steamCmdSetupProc;

    // Timer to send quit after the login token has been saved.
    // SteamCMD prints "Logged in OK" → "Waiting for user info" → "OK"
    // → "Steam>" — only at the Steam> prompt has the token been persisted.
    // We wait for the Steam> prompt, or fall back to a 5-second delay.
    auto quitTimer = new QTimer(this);
    quitTimer->setSingleShot(true);
    quitTimer->setInterval(5000);
    QPointer<QTimer> quitTimerGuard = quitTimer;
    connect(quitTimer, &QTimer::timeout, this, [procGuard, writeLog]() {
        // Don't deleteLater() here — the finished handler owns cleanup.
        // Deleting the timer here would cause a use-after-free when
        // the finished handler tries to stop/delete it.
        writeLog("Quit timer fired (5s)");
        if (procGuard && procGuard->state() == QProcess::Running) {
            qDebug() << "[steamcmd-setup] quit timer fired, sending quit";
            writeLog("Sending 'quit' to SteamCMD");
            procGuard->write("quit\n");
        } else {
            writeLog("Process no longer running, skipping quit");
        }
    });

    // Capture stderr for the log
    connect(m_steamCmdSetupProc, &QProcess::readyReadStandardError, this, [procGuard, writeLog]() {
        if (!procGuard) return;
        QString output = QString::fromUtf8(procGuard->readAllStandardError());
        for (const QString& line : output.split('\n')) {
            QString trimmed = line.trimmed();
            if (trimmed.isEmpty()) continue;
            writeLog("[stderr] " + trimmed);
            qDebug() << "[steamcmd-setup stderr]" << trimmed;
        }
    });

    connect(m_steamCmdSetupProc, &QProcess::readyReadStandardOutput, this, [this, procGuard, loginOk, awaitingGuard, quitTimerGuard, writeLog]() {
        if (!procGuard) return;
        QString output = QString::fromUtf8(procGuard->readAllStandardOutput());
        for (const QString& line : output.split('\n')) {
            QString trimmed = line.trimmed();
            if (trimmed.isEmpty()) continue;
            writeLog("[stdout] " + trimmed);
            qDebug() << "[steamcmd-setup]" << trimmed;

            // Password prompt
            if (trimmed.contains("password:", Qt::CaseInsensitive)) {
                writeLog(">> Password prompt detected");
                emit steamCmdSetupCredentialNeeded("password");
                continue;
            }
            // Steam Guard / Two-factor / authenticator prompt.
            // Reset loginOk and stop the quit timer — a bare "OK" from
            // the auth handshake may have fired earlier, but we haven't
            // actually logged in yet.
            if (trimmed.contains("Steam Guard", Qt::CaseInsensitive) ||
                trimmed.contains("Two-factor", Qt::CaseInsensitive)) {
                writeLog(">> Steam Guard prompt detected — resetting loginOk, stopping quit timer");
                *loginOk = false;
                *awaitingGuard = true;
                if (quitTimerGuard)
                    quitTimerGuard->stop();
                emit steamCmdSetupCredentialNeeded("steamguard");
                continue;
            }
            // Successful login detected — but do NOT quit yet.
            // SteamCMD needs to finish saving the login token to disk.
            // Start a timeout; if we see the "Steam>" prompt we'll
            // quit sooner.
            // Only match the explicit "Logged in OK" message, not bare
            // "OK" lines which appear during the auth handshake before
            // login is complete.
            if (trimmed.contains("Logged in OK", Qt::CaseInsensitive)) {
                writeLog(">> 'Logged in OK' detected — starting 5s quit timer");
                *loginOk = true;
                *awaitingGuard = false;
                if (quitTimerGuard && !quitTimerGuard->isActive()) {
                    qDebug() << "[steamcmd-setup] login OK, waiting for token save...";
                    quitTimerGuard->start();
                }
            }
            // The Steam> prompt means SteamCMD is idle and the login
            // token has been written to config.vdf. If SteamCMD reached
            // the interactive prompt, authentication succeeded — even if
            // we never saw "Logged in OK" explicitly (modern SteamCMD
            // versions may skip that message after guard code auth).
            if (trimmed.startsWith("Steam>")) {
                writeLog(">> Steam> prompt detected — login succeeded, sending quit");
                *loginOk = true;
                *awaitingGuard = false;
                if (quitTimerGuard)
                    quitTimerGuard->stop();
                if (procGuard && procGuard->state() == QProcess::Running) {
                    qDebug() << "[steamcmd-setup] Steam> prompt seen, sending quit";
                    procGuard->write("quit\n");
                }
            }
            // Login failure messages from SteamCMD itself
            if (trimmed.contains("FAILED login", Qt::CaseInsensitive) ||
                trimmed.contains("Invalid Password", Qt::CaseInsensitive) ||
                trimmed.contains("Login Failure", Qt::CaseInsensitive)) {
                writeLog(">> LOGIN FAILED: " + trimmed);
                *loginOk = false;
                *awaitingGuard = false;
                if (quitTimerGuard)
                    quitTimerGuard->stop();
                if (procGuard && procGuard->state() == QProcess::Running) {
                    procGuard->write("quit\n");
                }
            }
        }
    });

    connect(m_steamCmdSetupProc, QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished),
            this, [this, loginOk, quitTimerGuard, writeLog](int exitCode, QProcess::ExitStatus exitStatus) {
        // Always clean up the timer — it may still be running if the
        // process exited before the timer fired (e.g. crash, kill).
        // Use QPointer guard to avoid use-after-free.
        if (quitTimerGuard) {
            quitTimerGuard->stop();
            quitTimerGuard->deleteLater();
        }

        writeLog("Process exited — code=" + QString::number(exitCode) +
                 " status=" + (exitStatus == QProcess::NormalExit ? "normal" : "crashed") +
                 " loginOk=" + (*loginOk ? "true" : "false"));

        // Check token file after exit
        QString tokenFile = steamCmdDataDir() + "/config/config.vdf";
        QFileInfo tokenInfo(tokenFile);
        writeLog("Token file after exit: exists=" +
                 QString(tokenInfo.exists() ? "yes" : "no") +
                 " size=" + QString::number(tokenInfo.size()));

        m_steamCmdSetupProc->deleteLater();
        m_steamCmdSetupProc = nullptr;

        // Trust the stdout "Logged in OK" over the exit code, because
        // SteamCMD frequently exits with code 5 even after a successful
        // login+quit sequence.
        if (*loginOk || exitCode == 0) {
            writeLog("RESULT: LOGIN SUCCESS");
            qDebug() << "SteamCMD setup login successful (exit code:" << exitCode << ")";
            emit steamCmdSetupLoginSuccess();
        } else {
            writeLog("RESULT: LOGIN FAILED");
            qDebug() << "SteamCMD setup login failed, exit code:" << exitCode;
            emit steamCmdSetupLoginError(
                "Login failed. Check your password or Steam Guard code and try again.");
        }
        writeLog("───────────────────────────────────────────────────────");
    });

    m_steamCmdSetupProc->start(steamcmdBin, args);
    writeLog("Process started (PID: " + QString::number(m_steamCmdSetupProc->processId()) + ")");
    qDebug() << "Started steamcmd setup login for user:" << username;
}

void GameManager::provideSteamCmdSetupCredential(const QString& credential) {
    // Append to the same log file for a complete timeline.
    QFile log(QDir::homePath() + "/.config/luna-ui/steamcmd-setup.log");
    if (log.open(QIODevice::WriteOnly | QIODevice::Append | QIODevice::Text)) {
        QString ts = QDateTime::currentDateTime().toString("yyyy-MM-dd hh:mm:ss.zzz");
        // Mask the credential — show type/length but not the value.
        QString masked = (credential.length() <= 6)
            ? "guard code (" + QString::number(credential.length()) + " chars)"
            : "password (" + QString::number(credential.length()) + " chars)";
        QTextStream(&log) << "[" << ts << "] Credential sent: " << masked << "\n";
    }

    if (m_steamCmdSetupProc && m_steamCmdSetupProc->state() == QProcess::Running) {
        m_steamCmdSetupProc->write((credential + "\n").toUtf8());
    }
}

void GameManager::cancelSteamCmdSetup() {
    QFile log(QDir::homePath() + "/.config/luna-ui/steamcmd-setup.log");
    if (log.open(QIODevice::WriteOnly | QIODevice::Append | QIODevice::Text)) {
        QString ts = QDateTime::currentDateTime().toString("yyyy-MM-dd hh:mm:ss.zzz");
        QTextStream(&log) << "[" << ts << "] Setup cancelled by user\n"
                          << "[" << ts << "] ───────────────────────────────────────────────────────\n";
    }

    if (m_steamCmdSetupProc && m_steamCmdSetupProc->state() == QProcess::Running) {
        m_steamCmdSetupProc->terminate();
        if (!m_steamCmdSetupProc->waitForFinished(3000)) {
            m_steamCmdSetupProc->kill();
        }
    }
    if (m_steamCmdSetupProc) {
        m_steamCmdSetupProc->deleteLater();
        m_steamCmdSetupProc = nullptr;
    }
}

// ═══════════════════════════════════════════════════════════════════
// Epic Games integration via Legendary
// ═══════════════════════════════════════════════════════════════════

QString GameManager::findLegendaryBin() const {
    QString inPath = QStandardPaths::findExecutable("legendary");
    if (!inPath.isEmpty()) return inPath;

    QString home = QDir::homePath();
    QStringList candidates = {
        home + "/.local/bin/legendary",
        "/usr/local/bin/legendary",
        "/usr/bin/legendary",
    };
    for (const QString& path : candidates) {
        if (QFile::exists(path)) return path;
    }
    return QString();
}

bool GameManager::isEpicAvailable() {
    return !findLegendaryBin().isEmpty();
}

bool GameManager::isEpicLoggedIn() {
    for (StoreBackend* backend : m_backends) {
        if (backend->name() == "epic") {
            EpicBackend* epic = static_cast<EpicBackend*>(backend);
            return epic->isLoggedIn();
        }
    }
    return false;
}

bool GameManager::isEpicSetupComplete() {
    return isEpicAvailable() && isEpicLoggedIn();
}

QString GameManager::getEpicUsername() {
    QString userFile = EpicBackend::legendaryConfigDir() + "/user.json";
    QFile file(userFile);
    if (!file.open(QIODevice::ReadOnly)) return QString();

    QJsonDocument doc = QJsonDocument::fromJson(file.readAll());
    if (doc.isNull() || !doc.isObject()) return QString();

    QJsonObject root = doc.object();
    // Legendary stores the display name in the user.json
    QString displayName = root["displayName"].toString();
    if (!displayName.isEmpty()) return displayName;

    // Fallback: try account_id
    return root["account_id"].toString();
}

void GameManager::ensureLegendary() {
    // Auto-install Legendary if not found.
    //
    // Fedora 42+ enforces PEP 668 ("externally managed" Python), so
    // bare `pip3 install --user` is rejected. We try multiple methods
    // in order of preference:
    //   1. pipx — Fedora's recommended way to install Python CLI tools
    //      (isolated venv, no system conflicts)
    //   2. pip3 --user --break-system-packages — override PEP 668 guard
    //      (works on any distro, slightly messy)
    //   3. pip3 --user — legacy fallback for older distros without PEP 668

    if (isEpicAvailable()) {
        qDebug() << "Legendary already available";
        emit legendaryInstalled();
        return;
    }

    QProcess *installProc = new QProcess(this);

    // Try each method in sequence; stop at the first success.
    // pipx installs into ~/.local/bin which is already in PATH on Fedora.
    QString script = R"(
        if command -v pipx &>/dev/null; then
            echo '[legendary-install] Trying pipx...'
            pipx install legendary-gl 2>&1 && echo 'LEGENDARY_READY' && exit 0
        fi

        if command -v pip3 &>/dev/null; then
            echo '[legendary-install] Trying pip3 --break-system-packages...'
            pip3 install --user --break-system-packages legendary-gl 2>&1 && echo 'LEGENDARY_READY' && exit 0

            echo '[legendary-install] Trying pip3 --user (legacy)...'
            pip3 install --user legendary-gl 2>&1 && echo 'LEGENDARY_READY' && exit 0
        fi

        echo '[legendary-install] No pip3 or pipx found'
        exit 1
    )";

    connect(installProc, QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished),
            this, [this, installProc](int exitCode, QProcess::ExitStatus) {
        QString output = QString::fromUtf8(installProc->readAllStandardOutput());
        installProc->deleteLater();

        if (exitCode == 0 && output.contains("LEGENDARY_READY")) {
            qDebug() << "Legendary installed successfully";
            emit legendaryInstalled();
        } else {
            QString err = output.trimmed();
            if (err.length() > 300) err = err.right(300);
            qDebug() << "Failed to install Legendary:" << err;
            emit legendaryInstallError(
                "Failed to install Legendary automatically.\n"
                "Try manually: pipx install legendary-gl\n"
                "Or: pip3 install --user --break-system-packages legendary-gl");
        }
    });

    installProc->start("bash", QStringList() << "-c" << script);
    qDebug() << "Installing Legendary...";
}

void GameManager::epicLogin() {
    QString bin = findLegendaryBin();
    if (bin.isEmpty()) {
        emit epicLoginError("Legendary not found. Please install it first.");
        return;
    }

    if (m_epicLoginProc && m_epicLoginProc->state() == QProcess::Running) {
        qDebug() << "Epic login already in progress";
        return;
    }

    if (m_epicLoginProc) {
        m_epicLoginProc->deleteLater();
        m_epicLoginProc = nullptr;
    }

    m_epicLoginProc = new QProcess(this);
    emit epicLoginStarted();

    // Legendary auth opens a browser for Epic OAuth. The user logs in on
    // Epic's site and is redirected back with an auth code that Legendary
    // captures to generate tokens stored in ~/.config/legendary/user.json.
    //
    // Known issue: Epic sometimes requires a "corrective action" (e.g.
    // accepting an updated privacy policy) before issuing tokens. The
    // OAuth redirect page shows a raw JSON error instead of a form to
    // accept. When we detect this, we open Epic's correction page in the
    // browser so the user can accept, then ask them to retry.

    // Accumulate output to detect the corrective action error
    auto *loginOutput = new QString();

    connect(m_epicLoginProc, &QProcess::readyReadStandardOutput, this, [this, loginOutput]() {
        if (!m_epicLoginProc) return;
        QString output = QString::fromUtf8(m_epicLoginProc->readAllStandardOutput());
        loginOutput->append(output);
        qDebug() << "[epic-login]" << output.trimmed();
    });

    connect(m_epicLoginProc, &QProcess::readyReadStandardError, this, [this, loginOutput]() {
        if (!m_epicLoginProc) return;
        QString output = QString::fromUtf8(m_epicLoginProc->readAllStandardError());
        loginOutput->append(output);
        qDebug() << "[epic-login stderr]" << output.trimmed();
    });

    connect(m_epicLoginProc, QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished),
            this, [this, loginOutput](int exitCode, QProcess::ExitStatus) {
        if (m_epicLoginProc) {
            m_epicLoginProc->deleteLater();
            m_epicLoginProc = nullptr;
        }

        // Verify login succeeded by checking for user.json
        if (isEpicLoggedIn()) {
            qDebug() << "Epic Games login successful";
            delete loginOutput;
            emit epicLoginSuccess();

            // Immediately sync the library metadata
            fetchEpicLibrary();
            return;
        }

        // Check for the corrective action error (privacy policy, EULA, etc.)
        // Epic returns this as JSON in the OAuth redirect when policies
        // need to be accepted before tokens can be issued.
        bool needsCorrection = loginOutput->contains("corrective_action_required") ||
                               loginOutput->contains("PRIVACY_POLICY_ACCEPTANCE") ||
                               loginOutput->contains("correctiveAction");
        delete loginOutput;

        if (needsCorrection) {
            qDebug() << "[epic-login] Corrective action required — opening Epic's correction page";

            // Open Epic's correction/policy page in the browser so the
            // user can accept the privacy policy or EULA
            QProcess::startDetached("xdg-open",
                QStringList() << "https://www.epicgames.com");

            emit epicLoginError(
                "Epic requires you to accept an updated privacy policy.\n\n"
                "A browser window has been opened to epicgames.com.\n"
                "Please log in and accept the policy, then click\n"
                "\"Log In to Epic\" again.");
        } else if (exitCode == 0) {
            // Exit 0 but no token — may happen if user closed browser
            emit epicLoginError("Login was not completed. Please try again.");
        } else {
            emit epicLoginError("Login failed. Please try again.");
        }
    });

    // Run `legendary auth` which handles the full browser-based OAuth flow
    m_epicLoginProc->start(bin, QStringList() << "auth");
    qDebug() << "Starting Epic Games login via Legendary...";
}

QString GameManager::getEpicLoginUrl() {
    // Epic OAuth login page that redirects with an authorization code.
    // Client ID 34a02cf8f4414e29b15921876da36f9a is the Epic Games launcher
    // client used by Legendary.
    return QStringLiteral(
        "https://www.epicgames.com/id/login"
        "?redirectUrl=https%3A%2F%2Fwww.epicgames.com%2Fid%2Fapi%2Fredirect"
        "%3FclientId%3D34a02cf8f4414e29b15921876da36f9a%26responseType%3Dcode");
}

void GameManager::epicLoginWithCode(const QString& authorizationCode) {
    QString bin = findLegendaryBin();
    if (bin.isEmpty()) {
        emit epicLoginError("Legendary not found. Please install it first.");
        return;
    }

    if (authorizationCode.trimmed().isEmpty()) {
        emit epicLoginError("No authorization code received.");
        return;
    }

    if (m_epicLoginProc && m_epicLoginProc->state() == QProcess::Running) {
        qDebug() << "Epic login already in progress";
        return;
    }

    if (m_epicLoginProc) {
        m_epicLoginProc->deleteLater();
        m_epicLoginProc = nullptr;
    }

    m_epicLoginProc = new QProcess(this);
    emit epicLoginStarted();

    auto *loginOutput = new QString();

    connect(m_epicLoginProc, &QProcess::readyReadStandardOutput, this, [this, loginOutput]() {
        if (!m_epicLoginProc) return;
        QString chunk = QString::fromUtf8(m_epicLoginProc->readAllStandardOutput()).trimmed();
        qDebug() << "[epic-login-code]" << chunk;
        loginOutput->append(chunk);
    });

    connect(m_epicLoginProc, &QProcess::readyReadStandardError, this, [this, loginOutput]() {
        if (!m_epicLoginProc) return;
        QString chunk = QString::fromUtf8(m_epicLoginProc->readAllStandardError()).trimmed();
        qDebug() << "[epic-login-code stderr]" << chunk;
        loginOutput->append(chunk);
    });

    connect(m_epicLoginProc, QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished),
            this, [this, loginOutput](int exitCode, QProcess::ExitStatus) {
        if (m_epicLoginProc) {
            m_epicLoginProc->deleteLater();
            m_epicLoginProc = nullptr;
        }

        if (isEpicLoggedIn()) {
            qDebug() << "Epic Games login via code successful";
            delete loginOutput;
            emit epicLoginSuccess();
            fetchEpicLibrary();
            return;
        }

        // Check for the corrective action error (privacy policy, EULA, etc.)
        bool needsCorrection = loginOutput->contains("corrective_action_required") ||
                               loginOutput->contains("PRIVACY_POLICY_ACCEPTANCE") ||
                               loginOutput->contains("correctiveAction");
        delete loginOutput;

        if (needsCorrection) {
            qDebug() << "[epic-login-code] Corrective action required — privacy policy";
            emit epicLoginError(
                "Epic requires you to accept an updated privacy policy.\n\n"
                "Please click \"Log In to Epic\" again — you will be\n"
                "directed to accept the policy first.");
        } else if (exitCode == 0) {
            emit epicLoginError("Login was not completed. Please try again.");
        } else {
            emit epicLoginError("Login failed (code may have expired). Please try again.");
        }
    });

    qDebug() << "Exchanging Epic authorization code via Legendary...";
    m_epicLoginProc->start(bin, QStringList() << "auth" << "--code" << authorizationCode.trimmed());
}

void GameManager::epicLogout() {
    QString bin = findLegendaryBin();
    if (bin.isEmpty()) return;

    QProcess *proc = new QProcess(this);
    connect(proc, QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished),
            this, [this, proc](int, QProcess::ExitStatus) {
        proc->deleteLater();
        qDebug() << "Epic Games logout complete";
        emit gamesUpdated();
    });

    proc->start(bin, QStringList() << "auth" << "--delete");
}

void GameManager::fetchEpicLibrary() {
    QString bin = findLegendaryBin();
    if (bin.isEmpty()) {
        emit epicLibraryFetchError("Legendary not found");
        return;
    }
    if (!isEpicLoggedIn()) {
        emit epicLibraryFetchError("Not logged in to Epic Games");
        return;
    }

    QProcess *proc = new QProcess(this);

    connect(proc, QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished),
            this, [this, proc](int exitCode, QProcess::ExitStatus) {
        proc->deleteLater();

        if (exitCode != 0) {
            QString err = QString::fromUtf8(proc->readAllStandardError()).trimmed();
            qDebug() << "[epic] list-games failed:" << err;
            // Even if the command fails, try scanning local metadata
        }

        // After `legendary list-games`, metadata files are written to
        // ~/.config/legendary/metadata/. Scan those via the backend.
        EpicBackend* epic = nullptr;
        for (StoreBackend* backend : m_backends) {
            if (backend->name() == "epic") {
                epic = static_cast<EpicBackend*>(backend);
                break;
            }
        }
        if (!epic) {
            emit epicLibraryFetchError("Epic backend not found");
            return;
        }

        QVector<Game> games = epic->scanLibrary();
        int count = 0;
        for (const Game& game : games) {
            m_db->addOrUpdateGame(game);
            count++;
        }

        qDebug() << "Fetched" << count << "Epic Games via Legendary";
        emit epicLibraryFetched(count);
        emit gamesUpdated();
    });

    // `legendary list-games` refreshes metadata from Epic's servers
    // and writes JSON files to ~/.config/legendary/metadata/
    proc->start(bin, QStringList() << "list-games" << "--json");
    qDebug() << "Fetching Epic Games library via Legendary...";
}

void GameManager::installEpicGame(int gameId) {
    Game game = m_db->getGameById(gameId);
    if (game.storeSource != "epic" || game.appId.isEmpty()) return;

    // Already downloading?
    if (m_activeDownloads.contains(game.appId)) return;

    QString bin = findLegendaryBin();
    if (bin.isEmpty()) {
        emit epicInstallError(game.appId, "Legendary not found. Please install it first.");
        return;
    }

    if (!isEpicLoggedIn()) {
        emit epicInstallError(game.appId, "Not logged in to Epic Games. Please log in first.");
        return;
    }

    m_activeDownloads.insert(game.appId, gameId);
    m_downloadProgressCache.insert(game.appId, 0.0);
    emit epicDownloadStarted(game.appId, gameId);
    emit downloadStarted(game.appId, gameId);

    QProcess *proc = new QProcess(this);

    // Parse Legendary's download progress output
    connect(proc, &QProcess::readyReadStandardError, this, [this, proc, appId = game.appId]() {
        handleLegendaryOutput(appId, proc);
    });

    connect(proc, &QProcess::readyReadStandardOutput, this, [this, proc, appId = game.appId]() {
        handleLegendaryOutput(appId, proc);
    });

    connect(proc, QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished),
            this, [this, proc, appId = game.appId, gameId](int exitCode, QProcess::ExitStatus) {
        m_legendaryProcesses.remove(appId);
        proc->deleteLater();
        m_downloadProgressCache.remove(appId);

        if (exitCode == 0) {
            qDebug() << "[epic] Installation complete for" << appId;

            Game game = m_db->getGameById(gameId);
            game.isInstalled = true;
            game.launchCommand = "legendary launch " + appId;

            // Read install path from installed.json
            QString installedPath = EpicBackend::legendaryConfigDir() + "/installed.json";
            QFile instFile(installedPath);
            if (instFile.open(QIODevice::ReadOnly)) {
                QJsonDocument instDoc = QJsonDocument::fromJson(instFile.readAll());
                if (!instDoc.isNull() && instDoc.isObject()) {
                    QJsonObject instObj = instDoc.object()[appId].toObject();
                    game.installPath = instObj["install_path"].toString();
                }
            }

            m_db->updateGame(game);
            m_activeDownloads.remove(appId);
            emit epicDownloadComplete(appId, gameId);
            emit downloadComplete(appId, gameId);
            emit gamesUpdated();
        } else {
            qDebug() << "[epic] Installation failed for" << appId << "exit code:" << exitCode;
            m_activeDownloads.remove(appId);
            emit epicInstallError(appId, "Installation failed. Check your connection and try again.");
            emit downloadProgressChanged(appId, -1.0);
        }

        if (m_activeDownloads.isEmpty()) {
            m_downloadMonitor->stop();
        }
    });

    m_legendaryProcesses.insert(game.appId, proc);

    // `legendary install <app_name> -y` installs without confirmation prompt
    proc->start(bin, QStringList() << "install" << game.appId << "-y");

    if (!m_downloadMonitor->isActive()) {
        m_downloadMonitor->start(2000);
    }

    qDebug() << "[epic] Started download for" << game.title << "(appId:" << game.appId << ")";
}

void GameManager::handleLegendaryOutput(const QString& appId, QProcess *proc) {
    // Legendary outputs progress to stderr in the format:
    // [DLManager] INFO: = Progress: 12.34% (1234/5678), Running for 00:01:23, ETA: 00:05:00
    // [DLManager] INFO: = Downloaded: 1.23 GiB, Written: 1.45 GiB
    // Also check stdout for some messages
    QString output = QString::fromUtf8(proc->readAllStandardError())
                   + QString::fromUtf8(proc->readAllStandardOutput());

    for (const QString& line : output.split('\n')) {
        QString trimmed = line.trimmed();
        if (trimmed.isEmpty()) continue;

        qDebug() << "[legendary]" << appId << ":" << trimmed;

        // Parse progress: "Progress: XX.XX% (downloaded/total)"
        QRegularExpression progressRe("Progress:\\s+(\\d+\\.?\\d*)%");
        auto match = progressRe.match(trimmed);
        if (match.hasMatch()) {
            double pct = match.captured(1).toDouble() / 100.0;
            pct = qBound(0.0, pct, 1.0);
            m_downloadProgressCache.insert(appId, pct);
            emit downloadProgressChanged(appId, pct);
            emit epicDownloadProgressChanged(appId, pct);
            continue;
        }

        // Detect completion
        if (trimmed.contains("Finished installation", Qt::CaseInsensitive) ||
            trimmed.contains("Game has been successfully installed", Qt::CaseInsensitive)) {
            m_downloadProgressCache.insert(appId, 1.0);
            emit downloadProgressChanged(appId, 1.0);
            emit epicDownloadProgressChanged(appId, 1.0);
        }

        // Detect errors
        if (trimmed.contains("ERROR", Qt::CaseInsensitive) ||
            trimmed.contains("CRITICAL", Qt::CaseInsensitive)) {
            // Don't emit for every stderr line that says "error" — only real failures
            if (trimmed.contains("Login failed", Qt::CaseInsensitive) ||
                trimmed.contains("not found", Qt::CaseInsensitive) ||
                trimmed.contains("disk space", Qt::CaseInsensitive)) {
                emit epicInstallError(appId, trimmed);
                emit installError(appId, trimmed);
            }
        }
    }
}

void GameManager::cancelEpicDownload(const QString& appId) {
    if (m_legendaryProcesses.contains(appId)) {
        QProcess *proc = m_legendaryProcesses.value(appId);
        if (proc && proc->state() == QProcess::Running) {
            proc->terminate();
            if (!proc->waitForFinished(3000)) {
                proc->kill();
            }
        }
    }
    m_activeDownloads.remove(appId);
    m_downloadProgressCache.remove(appId);
    emit downloadProgressChanged(appId, -1.0);
    qDebug() << "[epic] Cancelled download for appId:" << appId;
}
