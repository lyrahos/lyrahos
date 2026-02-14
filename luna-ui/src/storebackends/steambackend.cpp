#include "steambackend.h"
#include <QDir>
#include <QFile>
#include <QTextStream>
#include <QProcess>
#include <QRegularExpression>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QSet>
#include <QDebug>

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
        qDebug() << "[steam-artwork] installed" << game.appId << game.title << "-> local cache:" << gridPath;
    } else {
        game.coverArtUrl = "https://steamcdn-a.akamaihd.net/steam/apps/" + game.appId + "/library_600x900_2x.jpg";
        qDebug() << "[steam-artwork] installed" << game.appId << game.title << "-> local cache MISSING, using CDN:" << game.coverArtUrl;
    }

    return game;
}

bool SteamBackend::launchGame(const Game& game) {
    // -silent: suppress the Steam client UI (no store/library windows),
    // Steam stays in the background and just launches the game.
    return QProcess::startDetached("steam", QStringList()
        << "-silent" << "steam://rungameid/" + game.appId);
}

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

    while (pathMatches.hasNext()) {
        auto pathMatch = pathMatches.next();
        QString folder = pathMatch.captured(1);
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
            game.launchCommand = "steam steam://rungameid/" + game.appId;
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

        if (!game.title.isEmpty()) {
            games.append(game);
        }
    }

    return games;
}
