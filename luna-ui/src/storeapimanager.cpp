#include "storeapimanager.h"
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QJsonDocument>
#include <QJsonArray>
#include <QJsonObject>
#include <QUrlQuery>
#include <QDir>
#include <QFile>
#include <QDateTime>
#include <QDebug>

static const QString CHEAPSHARK_BASE = "https://www.cheapshark.com/api/1.0";
static const QString PROTONDB_BASE   = "https://www.protondb.com/api/v1/reports/summaries";
static const QString IGDB_BASE       = "https://api.igdb.com/v4";
static const QString TWITCH_TOKEN    = "https://id.twitch.tv/oauth2/token";
static const QString STEAM_CDN       = "https://cdn.akamai.steamstatic.com/steam/apps";

StoreApiManager::StoreApiManager(QObject *parent)
    : QObject(parent)
    , m_nam(new QNetworkAccessManager(this))
{
    loadIGDBCredentials();
    // Pre-fetch store list on construction
    fetchStores();
}

// ─── CheapShark: Fetch Deals ───

void StoreApiManager::fetchDeals(const QString& sortBy, int pageNumber, int pageSize)
{
    QUrl url(CHEAPSHARK_BASE + "/deals");
    QUrlQuery query;
    query.addQueryItem("sortBy", sortBy);
    query.addQueryItem("pageNumber", QString::number(pageNumber));
    query.addQueryItem("pageSize", QString::number(pageSize));
    query.addQueryItem("onSale", "1");
    url.setQuery(query);

    QNetworkRequest req(url);
    req.setTransferTimeout(15000);
    QNetworkReply *reply = m_nam->get(req);

    connect(reply, &QNetworkReply::finished, this, [this, reply]() {
        reply->deleteLater();
        if (reply->error() != QNetworkReply::NoError) {
            emit dealsError(reply->errorString());
            return;
        }

        QJsonArray arr = QJsonDocument::fromJson(reply->readAll()).array();
        QVariantList deals;
        for (const auto& val : arr) {
            QJsonObject obj = val.toObject();
            QVariantMap deal;
            deal["dealID"]       = obj["dealID"].toString();
            deal["title"]        = obj["title"].toString();
            deal["salePrice"]    = obj["salePrice"].toString();
            deal["normalPrice"]  = obj["normalPrice"].toString();
            deal["savings"]      = obj["savings"].toString();
            deal["metacriticScore"]    = obj["metacriticScore"].toString();
            deal["steamRatingText"]    = obj["steamRatingText"].toString();
            deal["steamRatingPercent"] = obj["steamRatingPercent"].toString();
            deal["steamAppID"]   = obj["steamAppID"].toString();
            deal["gameID"]       = obj["gameID"].toString();
            deal["storeID"]      = obj["storeID"].toString();
            deal["dealRating"]   = obj["dealRating"].toString();
            deal["releaseDate"]  = obj["releaseDate"].toInteger();
            deal["thumb"]        = obj["thumb"].toString();
            deal["isOnSale"]     = obj["isOnSale"].toString();

            // Construct higher-quality image URLs from steamAppID
            QString appId = obj["steamAppID"].toString();
            if (!appId.isEmpty() && appId != "null" && appId != "0") {
                deal["headerImage"] = getSteamHeaderUrl(appId);
                deal["heroImage"]   = getSteamHeroUrl(appId);
                deal["capsuleImage"] = getSteamCapsuleUrl(appId);
            } else {
                deal["headerImage"] = obj["thumb"].toString();
                deal["heroImage"]   = obj["thumb"].toString();
                deal["capsuleImage"] = obj["thumb"].toString();
            }

            deals.append(deal);
        }

        emit dealsReady(deals);
    });
}

void StoreApiManager::fetchRecentDeals(int pageSize)
{
    QUrl url(CHEAPSHARK_BASE + "/deals");
    QUrlQuery query;
    query.addQueryItem("sortBy", "recent");
    query.addQueryItem("pageSize", QString::number(pageSize));
    query.addQueryItem("onSale", "1");
    url.setQuery(query);

    QNetworkRequest req(url);
    req.setTransferTimeout(15000);
    QNetworkReply *reply = m_nam->get(req);

    connect(reply, &QNetworkReply::finished, this, [this, reply]() {
        reply->deleteLater();
        if (reply->error() != QNetworkReply::NoError) {
            emit recentDealsError(reply->errorString());
            return;
        }

        QJsonArray arr = QJsonDocument::fromJson(reply->readAll()).array();
        QVariantList deals;
        for (const auto& val : arr) {
            QJsonObject obj = val.toObject();
            QVariantMap deal;
            deal["dealID"]       = obj["dealID"].toString();
            deal["title"]        = obj["title"].toString();
            deal["salePrice"]    = obj["salePrice"].toString();
            deal["normalPrice"]  = obj["normalPrice"].toString();
            deal["savings"]      = obj["savings"].toString();
            deal["metacriticScore"]    = obj["metacriticScore"].toString();
            deal["steamRatingText"]    = obj["steamRatingText"].toString();
            deal["steamRatingPercent"] = obj["steamRatingPercent"].toString();
            deal["steamAppID"]   = obj["steamAppID"].toString();
            deal["gameID"]       = obj["gameID"].toString();
            deal["storeID"]      = obj["storeID"].toString();
            deal["dealRating"]   = obj["dealRating"].toString();
            deal["releaseDate"]  = obj["releaseDate"].toInteger();
            deal["thumb"]        = obj["thumb"].toString();

            QString appId = obj["steamAppID"].toString();
            if (!appId.isEmpty() && appId != "null" && appId != "0") {
                deal["headerImage"] = getSteamHeaderUrl(appId);
                deal["heroImage"]   = getSteamHeroUrl(appId);
                deal["capsuleImage"] = getSteamCapsuleUrl(appId);
            } else {
                deal["headerImage"] = obj["thumb"].toString();
                deal["heroImage"]   = obj["thumb"].toString();
                deal["capsuleImage"] = obj["thumb"].toString();
            }

            deals.append(deal);
        }

        emit recentDealsReady(deals);
    });
}

// ─── CheapShark: Search Games ───

void StoreApiManager::searchGames(const QString& title)
{
    QUrl url(CHEAPSHARK_BASE + "/games");
    QUrlQuery query;
    query.addQueryItem("title", title);
    query.addQueryItem("limit", "60");
    url.setQuery(query);

    QNetworkRequest req(url);
    req.setTransferTimeout(15000);
    QNetworkReply *reply = m_nam->get(req);

    connect(reply, &QNetworkReply::finished, this, [this, reply]() {
        reply->deleteLater();
        if (reply->error() != QNetworkReply::NoError) {
            emit searchError(reply->errorString());
            return;
        }

        QJsonArray arr = QJsonDocument::fromJson(reply->readAll()).array();
        QVariantList results;
        for (const auto& val : arr) {
            QJsonObject obj = val.toObject();
            QVariantMap game;
            game["gameID"]      = obj["gameID"].toString();
            game["title"]       = obj["external"].toString();
            game["cheapest"]    = obj["cheapest"].toString();
            game["steamAppID"]  = obj["steamAppID"].toString();
            game["thumb"]       = obj["thumb"].toString();

            QString appId = obj["steamAppID"].toString();
            if (!appId.isEmpty() && appId != "null" && appId != "0") {
                game["headerImage"] = getSteamHeaderUrl(appId);
                game["capsuleImage"] = getSteamCapsuleUrl(appId);
            } else {
                game["headerImage"] = obj["thumb"].toString();
                game["capsuleImage"] = obj["thumb"].toString();
            }

            results.append(game);
        }

        emit searchResultsReady(results);
    });
}

// ─── CheapShark: Game Details (all deals for one game) ───

void StoreApiManager::fetchGameDeals(const QString& cheapSharkGameId)
{
    QUrl url(CHEAPSHARK_BASE + "/games");
    QUrlQuery query;
    query.addQueryItem("id", cheapSharkGameId);
    url.setQuery(query);

    QNetworkRequest req(url);
    req.setTransferTimeout(15000);
    QNetworkReply *reply = m_nam->get(req);

    connect(reply, &QNetworkReply::finished, this, [this, reply]() {
        reply->deleteLater();
        if (reply->error() != QNetworkReply::NoError) {
            emit gameDealsError(reply->errorString());
            return;
        }

        QJsonObject root = QJsonDocument::fromJson(reply->readAll()).object();
        QVariantMap details;

        // Game info
        QJsonObject info = root["info"].toObject();
        details["title"]      = info["title"].toString();
        details["steamAppID"] = info["steamAppID"].toString();
        details["thumb"]      = info["thumb"].toString();

        QString appId = info["steamAppID"].toString();
        if (!appId.isEmpty() && appId != "null" && appId != "0") {
            details["headerImage"] = getSteamHeaderUrl(appId);
            details["heroImage"]   = getSteamHeroUrl(appId);
        } else {
            details["headerImage"] = info["thumb"].toString();
            details["heroImage"]   = info["thumb"].toString();
        }

        // Cheapest price ever
        QJsonObject cheapest = root["cheapestPriceEver"].toObject();
        details["cheapestEverPrice"] = cheapest["price"].toString();
        details["cheapestEverDate"]  = cheapest["date"].toInteger();

        // All current deals across stores
        QJsonArray dealsArr = root["deals"].toArray();
        QVariantList deals;
        for (const auto& val : dealsArr) {
            QJsonObject obj = val.toObject();
            QVariantMap deal;
            deal["storeID"]     = obj["storeID"].toString();
            deal["dealID"]      = obj["dealID"].toString();
            deal["price"]       = obj["price"].toString();
            deal["retailPrice"] = obj["retailPrice"].toString();
            deal["savings"]     = obj["savings"].toString();

            int storeId = obj["storeID"].toString().toInt();
            deal["storeName"] = getStoreName(storeId);
            deal["storeIcon"] = getStoreIconUrl(storeId);

            deals.append(deal);
        }
        details["deals"] = deals;

        emit gameDealsReady(details);
    });
}

// ─── CheapShark: Store List ───

void StoreApiManager::fetchStores()
{
    QUrl url(CHEAPSHARK_BASE + "/stores");
    QNetworkRequest req(url);
    req.setTransferTimeout(10000);
    QNetworkReply *reply = m_nam->get(req);

    connect(reply, &QNetworkReply::finished, this, [this, reply]() {
        reply->deleteLater();
        if (reply->error() != QNetworkReply::NoError) {
            emit storesError(reply->errorString());
            return;
        }

        QJsonArray arr = QJsonDocument::fromJson(reply->readAll()).array();
        QVariantList stores;
        m_storeNames.clear();
        m_storeIcons.clear();

        for (const auto& val : arr) {
            QJsonObject obj = val.toObject();
            int storeId = obj["storeID"].toString().toInt();
            QString name = obj["storeName"].toString();
            QJsonObject images = obj["images"].toObject();
            QString icon = "https://www.cheapshark.com" + images["icon"].toString();

            m_storeNames[storeId] = name;
            m_storeIcons[storeId] = icon;

            QVariantMap store;
            store["storeID"]   = storeId;
            store["storeName"] = name;
            store["icon"]      = icon;
            store["isActive"]  = obj["isActive"].toInt();
            stores.append(store);
        }

        m_storesLoaded = true;
        emit storesReady(stores);
    });
}

// ─── IGDB API ───

void StoreApiManager::fetchIGDBGameInfo(const QString& gameName)
{
    if (m_igdbClientId.isEmpty() || m_igdbClientSecret.isEmpty()) {
        emit igdbGameInfoError("IGDB credentials not configured");
        return;
    }

    // Ensure we have a valid token, then make the request
    refreshIGDBToken([this, gameName]() {
        QUrl url(IGDB_BASE + "/games");
        QNetworkRequest req(url);
        req.setHeader(QNetworkRequest::ContentTypeHeader, "text/plain");
        req.setRawHeader("Client-ID", m_igdbClientId.toUtf8());
        req.setRawHeader("Authorization", ("Bearer " + m_igdbAccessToken).toUtf8());
        req.setTransferTimeout(15000);

        // IGDB uses POST with a body query
        QString body = QString(
            "search \"%1\"; "
            "fields name,summary,storyline,cover.url,screenshots.url,"
            "genres.name,platforms.name,first_release_date,rating,"
            "aggregated_rating,total_rating; "
            "limit 1;"
        ).arg(gameName);

        QNetworkReply *reply = m_nam->post(req, body.toUtf8());

        connect(reply, &QNetworkReply::finished, this, [this, reply]() {
            reply->deleteLater();
            if (reply->error() != QNetworkReply::NoError) {
                emit igdbGameInfoError(reply->errorString());
                return;
            }

            QJsonArray arr = QJsonDocument::fromJson(reply->readAll()).array();
            if (arr.isEmpty()) {
                emit igdbGameInfoError("Game not found on IGDB");
                return;
            }

            QJsonObject obj = arr.first().toObject();
            QVariantMap info;
            info["name"]        = obj["name"].toString();
            info["summary"]     = obj["summary"].toString();
            info["storyline"]   = obj["storyline"].toString();
            info["rating"]      = obj["rating"].toDouble();
            info["totalRating"] = obj["total_rating"].toDouble();
            info["aggregatedRating"] = obj["aggregated_rating"].toDouble();

            // Release date
            if (obj.contains("first_release_date")) {
                qint64 ts = obj["first_release_date"].toInteger();
                info["releaseDate"] = QDateTime::fromSecsSinceEpoch(ts).toString("MMM d, yyyy");
            }

            // Cover URL (IGDB returns //images.igdb.com/... — prepend https:)
            if (obj.contains("cover")) {
                QString coverUrl = obj["cover"].toObject()["url"].toString();
                if (coverUrl.startsWith("//"))
                    coverUrl = "https:" + coverUrl;
                // Get higher resolution: replace t_thumb with t_cover_big
                coverUrl.replace("t_thumb", "t_cover_big");
                info["coverUrl"] = coverUrl;
            }

            // Screenshots
            QVariantList screenshots;
            QJsonArray ssArr = obj["screenshots"].toArray();
            for (const auto& ss : ssArr) {
                QString ssUrl = ss.toObject()["url"].toString();
                if (ssUrl.startsWith("//"))
                    ssUrl = "https:" + ssUrl;
                ssUrl.replace("t_thumb", "t_screenshot_big");
                screenshots.append(ssUrl);
            }
            info["screenshots"] = screenshots;

            // Genres
            QStringList genres;
            QJsonArray genreArr = obj["genres"].toArray();
            for (const auto& g : genreArr)
                genres.append(g.toObject()["name"].toString());
            info["genres"] = genres.join(", ");

            // Platforms
            QStringList platforms;
            QJsonArray platArr = obj["platforms"].toArray();
            for (const auto& p : platArr)
                platforms.append(p.toObject()["name"].toString());
            info["platforms"] = platforms.join(", ");

            emit igdbGameInfoReady(info);
        });
    });
}

void StoreApiManager::refreshIGDBToken(std::function<void()> onReady)
{
    // Check if current token is still valid (with 60s buffer)
    if (!m_igdbAccessToken.isEmpty() &&
        QDateTime::currentSecsSinceEpoch() < m_igdbTokenExpiry - 60) {
        onReady();
        return;
    }

    QUrl url(TWITCH_TOKEN);
    QUrlQuery query;
    query.addQueryItem("client_id", m_igdbClientId);
    query.addQueryItem("client_secret", m_igdbClientSecret);
    query.addQueryItem("grant_type", "client_credentials");
    url.setQuery(query);

    QNetworkRequest req(url);
    req.setHeader(QNetworkRequest::ContentTypeHeader, "application/x-www-form-urlencoded");
    req.setTransferTimeout(10000);

    QNetworkReply *reply = m_nam->post(req, QByteArray());

    connect(reply, &QNetworkReply::finished, this, [this, reply, onReady]() {
        reply->deleteLater();
        if (reply->error() != QNetworkReply::NoError) {
            qWarning() << "IGDB token refresh failed:" << reply->errorString();
            emit igdbGameInfoError("Failed to authenticate with IGDB: " + reply->errorString());
            return;
        }

        QJsonObject obj = QJsonDocument::fromJson(reply->readAll()).object();
        m_igdbAccessToken = obj["access_token"].toString();
        int expiresIn = obj["expires_in"].toInt();
        m_igdbTokenExpiry = QDateTime::currentSecsSinceEpoch() + expiresIn;

        qDebug() << "IGDB token refreshed, expires in" << expiresIn << "seconds";
        onReady();
    });
}

void StoreApiManager::setIGDBCredentials(const QString& clientId, const QString& clientSecret)
{
    m_igdbClientId = clientId;
    m_igdbClientSecret = clientSecret;
    m_igdbAccessToken.clear();
    m_igdbTokenExpiry = 0;
    saveIGDBCredentials();
    emit igdbCredentialsSaved();
}

bool StoreApiManager::hasIGDBCredentials()
{
    return !m_igdbClientId.isEmpty() && !m_igdbClientSecret.isEmpty();
}

QString StoreApiManager::getIGDBClientId()
{
    return m_igdbClientId;
}

void StoreApiManager::loadIGDBCredentials()
{
    QFile file(igdbCredentialsPath());
    if (!file.open(QIODevice::ReadOnly))
        return;

    QJsonObject obj = QJsonDocument::fromJson(file.readAll()).object();
    m_igdbClientId = obj["client_id"].toString();
    m_igdbClientSecret = obj["client_secret"].toString();
}

void StoreApiManager::saveIGDBCredentials()
{
    QString dir = QDir::homePath() + "/.config/luna-ui";
    QDir().mkpath(dir);

    QFile file(igdbCredentialsPath());
    if (!file.open(QIODevice::WriteOnly))
        return;

    QJsonObject obj;
    obj["client_id"] = m_igdbClientId;
    obj["client_secret"] = m_igdbClientSecret;
    file.write(QJsonDocument(obj).toJson());
}

QString StoreApiManager::igdbCredentialsPath() const
{
    return QDir::homePath() + "/.config/luna-ui/igdb-credentials.json";
}

// ─── ProtonDB API ───

void StoreApiManager::fetchProtonRating(const QString& steamAppId)
{
    if (steamAppId.isEmpty() || steamAppId == "null" || steamAppId == "0") {
        emit protonRatingError(steamAppId, "No Steam App ID");
        return;
    }

    QUrl url(PROTONDB_BASE + "/" + steamAppId + ".json");
    QNetworkRequest req(url);
    req.setTransferTimeout(10000);
    QNetworkReply *reply = m_nam->get(req);

    connect(reply, &QNetworkReply::finished, this, [this, reply, steamAppId]() {
        reply->deleteLater();
        if (reply->error() != QNetworkReply::NoError) {
            emit protonRatingError(steamAppId, reply->errorString());
            return;
        }

        QJsonObject obj = QJsonDocument::fromJson(reply->readAll()).object();
        QVariantMap rating;
        rating["tier"]           = obj["tier"].toString();
        rating["trendingTier"]   = obj["trendingTier"].toString();
        rating["bestTier"]       = obj["bestReportedTier"].toString();
        rating["confidence"]     = obj["confidence"].toString();
        rating["score"]          = obj["score"].toDouble();
        rating["totalReports"]   = obj["total"].toInt();

        emit protonRatingReady(steamAppId, rating);
    });
}

// ─── Utility ───

QString StoreApiManager::getStoreName(int storeId)
{
    if (m_storeNames.contains(storeId))
        return m_storeNames[storeId];
    return "Store #" + QString::number(storeId);
}

QString StoreApiManager::getStoreIconUrl(int storeId)
{
    if (m_storeIcons.contains(storeId))
        return m_storeIcons[storeId];
    return QString();
}

QString StoreApiManager::getSteamHeaderUrl(const QString& steamAppId)
{
    return STEAM_CDN + "/" + steamAppId + "/header.jpg";
}

QString StoreApiManager::getSteamHeroUrl(const QString& steamAppId)
{
    return STEAM_CDN + "/" + steamAppId + "/library_hero.jpg";
}

QString StoreApiManager::getSteamCapsuleUrl(const QString& steamAppId)
{
    return STEAM_CDN + "/" + steamAppId + "/library_600x900_2x.jpg";
}
