#include "storeapimanager.h"
#include "credentialstore.h"
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QJsonDocument>
#include <QJsonArray>
#include <QJsonObject>
#include <QUrlQuery>
#include <QRegularExpression>
#include <QSet>
#include <QDir>
#include <QFile>
#include <QDateTime>
#include <QDebug>
#include <memory>

static const QString CHEAPSHARK_BASE = "https://www.cheapshark.com/api/1.0";
static const QString NEXARDA_BASE    = "https://www.nexarda.com/api/v3";
static const QString PROTONDB_BASE   = "https://www.protondb.com/api/v1/reports/summaries";
static const QString IGDB_BASE       = "https://api.igdb.com/v4";
static const QString TWITCH_TOKEN    = "https://id.twitch.tv/oauth2/token";
static const QString STEAM_CDN       = "https://cdn.akamai.steamstatic.com/steam/apps";

// Normalize a game title for fuzzy matching
static QString normalizeTitle(const QString& title) {
    QString norm = title.toLower().trimmed();
    // Remove common suffixes/prefixes, punctuation
    norm.remove(QRegularExpression("[^a-z0-9 ]"));
    // Collapse whitespace
    norm = norm.simplified();
    return norm;
}

StoreApiManager::StoreApiManager(QObject *parent)
    : QObject(parent)
    , m_nam(new QNetworkAccessManager(this))
{
    // Use build-time IGDB credentials as defaults (injected from GitHub Secrets)
#ifdef IGDB_CLIENT_ID
    m_igdbClientId = QStringLiteral(IGDB_CLIENT_ID);
    m_usingBuiltInCredentials = true;
#endif
#ifdef IGDB_CLIENT_SECRET
    m_igdbClientSecret = QStringLiteral(IGDB_CLIENT_SECRET);
#endif

    // User-saved credentials (encrypted) override built-in defaults
    loadIGDBCredentials();

    // Pre-fetch store list on construction
    fetchStores();
}

// ─── CheapShark: Fetch Deals ───

void StoreApiManager::fetchDeals(const QString& sortBy, int pageNumber, int pageSize)
{
    // Ensure store metadata is loaded (retries if initial fetch failed)
    if (!m_storesLoaded)
        fetchStores();

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
        QSet<QString> seenGameIDs;
        for (const auto& val : arr) {
            QJsonObject obj = val.toObject();
            QString gameId = obj["gameID"].toString();

            // Deduplicate: keep only the first (best) deal per game
            if (seenGameIDs.contains(gameId))
                continue;
            seenGameIDs.insert(gameId);

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
            deal["gameID"]       = gameId;
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
        QSet<QString> seenGameIDs;
        for (const auto& val : arr) {
            QJsonObject obj = val.toObject();
            QString gameId = obj["gameID"].toString();

            // Deduplicate: keep only the first deal per game
            if (seenGameIDs.contains(gameId))
                continue;
            seenGameIDs.insert(gameId);

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
            deal["gameID"]       = gameId;
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

// ─── Search: IGDB + CheapShark + Nexarda (parallel) ───

void StoreApiManager::searchGames(const QString& title)
{
    if (title.trimmed().isEmpty()) {
        emit searchResultsReady(QVariantList());
        return;
    }

    int generation = ++m_searchGeneration;
    auto state = std::make_shared<SearchMergeState>();

    // Lambda to check if all 3 searches are done, then merge
    auto checkMerge = [this, state, generation]() {
        if (state->completedCount >= 3)
            mergeSearchResults(state, generation);
    };

    // ── 1. IGDB search (primary: game metadata, platform-filtered) ──
    if (m_igdbClientId.isEmpty() || m_igdbClientSecret.isEmpty()) {
        // No IGDB credentials — skip IGDB, emit error
        state->completedCount++;
        // Still try CheapShark + Nexarda below
    } else {
        refreshIGDBToken([this, title, state, generation, checkMerge]() {
            if (generation != m_searchGeneration) return;

            QUrl url(IGDB_BASE + "/games");
            QNetworkRequest req(url);
            req.setHeader(QNetworkRequest::ContentTypeHeader, "text/plain");
            req.setRawHeader("Client-ID", m_igdbClientId.toUtf8());
            req.setRawHeader("Authorization", ("Bearer " + m_igdbAccessToken).toUtf8());
            req.setTransferTimeout(15000);

            // Search IGDB filtered to Windows (6) and Linux (3) platforms
            QString body = QString(
                "search \"%1\"; "
                "fields name,summary,cover.url,screenshots.url,"
                "genres.name,platforms.name,first_release_date,rating,"
                "aggregated_rating,total_rating,"
                "external_games.uid,external_games.category; "
                "where platforms = (6,3); "
                "limit 30;"
            ).arg(title);

            QNetworkReply *reply = m_nam->post(req, body.toUtf8());

            connect(reply, &QNetworkReply::finished, this, [this, reply, state, generation, checkMerge]() {
                reply->deleteLater();
                if (generation != m_searchGeneration) return;

                if (reply->error() != QNetworkReply::NoError) {
                    qWarning() << "IGDB search failed:" << reply->errorString();
                    state->completedCount++;
                    checkMerge();
                    return;
                }

                QJsonArray arr = QJsonDocument::fromJson(reply->readAll()).array();
                for (const auto& val : arr) {
                    QJsonObject obj = val.toObject();
                    QVariantMap game;
                    game["igdbId"] = obj["id"].toInt();
                    game["title"]  = obj["name"].toString();
                    game["summary"] = obj["summary"].toString();
                    game["rating"]  = obj["total_rating"].toDouble();
                    game["aggregatedRating"] = obj["aggregated_rating"].toDouble();

                    // Release date
                    if (obj.contains("first_release_date")) {
                        qint64 ts = obj["first_release_date"].toInteger();
                        game["releaseDate"] = QDateTime::fromSecsSinceEpoch(ts).toString("MMM d, yyyy");
                    }

                    // Cover URL
                    if (obj.contains("cover")) {
                        QString coverUrl = obj["cover"].toObject()["url"].toString();
                        if (coverUrl.startsWith("//"))
                            coverUrl = "https:" + coverUrl;
                        coverUrl.replace("t_thumb", "t_cover_big");
                        game["coverUrl"] = coverUrl;
                        // Also use as header image fallback
                        QString headerUrl = coverUrl;
                        headerUrl.replace("t_cover_big", "t_screenshot_big");
                        game["igdbHeaderUrl"] = headerUrl;
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
                    game["screenshots"] = screenshots;

                    // Genres
                    QStringList genres;
                    QJsonArray genreArr = obj["genres"].toArray();
                    for (const auto& g : genreArr)
                        genres.append(g.toObject()["name"].toString());
                    game["genres"] = genres.join(", ");

                    // Platforms
                    QStringList platforms;
                    QJsonArray platArr = obj["platforms"].toArray();
                    for (const auto& p : platArr)
                        platforms.append(p.toObject()["name"].toString());
                    game["platforms"] = platforms.join(", ");

                    // Extract Steam App ID from external_games (category 1 = Steam)
                    QJsonArray extArr = obj["external_games"].toArray();
                    for (const auto& ext : extArr) {
                        QJsonObject extObj = ext.toObject();
                        if (extObj["category"].toInt() == 1) {
                            game["steamAppID"] = extObj["uid"].toString();
                            break;
                        }
                    }

                    // Build image URLs from Steam App ID if available
                    QString appId = game["steamAppID"].toString();
                    if (!appId.isEmpty() && appId != "0") {
                        game["headerImage"] = getSteamHeaderUrl(appId);
                        game["heroImage"]   = getSteamHeroUrl(appId);
                        game["capsuleImage"] = getSteamCapsuleUrl(appId);
                    } else if (game.contains("coverUrl")) {
                        game["headerImage"] = game["igdbHeaderUrl"];
                        game["heroImage"]   = game["igdbHeaderUrl"];
                        game["capsuleImage"] = game["coverUrl"];
                    }

                    state->igdbResults.append(game);
                }

                state->completedCount++;
                checkMerge();
            });
        });
    }

    // ── 2. CheapShark search (for price data + CheapShark game IDs) ──
    {
        QUrl url(CHEAPSHARK_BASE + "/games");
        QUrlQuery query;
        query.addQueryItem("title", title);
        query.addQueryItem("limit", "60");
        url.setQuery(query);

        QNetworkRequest req(url);
        req.setTransferTimeout(15000);
        QNetworkReply *reply = m_nam->get(req);

        connect(reply, &QNetworkReply::finished, this, [this, reply, state, generation, checkMerge]() {
            reply->deleteLater();
            if (generation != m_searchGeneration) return;

            if (reply->error() != QNetworkReply::NoError) {
                qWarning() << "CheapShark search failed:" << reply->errorString();
                state->completedCount++;
                checkMerge();
                return;
            }

            QJsonArray arr = QJsonDocument::fromJson(reply->readAll()).array();
            for (const auto& val : arr) {
                QJsonObject obj = val.toObject();
                QVariantMap game;
                game["gameID"]     = obj["gameID"].toString();
                game["title"]      = obj["external"].toString();
                game["cheapest"]   = obj["cheapest"].toString();
                game["steamAppID"] = obj["steamAppID"].toString();
                game["thumb"]      = obj["thumb"].toString();
                state->cheapSharkResults.append(game);
            }

            state->completedCount++;
            checkMerge();
        });
    }

    // ── 3. Nexarda search (for Nexarda product IDs + prices) ──
    {
        QUrl url(NEXARDA_BASE + "/search");
        QUrlQuery query;
        query.addQueryItem("q", title);
        query.addQueryItem("type", "games");
        query.addQueryItem("currency", "USD");
        url.setQuery(query);

        QNetworkRequest req(url);
        req.setTransferTimeout(15000);
        QNetworkReply *reply = m_nam->get(req);

        connect(reply, &QNetworkReply::finished, this, [this, reply, state, generation, checkMerge]() {
            reply->deleteLater();
            if (generation != m_searchGeneration) return;

            if (reply->error() != QNetworkReply::NoError) {
                qWarning() << "Nexarda search failed:" << reply->errorString();
                state->completedCount++;
                checkMerge();
                return;
            }

            QByteArray data = reply->readAll();
            QJsonDocument doc = QJsonDocument::fromJson(data);

            // Nexarda response: { success, results: { items: [...] } }
            // Each item: { title, game_info: { id, name, lowest_price, highest_discount, ... } }
            QJsonArray arr;
            if (doc.isObject()) {
                QJsonObject root = doc.object();
                if (root.contains("results") && root["results"].isObject()) {
                    QJsonObject results = root["results"].toObject();
                    arr = results["items"].toArray();
                }
            }

            for (const auto& val : arr) {
                QJsonObject obj = val.toObject();
                QJsonObject gameInfo = obj["game_info"].toObject();
                QVariantMap game;
                game["nexardaId"] = QString::number(gameInfo["id"].toInt());
                game["title"]     = gameInfo["name"].toString();
                if (game["title"].toString().isEmpty())
                    game["title"] = obj["title"].toString();

                // Price info from game_info
                if (gameInfo.contains("lowest_price"))
                    game["lowestPrice"] = QString::number(gameInfo["lowest_price"].toDouble(), 'f', 2);

                if (gameInfo.contains("highest_discount"))
                    game["discount"] = QString::number(gameInfo["highest_discount"].toInt());

                if (!game["nexardaId"].toString().isEmpty() && game["nexardaId"].toString() != "0")
                    state->nexardaResults.append(game);
            }

            state->completedCount++;
            checkMerge();
        });
    }
}

void StoreApiManager::mergeSearchResults(std::shared_ptr<SearchMergeState> state, int generation)
{
    if (generation != m_searchGeneration)
        return;

    // Build lookup maps for CheapShark and Nexarda by normalized title and Steam ID
    QHash<QString, int> csByTitle;  // normalized title → index
    QHash<QString, int> csBySteam;  // steam app ID → index
    for (int i = 0; i < state->cheapSharkResults.size(); i++) {
        QVariantMap cs = state->cheapSharkResults[i].toMap();
        QString norm = normalizeTitle(cs["title"].toString());
        if (!norm.isEmpty())
            csByTitle.insert(norm, i);
        QString steamId = cs["steamAppID"].toString();
        if (!steamId.isEmpty() && steamId != "null" && steamId != "0")
            csBySteam.insert(steamId, i);
    }

    QHash<QString, int> nxByTitle;
    for (int i = 0; i < state->nexardaResults.size(); i++) {
        QVariantMap nx = state->nexardaResults[i].toMap();
        QString norm = normalizeTitle(nx["title"].toString());
        if (!norm.isEmpty())
            nxByTitle.insert(norm, i);
    }

    QVariantList results;

    for (const auto& igdbVar : state->igdbResults) {
        QVariantMap game = igdbVar.toMap();
        QString norm = normalizeTitle(game["title"].toString());
        QString steamId = game["steamAppID"].toString();

        // Try to match CheapShark by Steam ID first, then by title
        int csIdx = -1;
        if (!steamId.isEmpty() && csBySteam.contains(steamId))
            csIdx = csBySteam[steamId];
        else if (csByTitle.contains(norm))
            csIdx = csByTitle[norm];

        // Try to match Nexarda by title
        int nxIdx = -1;
        if (nxByTitle.contains(norm))
            nxIdx = nxByTitle[norm];

        // Only include if we have a price from at least one source
        bool hasPrice = false;
        QString cheapestPrice;
        QString normalPrice;
        QString savings;

        if (csIdx >= 0) {
            QVariantMap cs = state->cheapSharkResults[csIdx].toMap();
            game["cheapSharkGameID"] = cs["gameID"];
            QString csPrice = cs["cheapest"].toString();
            if (!csPrice.isEmpty()) {
                hasPrice = true;
                cheapestPrice = csPrice;
            }
            // Propagate Steam App ID from CheapShark if we didn't have one
            if (steamId.isEmpty() || steamId == "0") {
                QString csAppId = cs["steamAppID"].toString();
                if (!csAppId.isEmpty() && csAppId != "null" && csAppId != "0") {
                    game["steamAppID"] = csAppId;
                    game["headerImage"] = getSteamHeaderUrl(csAppId);
                    game["heroImage"]   = getSteamHeroUrl(csAppId);
                    game["capsuleImage"] = getSteamCapsuleUrl(csAppId);
                }
            }
        }

        if (nxIdx >= 0) {
            QVariantMap nx = state->nexardaResults[nxIdx].toMap();
            game["nexardaProductID"] = nx["nexardaId"];
            QString nxPrice = nx["lowestPrice"].toString();
            if (!nxPrice.isEmpty()) {
                hasPrice = true;
                // Use whichever is cheaper
                if (cheapestPrice.isEmpty() ||
                    nxPrice.toDouble() < cheapestPrice.toDouble()) {
                    cheapestPrice = nxPrice;
                }
            }
            if (nx.contains("discount")) {
                QString disc = nx["discount"].toString();
                if (!disc.isEmpty())
                    savings = disc;
            }
        }

        if (!hasPrice)
            continue;

        game["cheapestPrice"] = cheapestPrice;
        game["salePrice"]     = cheapestPrice;
        if (!savings.isEmpty())
            game["savings"] = savings;

        results.append(game);
    }

    // If no IGDB results came through but CheapShark has results, show those
    // (graceful fallback if IGDB is down or has no credentials)
    if (state->igdbResults.isEmpty() && !state->cheapSharkResults.isEmpty()) {
        for (const auto& csVar : state->cheapSharkResults) {
            QVariantMap cs = csVar.toMap();
            QVariantMap game;
            game["title"]     = cs["title"];
            game["steamAppID"] = cs["steamAppID"];
            game["cheapSharkGameID"] = cs["gameID"];
            game["cheapestPrice"] = cs["cheapest"];
            game["salePrice"]     = cs["cheapest"];

            QString appId = cs["steamAppID"].toString();
            if (!appId.isEmpty() && appId != "null" && appId != "0") {
                game["headerImage"] = getSteamHeaderUrl(appId);
                game["heroImage"]   = getSteamHeroUrl(appId);
                game["capsuleImage"] = getSteamCapsuleUrl(appId);
            } else {
                game["headerImage"] = cs["thumb"];
                game["capsuleImage"] = cs["thumb"];
            }

            results.append(game);
        }
    }

    emit searchResultsReady(results);
}

// ─── CheapShark: Game Details (all deals for one game) ───

void StoreApiManager::fetchGameDeals(const QString& cheapSharkGameId)
{
    if (cheapSharkGameId.isEmpty()) {
        emit gameDealsReady(QVariantMap());
        return;
    }

    // Ensure store metadata is available for resolving store names
    if (!m_storesLoaded) {
        auto successConn = std::make_shared<QMetaObject::Connection>();
        auto errorConn = std::make_shared<QMetaObject::Connection>();

        *successConn = connect(this, &StoreApiManager::storesReady, this,
            [this, cheapSharkGameId, successConn, errorConn](QVariantList) {
                disconnect(*successConn);
                disconnect(*errorConn);
                fetchGameDeals(cheapSharkGameId);
            });
        *errorConn = connect(this, &StoreApiManager::storesError, this,
            [this, cheapSharkGameId, successConn, errorConn](const QString&) {
                disconnect(*successConn);
                disconnect(*errorConn);
                m_storesLoaded = true;  // Prevent infinite retry
                fetchGameDeals(cheapSharkGameId);
            });

        fetchStores();
        return;
    }

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
            deal["dealLink"]  = QStringLiteral("https://www.cheapshark.com/redirect?dealID=")
                                + obj["dealID"].toString();
            deal["source"]    = QStringLiteral("CheapShark");

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

// ─── Nexarda: Fetch Prices for a specific product ───

void StoreApiManager::fetchNexardaPrices(const QString& nexardaId)
{
    if (nexardaId.isEmpty()) {
        emit nexardaPricesError("No Nexarda product ID");
        return;
    }

    QUrl url(NEXARDA_BASE + "/prices");
    QUrlQuery query;
    query.addQueryItem("type", "game");
    query.addQueryItem("id", nexardaId);
    query.addQueryItem("currency", "USD");
    url.setQuery(query);

    QNetworkRequest req(url);
    req.setTransferTimeout(15000);
    QNetworkReply *reply = m_nam->get(req);

    connect(reply, &QNetworkReply::finished, this, [this, reply]() {
        reply->deleteLater();
        if (reply->error() != QNetworkReply::NoError) {
            emit nexardaPricesError(reply->errorString());
            return;
        }

        QByteArray data = reply->readAll();
        QJsonDocument doc = QJsonDocument::fromJson(data);
        QVariantMap result;

        if (doc.isObject()) {
            QJsonObject root = doc.object();

            // Game info at root["info"]
            QJsonObject info = root["info"].toObject();
            result["gameName"] = info["name"].toVariant();
            result["cover"]    = info["cover"].toVariant();

            // Prices at root["prices"]
            QJsonObject prices = root["prices"].toObject();
            result["lowest"]  = prices["lowest"].toVariant();
            result["highest"] = prices["highest"].toVariant();
            result["stores"]  = prices["stores"].toVariant();
            result["offers"]  = prices["offers"].toVariant();

            // Flat list of offers at prices["list"]
            QVariantList deals;
            QJsonArray list = prices["list"].toArray();

            for (const auto& offerVal : list) {
                QJsonObject offer = offerVal.toObject();

                // Skip unavailable offers (price == -1)
                if (!offer["available"].toBool(true))
                    continue;
                double priceVal = offer["price"].toDouble(-1);
                if (priceVal < 0)
                    continue;

                QVariantMap deal;

                // Store is an object: { name, image, type, official }
                QJsonObject store = offer["store"].toObject();
                deal["storeName"] = store["name"].toString();
                deal["storeIcon"] = store["image"].toString();
                deal["storeType"] = store["type"].toString();

                deal["price"]    = QString::number(priceVal, 'f', 2);
                deal["discount"] = QString::number(offer["discount"].toInt());
                deal["savings"]  = QString::number(offer["discount"].toInt());
                deal["edition"]  = offer["edition"].toString();
                deal["region"]   = offer["region"].toString();
                deal["dealLink"] = offer["url"].toString();
                deal["source"]   = QStringLiteral("Nexarda");

                // Coupon info
                QJsonObject coupon = offer["coupon"].toObject();
                if (coupon["available"].toBool()) {
                    deal["couponCode"]     = coupon["code"].toString();
                    deal["couponDiscount"] = QString::number(coupon["discount"].toInt());
                }

                if (!deal["storeName"].toString().isEmpty()) {
                    deals.append(deal);
                }
            }

            result["deals"] = deals;
        }

        emit nexardaPricesReady(result);
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
    m_usingBuiltInCredentials = false;
    saveIGDBCredentials();
    emit igdbCredentialsSaved();
}

void StoreApiManager::clearIGDBCredentials()
{
    // Remove user-saved credentials, revert to built-in if available
    QFile::remove(igdbCredentialsPath());

#ifdef IGDB_CLIENT_ID
    m_igdbClientId = QStringLiteral(IGDB_CLIENT_ID);
    m_usingBuiltInCredentials = true;
#else
    m_igdbClientId.clear();
    m_usingBuiltInCredentials = false;
#endif
#ifdef IGDB_CLIENT_SECRET
    m_igdbClientSecret = QStringLiteral(IGDB_CLIENT_SECRET);
#else
    m_igdbClientSecret.clear();
#endif

    m_igdbAccessToken.clear();
    m_igdbTokenExpiry = 0;
    emit igdbCredentialsSaved();
}

bool StoreApiManager::hasIGDBCredentials()
{
    return !m_igdbClientId.isEmpty() && !m_igdbClientSecret.isEmpty();
}

bool StoreApiManager::hasBuiltInIGDBCredentials()
{
    // True when compile-time credentials were provided via GitHub Secrets
#if defined(IGDB_CLIENT_ID) && defined(IGDB_CLIENT_SECRET)
    return true;
#else
    return false;
#endif
}

QString StoreApiManager::getIGDBClientId()
{
    return m_igdbClientId;
}

void StoreApiManager::loadIGDBCredentials()
{
    QByteArray data = CredentialStore::loadEncrypted(igdbCredentialsPath());
    if (data.isEmpty())
        return;

    QJsonObject obj = QJsonDocument::fromJson(data).object();
    if (obj.isEmpty())
        return;

    // User-saved credentials override built-in defaults
    QString clientId = obj["client_id"].toString();
    QString clientSecret = obj["client_secret"].toString();
    if (!clientId.isEmpty() && !clientSecret.isEmpty()) {
        m_igdbClientId = clientId;
        m_igdbClientSecret = clientSecret;
        m_usingBuiltInCredentials = false;
    }
}

void StoreApiManager::saveIGDBCredentials()
{
    QJsonObject obj;
    obj["client_id"] = m_igdbClientId;
    obj["client_secret"] = m_igdbClientSecret;

    QByteArray json = QJsonDocument(obj).toJson(QJsonDocument::Compact);
    CredentialStore::saveEncrypted(igdbCredentialsPath(), json);
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
