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
static const QString PROTONDB_BASE   = "https://www.protondb.com/api/v1/reports/summaries";
static const QString IGDB_BASE       = "https://api.igdb.com/v4";
static const QString TWITCH_TOKEN    = "https://id.twitch.tv/oauth2/token";
static const QString STEAM_CDN       = "https://cdn.akamai.steamstatic.com/steam/apps";
static const QString STEAM_STORE_API = "https://store.steampowered.com/api";

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

// ─── Search: IGDB + CheapShark (parallel) ───

void StoreApiManager::searchGames(const QString& title)
{
    if (title.trimmed().isEmpty()) {
        emit searchResultsReady(QVariantList());
        return;
    }

    int generation = ++m_searchGeneration;
    auto state = std::make_shared<SearchMergeState>();

    // Lambda to check if both searches are done, then merge
    auto checkMerge = [this, state, generation]() {
        if (state->completedCount >= 2)
            mergeSearchResults(state, generation);
    };

    // ── 1. IGDB search (primary: game metadata, platform-filtered to Windows + Linux) ──
    if (m_igdbClientId.isEmpty() || m_igdbClientSecret.isEmpty()) {
        // No IGDB credentials — skip IGDB
        state->completedCount++;
        // Still try CheapShark below
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
            // Include websites for purchase links (13=Steam, 15=Itch, 16=Epic, 17=GOG)
            QString body = QString(
                "search \"%1\"; "
                "fields name,summary,cover.url,screenshots.url,"
                "genres.name,platforms.name,first_release_date,rating,"
                "aggregated_rating,total_rating,"
                "external_games.uid,external_games.category,"
                "websites.url,websites.category; "
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

                    // Extract purchase URLs from websites
                    // Categories: 13=Steam, 15=Itch.io, 16=Epic Games, 17=GOG
                    QVariantList purchaseUrls;
                    QJsonArray webArr = obj["websites"].toArray();
                    for (const auto& web : webArr) {
                        QJsonObject webObj = web.toObject();
                        int cat = webObj["category"].toInt();
                        QString webUrl = webObj["url"].toString();
                        if (webUrl.isEmpty()) continue;

                        QString storeName;
                        switch (cat) {
                            case 13: storeName = "Steam"; break;
                            case 15: storeName = "Itch.io"; break;
                            case 16: storeName = "Epic Games"; break;
                            case 17: storeName = "GOG"; break;
                            default: continue;
                        }
                        QVariantMap link;
                        link["storeName"] = storeName;
                        link["url"] = webUrl;
                        link["category"] = cat;
                        purchaseUrls.append(link);
                    }
                    game["purchaseUrls"] = purchaseUrls;

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
}

void StoreApiManager::mergeSearchResults(std::shared_ptr<SearchMergeState> state, int generation)
{
    if (generation != m_searchGeneration)
        return;

    // Build lookup maps for CheapShark by normalized title and Steam ID
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

        QString cheapestPrice;
        QString savings;

        if (csIdx >= 0) {
            QVariantMap cs = state->cheapSharkResults[csIdx].toMap();
            game["cheapSharkGameID"] = cs["gameID"];
            QString csPrice = cs["cheapest"].toString();
            if (!csPrice.isEmpty()) {
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

        // Set price fields if we have a CheapShark price
        if (!cheapestPrice.isEmpty()) {
            game["cheapestPrice"] = cheapestPrice;
            game["salePrice"]     = cheapestPrice;
            game["hasPrice"]      = true;
        } else {
            // No CheapShark price — mark for price scraping via IGDB purchase links
            game["hasPrice"] = false;
        }
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
            game["hasPrice"]      = true;

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

// ─── Store Price Scraping (fallback for games without CheapShark prices) ───

void StoreApiManager::fetchStorePrices(const QString& steamAppId, const QVariantList& purchaseUrls)
{
    // Use a shared state to collect results from multiple sources
    struct PriceState {
        QVariantList deals;
        int pending = 0;
    };
    auto priceState = std::make_shared<PriceState>();

    // Count expected requests
    bool hasSteam = !steamAppId.isEmpty() && steamAppId != "null" && steamAppId != "0";
    if (hasSteam)
        priceState->pending++;

    // Count non-Steam purchase URLs (we'll show them as buy links)
    for (const auto& urlVar : purchaseUrls) {
        QVariantMap link = urlVar.toMap();
        int cat = link["category"].toInt();
        if (cat != 13)  // Skip Steam (handled via API)
            priceState->pending++;
    }

    if (priceState->pending == 0) {
        emit storePricesError("No store links available");
        return;
    }

    auto checkDone = [this, priceState]() {
        if (priceState->pending <= 0)
            emit storePricesReady(priceState->deals);
    };

    // ── Fetch Steam price via Steam Store API ──
    if (hasSteam) {
        QUrl url(STEAM_STORE_API + "/appdetails");
        QUrlQuery query;
        query.addQueryItem("appids", steamAppId);
        query.addQueryItem("cc", "us");
        query.addQueryItem("filters", "price_overview");
        url.setQuery(query);

        QNetworkRequest req(url);
        req.setTransferTimeout(15000);
        QNetworkReply *reply = m_nam->get(req);

        connect(reply, &QNetworkReply::finished, this, [this, reply, steamAppId, priceState, checkDone]() {
            reply->deleteLater();

            if (reply->error() == QNetworkReply::NoError) {
                QJsonObject root = QJsonDocument::fromJson(reply->readAll()).object();
                QJsonObject appData = root[steamAppId].toObject();

                if (appData["success"].toBool()) {
                    QJsonObject data = appData["data"].toObject();
                    QJsonObject priceOverview = data["price_overview"].toObject();

                    if (!priceOverview.isEmpty()) {
                        QVariantMap deal;
                        deal["storeName"] = QStringLiteral("Steam");
                        deal["storeIcon"] = QStringLiteral("https://www.cheapshark.com/img/stores/icons/0.png");

                        // Steam returns prices in cents
                        double finalPrice = priceOverview["final"].toInt() / 100.0;
                        double initialPrice = priceOverview["initial"].toInt() / 100.0;
                        int discountPct = priceOverview["discount_percent"].toInt();

                        deal["price"] = QString::number(finalPrice, 'f', 2);
                        deal["retailPrice"] = QString::number(initialPrice, 'f', 2);
                        deal["savings"] = QString::number(discountPct);
                        deal["dealLink"] = QStringLiteral("https://store.steampowered.com/app/") + steamAppId;
                        deal["source"] = QStringLiteral("Steam");
                        priceState->deals.append(deal);
                    } else if (data.contains("is_free") && data["is_free"].toBool()) {
                        QVariantMap deal;
                        deal["storeName"] = QStringLiteral("Steam");
                        deal["storeIcon"] = QStringLiteral("https://www.cheapshark.com/img/stores/icons/0.png");
                        deal["price"] = QStringLiteral("0.00");
                        deal["retailPrice"] = QStringLiteral("0.00");
                        deal["savings"] = QStringLiteral("0");
                        deal["dealLink"] = QStringLiteral("https://store.steampowered.com/app/") + steamAppId;
                        deal["source"] = QStringLiteral("Steam");
                        priceState->deals.append(deal);
                    }
                }
            } else {
                qWarning() << "Steam Store API failed:" << reply->errorString();
            }

            priceState->pending--;
            checkDone();
        });
    }

    // ── Scrape GOG prices from their embed API ──
    for (const auto& urlVar : purchaseUrls) {
        QVariantMap link = urlVar.toMap();
        int cat = link["category"].toInt();
        QString storeUrl = link["url"].toString();
        QString storeName = link["storeName"].toString();

        if (cat == 13) continue;  // Steam handled above

        if (cat == 17 && storeUrl.contains("gog.com")) {
            // Try GOG API: extract slug from URL and query their catalog
            // GOG URL format: https://www.gog.com/en/game/<slug>
            QRegularExpression gogSlugRe("/game/([a-z0-9_]+)");
            QRegularExpressionMatch match = gogSlugRe.match(storeUrl);

            if (match.hasMatch()) {
                QString slug = match.captured(1);
                QUrl gogUrl("https://catalog.gog.com/v1/catalog");
                QUrlQuery gogQuery;
                gogQuery.addQueryItem("query", slug);
                gogQuery.addQueryItem("limit", "1");
                gogQuery.addQueryItem("countryCode", "US");
                gogQuery.addQueryItem("currencyCode", "USD");
                gogUrl.setQuery(gogQuery);

                QNetworkRequest gogReq(gogUrl);
                gogReq.setTransferTimeout(15000);
                QNetworkReply *gogReply = m_nam->get(gogReq);

                connect(gogReply, &QNetworkReply::finished, this,
                    [this, gogReply, storeUrl, priceState, checkDone]() {
                    gogReply->deleteLater();

                    if (gogReply->error() == QNetworkReply::NoError) {
                        QJsonObject root = QJsonDocument::fromJson(gogReply->readAll()).object();
                        QJsonArray products = root["products"].toArray();

                        if (!products.isEmpty()) {
                            QJsonObject product = products.first().toObject();
                            QJsonObject price = product["price"].toObject();

                            if (!price.isEmpty()) {
                                QVariantMap deal;
                                deal["storeName"] = QStringLiteral("GOG");
                                deal["storeIcon"] = QStringLiteral("");
                                QString finalMoney = price["finalMoney"].toObject()["amount"].toString();
                                QString baseMoney = price["baseMoney"].toObject()["amount"].toString();
                                int discount = price["discount"].toInt();

                                deal["price"] = finalMoney;
                                deal["retailPrice"] = baseMoney;
                                deal["savings"] = QString::number(discount);
                                deal["dealLink"] = storeUrl;
                                deal["source"] = QStringLiteral("GOG");
                                priceState->deals.append(deal);
                            }
                        }
                    } else {
                        qWarning() << "GOG catalog API failed:" << gogReply->errorString();
                    }

                    priceState->pending--;
                    checkDone();
                });
                continue;
            }
        }

        // For Epic, Itch.io, and other stores: add as purchase link without price
        QVariantMap deal;
        deal["storeName"] = storeName;
        deal["storeIcon"] = QStringLiteral("");
        deal["price"] = QStringLiteral("");
        deal["retailPrice"] = QStringLiteral("");
        deal["savings"] = QStringLiteral("0");
        deal["dealLink"] = storeUrl;
        deal["source"] = storeName;
        priceState->deals.append(deal);
        priceState->pending--;
        checkDone();
    }
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
