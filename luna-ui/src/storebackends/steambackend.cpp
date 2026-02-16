#include "steambackend.h"
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QTextStream>
#include <QProcess>
#include <QProcessEnvironment>
#include <QRegularExpression>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QSet>
#include <QDebug>

// Steam tools, runtimes, and redistributables that aren't actual games.
// Filter these from the library so only playable games show up.
static bool isSteamTool(const QString& appId, const QString& name) {
    // Known non-game appIds (Proton versions, runtimes, redistributables)
    static const QSet<QString> toolAppIds = {
        "228980",   // Steamworks Common Redistributables
        "1007",     // Steam Client
        "1070560",  // Steam Linux Runtime
        "1391110",  // Steam Linux Runtime - Soldier
        "1628350",  // Steam Linux Runtime - Sniper
        "1493710",  // Proton Experimental
        "2180100",  // Proton Hotfix
        "858280",   // Proton 3.7
        "930400",   // Proton 3.16
        "961940",   // Proton 4.2
        "1054830",  // Proton 4.11
        "1113280",  // Proton 5.0
        "1245040",  // Proton 5.13
        "1420170",  // Proton 6.3
        "1580130",  // Proton 7.0
        "2348590",  // Proton 8.0
        "2805730",  // Proton 9.0
        "1887720",  // Proton EasyAntiCheat Runtime
        "1161040",  // Proton BattlEye Runtime
        "250820",   // SteamVR
        "1974050",  // Proton Next
    };

    if (toolAppIds.contains(appId))
        return true;

    // Name-based filtering for tools we might not know the appId of
    // (e.g., future Proton versions)
    QString lower = name.toLower();
    if (lower.startsWith("proton ") || lower == "proton experimental")
        return true;
    if (lower.contains("steam linux runtime"))
        return true;
    if (lower.contains("steamworks common redistributable"))
        return true;
    if (lower == "steamvr")
        return true;

    return false;
}

bool SteamBackend::isAvailable() const {
    return QFile::exists(QDir::homePath() + "/.local/share/Steam/steamapps/libraryfolders.vdf");
}

QVector<Game> SteamBackend::scanLibrary() {
    QVector<Game> games;
    QVector<QString> folders = getLibraryFolders();

    for (const QString& folder : folders) {
        QDir steamapps(folder + "/steamapps");
        QStringList manifests = steamapps.entryList(QStringList() << "appmanifest_*.acf", QDir::Files);
        for (const QString& manifest : manifests) {
            Game game = parseAppManifest(steamapps.absoluteFilePath(manifest));
            if (!game.title.isEmpty() && !isSteamTool(game.appId, game.title)) {
                games.append(game);
            }
        }
    }
    return games;
}

// NOTE (FIX #21): This VDF parser is intentionally simplified and uses regex
// for basic key-value extraction. It does NOT handle nested structures,
// escaped quotes, or multi-line values. For a production system, consider
// using a proper VDF parser library (e.g., vdf-parser).
// This is sufficient for parsing libraryfolders.vdf and appmanifest files.
QVector<QString> SteamBackend::getLibraryFolders() {
    QVector<QString> folders;
    QString vdfPath = QDir::homePath() + "/.local/share/Steam/steamapps/libraryfolders.vdf";
    QFile file(vdfPath);
    if (!file.open(QIODevice::ReadOnly)) return folders;

    QTextStream in(&file);
    QString content = in.readAll();

    // Parse "path" entries from VDF
    QRegularExpression pathRe("\"path\"\\s+\"([^\"]+)\"");
    auto matches = pathRe.globalMatch(content);
    while (matches.hasNext()) {
        auto match = matches.next();
        folders.append(match.captured(1));
    }

    // Also include SteamCMD's data directory. SteamCMD installs games
    // to ~/.steam/steamcmd/ which is NOT listed in libraryfolders.vdf.
    // After relog, the Steam client may remove the symlinked manifests
    // we copied into its library, making SteamCMD-installed games
    // invisible. Including SteamCMD's path ensures they're always found.
    QString steamCmdDir = QDir::homePath() + "/.steam/steamcmd";
    if (QDir(steamCmdDir + "/steamapps").exists() && !folders.contains(steamCmdDir)) {
        folders.append(steamCmdDir);
    }

    return folders;
}

Game SteamBackend::parseAppManifest(const QString& manifestPath) {
    Game game;
    game.storeSource = "steam";

    QFile file(manifestPath);
    if (!file.open(QIODevice::ReadOnly)) return game;

    QTextStream in(&file);
    QString content = in.readAll();

    QRegularExpression appidRe("\"appid\"\\s+\"(\\d+)\"");
    auto appidMatch = appidRe.match(content);
    if (appidMatch.hasMatch()) {
        game.appId = appidMatch.captured(1);
    }

    QRegularExpression nameRe("\"name\"\\s+\"([^\"]+)\"");
    auto nameMatch = nameRe.match(content);
    if (nameMatch.hasMatch()) {
        game.title = nameMatch.captured(1);
    }

    QRegularExpression installRe("\"installdir\"\\s+\"([^\"]+)\"");
    auto installMatch = installRe.match(content);
    if (installMatch.hasMatch()) {
        game.installPath = installMatch.captured(1);
    }

    game.launchCommand = "steam -silent steam://rungameid/" + game.appId;
    game.isInstalled = true;

    QString gridPath = QDir::homePath() + "/.local/share/Steam/appcache/librarycache/" + game.appId + "_library_600x900.jpg";
    if (QFile::exists(gridPath)) {
        game.coverArtUrl = gridPath;
        qDebug() << "[steam-artwork] installed" << game.appId << game.title << "-> local cache:" << gridPath;
    } else {
        game.coverArtUrl = "https://steamcdn-a.akamaihd.net/steam/apps/" + game.appId + "/library_600x900_2x.jpg";
        qDebug() << "[steam-artwork] installed" << game.appId << game.title << "-> local cache MISSING, using CDN:" << game.coverArtUrl;
    }

    return game;
}

// ═══════════════════════════════════════════════════════════════════
// Game launching — direct executable to bypass Steam's launch dialog
// ═══════════════════════════════════════════════════════════════════

bool SteamBackend::launchGame(const Game& game) {
    // Try to run the game executable directly, bypassing Steam's
    // "Preparing to launch..." popup. Falls back to steam:// protocol
    // if we can't find the executable.
    QString gameDir = findGameDirectory(game.appId);
    if (!gameDir.isEmpty()) {
        QString steamRoot = QDir::homePath() + "/.local/share/Steam";

        QProcessEnvironment env = QProcessEnvironment::systemEnvironment();
        env.insert("SteamAppId", game.appId);
        env.insert("SteamGameId", game.appId);
        env.insert("SteamNoOverlayUIDrawing", "1");
        env.insert("STEAM_COMPAT_CLIENT_INSTALL_PATH", steamRoot);

        if (isProtonGame(game.appId)) {
            bool ok = launchProtonGame(game, gameDir, env);
            if (ok) return true;
        } else {
            bool ok = launchNativeGame(game, gameDir, env);
            if (ok) return true;
        }
    }

    qDebug() << "[steam-launch] direct launch failed, falling back to steam:// protocol for" << game.appId;
    return steamProtocolLaunch(game);
}

bool SteamBackend::launchNativeGame(const Game& game, const QString& gameDir,
                                     QProcessEnvironment env) {
    QString exe = findNativeExecutable(gameDir);
    if (exe.isEmpty()) {
        qDebug() << "[steam-launch] no native executable found in" << gameDir;
        return false;
    }

    qDebug() << "[steam-launch] native direct launch:" << exe;

    // Use Steam runtime if available (provides the libraries many games need)
    QString runtimeRunner = QDir::homePath() +
        "/.local/share/Steam/ubuntu12_32/steam-runtime/run.sh";

    QProcess proc;
    proc.setProcessEnvironment(env);
    proc.setWorkingDirectory(gameDir);

    if (QFile::exists(runtimeRunner)) {
        proc.setProgram(runtimeRunner);
        proc.setArguments(QStringList() << exe);
    } else {
        proc.setProgram(exe);
    }

    return proc.startDetached();
}

bool SteamBackend::launchProtonGame(const Game& game, const QString& gameDir,
                                     QProcessEnvironment env) {
    QString exe = findProtonExecutable(gameDir);
    if (exe.isEmpty()) {
        qDebug() << "[steam-launch] no .exe found in" << gameDir;
        return false;
    }

    QString protonBin = findProtonBinary();
    if (protonBin.isEmpty()) {
        qDebug() << "[steam-launch] no Proton installation found";
        return false;
    }

    // Find the compatdata path for this game's Wine prefix
    QString compatData = findCompatDataPath(game.appId);
    if (compatData.isEmpty()) {
        qDebug() << "[steam-launch] no compatdata for" << game.appId;
        return false;
    }

    qDebug() << "[steam-launch] proton direct launch:" << protonBin << "run" << exe;

    env.insert("STEAM_COMPAT_DATA_PATH", compatData);

    QProcess proc;
    proc.setProcessEnvironment(env);
    proc.setWorkingDirectory(gameDir);
    proc.setProgram(protonBin);
    proc.setArguments(QStringList() << "run" << exe);

    return proc.startDetached();
}

bool SteamBackend::steamProtocolLaunch(const Game& game) {
    // Fallback: use steam:// protocol (shows the "Preparing to launch" popup
    // but works for all games regardless of launch configuration complexity)
    QString url = "steam://rungameid/" + game.appId;
    qputenv("SteamNoOverlayUIDrawing", "1");

    QProcess pgrep;
    pgrep.start("pgrep", QStringList() << "-x" << "steam");
    pgrep.waitForFinished(2000);

    if (pgrep.exitCode() == 0) {
        return QProcess::startDetached("xdg-open", QStringList() << url);
    }

    return QProcess::startDetached("steam", QStringList()
        << "-silent" << url);
}

// ═══════════════════════════════════════════════════════════════════
// Helpers for finding game executables and directories
// ═══════════════════════════════════════════════════════════════════

QString SteamBackend::findGameDirectory(const QString& appId) {
    // Search all library folders for this game's manifest, then resolve
    // the install directory from it. More robust than using the stored
    // installPath since it always reads the live manifest.
    QVector<QString> folders = getLibraryFolders();
    for (const QString& folder : folders) {
        QString manifestPath = folder + "/steamapps/appmanifest_" + appId + ".acf";
        if (!QFile::exists(manifestPath)) continue;

        QFile file(manifestPath);
        if (!file.open(QIODevice::ReadOnly)) continue;

        QTextStream in(&file);
        QString content = in.readAll();

        QRegularExpression installRe("\"installdir\"\\s+\"([^\"]+)\"");
        auto match = installRe.match(content);
        if (match.hasMatch()) {
            QString dir = folder + "/steamapps/common/" + match.captured(1);
            if (QDir(dir).exists()) return dir;
        }
    }
    return QString();
}

bool SteamBackend::isProtonGame(const QString& appId) {
    QVector<QString> folders = getLibraryFolders();
    for (const QString& folder : folders) {
        if (QDir(folder + "/steamapps/compatdata/" + appId).exists())
            return true;
    }
    return false;
}

QString SteamBackend::findNativeExecutable(const QString& gameDir) {
    QDir dir(gameDir);

    // 1. Prefer known launch script names
    static const QStringList preferredScripts = {
        "start_game.sh", "run.sh", "start.sh", "launch.sh", "game.sh"
    };
    for (const QString& name : preferredScripts) {
        QString path = dir.absoluteFilePath(name);
        if (QFile::exists(path)) return path;
    }

    // 2. Any .sh script in root
    QStringList shFiles = dir.entryList(QStringList() << "*.sh",
        QDir::Files | QDir::Executable);
    if (!shFiles.isEmpty()) {
        return dir.absoluteFilePath(shFiles.first());
    }

    // 3. Look for ELF binaries in root (skip shared libs)
    QStringList allFiles = dir.entryList(QDir::Files | QDir::Executable);
    for (const QString& file : allFiles) {
        if (file.endsWith(".so") || file.endsWith(".sh") ||
            file.startsWith("lib") || file.contains(".so."))
            continue;

        QString fullPath = dir.absoluteFilePath(file);
        QFile f(fullPath);
        if (f.open(QIODevice::ReadOnly)) {
            QByteArray magic = f.read(4);
            if (magic.size() >= 4 &&
                magic[0] == 0x7f && magic[1] == 'E' &&
                magic[2] == 'L' && magic[3] == 'F') {
                return fullPath;
            }
        }
    }

    // 4. Check bin/ subdirectory
    QDir binDir(gameDir + "/bin");
    if (binDir.exists()) {
        QStringList binFiles = binDir.entryList(QDir::Files | QDir::Executable);
        for (const QString& file : binFiles) {
            if (file.endsWith(".so") || file.startsWith("lib")) continue;
            QString fullPath = binDir.absoluteFilePath(file);
            QFile f(fullPath);
            if (f.open(QIODevice::ReadOnly)) {
                QByteArray magic = f.read(4);
                if (magic.size() >= 4 &&
                    magic[0] == 0x7f && magic[1] == 'E' &&
                    magic[2] == 'L' && magic[3] == 'F') {
                    return fullPath;
                }
            }
        }
    }

    return QString();
}

QString SteamBackend::findProtonExecutable(const QString& gameDir) {
    QDir dir(gameDir);
    QStringList exeFiles = dir.entryList(QStringList() << "*.exe",
        QDir::Files, QDir::Size | QDir::Reversed);

    // Skip known non-game executables
    static const QStringList skipExes = {
        "UnityCrashHandler64.exe", "UnityCrashHandler32.exe",
        "CrashReportClient.exe", "CrashHandler.exe",
        "unins000.exe", "Uninstall.exe",
        "dxsetup.exe", "DXSETUP.exe", "vcredist_x64.exe", "vcredist_x86.exe"
    };

    // Return the largest non-skipped exe (main game binary is usually biggest)
    for (const QString& exe : exeFiles) {
        bool skip = false;
        for (const QString& s : skipExes) {
            if (exe.compare(s, Qt::CaseInsensitive) == 0) { skip = true; break; }
        }
        if (!skip) return dir.absoluteFilePath(exe);
    }

    return QString();
}

QString SteamBackend::findProtonBinary() {
    QVector<QString> folders = getLibraryFolders();

    for (const QString& folder : folders) {
        QString commonDir = folder + "/steamapps/common";
        QDir common(commonDir);

        // Prefer Proton Experimental (most commonly used)
        QString experimental = commonDir + "/Proton - Experimental/proton";
        if (QFile::exists(experimental)) return experimental;

        // Fall back to numbered versions (highest first)
        QStringList protonDirs = common.entryList(
            QStringList() << "Proton *", QDir::Dirs,
            QDir::Name | QDir::Reversed);

        for (const QString& d : protonDirs) {
            QString protonScript = commonDir + "/" + d + "/proton";
            if (QFile::exists(protonScript)) return protonScript;
        }
    }
    return QString();
}

QString SteamBackend::findCompatDataPath(const QString& appId) {
    QVector<QString> folders = getLibraryFolders();
    for (const QString& folder : folders) {
        QString path = folder + "/steamapps/compatdata/" + appId;
        if (QDir(path).exists()) return path;
    }
    return QString();
}

// ═══════════════════════════════════════════════════════════════════
// Utility methods
// ═══════════════════════════════════════════════════════════════════

QString SteamBackend::getLoggedInSteamId() const {
    QString loginUsersPath = QDir::homePath() + "/.local/share/Steam/config/loginusers.vdf";
    QFile file(loginUsersPath);
    if (!file.open(QIODevice::ReadOnly)) return QString();

    QTextStream in(&file);
    QString content = in.readAll();

    // loginusers.vdf structure:
    //   "users" { "76561198012345678" { "MostRecent" "1" ... } }
    // Find all Steam64 IDs (17-digit numbers) and pick the one with MostRecent=1
    QRegularExpression userBlockRe(
        "\"(7656119\\d{10})\"\\s*\\{([^}]+)\\}");
    auto matches = userBlockRe.globalMatch(content);

    QString fallbackId;
    while (matches.hasNext()) {
        auto match = matches.next();
        QString steamId = match.captured(1);
        QString block = match.captured(2);

        if (fallbackId.isEmpty()) {
            fallbackId = steamId;
        }

        if (block.contains("\"MostRecent\"") &&
            block.contains("\"1\"")) {
            return steamId;
        }
    }

    return fallbackId;
}

QSet<QString> SteamBackend::getInstalledAppIds() const {
    QSet<QString> ids;
    // Use a const-safe copy of getLibraryFolders logic
    QString vdfPath = QDir::homePath() + "/.local/share/Steam/steamapps/libraryfolders.vdf";
    QFile vdfFile(vdfPath);
    if (!vdfFile.open(QIODevice::ReadOnly)) return ids;

    QTextStream vdfIn(&vdfFile);
    QString vdfContent = vdfIn.readAll();
    QRegularExpression pathRe("\"path\"\\s+\"([^\"]+)\"");
    auto pathMatches = pathRe.globalMatch(vdfContent);

    QVector<QString> folders;
    while (pathMatches.hasNext()) {
        auto pathMatch = pathMatches.next();
        folders.append(pathMatch.captured(1));
    }

    // Include SteamCMD's directory (not listed in libraryfolders.vdf)
    QString steamCmdDir = QDir::homePath() + "/.steam/steamcmd";
    if (QDir(steamCmdDir + "/steamapps").exists() && !folders.contains(steamCmdDir)) {
        folders.append(steamCmdDir);
    }

    for (const QString& folder : folders) {
        QDir steamapps(folder + "/steamapps");
        QStringList manifests = steamapps.entryList(
            QStringList() << "appmanifest_*.acf", QDir::Files);
        for (const QString& manifest : manifests) {
            QRegularExpression idRe("appmanifest_(\\d+)\\.acf");
            auto idMatch = idRe.match(manifest);
            if (idMatch.hasMatch()) {
                ids.insert(idMatch.captured(1));
            }
        }
    }
    return ids;
}

QVector<Game> SteamBackend::parseOwnedGamesResponse(const QByteArray& jsonData) const {
    QVector<Game> games;
    QSet<QString> installedIds = getInstalledAppIds();

    QJsonDocument doc = QJsonDocument::fromJson(jsonData);
    if (doc.isNull()) return games;

    QJsonObject root = doc.object();
    QJsonObject response = root["response"].toObject();
    QJsonArray gamesArray = response["games"].toArray();

    for (const QJsonValue& val : gamesArray) {
        QJsonObject obj = val.toObject();
        Game game;
        game.storeSource = "steam";
        game.appId = QString::number(obj["appid"].toInt());
        game.title = obj["name"].toString();
        game.isInstalled = installedIds.contains(game.appId);
        game.playTimeHours = obj["playtime_forever"].toInt() / 60;

        if (game.isInstalled) {
            game.launchCommand = "steam -silent steam://rungameid/" + game.appId;
        }
        // Uninstalled games have no launchCommand — installation is
        // handled by GameManager::installGame() via steamcmd.

        // Use local cover art cache if available, otherwise use Steam CDN URL
        QString localGrid = QDir::homePath() +
            "/.local/share/Steam/appcache/librarycache/" +
            game.appId + "_library_600x900.jpg";
        if (QFile::exists(localGrid)) {
            game.coverArtUrl = localGrid;
            qDebug() << "[steam-artwork] api" << game.appId << game.title << "-> local cache:" << localGrid;
        } else {
            game.coverArtUrl =
                "https://steamcdn-a.akamaihd.net/steam/apps/" +
                game.appId + "/library_600x900_2x.jpg";
            qDebug() << "[steam-artwork] api" << game.appId << game.title << "-> CDN fallback:" << game.coverArtUrl;
        }

        if (!game.title.isEmpty() && !isSteamTool(game.appId, game.title)) {
            games.append(game);
        }
    }

    return games;
}
