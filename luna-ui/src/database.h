#ifndef DATABASE_H
#define DATABASE_H

#include <QObject>
#include <QSqlDatabase>
#include <QSqlQuery>      // FIX #33: Include QSqlQuery in header
#include <QVector>

struct Game {
    int id;
    QString title;
    QString storeSource;
    QString appId;
    QString installPath;
    QString executablePath;
    QString launchCommand;
    QString coverArtUrl;
    QString backgroundArtUrl;
    QString iconPath;
    qint64 lastPlayed;
    int playTimeHours;
    bool isFavorite;
    bool isInstalled;
    bool isHidden;
    QString tags;       // JSON array string
    QString metadata;   // JSON object string
};

struct GameSession {
    int id;
    int gameId;
    qint64 startTime;
    qint64 endTime;
    int durationMinutes;
};

class Database : public QObject {
    Q_OBJECT
public:
    explicit Database(QObject *parent = nullptr);
    bool initialize();

    // Game CRUD
    int addGame(const Game& game);
    bool updateGame(const Game& game);
    bool removeGame(int gameId);
    Game getGameById(int gameId);
    QVector<Game> getAllGames();
    QVector<Game> getInstalledGames();
    QVector<Game> getFavoriteGames();
    QVector<Game> getRecentlyPlayed(int limit = 10);
    QVector<Game> searchGames(const QString& query);
    QVector<Game> getGamesByStore(const QString& store);

    // Session tracking
    int startGameSession(int gameId);
    void endGameSession(int sessionId);
    QVector<GameSession> getSessionsForGame(int gameId);
    int getTotalPlayTime(int gameId);

    QSqlDatabase db() { return m_db; }

private:
    QSqlDatabase m_db;
    void createTables();
    Game gameFromQuery(const QSqlQuery& query);
};

#endif
