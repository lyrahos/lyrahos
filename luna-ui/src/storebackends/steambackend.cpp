#include "steambackend.h"
#include <QDir>
#include <QFile>
#include <QTextStream>
#include <QProcess>
#include <QRegularExpression>

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

bool SteamBackend::launchGame(const Game& game) {
    return QProcess::startDetached("steam", QStringList() << "steam://rungameid/" + game.appId);
}
