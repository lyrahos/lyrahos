#include "lutrisbackend.h"
#include <QDir>
#include <QFile>
#include <QSqlDatabase>
#include <QSqlQuery>
#include <QProcess>

bool LutrisBackend::isAvailable() const {
    return QFile::exists("/usr/bin/lutris") &&
           QFile::exists(QDir::homePath() + "/.local/share/lutris/pga.db");
}

QVector<Game> LutrisBackend::scanLibrary() {
    QVector<Game> games;
    QString dbPath = QDir::homePath() + "/.local/share/lutris/pga.db";

    QSqlDatabase lutrisDb = QSqlDatabase::addDatabase("QSQLITE", "lutris_connection");
    lutrisDb.setDatabaseName(dbPath);

    if (!lutrisDb.open()) return games;

    QSqlQuery query(lutrisDb);
    query.exec("SELECT id, name, slug, runner, directory, installed FROM games WHERE installed = 1");

    while (query.next()) {
        Game game;
        game.title = query.value("name").toString();
        game.storeSource = "lutris";
        game.appId = query.value("slug").toString();
        game.installPath = query.value("directory").toString();
        game.isInstalled = query.value("installed").toBool();
        game.launchCommand = "lutris lutris:rungame/" + game.appId;
        if (!game.title.isEmpty()) {
            games.append(game);
        }
    }

    lutrisDb.close();
    QSqlDatabase::removeDatabase("lutris_connection");
    return games;
}

bool LutrisBackend::launchGame(const Game& game) {
    return QProcess::startDetached("lutris", QStringList() << "lutris:rungame/" + game.appId);
}
