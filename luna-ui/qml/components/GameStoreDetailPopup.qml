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

    // Error states
    property string dealsErrorMsg: ""
    property string igdbErrorMsg: ""

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
        dealsErrorMsg = ""
        igdbErrorMsg = ""
        loadingDeals = true
        loadingIGDB = true
        loadingProton = true

        // Reset scroll position and screenshot index
        contentFlick.contentY = 0
        fullContent.currentScreenshotIndex = 0

        visible = true

        // Fetch details from all APIs
        if (gameID !== "") {
            StoreApi.fetchGameDeals(gameID)
        } else {
            loadingDeals = false
        }

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
        }

        function onGameDealsError(error) {
            if (!detailPopup.visible) return
            detailPopup.dealsErrorMsg = error
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
            detailPopup.igdbErrorMsg = ""
            detailPopup.loadingIGDB = false
        }

        function onIgdbGameInfoError(error) {
            if (!detailPopup.visible) return
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
        radius: 16
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
            anchors.margins: 16
            width: 40
            height: 40
            radius: 20
            z: 10
            color: closeBtnArea.containsMouse
                   ? Qt.rgba(1, 1, 1, 0.2) : Qt.rgba(0, 0, 0, 0.6)

            Behavior on color { ColorAnimation { duration: 150 } }

            Text {
                anchors.centerIn: parent
                text: "\u2715"
                font.pixelSize: 18
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
            contentHeight: fullContent.height + 32
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

                // ─── Top Section: Hero Image + Screenshot Viewer ───
                RowLayout {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.min(popupCard.height * 0.45, 420)
                    spacing: 0

                    // Left: Hero/Header image
                    Rectangle {
                        Layout.fillHeight: true
                        Layout.preferredWidth: igdbScreenshots.length > 0
                                               ? parent.width * 0.5 : parent.width
                        color: ThemeManager.getColor("surface")
                        clip: true

                        Image {
                            id: headerImg
                            anchors.fill: parent
                            source: headerImage
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            cache: true
                            sourceSize.width: popupCard.width
                            opacity: status === Image.Ready ? 1.0 : 0.0
                            Behavior on opacity { NumberAnimation { duration: 300 } }
                        }
                    }

                    // Right: Screenshot viewer with navigation
                    Rectangle {
                        visible: igdbScreenshots.length > 0
                        Layout.fillHeight: true
                        Layout.fillWidth: true
                        color: "#000000"
                        clip: true

                        Image {
                            id: screenshotViewer
                            anchors.fill: parent
                            source: igdbScreenshots.length > 0
                                    ? igdbScreenshots[fullContent.currentScreenshotIndex] : ""
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            cache: true
                            opacity: status === Image.Ready ? 1.0 : 0.0
                            Behavior on opacity { NumberAnimation { duration: 200 } }
                        }

                        // Previous button
                        Rectangle {
                            visible: igdbScreenshots.length > 1
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.leftMargin: 8
                            width: 36
                            height: 36
                            radius: 18
                            color: prevArea.containsMouse ? Qt.rgba(0, 0, 0, 0.8) : Qt.rgba(0, 0, 0, 0.5)
                            Behavior on color { ColorAnimation { duration: 150 } }

                            Text {
                                anchors.centerIn: parent
                                text: "\u276E"
                                font.pixelSize: 16
                                font.bold: true
                                color: "#ffffff"
                            }

                            MouseArea {
                                id: prevArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (fullContent.currentScreenshotIndex > 0)
                                        fullContent.currentScreenshotIndex--
                                    else
                                        fullContent.currentScreenshotIndex = igdbScreenshots.length - 1
                                }
                            }
                        }

                        // Next button
                        Rectangle {
                            visible: igdbScreenshots.length > 1
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.rightMargin: 8
                            width: 36
                            height: 36
                            radius: 18
                            color: nextArea.containsMouse ? Qt.rgba(0, 0, 0, 0.8) : Qt.rgba(0, 0, 0, 0.5)
                            Behavior on color { ColorAnimation { duration: 150 } }

                            Text {
                                anchors.centerIn: parent
                                text: "\u276F"
                                font.pixelSize: 16
                                font.bold: true
                                color: "#ffffff"
                            }

                            MouseArea {
                                id: nextArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (fullContent.currentScreenshotIndex < igdbScreenshots.length - 1)
                                        fullContent.currentScreenshotIndex++
                                    else
                                        fullContent.currentScreenshotIndex = 0
                                }
                            }
                        }

                        // Dot indicators
                        Row {
                            visible: igdbScreenshots.length > 1
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: 10
                            spacing: 6

                            Repeater {
                                model: igdbScreenshots.length

                                Rectangle {
                                    width: index === fullContent.currentScreenshotIndex ? 18 : 8
                                    height: 8
                                    radius: 4
                                    color: index === fullContent.currentScreenshotIndex
                                           ? "#ffffff" : Qt.rgba(1, 1, 1, 0.4)
                                    Behavior on width { NumberAnimation { duration: 150 } }
                                    Behavior on color { ColorAnimation { duration: 150 } }
                                }
                            }
                        }

                        // Screenshot counter
                        Rectangle {
                            anchors.top: parent.top
                            anchors.right: parent.right
                            anchors.margins: 10
                            width: counterText.width + 16
                            height: 26
                            radius: 13
                            color: Qt.rgba(0, 0, 0, 0.6)

                            Text {
                                id: counterText
                                anchors.centerIn: parent
                                text: (fullContent.currentScreenshotIndex + 1) + " / " + igdbScreenshots.length
                                font.pixelSize: 12
                                font.family: ThemeManager.getFont("ui")
                                color: "#ffffff"
                            }
                        }
                    }
                }

                // ─── Title, Pricing & Info Section ───
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: 32
                    Layout.rightMargin: 32
                    Layout.topMargin: 20
                    spacing: 12

                    Text {
                        text: gameTitle
                        font.pixelSize: 32
                        font.family: ThemeManager.getFont("heading")
                        font.bold: true
                        color: ThemeManager.getColor("textPrimary")
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }

                    RowLayout {
                        spacing: 16

                        // Genre tags
                        Text {
                            visible: igdbGenres !== ""
                            text: igdbGenres
                            font.pixelSize: 14
                            font.family: ThemeManager.getFont("ui")
                            color: ThemeManager.getColor("textSecondary")
                        }

                        // Separator
                        Text {
                            visible: igdbGenres !== "" && igdbReleaseDate !== ""
                            text: "|"
                            font.pixelSize: 14
                            color: ThemeManager.getColor("textSecondary")
                            opacity: 0.5
                        }

                        // Release date
                        Text {
                            visible: igdbReleaseDate !== ""
                            text: igdbReleaseDate
                            font.pixelSize: 14
                            font.family: ThemeManager.getFont("ui")
                            color: ThemeManager.getColor("textSecondary")
                        }
                    }

                    // Price row
                    RowLayout {
                        spacing: 12

                        // Discount badge
                        Rectangle {
                            visible: {
                                var s = parseFloat(savings)
                                return !isNaN(s) && s > 0
                            }
                            Layout.preferredWidth: heroDiscText.width + 16
                            Layout.preferredHeight: 32
                            radius: 6
                            color: "#4ade80"

                            Text {
                                id: heroDiscText
                                anchors.centerIn: parent
                                text: "-" + Math.round(parseFloat(savings)) + "%"
                                font.pixelSize: 15
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
                            font.pixelSize: 18
                            font.family: ThemeManager.getFont("ui")
                            color: ThemeManager.getColor("textSecondary")
                            font.strikeout: true
                        }

                        // Sale price
                        Text {
                            text: {
                                if (salePrice === "0.00") return "FREE"
                                if (salePrice !== "") return "$" + salePrice
                                return ""
                            }
                            font.pixelSize: 24
                            font.family: ThemeManager.getFont("ui")
                            font.bold: true
                            color: "#4ade80"
                        }
                    }
                }

                // ─── Content body ───
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: 32
                    Layout.rightMargin: 32
                    Layout.topMargin: 16
                    spacing: 20

                    // ─── Info badges row ───
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10

                        // Metacritic badge
                        Rectangle {
                            visible: metacriticScore !== "" && metacriticScore !== "0"
                            Layout.preferredWidth: metaRow.width + 20
                            Layout.preferredHeight: 44
                            radius: 10
                            color: ThemeManager.getColor("surface")

                            RowLayout {
                                id: metaRow
                                anchors.centerIn: parent
                                spacing: 8

                                Rectangle {
                                    Layout.preferredWidth: 32
                                    Layout.preferredHeight: 32
                                    radius: 6
                                    color: {
                                        var score = parseInt(metacriticScore)
                                        if (score >= 75) return "#4ade80"
                                        if (score >= 50) return "#fbbf24"
                                        return "#ff6b6b"
                                    }

                                    Text {
                                        anchors.centerIn: parent
                                        text: metacriticScore
                                        font.pixelSize: 14
                                        font.bold: true
                                        color: "#0a0a0a"
                                    }
                                }

                                Text {
                                    text: "Metacritic"
                                    font.pixelSize: 13
                                    font.family: ThemeManager.getFont("ui")
                                    color: ThemeManager.getColor("textSecondary")
                                }
                            }
                        }

                        // Steam rating badge
                        Rectangle {
                            visible: steamRatingText !== "" && steamRatingText !== "null"
                            Layout.preferredWidth: ratingRow.width + 20
                            Layout.preferredHeight: 44
                            radius: 10
                            color: ThemeManager.getColor("surface")

                            RowLayout {
                                id: ratingRow
                                anchors.centerIn: parent
                                spacing: 8

                                Text {
                                    text: (steamRatingPercent !== "" && steamRatingPercent !== "0")
                                          ? steamRatingPercent + "%" : ""
                                    font.pixelSize: 16
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
                                    font.pixelSize: 13
                                    font.family: ThemeManager.getFont("ui")
                                    color: ThemeManager.getColor("textSecondary")
                                }
                            }
                        }

                        // ProtonDB compatibility badge
                        Rectangle {
                            visible: protonTier !== "" || loadingProton
                            Layout.preferredWidth: protonRow.width + 20
                            Layout.preferredHeight: 44
                            radius: 10
                            color: ThemeManager.getColor("surface")

                            RowLayout {
                                id: protonRow
                                anchors.centerIn: parent
                                spacing: 8

                                Rectangle {
                                    Layout.preferredWidth: 14
                                    Layout.preferredHeight: 14
                                    radius: 7
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
                                    font.pixelSize: 13
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
                                    font.pixelSize: 11
                                    font.family: ThemeManager.getFont("ui")
                                    color: ThemeManager.getColor("textSecondary")
                                    opacity: 0.7
                                }
                            }
                        }

                        // Cheapest ever badge
                        Rectangle {
                            visible: cheapestEverPrice !== "" && cheapestEverPrice !== "0.00"
                            Layout.preferredWidth: cheapestRow.width + 20
                            Layout.preferredHeight: 44
                            radius: 10
                            color: ThemeManager.getColor("surface")

                            RowLayout {
                                id: cheapestRow
                                anchors.centerIn: parent
                                spacing: 6

                                Text {
                                    text: "Cheapest ever:"
                                    font.pixelSize: 12
                                    font.family: ThemeManager.getFont("ui")
                                    color: ThemeManager.getColor("textSecondary")
                                }
                                Text {
                                    text: "$" + cheapestEverPrice
                                    font.pixelSize: 14
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
                        spacing: 20

                        // Left column
                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.preferredWidth: parent.width * 0.55
                            spacing: 16

                            // ─── IGDB Description ───
                            Rectangle {
                                visible: igdbSummary !== "" || loadingIGDB || igdbErrorMsg !== ""
                                Layout.fillWidth: true
                                Layout.preferredHeight: descCol.height + 28
                                radius: 12
                                color: ThemeManager.getColor("surface")

                                ColumnLayout {
                                    id: descCol
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    anchors.margins: 14
                                    spacing: 10

                                    Text {
                                        text: "About"
                                        font.pixelSize: ThemeManager.getFontSize("large")
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

                                    // IGDB error with retry
                                    RowLayout {
                                        visible: !loadingIGDB && igdbErrorMsg !== "" && igdbSummary === ""
                                        Layout.fillWidth: true
                                        spacing: 10

                                        Text {
                                            text: "Could not load description"
                                            font.pixelSize: ThemeManager.getFontSize("small")
                                            font.family: ThemeManager.getFont("body")
                                            color: ThemeManager.getColor("textSecondary")
                                            font.italic: true
                                        }

                                        Rectangle {
                                            Layout.preferredWidth: retryIgdbLabel.width + 20
                                            Layout.preferredHeight: 28
                                            radius: 6
                                            color: retryIgdbArea.containsMouse
                                                   ? ThemeManager.getColor("primary")
                                                   : ThemeManager.getColor("hover")

                                            Text {
                                                id: retryIgdbLabel
                                                anchors.centerIn: parent
                                                text: "Retry"
                                                font.pixelSize: 11
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
                                        font.pixelSize: ThemeManager.getFontSize("medium")
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
                                Layout.preferredHeight: protonCol.height + 28
                                radius: 12
                                color: ThemeManager.getColor("surface")

                                ColumnLayout {
                                    id: protonCol
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    anchors.margins: 14
                                    spacing: 10

                                    Text {
                                        text: "Linux Compatibility (ProtonDB)"
                                        font.pixelSize: ThemeManager.getFontSize("large")
                                        font.family: ThemeManager.getFont("heading")
                                        font.bold: true
                                        color: ThemeManager.getColor("textPrimary")
                                    }

                                    RowLayout {
                                        spacing: 16

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
                                                font.pixelSize: ThemeManager.getFontSize("medium")
                                                font.family: ThemeManager.getFont("body")
                                                color: ThemeManager.getColor("textPrimary")
                                                Layout.fillWidth: true
                                                wrapMode: Text.WordWrap
                                            }

                                            Text {
                                                visible: protonConfidence !== ""
                                                text: "Confidence: " + protonConfidence.charAt(0).toUpperCase() + protonConfidence.slice(1)
                                                font.pixelSize: 13
                                                font.family: ThemeManager.getFont("ui")
                                                color: ThemeManager.getColor("textSecondary")
                                            }

                                            Text {
                                                visible: protonTotalReports > 0
                                                text: "Based on " + protonTotalReports + " user reports"
                                                font.pixelSize: 13
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
                            spacing: 10

                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: storePricesContent.height + 28
                                radius: 12
                                color: ThemeManager.getColor("surface")

                                ColumnLayout {
                                    id: storePricesContent
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    anchors.margins: 14
                                    spacing: 10

                                    RowLayout {
                                        spacing: 8

                                        Text {
                                            text: "Store Prices"
                                            font.pixelSize: ThemeManager.getFontSize("large")
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
                                    }

                                    // Deals list
                                    Repeater {
                                        model: gameDeals

                                        Rectangle {
                                            Layout.fillWidth: true
                                            Layout.preferredHeight: 56
                                            radius: 10
                                            color: dealItemArea.containsMouse
                                                   ? ThemeManager.getColor("hover")
                                                   : ThemeManager.getColor("cardBackground")

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
                                                spacing: 10

                                                // Store icon
                                                Image {
                                                    Layout.preferredWidth: 20
                                                    Layout.preferredHeight: 20
                                                    source: modelData.storeIcon || ""
                                                    asynchronous: true
                                                    cache: true
                                                    fillMode: Image.PreserveAspectFit
                                                    visible: source !== ""
                                                }

                                                // Store name
                                                Text {
                                                    text: modelData.storeName || ("Store #" + modelData.storeID)
                                                    font.pixelSize: ThemeManager.getFontSize("small")
                                                    font.family: ThemeManager.getFont("body")
                                                    font.bold: true
                                                    color: ThemeManager.getColor("textPrimary")
                                                    Layout.fillWidth: true
                                                }

                                                // Savings badge
                                                Rectangle {
                                                    visible: {
                                                        var s = parseFloat(modelData.savings)
                                                        return !isNaN(s) && s > 0
                                                    }
                                                    Layout.preferredWidth: dealSavingsText.width + 12
                                                    Layout.preferredHeight: 24
                                                    radius: 6
                                                    color: "#4ade80"

                                                    Text {
                                                        id: dealSavingsText
                                                        anchors.centerIn: parent
                                                        text: "-" + Math.round(parseFloat(modelData.savings)) + "%"
                                                        font.pixelSize: 12
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
                                                    font.pixelSize: 16
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
                                        spacing: 8

                                        Text {
                                            text: "Failed to load store prices"
                                            font.pixelSize: ThemeManager.getFontSize("small")
                                            font.family: ThemeManager.getFont("body")
                                            color: "#ff6b6b"
                                        }

                                        Rectangle {
                                            Layout.preferredWidth: retryDealsLabel.width + 24
                                            Layout.preferredHeight: 32
                                            radius: 8
                                            color: retryDealsArea.containsMouse
                                                   ? ThemeManager.getColor("primary")
                                                   : ThemeManager.getColor("hover")

                                            Behavior on color { ColorAnimation { duration: 150 } }

                                            Text {
                                                id: retryDealsLabel
                                                anchors.centerIn: parent
                                                text: "Retry"
                                                font.pixelSize: 12
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
                                                    detailPopup.loadingDeals = true
                                                    StoreApi.fetchGameDeals(detailPopup.gameID)
                                                }
                                            }
                                        }
                                    }

                                    // No deals message
                                    Text {
                                        visible: !loadingDeals && dealsErrorMsg === "" && gameDeals.length === 0
                                        text: "No deals found for this game"
                                        font.pixelSize: ThemeManager.getFontSize("small")
                                        font.family: ThemeManager.getFont("body")
                                        color: ThemeManager.getColor("textSecondary")
                                        font.italic: true
                                    }
                                }
                            }
                        }
                    }

                    // Bottom spacer
                    Item { Layout.preferredHeight: 24 }
                }
            }
        }
    }
}
