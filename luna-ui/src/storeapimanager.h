#ifndef STOREAPIMANAGER_H
#define STOREAPIMANAGER_H

#include <QObject>
#include <QVariantList>
#include <QVariantMap>
#include <QHash>
#include <memory>

class QNetworkAccessManager;

class StoreApiManager : public QObject {
    Q_OBJECT
public:
    explicit StoreApiManager(QObject *parent = nullptr);

    // ── CheapShark API ──
    Q_INVOKABLE void fetchDeals(const QString& sortBy = "Deal Rating",
                                int pageNumber = 0, int pageSize = 60);
    Q_INVOKABLE void fetchRecentDeals(int pageSize = 20);
    Q_INVOKABLE void fetchGameDeals(const QString& cheapSharkGameId);
    Q_INVOKABLE void fetchStores();

    // ── Search (IGDB + CheapShark) ──
    Q_INVOKABLE void searchGames(const QString& title);

    // ── IGDB API ──
    Q_INVOKABLE void fetchIGDBGameInfo(const QString& gameName);
    Q_INVOKABLE void fetchIGDBFeatured();
    Q_INVOKABLE void fetchIGDBNewReleases();
    Q_INVOKABLE void fetchIGDBTopRated();
    Q_INVOKABLE void setIGDBCredentials(const QString& clientId, const QString& clientSecret);
    Q_INVOKABLE void clearIGDBCredentials();
    Q_INVOKABLE bool hasIGDBCredentials();
    Q_INVOKABLE bool hasBuiltInIGDBCredentials();
    Q_INVOKABLE QString getIGDBClientId();

    // ── IGDB Image Helpers ──
    Q_INVOKABLE QString getIGDBImageUrl(const QString& imageUrl, const QString& size);

    // ── Store Price Scraping (supplements CheapShark with missing stores) ──
    Q_INVOKABLE void fetchStorePrices(const QString& steamAppId, const QVariantList& purchaseUrls,
                                       const QString& gameTitle = QString(),
                                       const QStringList& coveredStores = QStringList());

    // ── Browse Price Enrichment (batch-enrich IGDB browse results with prices) ──
    Q_INVOKABLE void fetchBrowsePrices(QVariantList games, const QString& section);

    // ── ProtonDB API ──
    Q_INVOKABLE void fetchProtonRating(const QString& steamAppId);

    // ── Utility ──
    Q_INVOKABLE QString getStoreName(int storeId);
    Q_INVOKABLE QString getStoreIconUrl(int storeId);
    Q_INVOKABLE QString getSteamHeaderUrl(const QString& steamAppId);
    Q_INVOKABLE QString getSteamHeroUrl(const QString& steamAppId);
    Q_INVOKABLE QString getSteamCapsuleUrl(const QString& steamAppId);

signals:
    // CheapShark
    void dealsReady(QVariantList deals);
    void dealsError(const QString& error);
    void recentDealsReady(QVariantList deals);
    void recentDealsError(const QString& error);
    void gameDealsReady(QVariantMap details);
    void gameDealsError(const QString& error);
    void storesReady(QVariantList stores);
    void storesError(const QString& error);

    // Search (merged IGDB + price sources)
    void searchResultsReady(QVariantList results);
    void searchError(const QString& error);

    // Store price scraping
    void storePricesReady(QVariantList deals);
    void storePricesError(const QString& error);

    // Browse price enrichment
    void browsePricesReady(const QString& section, QVariantList games);

    // IGDB
    void igdbGameInfoReady(QVariantMap gameInfo);
    void igdbGameInfoError(const QString& error);
    void igdbCredentialsSaved();
    void igdbFeaturedReady(QVariantList games);
    void igdbFeaturedError(const QString& error);
    void igdbNewReleasesReady(QVariantList games);
    void igdbNewReleasesError(const QString& error);
    void igdbTopRatedReady(QVariantList games);
    void igdbTopRatedError(const QString& error);

    // ProtonDB
    void protonRatingReady(const QString& steamAppId, QVariantMap rating);
    void protonRatingError(const QString& steamAppId, const QString& error);

private:
    QNetworkAccessManager *m_nam;

    // Store name cache (storeID → name)
    QHash<int, QString> m_storeNames;
    QHash<int, QString> m_storeIcons;
    bool m_storesLoaded = false;

    // IGDB auth
    QString m_igdbClientId;
    QString m_igdbClientSecret;
    QString m_igdbAccessToken;
    qint64 m_igdbTokenExpiry = 0;
    bool m_usingBuiltInCredentials = false;

    // Search merge state for parallel IGDB + CheapShark queries
    struct SearchMergeState {
        QVariantList igdbResults;
        QVariantList cheapSharkResults;
        int completedCount = 0;
    };
    int m_searchGeneration = 0;
    void mergeSearchResults(std::shared_ptr<SearchMergeState> state, int generation);

    void loadIGDBCredentials();
    void saveIGDBCredentials();
    void refreshIGDBToken(std::function<void()> onReady);
    QString igdbCredentialsPath() const;
    QVariantMap parseIGDBGame(const QJsonObject& obj);
    void fetchIGDBBrowse(const QString& query,
                         std::function<void(QVariantList)> onSuccess,
                         std::function<void(QString)> onError);
};

#endif
