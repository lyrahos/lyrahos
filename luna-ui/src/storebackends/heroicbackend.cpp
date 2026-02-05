#include "heroicbackend.h"
#include <QDir>
#include <QFile>
#include <QJsonDocument>
#include <QJsonArray>
#include <QJsonObject>
#include <QProcess>

// NOTE (FIX #22): This integration targets Heroic Games Launcher v2.x.
// The JSON library format may change across major versions.
// Supported formats: legendary_library.json (Epic) and gog_store/library.json (GOG).

bool HeroicBackend::isAvailable() const {
    return QFile::exists("/usr/bin/heroic") ||
           QFile::exists(QDir::homePath() + "/.config/heroic");
}

QVector<Game> HeroicBackend::scanLibrary() {
    QVector<Game> games;

    // Scan Epic Games via Legendary library
    QString epicPath = QDir::homePath() + "/.config/heroic/store_cache/legendary_library.json";
    if (QFile::exists(epicPath)) {
        QFile file(epicPath);
        if (file.open(QIODevice::ReadOnly)) {
            QJsonDocument doc = QJsonDocument::fromJson(file.readAll());
            QJsonObject root = doc.object();
            QJsonArray library = root["library"].toArray();
            for (const QJsonValue& val : library) {
                QJsonObject obj = val.toObject();
                Game game;
                game.title = obj["title"].toString();
                game.storeSource = "epic";
                game.appId = obj["app_name"].toString();
                game.isInstalled = obj["is_installed"].toBool();
                game.launchCommand = "heroic://launch/epic/" + game.appId;
                if (obj.contains("art_cover")) {
                    game.coverArtUrl = obj["art_cover"].toString();
                }
                if (!game.title.isEmpty()) {
                    games.append(game);
                }
            }
        }
    }

    // Scan GOG via Heroic
    QString gogPath = QDir::homePath() + "/.config/heroic/gog_store/library.json";
    if (QFile::exists(gogPath)) {
        QFile file(gogPath);
        if (file.open(QIODevice::ReadOnly)) {
            QJsonDocument doc = QJsonDocument::fromJson(file.readAll());
            QJsonArray library = doc.array();
            for (const QJsonValue& val : library) {
                QJsonObject obj = val.toObject();
                Game game;
                game.title = obj["title"].toString();
                game.storeSource = "gog";
                game.appId = obj["app_name"].toString();
                game.isInstalled = obj["is_installed"].toBool();
                game.launchCommand = "heroic://launch/gog/" + game.appId;
                if (!game.title.isEmpty()) {
                    games.append(game);
                }
            }
        }
    }

    return games;
}

bool HeroicBackend::launchGame(const Game& game) {
    QString store = (game.storeSource == "epic") ? "epic" : "gog";
    return QProcess::startDetached("xdg-open",
        QStringList() << "heroic://launch/" + store + "/" + game.appId);
}
