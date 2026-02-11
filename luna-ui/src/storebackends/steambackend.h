#ifndef STEAMBACKEND_H
#define STEAMBACKEND_H

#include "../storebackend.h"
#include <QVariantMap>

class SteamBackend : public StoreBackend {
public:
    QString name() const override { return "steam"; }
    QVector<Game> scanLibrary() override;
    bool launchGame(const Game& game) override;
    bool isAvailable() const override;

    QVector<Game> scanOwnedGames();
    bool installGame(const QString& appId);
    QVariantMap checkDownloadProgress(const QString& appId);
    static bool isToolApp(const QString& name);

private:
    QVector<QString> getLibraryFolders();
    Game parseAppManifest(const QString& manifestPath);
};

#endif
