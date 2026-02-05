#ifndef ARTWORKMANAGER_H
#define ARTWORKMANAGER_H

#include <QObject>
#include <QCache>

class ArtworkManager : public QObject {
    Q_OBJECT
public:
    explicit ArtworkManager(QObject *parent = nullptr);

    Q_INVOKABLE QString getCoverArt(int gameId, const QString& url);
    void prefetchArtwork(int gameId, const QString& url);

signals:
    void artworkReady(int gameId, const QString& localPath);

private:
    QCache<int, QString> m_cache;
    QString cacheDir();
    void downloadArtwork(int gameId, const QString& url);
};

#endif
