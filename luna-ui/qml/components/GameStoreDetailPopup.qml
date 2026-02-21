import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Rectangle {
    id: detailPopup
    anchors.fill: parent
    color: Qt.rgba(0, 0, 0, 0.85)
    visible: false
    z: 500

    property string gameTitle: ""
    property string gameID: ""
    property string cheapSharkGameID: ""
    property string steamAppID: ""
    property string headerImage: ""
    property string salePrice: ""
    property string normalPrice: ""
    property string savings: ""
    property string metacriticScore: ""
    property string steamRatingText: ""
    property string steamRatingPercent: ""

    // Data loaded from APIs
    property var gameDeals: []        // CheapShark deals
    property var scrapedDeals: []     // Deals from Steam/GOG/IGDB purchase links
    property var allDeals: []         // Combined deals from all sources
    property var purchaseUrls: []     // IGDB purchase URLs for price scraping
    property string igdbSummary: ""
    property string igdbStoryline: ""
    property string igdbGenres: ""
    property string igdbPlatforms: ""
    property string igdbReleaseDate: ""
    property double igdbRating: 0
    property var igdbScreenshots: []
    property var igdbArtworks: []
    property var igdbVideos: []
    property string igdbDeveloper: ""
    property string igdbPublisher: ""
    property string igdbGameModes: ""
    property string igdbThemes: ""
    property string igdbPerspectives: ""
    property string igdbCoverUrl: ""
    property string protonTier: ""
    property string protonConfidence: ""
    property int protonTotalReports: 0
    property string cheapestEverPrice: ""

    // Loading states
    property bool loadingDeals: false
    property bool loadingStorePrices: false
    property bool loadingIGDB: false
    property bool loadingProton: false

    // Error states
    property string dealsErrorMsg: ""
    property string igdbErrorMsg: ""

    signal openDealUrl(string url, string storeName)

    // ─── Keyboard Navigation ───
    // Zones: "screenshots", "stores"
    property string popupNavZone: "screenshots"
    property int storeFocusIndex: 0

    function handleKeys(event) {
        switch (event.key) {
        case Qt.Key_Escape:
            close()
            event.accepted = true
            break
        case Qt.Key_Left:
            if (popupNavZone === "screenshots" && igdbScreenshots.length > 1) {
                if (fullContent.currentScreenshotIndex > 0)
                    fullContent.currentScreenshotIndex--
                else
                    fullContent.currentScreenshotIndex = igdbScreenshots.length - 1
            }
            event.accepted = true
            break
        case Qt.Key_Right:
            if (popupNavZone === "screenshots" && igdbScreenshots.length > 1) {
                if (fullContent.currentScreenshotIndex < igdbScreenshots.length - 1)
                    fullContent.currentScreenshotIndex++
                else
                    fullContent.currentScreenshotIndex = 0
            }
            event.accepted = true
            break
        case Qt.Key_Down:
            if (popupNavZone === "screenshots") {
                if (allDeals.length > 0) {
                    popupNavZone = "stores"
                    storeFocusIndex = 0
                }
            } else if (popupNavZone === "stores") {
                if (storeFocusIndex < allDeals.length - 1)
                    storeFocusIndex++
            }
            // Scroll down in the detail flickable
            contentFlick.contentY = Math.min(contentFlick.contentY + 80, contentFlick.contentHeight - contentFlick.height)
            event.accepted = true
            break
        case Qt.Key_Up:
            if (popupNavZone === "stores") {
                if (storeFocusIndex > 0) storeFocusIndex--
                else popupNavZone = "screenshots"
            } else if (popupNavZone === "screenshots") {
                // Scroll up
                contentFlick.contentY = Math.max(contentFlick.contentY - 80, 0)
            }
            event.accepted = true
            break
        case Qt.Key_Return:
        case Qt.Key_Enter:
            if (popupNavZone === "stores" && storeFocusIndex >= 0 && storeFocusIndex < allDeals.length) {
                var deal = allDeals[storeFocusIndex]
                if (deal.dealLink) {
                    openDealUrl(deal.dealLink, deal.storeName || "")
                }
            }
            event.accepted = true
            break
        }
    }

    function open(deal) {
        gameTitle = deal.title || ""
        gameID = deal.gameID || deal.cheapSharkGameID || ""
        cheapSharkGameID = deal.cheapSharkGameID || deal.gameID || ""
        steamAppID = deal.steamAppID || ""
        headerImage = deal.headerImage || deal.heroImage || deal.coverUrl || ""
        salePrice = deal.salePrice || deal.cheapestPrice || deal.cheapest || ""
        normalPrice = deal.normalPrice || ""
        savings = deal.savings || ""
        metacriticScore = deal.metacriticScore || ""
        steamRatingText = deal.steamRatingText || ""
        steamRatingPercent = deal.steamRatingPercent || ""
        purchaseUrls = deal.purchaseUrls || []

        // Reset loaded data
        gameDeals = []
        scrapedDeals = []
        allDeals = []
        igdbSummary = ""
        igdbStoryline = ""
        igdbGenres = ""
        igdbPlatforms = ""
        igdbReleaseDate = ""
        igdbRating = 0
        igdbScreenshots = []
        igdbArtworks = []
        igdbVideos = []
        igdbDeveloper = ""
        igdbPublisher = ""
        igdbGameModes = ""
        igdbThemes = ""
        igdbPerspectives = ""
        igdbCoverUrl = ""
        protonTier = ""
        protonConfidence = ""
        protonTotalReports = 0
        cheapestEverPrice = ""
        dealsErrorMsg = ""
        igdbErrorMsg = ""
        loadingDeals = true
        loadingStorePrices = false
        loadingIGDB = true
        loadingProton = true

        // Pre-populate IGDB data from browse/search results
        if (deal.summary) igdbSummary = deal.summary
        if (deal.storyline) igdbStoryline = deal.storyline
        if (deal.genres) igdbGenres = deal.genres
        if (deal.platforms) igdbPlatforms = deal.platforms
        if (deal.releaseDate) igdbReleaseDate = deal.releaseDate
        if (deal.rating) igdbRating = deal.rating
        if (deal.screenshots && deal.screenshots.length > 0) igdbScreenshots = deal.screenshots
        if (deal.artworks && deal.artworks.length > 0) igdbArtworks = deal.artworks
        if (deal.videos && deal.videos.length > 0) igdbVideos = deal.videos
        if (deal.developer) igdbDeveloper = deal.developer
        if (deal.publisher) igdbPublisher = deal.publisher
        if (deal.gameModes) igdbGameModes = deal.gameModes
        if (deal.themes) igdbThemes = deal.themes
        if (deal.playerPerspectives) igdbPerspectives = deal.playerPerspectives
        if (deal.coverUrl) igdbCoverUrl = deal.coverUrl

        // Reset scroll position, screenshot index, and keyboard nav
        contentFlick.contentY = 0
        fullContent.currentScreenshotIndex = 0
        popupNavZone = "screenshots"
        storeFocusIndex = 0

        visible = true

        // Fetch CheapShark deals (if we have a CheapShark game ID)
        if (cheapSharkGameID !== "") {
            StoreApi.fetchGameDeals(cheapSharkGameID)
        } else {
            loadingDeals = false
            // No CheapShark data — try scraping prices from store APIs
            if (steamAppID !== "" || (purchaseUrls && purchaseUrls.length > 0) || gameTitle !== "") {
                loadingStorePrices = true
                StoreApi.fetchStorePrices(steamAppID, purchaseUrls, gameTitle)
            }
        }

        // Fetch full IGDB info (may enrich with screenshots, storyline)
        if (gameTitle !== "") {
            StoreApi.fetchIGDBGameInfo(gameTitle)
        } else {
            loadingIGDB = false
        }

        if (steamAppID !== "" && steamAppID !== "null" && steamAppID !== "0")
            StoreApi.fetchProtonRating(steamAppID)
        else
            loadingProton = false
    }

    function close() {
        visible = false
    }

    // Block clicks behind popup
    MouseArea {
        anchors.fill: parent
        onClicked: detailPopup.close()
    }

    // Merge CheapShark + scraped deals into a single combined list,
    // deduplicating so the same store doesn't appear twice.
    function rebuildAllDeals() {
        // Canonical key for store-name matching (handles naming variants)
        function storeKey(name) {
            var n = (name || "").toLowerCase()
            if (n.indexOf("steam") >= 0) return "steam"
            if (n.indexOf("epic") >= 0) return "epic"
            if (n.indexOf("green") >= 0 || n.indexOf("gmg") >= 0) return "gmg"
            if (n.indexOf("gog") >= 0) return "gog"
            if (n.indexOf("humble") >= 0) return "humble"
            if (n.indexOf("fanatical") >= 0) return "fanatical"
            return n.replace(/\s+/g, "")
        }

        var combined = []
        var seen = {}

        // CheapShark deals first (preferred — includes redirect tracking)
        for (var i = 0; i < gameDeals.length; i++) {
            combined.push(gameDeals[i])
            var k = storeKey(gameDeals[i].storeName)
            if (k) seen[k] = true
        }

        // Scraped deals: only add stores not already covered by CheapShark
        for (var j = 0; j < scrapedDeals.length; j++) {
            var sk = storeKey(scrapedDeals[j].storeName)
            if (!sk || !seen[sk]) {
                combined.push(scrapedDeals[j])
                if (sk) seen[sk] = true
            }
        }

        allDeals = combined
    }

    // ─── API Response Handlers ───
    Connections {
        target: StoreApi

        function onGameDealsReady(details) {
            if (!detailPopup.visible) return
            detailPopup.gameDeals = details.deals || []
            detailPopup.cheapestEverPrice = details.cheapestEverPrice || ""
            if (details.headerImage)
                detailPopup.headerImage = details.headerImage
            detailPopup.dealsErrorMsg = ""
            detailPopup.loadingDeals = false
            detailPopup.rebuildAllDeals()

            // Supplement CheapShark with stores it doesn't cover
            // Build list of store names CheapShark already has deals for
            var coveredStores = []
            var deals = details.deals || []
            for (var i = 0; i < deals.length; i++) {
                if (deals[i].storeName)
                    coveredStores.push(deals[i].storeName)
            }

            // Fetch prices from stores not covered by CheapShark
            if (detailPopup.steamAppID !== "" ||
                (detailPopup.purchaseUrls && detailPopup.purchaseUrls.length > 0) ||
                detailPopup.gameTitle !== "") {
                detailPopup.loadingStorePrices = true
                StoreApi.fetchStorePrices(detailPopup.steamAppID, detailPopup.purchaseUrls,
                                          detailPopup.gameTitle, coveredStores)
            }
        }

        function onGameDealsError(error) {
            if (!detailPopup.visible) return
            detailPopup.dealsErrorMsg = error
            detailPopup.loadingDeals = false

            // CheapShark failed — fetch from all stores directly (no covered stores)
            if (detailPopup.steamAppID !== "" ||
                (detailPopup.purchaseUrls && detailPopup.purchaseUrls.length > 0) ||
                detailPopup.gameTitle !== "") {
                detailPopup.loadingStorePrices = true
                StoreApi.fetchStorePrices(detailPopup.steamAppID, detailPopup.purchaseUrls, detailPopup.gameTitle)
            } else {
                detailPopup.rebuildAllDeals()
            }
        }

        function onStorePricesReady(deals) {
            if (!detailPopup.visible) return
            detailPopup.scrapedDeals = deals || []
            detailPopup.loadingStorePrices = false
            detailPopup.rebuildAllDeals()
        }

        function onStorePricesError(error) {
            if (!detailPopup.visible) return
            detailPopup.loadingStorePrices = false
            detailPopup.rebuildAllDeals()
        }

        function onIgdbGameInfoReady(info) {
            if (!detailPopup.visible) return
            // Update with full IGDB data (richer than browse results)
            if (info.summary) detailPopup.igdbSummary = info.summary
            if (info.storyline) detailPopup.igdbStoryline = info.storyline
            if (info.genres) detailPopup.igdbGenres = info.genres
            if (info.platforms) detailPopup.igdbPlatforms = info.platforms
            if (info.releaseDate) detailPopup.igdbReleaseDate = info.releaseDate
            if (info.totalRating) detailPopup.igdbRating = info.totalRating
            if (info.screenshots && info.screenshots.length > 0) detailPopup.igdbScreenshots = info.screenshots
            if (info.artworks && info.artworks.length > 0) detailPopup.igdbArtworks = info.artworks
            if (info.videos && info.videos.length > 0) detailPopup.igdbVideos = info.videos
            if (info.developer) detailPopup.igdbDeveloper = info.developer
            if (info.publisher) detailPopup.igdbPublisher = info.publisher
            if (info.gameModes) detailPopup.igdbGameModes = info.gameModes
            if (info.themes) detailPopup.igdbThemes = info.themes
            if (info.playerPerspectives) detailPopup.igdbPerspectives = info.playerPerspectives
            if (info.coverUrl) detailPopup.igdbCoverUrl = info.coverUrl
            detailPopup.igdbErrorMsg = ""
            detailPopup.loadingIGDB = false
        }

        function onIgdbGameInfoError(error) {
            if (!detailPopup.visible) return
            // Only set error if we don't already have pre-populated data
            if (detailPopup.igdbSummary === "")
                detailPopup.igdbErrorMsg = error
            detailPopup.loadingIGDB = false
        }

        function onProtonRatingReady(appId, rating) {
            if (!detailPopup.visible) return
            if (appId !== detailPopup.steamAppID) return
            detailPopup.protonTier = rating.tier || ""
            detailPopup.protonConfidence = rating.confidence || ""
            detailPopup.protonTotalReports = rating.totalReports || 0
            detailPopup.loadingProton = false
        }

        function onProtonRatingError(appId, error) {
            if (!detailPopup.visible) return
            if (appId !== detailPopup.steamAppID) return
            detailPopup.loadingProton = false
        }
    }

    // ─── Popup Card (near fullscreen) ───
    Rectangle {
        id: popupCard
        anchors.centerIn: parent
        width: parent.width - 60
        height: parent.height - 40
        radius: 20
        color: ThemeManager.getColor("background")
        border.color: Qt.rgba(ThemeManager.getColor("primary").r,
                              ThemeManager.getColor("primary").g,
                              ThemeManager.getColor("primary").b, 0.3)
        border.width: 1
        clip: true

        // Prevent clicks from closing
        MouseArea { anchors.fill: parent; onClicked: {} }

        // Close button (always visible, on top)
        Rectangle {
            id: closeBtn
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.margins: 20
            width: 56
            height: 56
            radius: 28
            z: 10
            color: closeBtnArea.containsMouse
                   ? ThemeManager.getColor("hover") : ThemeManager.getColor("surface")

            Behavior on color { ColorAnimation { duration: 150 } }

            Text {
                anchors.centerIn: parent
                text: "\u2715"
                font.pixelSize: 28
                font.bold: true
                color: "#ffffff"
            }

            MouseArea {
                id: closeBtnArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: detailPopup.close()
            }
        }

        // ─── Full scrollable content ───
        Flickable {
            id: contentFlick
            anchors.fill: parent
            contentHeight: fullContent.height + 40
            clip: true
            flickableDirection: Flickable.VerticalFlick
            boundsBehavior: Flickable.StopAtBounds

            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

            ColumnLayout {
                id: fullContent
                width: contentFlick.width
                spacing: 0

                // Track current screenshot index
                property int currentScreenshotIndex: 0

                // ─── Hero Banner with Screenshot Viewer ───
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.min(popupCard.height * 0.45, 480)
                    color: "#000000"
                    clip: true

                    // Background: artwork or screenshot or header
                    Image {
                        id: heroBackdrop
                        anchors.fill: parent
                        source: {
                            if (igdbArtworks.length > 0) return igdbArtworks[0]
                            if (igdbScreenshots.length > 0) return igdbScreenshots[fullContent.currentScreenshotIndex]
                            return headerImage
                        }
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        cache: true
                        opacity: status === Image.Ready ? 1.0 : 0.0
                        Behavior on opacity { NumberAnimation { duration: 400 } }
                    }

                    // Gradient overlay for readability
                    Rectangle {
                        anchors.fill: parent
                        gradient: Gradient {
                            GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, 0.15) }
                            GradientStop { position: 0.6; color: Qt.rgba(0, 0, 0, 0.4) }
                            GradientStop { position: 1.0; color: Qt.rgba(ThemeManager.getColor("background").r,
                                                                          ThemeManager.getColor("background").g,
                                                                          ThemeManager.getColor("background").b, 0.95) }
                        }
                    }

                    // Screenshot navigation (if viewing screenshots)
                    Rectangle {
                        visible: igdbScreenshots.length > 1
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.leftMargin: 16
                        width: 44; height: 44; radius: 22
                        color: prevArea.containsMouse ? ThemeManager.getColor("hover") : ThemeManager.getColor("surface")
                        Text { anchors.centerIn: parent; text: "\u276E"; font.pixelSize: 22; font.bold: true; color: ThemeManager.getColor("textPrimary") }
                        MouseArea {
                            id: prevArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: fullContent.currentScreenshotIndex = fullContent.currentScreenshotIndex > 0 ? fullContent.currentScreenshotIndex - 1 : igdbScreenshots.length - 1
                        }
                    }
                    Rectangle {
                        visible: igdbScreenshots.length > 1
                        anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; anchors.rightMargin: 16
                        width: 44; height: 44; radius: 22
                        color: nextArea.containsMouse ? ThemeManager.getColor("hover") : ThemeManager.getColor("surface")
                        Text { anchors.centerIn: parent; text: "\u276F"; font.pixelSize: 22; font.bold: true; color: ThemeManager.getColor("textPrimary") }
                        MouseArea {
                            id: nextArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: fullContent.currentScreenshotIndex = fullContent.currentScreenshotIndex < igdbScreenshots.length - 1 ? fullContent.currentScreenshotIndex + 1 : 0
                        }
                    }

                    // Screenshot dots
                    Row {
                        visible: igdbScreenshots.length > 1
                        anchors.bottom: parent.bottom; anchors.horizontalCenter: parent.horizontalCenter; anchors.bottomMargin: 60
                        spacing: 8
                        Repeater {
                            model: igdbScreenshots.length
                            Rectangle {
                                width: index === fullContent.currentScreenshotIndex ? 24 : 10; height: 10; radius: 5
                                color: index === fullContent.currentScreenshotIndex ? "#fff" : Qt.rgba(1, 1, 1, 0.4)
                                Behavior on width { NumberAnimation { duration: 150 } }
                            }
                        }
                    }

                    // Focus border
                    Rectangle {
                        anchors.fill: parent; color: "transparent"
                        border.color: (detailPopup.visible && popupNavZone === "screenshots") ? ThemeManager.getColor("focus") : "transparent"
                        border.width: (detailPopup.visible && popupNavZone === "screenshots") ? 3 : 0
                    }
                }

                // ─── Title & Info Section (Apple-style with cover art) ───
                RowLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: 36
                    Layout.rightMargin: 36
                    Layout.topMargin: -60
                    spacing: 24

                    // Cover art thumbnail
                    Rectangle {
                        Layout.preferredWidth: 140
                        Layout.preferredHeight: 190
                        radius: 16
                        clip: true
                        color: ThemeManager.getColor("surface")
                        visible: igdbCoverUrl !== "" || headerImage !== ""

                        Image {
                            anchors.fill: parent
                            source: igdbCoverUrl !== "" ? igdbCoverUrl : headerImage
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true; cache: true
                            opacity: status === Image.Ready ? 1.0 : 0.0
                            Behavior on opacity { NumberAnimation { duration: 300 } }
                        }

                        Rectangle {
                            anchors.fill: parent; radius: 16; color: "transparent"
                            border.color: Qt.rgba(1, 1, 1, 0.1); border.width: 1
                        }
                    }

                    // Title + metadata
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignBottom
                        spacing: 8

                        Text {
                            text: gameTitle
                            font.pixelSize: 44
                            font.family: ThemeManager.getFont("heading")
                            font.bold: true
                            color: ThemeManager.getColor("textPrimary")
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }

                        // Developer / Publisher
                        Text {
                            visible: igdbDeveloper !== "" || igdbPublisher !== ""
                            text: {
                                var parts = []
                                if (igdbDeveloper !== "") parts.push(igdbDeveloper)
                                if (igdbPublisher !== "" && igdbPublisher !== igdbDeveloper) parts.push(igdbPublisher)
                                return parts.join("  \u2022  ")
                            }
                            font.pixelSize: 22
                            font.family: ThemeManager.getFont("body")
                            color: ThemeManager.getColor("textSecondary")
                        }

                        // Genre + Release
                        RowLayout {
                            spacing: 14

                            Text {
                                visible: igdbGenres !== ""
                                text: igdbGenres
                                font.pixelSize: 20; font.family: ThemeManager.getFont("ui")
                                color: ThemeManager.getColor("textSecondary"); opacity: 0.8
                            }
                            Text {
                                visible: igdbGenres !== "" && igdbReleaseDate !== ""
                                text: "\u2022"; font.pixelSize: 20; color: ThemeManager.getColor("textSecondary"); opacity: 0.5
                            }
                            Text {
                                visible: igdbReleaseDate !== ""
                                text: igdbReleaseDate
                                font.pixelSize: 20; font.family: ThemeManager.getFont("ui")
                                color: ThemeManager.getColor("textSecondary"); opacity: 0.8
                            }
                        }

                        // Rating + Price row
                        RowLayout {
                            spacing: 16

                            // IGDB Rating badge
                            Row {
                                visible: igdbRating > 0
                                spacing: 6
                                Text { text: "\u2605"; font.pixelSize: 24; color: "#fbbf24"; anchors.verticalCenter: parent.verticalCenter }
                                Text {
                                    text: Math.round(igdbRating) + "/100"
                                    font.pixelSize: 22; font.family: ThemeManager.getFont("ui"); font.bold: true
                                    color: ThemeManager.getColor("textPrimary"); anchors.verticalCenter: parent.verticalCenter
                                }
                            }

                            // Discount badge
                            Rectangle {
                                visible: { var s = parseFloat(savings); return !isNaN(s) && s > 0 }
                                width: heroDiscText.width + 20; height: 36; radius: 8
                                color: "#34c759"
                                Text {
                                    id: heroDiscText; anchors.centerIn: parent
                                    text: "-" + Math.round(parseFloat(savings)) + "%"
                                    font.pixelSize: 22; font.bold: true; color: "#0a0a0a"
                                }
                            }

                            // Price
                            Text {
                                visible: { var s = parseFloat(savings); return !isNaN(s) && s > 0 }
                                text: "$" + normalPrice
                                font.pixelSize: 24; font.family: ThemeManager.getFont("ui")
                                color: ThemeManager.getColor("textSecondary"); font.strikeout: true
                            }
                            Text {
                                text: { if (salePrice === "0.00") return "Free"; if (salePrice !== "") return "$" + salePrice; return "" }
                                visible: salePrice !== ""
                                font.pixelSize: 28; font.family: ThemeManager.getFont("ui"); font.bold: true
                                color: "#34c759"
                            }
                        }
                    }
                }

                // ─── Content body ───
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: 36
                    Layout.rightMargin: 36
                    Layout.topMargin: 20
                    spacing: 24

                    // ─── Game Information Panel ───
                    Rectangle {
                        visible: igdbGameModes !== "" || igdbThemes !== "" || igdbPlatforms !== "" || igdbPerspectives !== ""
                        Layout.fillWidth: true
                        Layout.preferredHeight: infoGrid.height + 36
                        radius: 14
                        color: ThemeManager.getColor("surface")

                        GridLayout {
                            id: infoGrid
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: 18
                            columns: 2
                            columnSpacing: 24
                            rowSpacing: 14

                            Text {
                                text: "Information"
                                font.pixelSize: 30
                                font.family: ThemeManager.getFont("heading")
                                font.bold: true
                                color: ThemeManager.getColor("textPrimary")
                                Layout.columnSpan: 2
                                Layout.bottomMargin: 4
                            }

                            // Developer
                            Text { visible: igdbDeveloper !== ""; text: "Developer"; font.pixelSize: 22; font.family: ThemeManager.getFont("ui"); color: ThemeManager.getColor("textSecondary") }
                            Text { visible: igdbDeveloper !== ""; text: igdbDeveloper; font.pixelSize: 22; font.family: ThemeManager.getFont("body"); color: ThemeManager.getColor("textPrimary") }

                            // Publisher
                            Text { visible: igdbPublisher !== "" && igdbPublisher !== igdbDeveloper; text: "Publisher"; font.pixelSize: 22; font.family: ThemeManager.getFont("ui"); color: ThemeManager.getColor("textSecondary") }
                            Text { visible: igdbPublisher !== "" && igdbPublisher !== igdbDeveloper; text: igdbPublisher; font.pixelSize: 22; font.family: ThemeManager.getFont("body"); color: ThemeManager.getColor("textPrimary") }

                            // Release Date
                            Text { visible: igdbReleaseDate !== ""; text: "Released"; font.pixelSize: 22; font.family: ThemeManager.getFont("ui"); color: ThemeManager.getColor("textSecondary") }
                            Text { visible: igdbReleaseDate !== ""; text: igdbReleaseDate; font.pixelSize: 22; font.family: ThemeManager.getFont("body"); color: ThemeManager.getColor("textPrimary") }

                            // Platforms
                            Text { visible: igdbPlatforms !== ""; text: "Platforms"; font.pixelSize: 22; font.family: ThemeManager.getFont("ui"); color: ThemeManager.getColor("textSecondary") }
                            Text { visible: igdbPlatforms !== ""; text: igdbPlatforms; font.pixelSize: 22; font.family: ThemeManager.getFont("body"); color: ThemeManager.getColor("textPrimary"); Layout.fillWidth: true; wrapMode: Text.WordWrap }

                            // Game Modes
                            Text { visible: igdbGameModes !== ""; text: "Game Modes"; font.pixelSize: 22; font.family: ThemeManager.getFont("ui"); color: ThemeManager.getColor("textSecondary") }
                            Text { visible: igdbGameModes !== ""; text: igdbGameModes; font.pixelSize: 22; font.family: ThemeManager.getFont("body"); color: ThemeManager.getColor("textPrimary") }

                            // Player Perspectives
                            Text { visible: igdbPerspectives !== ""; text: "Perspective"; font.pixelSize: 22; font.family: ThemeManager.getFont("ui"); color: ThemeManager.getColor("textSecondary") }
                            Text { visible: igdbPerspectives !== ""; text: igdbPerspectives; font.pixelSize: 22; font.family: ThemeManager.getFont("body"); color: ThemeManager.getColor("textPrimary") }

                            // Themes
                            Text { visible: igdbThemes !== ""; text: "Themes"; font.pixelSize: 22; font.family: ThemeManager.getFont("ui"); color: ThemeManager.getColor("textSecondary") }
                            Text { visible: igdbThemes !== ""; text: igdbThemes; font.pixelSize: 22; font.family: ThemeManager.getFont("body"); color: ThemeManager.getColor("textPrimary"); Layout.fillWidth: true; wrapMode: Text.WordWrap }

                            // Genres
                            Text { visible: igdbGenres !== ""; text: "Genres"; font.pixelSize: 22; font.family: ThemeManager.getFont("ui"); color: ThemeManager.getColor("textSecondary") }
                            Text { visible: igdbGenres !== ""; text: igdbGenres; font.pixelSize: 22; font.family: ThemeManager.getFont("body"); color: ThemeManager.getColor("textPrimary"); Layout.fillWidth: true; wrapMode: Text.WordWrap }
                        }
                    }

                    // ─── Info badges row ───
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 14

                        // Metacritic badge
                        Rectangle {
                            visible: metacriticScore !== "" && metacriticScore !== "0"
                            Layout.preferredWidth: metaRow.width + 28
                            Layout.preferredHeight: 56
                            radius: 12
                            color: ThemeManager.getColor("surface")

                            RowLayout {
                                id: metaRow
                                anchors.centerIn: parent
                                spacing: 10

                                Rectangle {
                                    Layout.preferredWidth: 40
                                    Layout.preferredHeight: 40
                                    radius: 8
                                    color: {
                                        var score = parseInt(metacriticScore)
                                        if (score >= 75) return "#4ade80"
                                        if (score >= 50) return "#fbbf24"
                                        return "#ff6b6b"
                                    }

                                    Text {
                                        anchors.centerIn: parent
                                        text: metacriticScore
                                        font.pixelSize: 22
                                        font.bold: true
                                        color: "#0a0a0a"
                                    }
                                }

                                Text {
                                    text: "Metacritic"
                                    font.pixelSize: 24
                                    font.family: ThemeManager.getFont("ui")
                                    color: ThemeManager.getColor("textSecondary")
                                }
                            }
                        }

                        // Steam rating badge
                        Rectangle {
                            visible: steamRatingText !== "" && steamRatingText !== "null"
                            Layout.preferredWidth: ratingRow.width + 28
                            Layout.preferredHeight: 56
                            radius: 12
                            color: ThemeManager.getColor("surface")

                            RowLayout {
                                id: ratingRow
                                anchors.centerIn: parent
                                spacing: 10

                                Text {
                                    text: (steamRatingPercent !== "" && steamRatingPercent !== "0")
                                          ? steamRatingPercent + "%" : ""
                                    font.pixelSize: 28
                                    font.bold: true
                                    color: {
                                        var pct = parseInt(steamRatingPercent)
                                        if (pct >= 70) return "#4ade80"
                                        if (pct >= 40) return "#fbbf24"
                                        return "#ff6b6b"
                                    }
                                    visible: text !== ""
                                }

                                Text {
                                    text: steamRatingText
                                    font.pixelSize: 24
                                    font.family: ThemeManager.getFont("ui")
                                    color: ThemeManager.getColor("textSecondary")
                                }
                            }
                        }

                        // ProtonDB compatibility badge
                        Rectangle {
                            visible: protonTier !== "" || loadingProton
                            Layout.preferredWidth: protonRow.width + 28
                            Layout.preferredHeight: 56
                            radius: 12
                            color: ThemeManager.getColor("surface")

                            RowLayout {
                                id: protonRow
                                anchors.centerIn: parent
                                spacing: 10

                                Rectangle {
                                    Layout.preferredWidth: 16
                                    Layout.preferredHeight: 16
                                    radius: 8
                                    color: {
                                        switch (protonTier.toLowerCase()) {
                                            case "platinum": return "#b4c7dc"
                                            case "gold":     return "#cfb53b"
                                            case "silver":   return "#a6a6a6"
                                            case "bronze":   return "#cd7f32"
                                            case "borked":   return "#ff6b6b"
                                            default:         return ThemeManager.getColor("textSecondary")
                                        }
                                    }
                                    visible: protonTier !== ""
                                }

                                Text {
                                    text: {
                                        if (loadingProton) return "Checking..."
                                        if (protonTier === "") return ""
                                        var t = protonTier.charAt(0).toUpperCase() + protonTier.slice(1)
                                        return "Linux: " + t
                                    }
                                    font.pixelSize: 24
                                    font.family: ThemeManager.getFont("ui")
                                    font.bold: true
                                    color: {
                                        switch (protonTier.toLowerCase()) {
                                            case "platinum": return "#b4c7dc"
                                            case "gold":     return "#cfb53b"
                                            case "silver":   return "#a6a6a6"
                                            case "bronze":   return "#cd7f32"
                                            case "borked":   return "#ff6b6b"
                                            default:         return ThemeManager.getColor("textSecondary")
                                        }
                                    }
                                }

                                Text {
                                    visible: protonTotalReports > 0
                                    text: "(" + protonTotalReports + " reports)"
                                    font.pixelSize: 22
                                    font.family: ThemeManager.getFont("ui")
                                    color: ThemeManager.getColor("textSecondary")
                                    opacity: 0.7
                                }
                            }
                        }

                        // Cheapest ever badge
                        Rectangle {
                            visible: cheapestEverPrice !== "" && cheapestEverPrice !== "0.00"
                            Layout.preferredWidth: cheapestRow.width + 28
                            Layout.preferredHeight: 56
                            radius: 12
                            color: ThemeManager.getColor("surface")

                            RowLayout {
                                id: cheapestRow
                                anchors.centerIn: parent
                                spacing: 10

                                Text {
                                    text: "Cheapest ever:"
                                    font.pixelSize: 24
                                    font.family: ThemeManager.getFont("ui")
                                    color: ThemeManager.getColor("textSecondary")
                                }
                                Text {
                                    text: "$" + cheapestEverPrice
                                    font.pixelSize: 28
                                    font.family: ThemeManager.getFont("ui")
                                    font.bold: true
                                    color: ThemeManager.getColor("accent")
                                }
                            }
                        }

                        Item { Layout.fillWidth: true }
                    }

                    // ─── Two-column layout: Left (description/screenshots) + Right (store prices) ───
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 24

                        // Left column
                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.preferredWidth: parent.width * 0.55
                            spacing: 20

                            // ─── IGDB Description ───
                            Rectangle {
                                visible: igdbSummary !== "" || loadingIGDB || igdbErrorMsg !== ""
                                Layout.fillWidth: true
                                Layout.preferredHeight: descCol.height + 36
                                radius: 14
                                color: ThemeManager.getColor("surface")

                                ColumnLayout {
                                    id: descCol
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    anchors.margins: 18
                                    spacing: 12

                                    Text {
                                        text: "About"
                                        font.pixelSize: 36
                                        font.family: ThemeManager.getFont("heading")
                                        font.bold: true
                                        color: ThemeManager.getColor("textPrimary")
                                    }

                                    Text {
                                        visible: loadingIGDB && igdbSummary === ""
                                        text: "Loading description..."
                                        font.pixelSize: 24
                                        font.family: ThemeManager.getFont("body")
                                        color: ThemeManager.getColor("textSecondary")
                                        font.italic: true
                                    }

                                    // IGDB error with retry
                                    RowLayout {
                                        visible: !loadingIGDB && igdbErrorMsg !== "" && igdbSummary === ""
                                        Layout.fillWidth: true
                                        spacing: 14

                                        Text {
                                            text: "Could not load description"
                                            font.pixelSize: 24
                                            font.family: ThemeManager.getFont("body")
                                            color: ThemeManager.getColor("textSecondary")
                                            font.italic: true
                                        }

                                        Rectangle {
                                            Layout.preferredWidth: retryIgdbLabel.width + 28
                                            Layout.preferredHeight: 44
                                            radius: 10
                                            color: retryIgdbArea.containsMouse
                                                   ? ThemeManager.getColor("primary")
                                                   : ThemeManager.getColor("hover")

                                            Text {
                                                id: retryIgdbLabel
                                                anchors.centerIn: parent
                                                text: "Retry"
                                                font.pixelSize: 24
                                                font.family: ThemeManager.getFont("ui")
                                                font.bold: true
                                                color: retryIgdbArea.containsMouse
                                                       ? "#ffffff"
                                                       : ThemeManager.getColor("textPrimary")
                                            }

                                            MouseArea {
                                                id: retryIgdbArea
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    detailPopup.igdbErrorMsg = ""
                                                    detailPopup.loadingIGDB = true
                                                    StoreApi.fetchIGDBGameInfo(detailPopup.gameTitle)
                                                }
                                            }
                                        }
                                    }

                                    Text {
                                        visible: igdbSummary !== ""
                                        Layout.fillWidth: true
                                        text: igdbSummary
                                        font.pixelSize: 26
                                        font.family: ThemeManager.getFont("body")
                                        color: ThemeManager.getColor("textSecondary")
                                        wrapMode: Text.WordWrap
                                        lineHeight: 1.5
                                    }
                                }
                            }

                            // ─── ProtonDB Details ───
                            Rectangle {
                                visible: protonTier !== ""
                                Layout.fillWidth: true
                                Layout.preferredHeight: protonCol.height + 36
                                radius: 14
                                color: ThemeManager.getColor("surface")

                                ColumnLayout {
                                    id: protonCol
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    anchors.margins: 18
                                    spacing: 12

                                    Text {
                                        text: "Linux Compatibility (ProtonDB)"
                                        font.pixelSize: 36
                                        font.family: ThemeManager.getFont("heading")
                                        font.bold: true
                                        color: ThemeManager.getColor("textPrimary")
                                    }

                                    RowLayout {
                                        spacing: 20

                                        Rectangle {
                                            Layout.preferredWidth: 90
                                            Layout.preferredHeight: 90
                                            radius: 14
                                            color: {
                                                switch (protonTier.toLowerCase()) {
                                                    case "platinum": return Qt.rgba(0.71, 0.78, 0.86, 0.2)
                                                    case "gold":     return Qt.rgba(0.81, 0.71, 0.23, 0.2)
                                                    case "silver":   return Qt.rgba(0.65, 0.65, 0.65, 0.2)
                                                    case "bronze":   return Qt.rgba(0.80, 0.50, 0.20, 0.2)
                                                    case "borked":   return Qt.rgba(1.0, 0.0, 0.0, 0.2)
                                                    default:         return ThemeManager.getColor("hover")
                                                }
                                            }
                                            border.color: {
                                                switch (protonTier.toLowerCase()) {
                                                    case "platinum": return "#b4c7dc"
                                                    case "gold":     return "#cfb53b"
                                                    case "silver":   return "#a6a6a6"
                                                    case "bronze":   return "#cd7f32"
                                                    case "borked":   return "#ff6b6b"
                                                    default:         return "transparent"
                                                }
                                            }
                                            border.width: 2

                                            Text {
                                                anchors.centerIn: parent
                                                text: protonTier.charAt(0).toUpperCase() + protonTier.slice(1)
                                                font.pixelSize: 24
                                                font.family: ThemeManager.getFont("heading")
                                                font.bold: true
                                                color: {
                                                    switch (protonTier.toLowerCase()) {
                                                        case "platinum": return "#b4c7dc"
                                                        case "gold":     return "#cfb53b"
                                                        case "silver":   return "#a6a6a6"
                                                        case "bronze":   return "#cd7f32"
                                                        case "borked":   return "#ff6b6b"
                                                        default:         return ThemeManager.getColor("textPrimary")
                                                    }
                                                }
                                            }
                                        }

                                        ColumnLayout {
                                            spacing: 6
                                            Layout.fillWidth: true

                                            Text {
                                                text: {
                                                    switch (protonTier.toLowerCase()) {
                                                        case "platinum": return "Runs perfectly on Linux"
                                                        case "gold":     return "Runs well on Linux with minor tweaks"
                                                        case "silver":   return "Runs with some issues on Linux"
                                                        case "bronze":   return "Runs poorly, major issues on Linux"
                                                        case "borked":   return "Does not work on Linux"
                                                        default:         return "Unknown compatibility"
                                                    }
                                                }
                                                font.pixelSize: 26
                                                font.family: ThemeManager.getFont("body")
                                                color: ThemeManager.getColor("textPrimary")
                                                Layout.fillWidth: true
                                                wrapMode: Text.WordWrap
                                            }

                                            Text {
                                                visible: protonConfidence !== ""
                                                text: "Confidence: " + protonConfidence.charAt(0).toUpperCase() + protonConfidence.slice(1)
                                                font.pixelSize: 24
                                                font.family: ThemeManager.getFont("ui")
                                                color: ThemeManager.getColor("textSecondary")
                                            }

                                            Text {
                                                visible: protonTotalReports > 0
                                                text: "Based on " + protonTotalReports + " user reports"
                                                font.pixelSize: 24
                                                font.family: ThemeManager.getFont("ui")
                                                color: ThemeManager.getColor("textSecondary")
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // ─── Right column: Store Prices ───
                        ColumnLayout {
                            Layout.preferredWidth: parent.width * 0.40
                            Layout.alignment: Qt.AlignTop
                            spacing: 14

                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: storePricesContent.height + 36
                                radius: 14
                                color: ThemeManager.getColor("surface")

                                ColumnLayout {
                                    id: storePricesContent
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    anchors.margins: 18
                                    spacing: 12

                                    RowLayout {
                                        spacing: 12

                                        Text {
                                            text: "Store Prices"
                                            font.pixelSize: 36
                                            font.family: ThemeManager.getFont("heading")
                                            font.bold: true
                                            color: ThemeManager.getColor("textPrimary")
                                        }

                                        Text {
                                            visible: loadingDeals || loadingStorePrices
                                            text: "Loading..."
                                            font.pixelSize: 24
                                            font.family: ThemeManager.getFont("body")
                                            color: ThemeManager.getColor("textSecondary")
                                            font.italic: true
                                        }

                                        Item { Layout.fillWidth: true }
                                    }

                                    // Combined deals list (CheapShark + scraped store prices)
                                    Repeater {
                                        model: allDeals

                                        Rectangle {
                                            property bool isKbFocused: detailPopup.visible && popupNavZone === "stores" && storeFocusIndex === index
                                            Layout.fillWidth: true
                                            Layout.preferredHeight: 64
                                            radius: 12
                                            color: (dealItemArea.containsMouse || isKbFocused)
                                                   ? ThemeManager.getColor("hover")
                                                   : ThemeManager.getColor("cardBackground")
                                            border.color: isKbFocused ? ThemeManager.getColor("focus") : "transparent"
                                            border.width: isKbFocused ? 2 : 0

                                            Behavior on color { ColorAnimation { duration: 150 } }

                                            MouseArea {
                                                id: dealItemArea
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    if (modelData.dealLink)
                                                        detailPopup.openDealUrl(modelData.dealLink, modelData.storeName || "")
                                                }
                                            }

                                            RowLayout {
                                                anchors.fill: parent
                                                anchors.leftMargin: 16
                                                anchors.rightMargin: 16
                                                spacing: 12

                                                // Store icon
                                                Image {
                                                    Layout.preferredWidth: 24
                                                    Layout.preferredHeight: 24
                                                    source: modelData.storeIcon || ""
                                                    asynchronous: true
                                                    cache: true
                                                    fillMode: Image.PreserveAspectFit
                                                    visible: source !== ""
                                                }

                                                // Store name
                                                Text {
                                                    text: modelData.storeName || ("Store #" + modelData.storeID)
                                                    font.pixelSize: 24
                                                    font.family: ThemeManager.getFont("body")
                                                    font.bold: true
                                                    color: ThemeManager.getColor("textPrimary")
                                                    Layout.fillWidth: true
                                                }

                                                // Source badge
                                                Rectangle {
                                                    visible: (modelData.source || "") !== ""
                                                    Layout.preferredWidth: srcLabel.width + 14
                                                    Layout.preferredHeight: 28
                                                    radius: 6
                                                    color: {
                                                        var src = modelData.source || ""
                                                        if (src === "Steam") return Qt.rgba(0.10, 0.36, 0.69, 0.15)
                                                        if (src === "GOG") return Qt.rgba(0.60, 0.20, 0.80, 0.15)
                                                        if (src === "Epic Games") return Qt.rgba(0.0, 0.0, 0.0, 0.25)
                                                        if (src === "GMG") return Qt.rgba(0.18, 0.65, 0.25, 0.15)
                                                        return Qt.rgba(1, 1, 1, 0.08)
                                                    }

                                                    Text {
                                                        id: srcLabel
                                                        anchors.centerIn: parent
                                                        text: modelData.source || ""
                                                        font.pixelSize: 18
                                                        font.family: ThemeManager.getFont("ui")
                                                        color: ThemeManager.getColor("textSecondary")
                                                        opacity: 0.7
                                                    }
                                                }

                                                // Savings badge
                                                Rectangle {
                                                    visible: {
                                                        var s = parseFloat(modelData.savings)
                                                        return !isNaN(s) && s > 0
                                                    }
                                                    Layout.preferredWidth: dealSavingsText.width + 18
                                                    Layout.preferredHeight: 36
                                                    radius: 8
                                                    color: "#4ade80"

                                                    Text {
                                                        id: dealSavingsText
                                                        anchors.centerIn: parent
                                                        text: "-" + Math.round(parseFloat(modelData.savings)) + "%"
                                                        font.pixelSize: 22
                                                        font.bold: true
                                                        color: "#0a0a0a"
                                                    }
                                                }

                                                // Original price
                                                Text {
                                                    visible: {
                                                        var s = parseFloat(modelData.savings)
                                                        return !isNaN(s) && s > 0
                                                    }
                                                    text: "$" + (modelData.retailPrice || "")
                                                    font.pixelSize: 22
                                                    font.family: ThemeManager.getFont("ui")
                                                    color: ThemeManager.getColor("textSecondary")
                                                    font.strikeout: true
                                                }

                                                // Current price or "Buy" for links without prices
                                                Text {
                                                    text: {
                                                        if (modelData.price === "0.00") return "FREE"
                                                        if (modelData.price && modelData.price !== "")
                                                            return "$" + modelData.price
                                                        return "Buy"
                                                    }
                                                    font.pixelSize: 28
                                                    font.family: ThemeManager.getFont("ui")
                                                    font.bold: true
                                                    color: (modelData.price === "0.00" || parseFloat(modelData.savings) > 0)
                                                           ? "#4ade80"
                                                           : ThemeManager.getColor("textPrimary")
                                                }
                                            }
                                        }
                                    }

                                    // Error loading deals
                                    ColumnLayout {
                                        visible: !loadingDeals && dealsErrorMsg !== ""
                                        Layout.fillWidth: true
                                        spacing: 10

                                        Text {
                                            text: "Failed to load store prices"
                                            font.pixelSize: 24
                                            font.family: ThemeManager.getFont("body")
                                            color: "#ff6b6b"
                                        }

                                        Rectangle {
                                            Layout.preferredWidth: retryDealsLabel.width + 32
                                            Layout.preferredHeight: 44
                                            radius: 10
                                            color: retryDealsArea.containsMouse
                                                   ? ThemeManager.getColor("primary")
                                                   : ThemeManager.getColor("hover")

                                            Behavior on color { ColorAnimation { duration: 150 } }

                                            Text {
                                                id: retryDealsLabel
                                                anchors.centerIn: parent
                                                text: "Retry"
                                                font.pixelSize: 24
                                                font.family: ThemeManager.getFont("ui")
                                                font.bold: true
                                                color: retryDealsArea.containsMouse
                                                       ? "#ffffff"
                                                       : ThemeManager.getColor("textPrimary")
                                            }

                                            MouseArea {
                                                id: retryDealsArea
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    detailPopup.dealsErrorMsg = ""
                                                    if (detailPopup.cheapSharkGameID !== "") {
                                                        detailPopup.loadingDeals = true
                                                        StoreApi.fetchGameDeals(detailPopup.cheapSharkGameID)
                                                    } else if (detailPopup.steamAppID !== "" ||
                                                               (detailPopup.purchaseUrls && detailPopup.purchaseUrls.length > 0) ||
                                                               detailPopup.gameTitle !== "") {
                                                        detailPopup.loadingStorePrices = true
                                                        StoreApi.fetchStorePrices(detailPopup.steamAppID, detailPopup.purchaseUrls, detailPopup.gameTitle)
                                                    }
                                                }
                                            }
                                        }
                                    }

                                    // No deals message
                                    Text {
                                        visible: !loadingDeals && !loadingStorePrices && dealsErrorMsg === "" && allDeals.length === 0
                                        text: "No deals found for this game"
                                        font.pixelSize: 24
                                        font.family: ThemeManager.getFont("body")
                                        color: ThemeManager.getColor("textSecondary")
                                        font.italic: true
                                    }
                                }
                            }
                        }
                    }

                    // Bottom spacer
                    Item { Layout.preferredHeight: 32 }
                }
            }
        }
    }
}
