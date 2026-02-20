#ifndef EPICBACKEND_H
#define EPICBACKEND_H

#include "../storebackend.h"
#include <QJsonArray>

class EpicBackend : public StoreBackend {
public:
    QString name() const override { return "epic"; }
    QVector<Game> scanLibrary() override;
    bool launchGame(const Game& game) override;
    bool isAvailable() const override;

    // Check if the user is logged in to Legendary
    bool isLoggedIn() const;

    // Parse the JSON output from `legendary list-games --json`
    QVector<Game> parseLibraryResponse(const QByteArray& jsonData) const;

    // Get the set of locally installed app names
    QSet<QString> getInstalledAppNames() const;

    // Get the Legendary config directory
    static QString legendaryConfigDir();

    // Check if a specific installed game is a Windows game (needs Proton/Wine)
    bool isWindowsGame(const QString& appName) const;

    // Write Legendary's config.ini so Windows games use Steam's Proton
    void ensureProtonConfig() const;

private:
    // Find the legendary binary
    QString findLegendaryBin() const;

    // Build cover art URL from Epic metadata
    QString getCoverArtUrl(const QJsonObject& metadata) const;

    // Find Steam's Proton binary (same logic as SteamBackend)
    QString findProtonBinary() const;

    // Find or create a Wine prefix directory for an Epic game
    QString getWinePrefixPath(const QString& appName) const;
};

#endif
