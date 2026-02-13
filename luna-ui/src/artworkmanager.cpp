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
        downloadArtwork(gameId, url);
    } else if (!url.startsWith("http")) {
        log(QString("game %1: local file MISSING -> %2").arg(gameId).arg(url));
    }

    return QString();
}

void ArtworkManager::downloadArtwork(int gameId, const QString& url) {
    m_pending.insert(gameId);

    QNetworkRequest req{QUrl(url)};
    req.setTransferTimeout(10000); // 10s timeout
    QNetworkReply *reply = m_nam->get(req);

    connect(reply, &QNetworkReply::finished, this, [this, reply, gameId, url]() {
        reply->deleteLater();
        m_pending.remove(gameId);

        int httpStatus = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();

        if (reply->error() != QNetworkReply::NoError) {
            log(QString("game %1: DOWNLOAD FAILED  http=%2  error=\"%3\"  url=%4")
                .arg(gameId).arg(httpStatus).arg(reply->errorString(), url));
            return;
        }

        QByteArray data = reply->readAll();
        if (data.isEmpty()) {
            log(QString("game %1: DOWNLOAD EMPTY BODY  http=%2  url=%3")
                .arg(gameId).arg(httpStatus).arg(url));
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
    });
}
