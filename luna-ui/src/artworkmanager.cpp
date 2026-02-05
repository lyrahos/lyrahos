#include "artworkmanager.h"
#include <QDir>
#include <QFile>
#include <QDebug>

ArtworkManager::ArtworkManager(QObject *parent) : QObject(parent) {
    m_cache.setMaxCost(200); // Cache up to 200 entries
}

QString ArtworkManager::cacheDir() {
    QString dir = QDir::homePath() + "/.local/share/luna-ui/artwork-cache/covers";
    QDir().mkpath(dir);
    return dir;
}

QString ArtworkManager::getCoverArt(int gameId, const QString& url) {
    // Check memory cache first
    if (m_cache.contains(gameId)) {
        return *m_cache.object(gameId);
    }

    // Check disk cache
    QString cachedPath = cacheDir() + "/" + QString::number(gameId) + "-cover.jpg";
    if (QFile::exists(cachedPath)) {
        m_cache.insert(gameId, new QString(cachedPath));
        return cachedPath;
    }

    // If URL is a local file, use it directly
    if (QFile::exists(url)) {
        m_cache.insert(gameId, new QString(url));
        return url;
    }

    // TODO: Implement async download from SteamGridDB/IGDB APIs
    // For now, return empty string (placeholder will be shown)
    return QString();
}

void ArtworkManager::prefetchArtwork(int gameId, const QString& url) {
    // TODO: Queue async download for pre-fetching
    Q_UNUSED(gameId);
    Q_UNUSED(url);
}

void ArtworkManager::downloadArtwork(int gameId, const QString& url) {
    // TODO: Implement HTTP download to disk cache
    // Use QNetworkAccessManager for async downloads
    Q_UNUSED(gameId);
    Q_UNUSED(url);
}
