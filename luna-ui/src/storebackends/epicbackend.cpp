#include "epicbackend.h"
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QProcess>
#include <QProcessEnvironment>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QStandardPaths>
#include <QTextStream>
#include <QSettings>
#include <QRegularExpression>
#include <QDebug>

// Epic Games integration via Legendary — an open-source Epic Games Store
// client for Linux. Legendary handles authentication, library management,
// game installation, and launching.
//
// Proton/Wine strategy:
//   Almost all Epic Games are Windows-only (no native Linux builds).
//   Legendary needs a Wine/Proton runner configured to launch them.
//   We auto-detect Steam's Proton installation and configure Legendary
//   to use it, giving the same compatibility as Steam games.
//
// How we determine if a game needs Proton:
//   1. Legendary's installed.json records "platform": "Windows" or "Mac"
//   2. Epic's metadata has "releaseInfo" with "platform" arrays
//   3. If installed as Windows → needs Proton/Wine
//   Most Epic games are Windows-only. Native Linux builds are rare
//   (e.g., a few Unreal Engine games).
//
// Key paths:
//   Config:    ~/.config/legendary/
//   Auth:      ~/.config/legendary/user.json
//   Installed: ~/.config/legendary/installed.json
//   Metadata:  ~/.config/legendary/metadata/
//   Prefixes:  ~/.config/legendary/wine_prefixes/<appName>/

QString EpicBackend::findLegendaryBin() const {
    // 1. Check PATH for legendary
    QString inPath = QStandardPaths::findExecutable("legendary");
    if (!inPath.isEmpty()) return inPath;

    // 2. Check common pip install locations
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

QString EpicBackend::legendaryConfigDir() {
    return QDir::homePath() + "/.config/legendary";
}

bool EpicBackend::isAvailable() const {
    return !findLegendaryBin().isEmpty();
}

bool EpicBackend::isLoggedIn() const {
    // Legendary stores auth tokens in user.json
    QString userFile = legendaryConfigDir() + "/user.json";
    if (!QFile::exists(userFile)) return false;

    QFile file(userFile);
    if (!file.open(QIODevice::ReadOnly)) return false;

    QJsonDocument doc = QJsonDocument::fromJson(file.readAll());
    if (doc.isNull() || !doc.isObject()) return false;

    // user.json must have a non-empty access token or refresh token
    QJsonObject root = doc.object();
    return !root["access_token"].toString().isEmpty() ||
           !root["refresh_token"].toString().isEmpty();
}

QSet<QString> EpicBackend::getInstalledAppNames() const {
    QSet<QString> names;
    QString installedPath = legendaryConfigDir() + "/installed.json";
    QFile file(installedPath);
    if (!file.open(QIODevice::ReadOnly)) return names;

    QJsonDocument doc = QJsonDocument::fromJson(file.readAll());
    if (doc.isNull() || !doc.isObject()) return names;

    QJsonObject root = doc.object();
    for (auto it = root.begin(); it != root.end(); ++it) {
        names.insert(it.key());
    }
    return names;
}

bool EpicBackend::isWindowsGame(const QString& appName) const {
    // Check installed.json for the platform field
    QString installedPath = legendaryConfigDir() + "/installed.json";
    QFile file(installedPath);
    if (!file.open(QIODevice::ReadOnly)) return true; // assume Windows if unknown

    QJsonDocument doc = QJsonDocument::fromJson(file.readAll());
    if (doc.isNull() || !doc.isObject()) return true;

    QJsonObject instObj = doc.object()[appName].toObject();
    QString platform = instObj["platform"].toString();

    // Legendary records "Windows" or "Mac" as the platform.
    // If it's "Windows" or empty/unknown, the game needs Proton.
    if (platform.isEmpty() || platform == "Windows") return true;

    // Also check the metadata for Linux support
    QString metaFile = legendaryConfigDir() + "/metadata/" + appName + ".json";
    QFile meta(metaFile);
    if (meta.open(QIODevice::ReadOnly)) {
        QJsonDocument metaDoc = QJsonDocument::fromJson(meta.readAll());
        if (!metaDoc.isNull() && metaDoc.isObject()) {
            QJsonObject metaObj = metaDoc.object();
            QJsonArray releaseInfo = metaObj["metadata"].toObject()["releaseInfo"].toArray();
            for (const QJsonValue& ri : releaseInfo) {
                QJsonArray platforms = ri.toObject()["platform"].toArray();
                for (const QJsonValue& p : platforms) {
                    if (p.toString() == "Linux") return false;
                }
            }
        }
    }

    return true;
}

QString EpicBackend::findProtonBinary() const {
    // Same search strategy as SteamBackend — find Proton in Steam library folders
    QString steamRoot = QDir::homePath() + "/.local/share/Steam";
    QString vdfPath = steamRoot + "/steamapps/libraryfolders.vdf";

    QVector<QString> folders;
    folders.append(steamRoot); // primary Steam dir

    // Parse libraryfolders.vdf for additional library paths
    QFile vdfFile(vdfPath);
    if (vdfFile.open(QIODevice::ReadOnly)) {
        QTextStream in(&vdfFile);
        QString content = in.readAll();
        QRegularExpression pathRe("\"path\"\\s+\"([^\"]+)\"");
        auto matches = pathRe.globalMatch(content);
        while (matches.hasNext()) {
            auto match = matches.next();
            QString path = match.captured(1);
            if (!folders.contains(path)) folders.append(path);
        }
    }

    for (const QString& folder : folders) {
        QString commonDir = folder + "/steamapps/common";
        QDir common(commonDir);
        if (!common.exists()) continue;

        // Prefer Proton Experimental (most commonly used, best compatibility)
        QString experimental = commonDir + "/Proton - Experimental/proton";
        if (QFile::exists(experimental)) {
            qDebug() << "[epic] Found Proton Experimental:" << experimental;
            return experimental;
        }

        // Fall back to numbered versions (highest first)
        QStringList protonDirs = common.entryList(
            QStringList() << "Proton *", QDir::Dirs,
            QDir::Name | QDir::Reversed);

        for (const QString& d : protonDirs) {
            QString protonScript = commonDir + "/" + d + "/proton";
            if (QFile::exists(protonScript)) {
                qDebug() << "[epic] Found Proton:" << protonScript;
                return protonScript;
            }
        }
    }

    qDebug() << "[epic] No Proton installation found in Steam libraries";
    return QString();
}

QString EpicBackend::getWinePrefixPath(const QString& appName) const {
    // Each Epic game gets its own Wine prefix to avoid conflicts.
    // Store them under Legendary's config directory.
    QString prefixDir = legendaryConfigDir() + "/wine_prefixes/" + appName;
    QDir().mkpath(prefixDir);
    return prefixDir;
}

void EpicBackend::ensureProtonConfig() const {
    // Write/update Legendary's config.ini to use Steam's Proton as the
    // default Wine runner for all games. This is a one-time setup that
    // persists across launches.
    //
    // Legendary's config.ini format:
    //   [Legendary]
    //   wine_executable = /path/to/proton/dist/bin/wine
    //   wine_prefix = /path/to/default/prefix
    //
    // OR for Proton directly:
    //   [Legendary]
    //   wrapper = /path/to/proton run

    QString proton = findProtonBinary();
    if (proton.isEmpty()) {
        qDebug() << "[epic] Cannot configure Proton — not found";
        return;
    }

    // Proton's bundled Wine is at: <proton_dir>/dist/bin/wine
    // But for Proton 7+, it's at: <proton_dir>/files/bin/wine
    QFileInfo protonInfo(proton);
    QString protonDir = protonInfo.absolutePath();
    QString wine;

    // Check Proton 7+ layout first
    QString filesWine = protonDir + "/files/bin/wine";
    QString distWine = protonDir + "/dist/bin/wine";
    if (QFile::exists(filesWine)) {
        wine = filesWine;
    } else if (QFile::exists(distWine)) {
        wine = distWine;
    }

    // Read existing config, update only our sections
    QString configPath = legendaryConfigDir() + "/config.ini";
    QSettings config(configPath, QSettings::IniFormat);

    // Only write if not already configured, or if the path changed
    QString currentWrapper = config.value("Legendary/wrapper").toString();
    QString expectedWrapper = proton + " run";

    if (currentWrapper != expectedWrapper) {
        // Use Proton as a wrapper rather than pointing at Wine directly.
        // `proton run <exe>` sets up DXVK, vkd3d-proton, fsync, esync,
        // and all the Steam Runtime compatibility shims automatically.
        config.setValue("Legendary/wrapper", expectedWrapper);

        // Set default environment variables that Proton needs
        QString steamRoot = QDir::homePath() + "/.local/share/Steam";
        config.setValue("Legendary.env/STEAM_COMPAT_CLIENT_INSTALL_PATH", steamRoot);
        config.setValue("Legendary.env/STEAM_COMPAT_DATA_PATH",
                       legendaryConfigDir() + "/wine_prefixes");

        config.sync();
        qDebug() << "[epic] Configured Legendary to use Proton wrapper:" << expectedWrapper;
        if (!wine.isEmpty()) {
            qDebug() << "[epic] Proton Wine binary:" << wine;
        }
    } else {
        qDebug() << "[epic] Proton already configured in Legendary";
    }
}

QVector<Game> EpicBackend::scanLibrary() {
    QVector<Game> games;
    if (!isLoggedIn()) return games;

    // Read metadata files from Legendary's cache
    QString metadataDir = legendaryConfigDir() + "/metadata";
    QDir dir(metadataDir);
    if (!dir.exists()) return games;

    QSet<QString> installedApps = getInstalledAppNames();
    QStringList jsonFiles = dir.entryList(QStringList() << "*.json", QDir::Files);

    for (const QString& filename : jsonFiles) {
        QFile file(dir.absoluteFilePath(filename));
        if (!file.open(QIODevice::ReadOnly)) continue;

        QJsonDocument doc = QJsonDocument::fromJson(file.readAll());
        if (doc.isNull() || !doc.isObject()) continue;

        QJsonObject obj = doc.object();
        QJsonObject metadata = obj["metadata"].toObject();

        // Skip DLC entries — they don't have their own launch command
        QJsonArray categories = metadata["categories"].toArray();
        bool isDLC = false;
        bool isGame = false;
        for (const QJsonValue& cat : categories) {
            QString path = cat.toObject()["path"].toString();
            if (path == "dlc") isDLC = true;
            if (path == "games" || path == "applications") isGame = true;
        }
        if (isDLC || !isGame) continue;

        Game game;
        game.title = obj["app_title"].toString();
        if (game.title.isEmpty())
            game.title = metadata["title"].toString();
        game.storeSource = "epic";
        game.appId = obj["app_name"].toString();
        game.isInstalled = installedApps.contains(game.appId);
        game.launchCommand = "legendary launch " + game.appId;
        game.coverArtUrl = getCoverArtUrl(metadata);

        // Read install path from installed.json if installed
        if (game.isInstalled) {
            QString installedPath = legendaryConfigDir() + "/installed.json";
            QFile instFile(installedPath);
            if (instFile.open(QIODevice::ReadOnly)) {
                QJsonDocument instDoc = QJsonDocument::fromJson(instFile.readAll());
                if (!instDoc.isNull() && instDoc.isObject()) {
                    QJsonObject instObj = instDoc.object()[game.appId].toObject();
                    game.installPath = instObj["install_path"].toString();
                }
            }
        }

        if (!game.title.isEmpty() && !game.appId.isEmpty()) {
            games.append(game);
        }
    }

    qDebug() << "[epic] Scanned" << games.size() << "games from Legendary metadata"
             << "(" << getInstalledAppNames().size() << "installed)";
    return games;
}

QString EpicBackend::getCoverArtUrl(const QJsonObject& metadata) const {
    // Epic metadata contains keyImages array with various image types:
    //   "type": "DieselGameBoxTall"  → vertical cover art (preferred)
    //   "type": "DieselGameBox"      → horizontal cover art
    //   "type": "Thumbnail"          → small thumbnail
    //   "type": "OfferImageTall"     → alternative tall image
    QJsonArray images = metadata["keyImages"].toArray();

    // Priority order for cover art types
    static const QStringList preferredTypes = {
        "DieselGameBoxTall",
        "OfferImageTall",
        "DieselGameBox",
        "OfferImageWide",
        "Thumbnail",
        "DieselStoreFrontTall",
        "CodeRedemption_340x440",
    };

    for (const QString& type : preferredTypes) {
        for (const QJsonValue& img : images) {
            QJsonObject imgObj = img.toObject();
            if (imgObj["type"].toString() == type) {
                return imgObj["url"].toString();
            }
        }
    }

    // Fallback: use the first available image
    if (!images.isEmpty()) {
        return images.first().toObject()["url"].toString();
    }

    return QString();
}

QVector<Game> EpicBackend::parseLibraryResponse(const QByteArray& jsonData) const {
    QVector<Game> games;
    QSet<QString> installedApps = getInstalledAppNames();

    QJsonDocument doc = QJsonDocument::fromJson(jsonData);
    if (doc.isNull() || !doc.isArray()) return games;

    QJsonArray arr = doc.array();
    for (const QJsonValue& val : arr) {
        QJsonObject obj = val.toObject();
        QJsonObject metadata = obj["metadata"].toObject();

        // Skip DLC
        QJsonArray categories = metadata["categories"].toArray();
        bool isDLC = false;
        bool isGame = false;
        for (const QJsonValue& cat : categories) {
            QString path = cat.toObject()["path"].toString();
            if (path == "dlc") isDLC = true;
            if (path == "games" || path == "applications") isGame = true;
        }
        if (isDLC || !isGame) continue;

        Game game;
        game.title = obj["app_title"].toString();
        if (game.title.isEmpty())
            game.title = metadata["title"].toString();
        game.storeSource = "epic";
        game.appId = obj["app_name"].toString();
        game.isInstalled = installedApps.contains(game.appId);
        game.launchCommand = "legendary launch " + game.appId;
        game.coverArtUrl = getCoverArtUrl(metadata);

        if (!game.title.isEmpty() && !game.appId.isEmpty()) {
            games.append(game);
        }
    }

    return games;
}

bool EpicBackend::launchGame(const Game& game) {
    QString bin = findLegendaryBin();
    if (bin.isEmpty()) {
        qDebug() << "[epic-launch] legendary binary not found";
        return false;
    }

    bool needsProton = isWindowsGame(game.appId);
    qDebug() << "[epic-launch]" << game.appId
             << "platform:" << (needsProton ? "Windows (needs Proton)" : "native Linux");

    QStringList args;
    args << "launch" << game.appId;

    if (needsProton) {
        // Ensure Legendary is configured to use Proton
        ensureProtonConfig();

        QString proton = findProtonBinary();
        if (!proton.isEmpty()) {
            // Set up per-game Wine prefix so games don't share state
            QString prefix = getWinePrefixPath(game.appId);
            QString steamRoot = QDir::homePath() + "/.local/share/Steam";

            // Pass Proton wrapper and environment via command line.
            // This overrides config.ini for this specific launch,
            // ensuring the correct prefix is used per-game.
            args << "--wrapper" << (proton + " run")
                 << "--wine-prefix" << prefix;

            qDebug() << "[epic-launch] Proton:" << proton;
            qDebug() << "[epic-launch] Prefix:" << prefix;

            // Set environment variables that Proton expects
            QProcess *proc = new QProcess();
            QProcessEnvironment env = QProcessEnvironment::systemEnvironment();
            env.insert("STEAM_COMPAT_CLIENT_INSTALL_PATH", steamRoot);
            env.insert("STEAM_COMPAT_DATA_PATH", prefix);

            proc->setProcessEnvironment(env);
            proc->setProgram(bin);
            proc->setArguments(args);

            bool ok = proc->startDetached();
            proc->deleteLater();
            return ok;
        } else {
            // No Proton found — fall back to system Wine.
            // Legendary will try to use whatever `wine` is in PATH.
            qDebug() << "[epic-launch] No Proton found, falling back to system Wine";

            // Still set a per-game prefix
            QString prefix = getWinePrefixPath(game.appId);
            args << "--wine-prefix" << prefix;
        }
    }

    // Native game or Wine fallback — just launch directly
    qDebug() << "[epic-launch] launching" << game.appId << "via legendary";
    return QProcess::startDetached(bin, args);
}
