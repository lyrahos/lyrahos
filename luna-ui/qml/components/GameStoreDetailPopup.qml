import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Rectangle {
    id: detailPopup
    anchors.fill: parent
    color: Qt.rgba(0, 0, 0, 0.8)
    visible: false
    z: 500

    property string gameTitle: ""
    property string gameID: ""
    property string steamAppID: ""
    property string headerImage: ""
    property string salePrice: ""
    property string normalPrice: ""
    property string savings: ""
    property string metacriticScore: ""
    property string steamRatingText: ""
    property string steamRatingPercent: ""

    // Data loaded from APIs
    property var gameDeals: []
    property string igdbSummary: ""
    property string igdbGenres: ""
    property string igdbPlatforms: ""
    property string igdbReleaseDate: ""
    property double igdbRating: 0
    property var igdbScreenshots: []
    property string protonTier: ""
    property string protonConfidence: ""
    property int protonTotalReports: 0
    property string cheapestEverPrice: ""

    // Loading states
    property bool loadingDeals: false
    property bool loadingIGDB: false
    property bool loadingProton: false

    function open(deal) {
        gameTitle = deal.title || ""
        gameID = deal.gameID || ""
        steamAppID = deal.steamAppID || ""
        headerImage = deal.headerImage || deal.heroImage || ""
        salePrice = deal.salePrice || deal.cheapest || ""
        normalPrice = deal.normalPrice || ""
        savings = deal.savings || ""
        metacriticScore = deal.metacriticScore || ""
        steamRatingText = deal.steamRatingText || ""
        steamRatingPercent = deal.steamRatingPercent || ""

        // Reset loaded data
        gameDeals = []
        igdbSummary = ""
        igdbGenres = ""
        igdbPlatforms = ""
        igdbReleaseDate = ""
        igdbRating = 0
        igdbScreenshots = []
        protonTier = ""
        protonConfidence = ""
        protonTotalReports = 0
        cheapestEverPrice = ""
        loadingDeals = true
        loadingIGDB = true
        loadingProton = true

        visible = true

        // Fetch details from all APIs
        if (gameID !== "")
            StoreApi.fetchGameDeals(gameID)

        if (gameTitle !== "")
            StoreApi.fetchIGDBGameInfo(gameTitle)

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

    // ─── API Response Handlers ───
    Connections {
        target: StoreApi

        function onGameDealsReady(details) {
            if (!detailPopup.visible) return
            detailPopup.gameDeals = details.deals || []
            detailPopup.cheapestEverPrice = details.cheapestEverPrice || ""
            if (details.headerImage)
                detailPopup.headerImage = details.headerImage
            detailPopup.loadingDeals = false
        }

        function onGameDealsError(error) {
            if (!detailPopup.visible) return
            detailPopup.loadingDeals = false
        }

        function onIgdbGameInfoReady(info) {
            if (!detailPopup.visible) return
            detailPopup.igdbSummary = info.summary || ""
            detailPopup.igdbGenres = info.genres || ""
            detailPopup.igdbPlatforms = info.platforms || ""
            detailPopup.igdbReleaseDate = info.releaseDate || ""
            detailPopup.igdbRating = info.totalRating || 0
            detailPopup.igdbScreenshots = info.screenshots || []
            detailPopup.loadingIGDB = false
        }

        function onIgdbGameInfoError(error) {
            if (!detailPopup.visible) return
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

    // ─── Popup Card ───
    Rectangle {
        id: popupCard
        anchors.centerIn: parent
        width: Math.min(parent.width - 80, 900)
        height: Math.min(parent.height - 60, 680)
        radius: 16
        color: ThemeManager.getColor("background")
        border.color: Qt.rgba(ThemeManager.getColor("primary").r,
                              ThemeManager.getColor("primary").g,
                              ThemeManager.getColor("primary").b, 0.3)
        border.width: 1
        clip: true

        // Prevent clicks from closing
        MouseArea { anchors.fill: parent; onClicked: {} }

        // ─── Header image ───
        Rectangle {
            id: headerSection
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: 200
            clip: true
            color: ThemeManager.getColor("surface")

            Image {
                id: headerImg
                anchors.fill: parent
                source: headerImage
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: true
                opacity: status === Image.Ready ? 1.0 : 0.0
                Behavior on opacity { NumberAnimation { duration: 300 } }
            }

            // Gradient fade at bottom
            Rectangle {
                anchors.fill: parent
                gradient: Gradient {
                    GradientStop { position: 0.0; color: "transparent" }
                    GradientStop { position: 0.6; color: "transparent" }
                    GradientStop { position: 1.0; color: ThemeManager.getColor("background") }
                }
            }

            // Close button
            Rectangle {
                anchors.top: parent.top
                anchors.right: parent.right
                anchors.margins: 12
                width: 36
                height: 36
                radius: 18
                color: Qt.rgba(0, 0, 0, 0.6)

                Text {
                    anchors.centerIn: parent
                    text: "\u2715"
                    font.pixelSize: 16
                    font.bold: true
                    color: "#ffffff"
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: detailPopup.close()
                }
            }

            // Title overlay at bottom of header
            ColumnLayout {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.leftMargin: 24
                anchors.rightMargin: 24
                anchors.bottomMargin: 8
                spacing: 6

                Text {
                    text: gameTitle
                    font.pixelSize: ThemeManager.getFontSize("xlarge")
                    font.family: ThemeManager.getFont("heading")
                    font.bold: true
                    color: "#ffffff"
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }

                RowLayout {
                    spacing: 12

                    // Genre tags
                    Text {
                        visible: igdbGenres !== ""
                        text: igdbGenres
                        font.pixelSize: 12
                        font.family: ThemeManager.getFont("ui")
                        color: ThemeManager.getColor("textSecondary")
                    }

                    // Release date
                    Text {
                        visible: igdbReleaseDate !== ""
                        text: igdbReleaseDate
                        font.pixelSize: 12
                        font.family: ThemeManager.getFont("ui")
                        color: ThemeManager.getColor("textSecondary")
                    }
                }
            }
        }

        // ─── Scrollable content below header ───
        Flickable {
            id: contentFlick
            anchors.top: headerSection.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.topMargin: 8
            contentHeight: contentColumn.height + 24
            clip: true
            flickableDirection: Flickable.VerticalFlick

            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

            ColumnLayout {
                id: contentColumn
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: 24
                anchors.rightMargin: 24
                spacing: 16

                // ─── Info badges row ───
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    // Price badge
                    Rectangle {
                        Layout.preferredHeight: 40
                        Layout.preferredWidth: priceRow.width + 20
                        radius: 8
                        color: ThemeManager.getColor("surface")

                        RowLayout {
                            id: priceRow
                            anchors.centerIn: parent
                            spacing: 8

                            // Discount badge
                            Rectangle {
                                visible: {
                                    var s = parseFloat(savings)
                                    return !isNaN(s) && s > 0
                                }
                                Layout.preferredWidth: discBadgeText.width + 12
                                Layout.preferredHeight: 24
                                radius: 4
                                color: "#4ade80"

                                Text {
                                    id: discBadgeText
                                    anchors.centerIn: parent
                                    text: "-" + Math.round(parseFloat(savings)) + "%"
                                    font.pixelSize: 12
                                    font.bold: true
                                    color: "#0a0a0a"
                                }
                            }

                            // Original price
                            Text {
                                visible: {
                                    var s = parseFloat(savings)
                                    return !isNaN(s) && s > 0
                                }
                                text: "$" + normalPrice
                                font.pixelSize: 14
                                font.family: ThemeManager.getFont("ui")
                                color: ThemeManager.getColor("textSecondary")
                                font.strikeout: true
                            }

                            // Sale price
                            Text {
                                text: {
                                    if (salePrice === "0.00") return "FREE"
                                    return "$" + salePrice
                                }
                                font.pixelSize: 18
                                font.family: ThemeManager.getFont("ui")
                                font.bold: true
                                color: (salePrice === "0.00" || parseFloat(savings) > 0)
                                       ? "#4ade80"
                                       : ThemeManager.getColor("textPrimary")
                            }
                        }
                    }

                    // Metacritic badge
                    Rectangle {
                        visible: metacriticScore !== "" && metacriticScore !== "0"
                        Layout.preferredWidth: metaRow.width + 16
                        Layout.preferredHeight: 40
                        radius: 8
                        color: ThemeManager.getColor("surface")

                        RowLayout {
                            id: metaRow
                            anchors.centerIn: parent
                            spacing: 6

                            Rectangle {
                                Layout.preferredWidth: 28
                                Layout.preferredHeight: 28
                                radius: 4
                                color: {
                                    var score = parseInt(metacriticScore)
                                    if (score >= 75) return "#4ade80"
                                    if (score >= 50) return "#fbbf24"
                                    return "#ff6b6b"
                                }

                                Text {
                                    anchors.centerIn: parent
                                    text: metacriticScore
                                    font.pixelSize: 12
                                    font.bold: true
                                    color: "#0a0a0a"
                                }
                            }

                            Text {
                                text: "Metacritic"
                                font.pixelSize: 12
                                font.family: ThemeManager.getFont("ui")
                                color: ThemeManager.getColor("textSecondary")
                            }
                        }
                    }

                    // Steam rating badge
                    Rectangle {
                        visible: steamRatingText !== "" && steamRatingText !== "null"
                        Layout.preferredWidth: ratingRow.width + 16
                        Layout.preferredHeight: 40
                        radius: 8
                        color: ThemeManager.getColor("surface")

                        RowLayout {
                            id: ratingRow
                            anchors.centerIn: parent
                            spacing: 6

                            Text {
                                text: (steamRatingPercent !== "" && steamRatingPercent !== "0")
                                      ? steamRatingPercent + "%" : ""
                                font.pixelSize: 14
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
                                font.pixelSize: 12
                                font.family: ThemeManager.getFont("ui")
                                color: ThemeManager.getColor("textSecondary")
                            }
                        }
                    }

                    // ProtonDB compatibility badge
                    Rectangle {
                        visible: protonTier !== "" || loadingProton
                        Layout.preferredWidth: protonRow.width + 16
                        Layout.preferredHeight: 40
                        radius: 8
                        color: ThemeManager.getColor("surface")

                        RowLayout {
                            id: protonRow
                            anchors.centerIn: parent
                            spacing: 6

                            // Tier color dot
                            Rectangle {
                                Layout.preferredWidth: 12
                                Layout.preferredHeight: 12
                                radius: 6
                                color: {
                                    switch (protonTier.toLowerCase()) {
                                        case "platinum": return "#b4c7dc"
                                        case "gold":     return "#cfb53b"
                                        case "silver":   return "#a6a6a6"
                                        case "bronze":   return "#cd7f32"
                                        case "borked":   return "#ff0000"
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
                                font.pixelSize: 12
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
                                font.pixelSize: 10
                                font.family: ThemeManager.getFont("ui")
                                color: ThemeManager.getColor("textSecondary")
                                opacity: 0.7
                            }
                        }
                    }

                    Item { Layout.fillWidth: true }
                }

                // ─── IGDB Description ───
                Rectangle {
                    visible: igdbSummary !== "" || loadingIGDB
                    Layout.fillWidth: true
                    Layout.preferredHeight: descCol.height + 24
                    radius: 10
                    color: ThemeManager.getColor("surface")

                    ColumnLayout {
                        id: descCol
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 12
                        spacing: 8

                        Text {
                            text: "About"
                            font.pixelSize: ThemeManager.getFontSize("medium")
                            font.family: ThemeManager.getFont("heading")
                            font.bold: true
                            color: ThemeManager.getColor("textPrimary")
                        }

                        Text {
                            visible: loadingIGDB && igdbSummary === ""
                            text: "Loading description..."
                            font.pixelSize: ThemeManager.getFontSize("small")
                            font.family: ThemeManager.getFont("body")
                            color: ThemeManager.getColor("textSecondary")
                            font.italic: true
                        }

                        Text {
                            visible: igdbSummary !== ""
                            Layout.fillWidth: true
                            text: igdbSummary
                            font.pixelSize: ThemeManager.getFontSize("small")
                            font.family: ThemeManager.getFont("body")
                            color: ThemeManager.getColor("textSecondary")
                            wrapMode: Text.WordWrap
                            lineHeight: 1.4
                        }
                    }
                }

                // ─── Screenshots (from IGDB) ───
                ColumnLayout {
                    visible: igdbScreenshots.length > 0
                    Layout.fillWidth: true
                    spacing: 8

                    Text {
                        text: "Screenshots"
                        font.pixelSize: ThemeManager.getFontSize("medium")
                        font.family: ThemeManager.getFont("heading")
                        font.bold: true
                        color: ThemeManager.getColor("textPrimary")
                    }

                    ListView {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 160
                        orientation: ListView.Horizontal
                        spacing: 10
                        clip: true
                        model: igdbScreenshots

                        delegate: Rectangle {
                            width: 280
                            height: 158
                            radius: 8
                            color: ThemeManager.getColor("surface")
                            clip: true

                            Image {
                                anchors.fill: parent
                                source: modelData
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                cache: true
                            }
                        }
                    }
                }

                // ─── Store Prices Table ───
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    RowLayout {
                        spacing: 8

                        Text {
                            text: "Store Prices"
                            font.pixelSize: ThemeManager.getFontSize("medium")
                            font.family: ThemeManager.getFont("heading")
                            font.bold: true
                            color: ThemeManager.getColor("textPrimary")
                        }

                        Text {
                            visible: loadingDeals
                            text: "Loading..."
                            font.pixelSize: 12
                            font.family: ThemeManager.getFont("body")
                            color: ThemeManager.getColor("textSecondary")
                            font.italic: true
                        }

                        Item { Layout.fillWidth: true }

                        // Cheapest ever
                        Text {
                            visible: cheapestEverPrice !== "" && cheapestEverPrice !== "0.00"
                            text: "Cheapest ever: $" + cheapestEverPrice
                            font.pixelSize: 11
                            font.family: ThemeManager.getFont("ui")
                            color: ThemeManager.getColor("accent")
                        }
                    }

                    // Deals list
                    Repeater {
                        model: gameDeals

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 52
                            radius: 8
                            color: dealItemArea.containsMouse
                                   ? ThemeManager.getColor("hover")
                                   : ThemeManager.getColor("surface")

                            Behavior on color { ColorAnimation { duration: 150 } }

                            MouseArea {
                                id: dealItemArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                            }

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 14
                                anchors.rightMargin: 14
                                spacing: 12

                                // Store icon
                                Image {
                                    Layout.preferredWidth: 16
                                    Layout.preferredHeight: 16
                                    source: modelData.storeIcon || ""
                                    asynchronous: true
                                    cache: true
                                    fillMode: Image.PreserveAspectFit
                                    visible: source !== ""
                                }

                                // Store name
                                Text {
                                    text: modelData.storeName || ("Store " + modelData.storeID)
                                    font.pixelSize: ThemeManager.getFontSize("small")
                                    font.family: ThemeManager.getFont("body")
                                    font.bold: true
                                    color: ThemeManager.getColor("textPrimary")
                                    Layout.fillWidth: true
                                }

                                // Savings
                                Rectangle {
                                    visible: {
                                        var s = parseFloat(modelData.savings)
                                        return !isNaN(s) && s > 0
                                    }
                                    Layout.preferredWidth: dealSavingsText.width + 12
                                    Layout.preferredHeight: 22
                                    radius: 4
                                    color: "#4ade80"

                                    Text {
                                        id: dealSavingsText
                                        anchors.centerIn: parent
                                        text: "-" + Math.round(parseFloat(modelData.savings)) + "%"
                                        font.pixelSize: 11
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
                                    font.pixelSize: 13
                                    font.family: ThemeManager.getFont("ui")
                                    color: ThemeManager.getColor("textSecondary")
                                    font.strikeout: true
                                }

                                // Current price
                                Text {
                                    text: {
                                        if (modelData.price === "0.00") return "FREE"
                                        return "$" + (modelData.price || "")
                                    }
                                    font.pixelSize: 15
                                    font.family: ThemeManager.getFont("ui")
                                    font.bold: true
                                    color: (modelData.price === "0.00" || parseFloat(modelData.savings) > 0)
                                           ? "#4ade80"
                                           : ThemeManager.getColor("textPrimary")
                                }
                            }
                        }
                    }

                    // No deals message
                    Text {
                        visible: !loadingDeals && gameDeals.length === 0
                        text: "No deals found for this game"
                        font.pixelSize: ThemeManager.getFontSize("small")
                        font.family: ThemeManager.getFont("body")
                        color: ThemeManager.getColor("textSecondary")
                        font.italic: true
                    }
                }

                // ─── ProtonDB Details ───
                Rectangle {
                    visible: protonTier !== ""
                    Layout.fillWidth: true
                    Layout.preferredHeight: protonCol.height + 24
                    radius: 10
                    color: ThemeManager.getColor("surface")

                    ColumnLayout {
                        id: protonCol
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 12
                        spacing: 8

                        Text {
                            text: "Linux Compatibility (ProtonDB)"
                            font.pixelSize: ThemeManager.getFontSize("medium")
                            font.family: ThemeManager.getFont("heading")
                            font.bold: true
                            color: ThemeManager.getColor("textPrimary")
                        }

                        RowLayout {
                            spacing: 16

                            // Large tier badge
                            Rectangle {
                                Layout.preferredWidth: 80
                                Layout.preferredHeight: 80
                                radius: 12
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
                                        case "borked":   return "#ff0000"
                                        default:         return "transparent"
                                    }
                                }
                                border.width: 2

                                Text {
                                    anchors.centerIn: parent
                                    text: protonTier.charAt(0).toUpperCase() + protonTier.slice(1)
                                    font.pixelSize: 16
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
                                spacing: 4
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
                                    font.pixelSize: ThemeManager.getFontSize("small")
                                    font.family: ThemeManager.getFont("body")
                                    color: ThemeManager.getColor("textPrimary")
                                    Layout.fillWidth: true
                                    wrapMode: Text.WordWrap
                                }

                                Text {
                                    visible: protonConfidence !== ""
                                    text: "Confidence: " + protonConfidence.charAt(0).toUpperCase() + protonConfidence.slice(1)
                                    font.pixelSize: 12
                                    font.family: ThemeManager.getFont("ui")
                                    color: ThemeManager.getColor("textSecondary")
                                }

                                Text {
                                    visible: protonTotalReports > 0
                                    text: "Based on " + protonTotalReports + " user reports"
                                    font.pixelSize: 12
                                    font.family: ThemeManager.getFont("ui")
                                    color: ThemeManager.getColor("textSecondary")
                                }
                            }
                        }
                    }
                }

                // Bottom spacer
                Item { Layout.preferredHeight: 16 }
            }
        }
    }
}
