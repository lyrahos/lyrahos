#ifndef GAMEMANAGER_H
#define GAMEMANAGER_H

#include <QObject>
#include <QVector>
#include <QTimer>
#include <QVariantList>
#include "database.h"
#include "storebackend.h"

class GameManager : public QObject {
    Q_OBJECT
public:
    explicit GameManager(Database *db, QObject *parent = nullptr);

    Q_INVOKABLE void scanAllStores();
    Q_INVOKABLE void launchGame(int gameId);
    Q_INVOKABLE void toggleFavorite(int gameId);
    Q_INVOKABLE QVariantList getGames();
    Q_INVOKABLE QVariantList getRecentGames();
    Q_INVOKABLE QVariantList getFavorites();
    Q_INVOKABLE QVariantList search(const QString& query);
    Q_INVOKABLE void executeCommand(const QString& program, const QStringList& args = {});
    Q_INVOKABLE bool isSteamAvailable();
    Q_INVOKABLE bool isSteamInstalled();
    Q_INVOKABLE void launchSteam();
    Q_INVOKABLE void launchSteamLogin();
    Q_INVOKABLE void switchToDesktop();
    Q_INVOKABLE int getGameCount();
    Q_INVOKABLE bool isNetworkAvailable();

signals:
    void gamesUpdated();
    void gameLaunched(int gameId);
    void gameExited(int gameId);
    void scanComplete(int gamesFound);

private:
    Database *m_db;
    QVector<StoreBackend*> m_backends;
    int m_activeSessionId = -1;
    int m_activeGameId = -1;
    QTimer *m_processMonitor;

    void registerBackends();
    void monitorGameProcess();
    StoreBackend* getBackendForGame(const Game& game);
    QVariantList gamesToVariantList(const QVector<Game>& games);
};

#endif
