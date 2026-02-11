#include "steambackend.h"
#include <QDir>
#include <QFile>
#include <QTextStream>
#include <QProcess>
#include <QRegularExpression>
#include <QSet>
#include <QStringList>

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
            if (!game.title.isEmpty()) {
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

    game.launchCommand = "steam steam://rungameid/" + game.appId;
    game.isInstalled = true;

    QString gridPath = QDir::homePath() + "/.local/share/Steam/appcache/librarycache/" + game.appId + "_library_600x900.jpg";
    if (QFile::exists(gridPath)) {
        game.coverArtUrl = gridPath;
    }

    return game;
}

QVector<Game> SteamBackend::scanOwnedGames() {
    // Start with installed games (full metadata from appmanifests)
    QVector<Game> games = scanLibrary();
    QSet<QString> installedIds;
    for (const Game& g : games)
        installedIds.insert(g.appId);

    // Scan librarycache for cover art of ALL owned games.  Steam downloads
    // library capsule art for every game in the user's library after login,
    // not just installed ones — so this discovers uninstalled games too.
    QString cachePath = QDir::homePath() +
        "/.local/share/Steam/appcache/librarycache";
    QDir cacheDir(cachePath);
    if (!cacheDir.exists()) return games;

    QStringList coverFiles = cacheDir.entryList(
        QStringList() << "*_library_600x900.jpg", QDir::Files);
    QRegularExpression idRe("^(\\d+)_library_600x900\\.jpg$");

    for (const QString& file : coverFiles) {
        auto match = idRe.match(file);
        if (!match.hasMatch()) continue;

        QString appId = match.captured(1);
        if (installedIds.contains(appId)) continue;

        Game game;
        game.storeSource = "steam";
        game.appId = appId;
        game.title = "";  // resolved later via GetAppList API
        game.isInstalled = false;
        game.coverArtUrl = cachePath + "/" + file;
        game.launchCommand = "steam steam://rungameid/" + appId;
        games.append(game);
    }
    return games;
}

bool SteamBackend::installGame(const QString& appId) {
    return QProcess::startDetached("steam",
        QStringList() << "steam://install/" + appId);
}

QVariantMap SteamBackend::checkDownloadProgress(const QString& appId) {
    QVariantMap result;
    result["downloading"] = false;
    result["progress"] = 0.0;
    result["installed"] = false;

    for (const QString& folder : getLibraryFolders()) {
        QString manifestPath = folder + "/steamapps/appmanifest_" + appId + ".acf";
        QFile file(manifestPath);
        if (!file.open(QIODevice::ReadOnly)) continue;

        QString content = QTextStream(&file).readAll();

        QRegularExpression stateRe("\"StateFlags\"\\s+\"(\\d+)\"");
        auto stateMatch = stateRe.match(content);
        int stateFlags = stateMatch.hasMatch()
            ? stateMatch.captured(1).toInt() : 0;

        if (stateFlags == 4) {
            result["installed"] = true;
            result["progress"] = 1.0;
            return result;
        }

        if (stateFlags & 1024) {  // downloading/updating
            result["downloading"] = true;

            QRegularExpression dlRe("\"BytesDownloaded\"\\s+\"(\\d+)\"");
            QRegularExpression totalRe("\"BytesToDownload\"\\s+\"(\\d+)\"");
            auto dlMatch = dlRe.match(content);
            auto totalMatch = totalRe.match(content);

            if (dlMatch.hasMatch() && totalMatch.hasMatch()) {
                qint64 downloaded = dlMatch.captured(1).toLongLong();
                qint64 total = totalMatch.captured(1).toLongLong();
                if (total > 0)
                    result["progress"] = static_cast<double>(downloaded) / total;
            }
            return result;
        }
    }
    return result;
}

bool SteamBackend::isToolApp(const QString& name) {
    static const QStringList filters = {
        "Proton", "Steam Linux Runtime", "Steamworks Common",
        "Redistributable", "dedicated server", "SDK",
        "SteamVR", "Pressure Vessel"
    };
    for (const QString& f : filters) {
        if (name.contains(f, Qt::CaseInsensitive)) return true;
    }
    return false;
}

bool SteamBackend::launchGame(const Game& game) {
    return QProcess::startDetached("steam", QStringList() << "steam://rungameid/" + game.appId);
}
