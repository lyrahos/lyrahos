#ifndef ARTWORKMANAGER_H
#define ARTWORKMANAGER_H

#include <QObject>
#include <QCache>
#include <QSet>
#include <QFile>
#include <QStringList>
#include <QUrl>

class QNetworkAccessManager;

class ArtworkManager : public QObject {
    Q_OBJECT
public:
    explicit ArtworkManager(QObject *parent = nullptr);

    Q_INVOKABLE QString getCoverArt(int gameId, const QString& url);

signals:
    void artworkReady(int gameId, const QString& localPath);

private:
    QNetworkAccessManager *m_nam;
    QCache<int, QString> m_cache;
    QSet<int> m_pending;  // downloads in flight
    QFile m_logFile;
    QString cacheDir();
    void downloadArtwork(int gameId, const QString& url,
                         const QStringList& fallbacks = {});
    static QStringList steamFallbackUrls(const QString& failedUrl);
    void log(const QString& msg);
};

#endif
