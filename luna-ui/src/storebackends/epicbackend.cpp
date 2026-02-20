#include "epicbackend.h"
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QProcess>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QStandardPaths>
#include <QDebug>

// Epic Games integration via Legendary — an open-source Epic Games Store
// client for Linux. Legendary handles authentication, library management,
// game installation, and launching with Proton/Wine support.
//
// Key paths:
//   Config:    ~/.config/legendary/
//   Auth:      ~/.config/legendary/user.json
//   Installed: ~/.config/legendary/installed.json
//   Metadata:  ~/.config/legendary/metadata/

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

    qDebug() << "[epic-launch] launching" << game.appId << "via legendary";
    return QProcess::startDetached(bin, QStringList() << "launch" << game.appId);
}
