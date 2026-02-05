#ifndef STEAMBACKEND_H
#define STEAMBACKEND_H

#include "../storebackend.h"

class SteamBackend : public StoreBackend {
public:
    QString name() const override { return "steam"; }
    QVector<Game> scanLibrary() override;
    bool launchGame(const Game& game) override;
    bool isAvailable() const override;

private:
    QVector<QString> getLibraryFolders();
    Game parseAppManifest(const QString& manifestPath);
};

#endif
