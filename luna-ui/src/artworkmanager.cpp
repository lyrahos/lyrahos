#include "artworkmanager.h"
#include <QDir>
#include <QFile>
#include <QDebug>
#include <QDateTime>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QNetworkRequest>

ArtworkManager::ArtworkManager(QObject *parent) : QObject(parent) {
    m_cache.setMaxCost(200);
    m_nam = new QNetworkAccessManager(this);

    QString logDir = QDir::homePath() + "/.local/share/luna-ui";
    QDir().mkpath(logDir);
    m_logFile.setFileName(logDir + "/artwork-debug.log");
    m_logFile.open(QIODevice::WriteOnly | QIODevice::Append | QIODevice::Text);
    log("=== ArtworkManager started ===");
}

void ArtworkManager::log(const QString& msg) {
    if (!m_logFile.isOpen()) return;
    QString line = QDateTime::currentDateTime().toString("yyyy-MM-dd hh:mm:ss.zzz") +
                   "  " + msg + "\n";
    m_logFile.write(line.toUtf8());
    m_logFile.flush();
}

QString ArtworkManager::cacheDir() {
    QString dir = QDir::homePath() + "/.local/share/luna-ui/artwork-cache/covers";
    QDir().mkpath(dir);
    return dir;
}

QString ArtworkManager::getCoverArt(int gameId, const QString& url) {
    if (url.isEmpty()) {
        log(QString("game %1: url is EMPTY — no artwork source").arg(gameId));
        return QString();
    }

    // Memory cache hit
    if (m_cache.contains(gameId)) {
        return *m_cache.object(gameId);
    }

    // Disk cache hit
    QString cachedPath = cacheDir() + "/" + QString::number(gameId) + "-cover.jpg";
    if (QFile::exists(cachedPath)) {
        m_cache.insert(gameId, new QString(cachedPath));
        log(QString("game %1: disk cache HIT -> %2").arg(gameId).arg(cachedPath));
        return cachedPath;
    }

    // Local file (e.g. Steam library cache)
    if (QFile::exists(url)) {
        m_cache.insert(gameId, new QString(url));
        log(QString("game %1: local file HIT -> %2").arg(gameId).arg(url));
        return url;
    }

    // Remote URL — kick off async download, return empty for now
    if (url.startsWith("http") && !m_pending.contains(gameId)) {
        log(QString("game %1: no cache, starting download -> %2").arg(gameId).arg(url));
        downloadArtwork(gameId, url, steamFallbackUrls(url));
    } else if (!url.startsWith("http")) {
        log(QString("game %1: local file MISSING -> %2").arg(gameId).arg(url));
    }

    return QString();
}

void ArtworkManager::downloadArtwork(int gameId, const QString& url,
                                     const QStringList& fallbacks) {
    m_pending.insert(gameId);

    QNetworkRequest req{QUrl(url)};
    req.setTransferTimeout(10000); // 10s timeout
    QNetworkReply *reply = m_nam->get(req);

    connect(reply, &QNetworkReply::finished, this, [this, reply, gameId, url, fallbacks]() {
        reply->deleteLater();

        int httpStatus = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();

        if (reply->error() != QNetworkReply::NoError) {
            log(QString("game %1: DOWNLOAD FAILED  http=%2  error=\"%3\"  url=%4")
                .arg(gameId).arg(httpStatus).arg(reply->errorString(), url));

            // Try the next fallback URL if available
            if (!fallbacks.isEmpty()) {
                QString next = fallbacks.first();
                QStringList remaining = fallbacks.mid(1);
                log(QString("game %1: trying fallback -> %2").arg(gameId).arg(next));
                downloadArtwork(gameId, next, remaining);
            } else {
                m_pending.remove(gameId);
            }
            return;
        }

        QByteArray data = reply->readAll();
        if (data.isEmpty()) {
            log(QString("game %1: DOWNLOAD EMPTY BODY  http=%2  url=%3")
                .arg(gameId).arg(httpStatus).arg(url));

            if (!fallbacks.isEmpty()) {
                QString next = fallbacks.first();
                QStringList remaining = fallbacks.mid(1);
                log(QString("game %1: trying fallback -> %2").arg(gameId).arg(next));
                downloadArtwork(gameId, next, remaining);
            } else {
                m_pending.remove(gameId);
            }
            return;
        }

        QString path = cacheDir() + "/" + QString::number(gameId) + "-cover.jpg";
        QFile file(path);
        if (file.open(QIODevice::WriteOnly)) {
            file.write(data);
            file.close();
            m_cache.insert(gameId, new QString(path));
            log(QString("game %1: DOWNLOAD OK  %2 bytes  http=%3  saved=%4")
                .arg(gameId).arg(data.size()).arg(httpStatus).arg(path));
            emit artworkReady(gameId, path);
        } else {
            log(QString("game %1: FILE WRITE FAILED  path=%2  error=\"%3\"")
                .arg(gameId).arg(path, file.errorString()));
        }
        m_pending.remove(gameId);
    });
}

QStringList ArtworkManager::steamFallbackUrls(const QString& url) {
    // Build fallback URLs for Steam CDN images.
    // Not all games have library_600x900_2x.jpg — older/smaller titles
    // often only have header.jpg.
    QStringList fallbacks;

    // Only generate fallbacks for Steam CDN URLs
    static const QStringList steamHosts = {
        "steamcdn-a.akamaihd.net",
        "cdn.akamai.steamstatic.com",
        "cdn.cloudflare.steamstatic.com",
    };

    QUrl parsed(url);
    bool isSteam = false;
    for (const auto& host : steamHosts) {
        if (parsed.host() == host) { isSteam = true; break; }
    }
    if (!isSteam) return fallbacks;

    // Extract the appId from the path: /steam/apps/{appId}/...
    QString path = parsed.path();          // e.g. /steam/apps/730/library_600x900_2x.jpg
    int appsIdx = path.indexOf("/apps/");
    if (appsIdx < 0) return fallbacks;
    QString after = path.mid(appsIdx + 6); // e.g. 730/library_600x900_2x.jpg
    int slash = after.indexOf('/');
    if (slash < 0) return fallbacks;
    QString appId = after.left(slash);
    QString basePath = path.left(appsIdx + 6) + appId + "/";

    // Ordered by quality: high-res vertical → standard vertical → header
    QStringList candidates = {
        basePath + "library_600x900_2x.jpg",
        basePath + "library_600x900.jpg",
        basePath + "header.jpg",
    };

    // Return only candidates that differ from the original URL
    QString origPath = parsed.path();
    for (const auto& candidate : candidates) {
        if (candidate != origPath) {
            QUrl fallback(url);
            fallback.setPath(candidate);
            fallbacks.append(fallback.toString());
        }
    }
    return fallbacks;
}
