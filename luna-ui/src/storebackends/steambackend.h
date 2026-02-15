#ifndef STEAMBACKEND_H
#define STEAMBACKEND_H

#include "../storebackend.h"
#include <QJsonArray>
#include <QProcessEnvironment>

class SteamBackend : public StoreBackend {
public:
    QString name() const override { return "steam"; }
    QVector<Game> scanLibrary() override;
    bool launchGame(const Game& game) override;
    bool isAvailable() const override;

    // Steam ID auto-detection from local config files
    QString getLoggedInSteamId() const;

    // Parse the JSON response from IPlayerService/GetOwnedGames
    QVector<Game> parseOwnedGamesResponse(const QByteArray& jsonData) const;

    // Get the set of locally installed appIds (for marking is_installed)
    QSet<QString> getInstalledAppIds() const;

private:
    QVector<QString> getLibraryFolders();
    Game parseAppManifest(const QString& manifestPath);

    // Direct launch helpers (bypass Steam's "Preparing to launch" popup)
    bool launchNativeGame(const Game& game, const QString& gameDir,
                          QProcessEnvironment env);
    bool launchProtonGame(const Game& game, const QString& gameDir,
                          QProcessEnvironment env);
    bool steamProtocolLaunch(const Game& game);

    // Executable/directory discovery
    QString findGameDirectory(const QString& appId);
    bool isProtonGame(const QString& appId);
    QString findNativeExecutable(const QString& gameDir);
    QString findProtonExecutable(const QString& gameDir);
    QString findProtonBinary();
    QString findCompatDataPath(const QString& appId);
};

#endif
