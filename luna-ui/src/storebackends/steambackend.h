#ifndef STEAMBACKEND_H
#define STEAMBACKEND_H

#include "../storebackend.h"
#include <QJsonArray>

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
};

#endif
