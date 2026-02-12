#include "artworkmanager.h"
#include <QDir>
#include <QFile>
#include <QDebug>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QNetworkRequest>

ArtworkManager::ArtworkManager(QObject *parent) : QObject(parent) {
    m_cache.setMaxCost(200);
    m_nam = new QNetworkAccessManager(this);
}

QString ArtworkManager::cacheDir() {
    QString dir = QDir::homePath() + "/.local/share/luna-ui/artwork-cache/covers";
    QDir().mkpath(dir);
    return dir;
}

QString ArtworkManager::getCoverArt(int gameId, const QString& url) {
    if (url.isEmpty()) return QString();

    // Memory cache hit
    if (m_cache.contains(gameId)) {
        return *m_cache.object(gameId);
    }

    // Disk cache hit
    QString cachedPath = cacheDir() + "/" + QString::number(gameId) + "-cover.jpg";
    if (QFile::exists(cachedPath)) {
        m_cache.insert(gameId, new QString(cachedPath));
        return cachedPath;
    }

    // Local file (e.g. Steam library cache)
    if (QFile::exists(url)) {
        m_cache.insert(gameId, new QString(url));
        return url;
    }

    // Remote URL — kick off async download, return empty for now
    if (url.startsWith("http") && !m_pending.contains(gameId)) {
        downloadArtwork(gameId, url);
    }

    return QString();
}

void ArtworkManager::downloadArtwork(int gameId, const QString& url) {
    m_pending.insert(gameId);

    QNetworkRequest req(QUrl(url));
    req.setTransferTimeout(10000); // 10s timeout
    QNetworkReply *reply = m_nam->get(req);

    connect(reply, &QNetworkReply::finished, this, [this, reply, gameId]() {
        reply->deleteLater();
        m_pending.remove(gameId);

        if (reply->error() != QNetworkReply::NoError) {
            qDebug() << "Artwork download failed for game" << gameId << reply->errorString();
            return;
        }

        QByteArray data = reply->readAll();
        if (data.isEmpty()) return;

        QString path = cacheDir() + "/" + QString::number(gameId) + "-cover.jpg";
        QFile file(path);
        if (file.open(QIODevice::WriteOnly)) {
            file.write(data);
            file.close();
            m_cache.insert(gameId, new QString(path));
            emit artworkReady(gameId, path);
        }
    });
}
