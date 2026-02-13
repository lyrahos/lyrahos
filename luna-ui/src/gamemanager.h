#ifndef GAMEMANAGER_H
#define GAMEMANAGER_H

#include <QObject>
#include <QVector>
#include <QHash>
#include <QTimer>
#include <QVariantList>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QFileSystemWatcher>
#include <QProcess>
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
    Q_INVOKABLE QVariantList getWifiNetworks();
    Q_INVOKABLE void connectToWifi(const QString& ssid, const QString& password);

    // Steam API key & owned games
    Q_INVOKABLE QString getSteamApiKey();
    Q_INVOKABLE void setSteamApiKey(const QString& key);
    Q_INVOKABLE bool hasSteamApiKey();
    Q_INVOKABLE QString getDetectedSteamId();
    Q_INVOKABLE void fetchSteamOwnedGames();
    Q_INVOKABLE void openSteamApiKeyPage();

    // SteamCMD-based game installation
    Q_INVOKABLE void installGame(int gameId);
    Q_INVOKABLE bool isDownloading(const QString& appId);
    Q_INVOKABLE double getDownloadProgress(const QString& appId);
    Q_INVOKABLE void cancelDownload(const QString& appId);
    Q_INVOKABLE bool isSteamCmdAvailable();
    Q_INVOKABLE QString getSteamUsername();

    // SteamCMD credential input (for interactive login)
    Q_INVOKABLE void provideSteamCmdCredential(const QString& appId, const QString& credential);

signals:
    void gamesUpdated();
    void gameLaunched(int gameId);
    void gameExited(int gameId);
    void scanComplete(int gamesFound);
    void wifiConnectResult(bool success, const QString& message);
    void steamOwnedGamesFetched(int gamesFound);
    void steamOwnedGamesFetchError(const QString& error);
    void downloadStarted(QString appId, int gameId);
    void downloadProgressChanged(QString appId, double progress);
    void downloadComplete(QString appId, int gameId);
    void installError(QString appId, QString error);
    void steamCmdCredentialNeeded(QString appId, QString promptType);

private:
    Database *m_db;
    QVector<StoreBackend*> m_backends;
    int m_activeSessionId = -1;
    int m_activeGameId = -1;
    QTimer *m_processMonitor;
    QNetworkAccessManager *m_networkManager;

    // Download tracking: appId → gameId
    QHash<QString, int> m_activeDownloads;
    // SteamCMD processes: appId → QProcess*
    QHash<QString, QProcess*> m_steamCmdProcesses;
    // Download progress cache: appId → progress (0.0-1.0)
    QHash<QString, double> m_downloadProgressCache;
    QTimer *m_downloadMonitor;
    QFileSystemWatcher *m_acfWatcher;

    void registerBackends();
    void monitorGameProcess();
    void checkDownloadProgress();
    void handleSteamCmdOutput(const QString& appId, QProcess *proc);
    StoreBackend* getBackendForGame(const Game& game);
    QVariantList gamesToVariantList(const QVector<Game>& games);
    QString steamApiKeyPath() const;
    QStringList getSteamAppsDirs() const;
};

#endif
