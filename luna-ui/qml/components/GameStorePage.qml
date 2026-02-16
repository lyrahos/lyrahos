import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
    id: storePage

    // ─── State ───
    property var topDeals: []
    property var recentDeals: []
    property var searchResults: []
    property bool isSearching: false
    property bool loadingTopDeals: true
    property bool loadingRecentDeals: true
    property bool loadingSearch: false
    property string searchQuery: ""
    property string currentSort: "Deal Rating"
    property int currentPage: 0
    property bool hasNetwork: GameManager.isNetworkAvailable()
    property bool appendNextDeals: false  // true when "Load More" is pending
    property string topDealsError: ""
    property string recentDealsError: ""

    // Sort options
    property var sortOptions: [
        { label: "Best Deals",  value: "Deal Rating" },
        { label: "Lowest Price", value: "Price" },
        { label: "Highest Metacritic", value: "Metacritic" },
        { label: "Best Reviews", value: "Reviews" },
        { label: "Newest",      value: "recent" }
    ]

    // Periodically check network status
    Timer {
        id: storeNetworkCheck
        interval: 3000
        running: storePage.visible
        repeat: true
        onTriggered: {
            var wasOffline = !storePage.hasNetwork
            storePage.hasNetwork = GameManager.isNetworkAvailable()
            // Auto-load deals when coming back online
            if (wasOffline && storePage.hasNetwork) {
                storePage.loadingTopDeals = true
                storePage.loadingRecentDeals = true
                StoreApi.fetchDeals(storePage.currentSort, 0, 30)
                StoreApi.fetchRecentDeals(20)
            }
        }
    }

    Component.onCompleted: {
        hasNetwork = GameManager.isNetworkAvailable()
        if (hasNetwork) {
            StoreApi.fetchDeals("Deal Rating", 0, 30)
            StoreApi.fetchRecentDeals(20)
        }
    }

    // ─── API Connections ───
    Connections {
        target: StoreApi

        function onDealsReady(deals) {
            if (storePage.isSearching) return
            if (storePage.appendNextDeals) {
                // "Load More" — append new deals to existing list
                storePage.topDeals = storePage.topDeals.concat(deals)
                storePage.appendNextDeals = false
            } else {
                storePage.topDeals = deals
            }
            storePage.topDealsError = ""
            storePage.loadingTopDeals = false
        }

        function onDealsError(error) {
            storePage.loadingTopDeals = false
            storePage.appendNextDeals = false
            storePage.topDealsError = error
            console.warn("Failed to fetch deals:", error)
        }

        function onRecentDealsReady(deals) {
            storePage.recentDeals = deals
            storePage.recentDealsError = ""
            storePage.loadingRecentDeals = false
        }

        function onRecentDealsError(error) {
            storePage.loadingRecentDeals = false
            storePage.recentDealsError = error
        }

        function onSearchResultsReady(results) {
            storePage.searchResults = results
            storePage.loadingSearch = false
        }

        function onSearchError(error) {
            storePage.loadingSearch = false
        }
    }

    // ─── No Internet Overlay ───
    ColumnLayout {
        anchors.centerIn: parent
        spacing: 24
        visible: !storePage.hasNetwork

        Rectangle {
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: 96
            Layout.preferredHeight: 96
            radius: 48
            color: ThemeManager.getColor("surface")

            Text {
                anchors.centerIn: parent
                text: "\u26A0"
                font.pixelSize: 48
                color: ThemeManager.getColor("textSecondary")
            }
        }

        Text {
            text: "No Internet Connection"
            font.pixelSize: 48
            font.family: ThemeManager.getFont("heading")
            font.bold: true
            color: ThemeManager.getColor("textPrimary")
            Layout.alignment: Qt.AlignHCenter
        }

        Text {
            text: "Connect to the internet to browse game deals"
            font.pixelSize: 28
            font.family: ThemeManager.getFont("body")
            color: ThemeManager.getColor("textSecondary")
            Layout.alignment: Qt.AlignHCenter
        }

        Rectangle {
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: settingsBtnLabel.width + 56
            Layout.preferredHeight: 64
            radius: 14
            color: settingsBtnArea.containsMouse
                   ? Qt.darker(ThemeManager.getColor("primary"), 1.1)
                   : ThemeManager.getColor("primary")

            Behavior on color { ColorAnimation { duration: 150 } }

            Text {
                id: settingsBtnLabel
                anchors.centerIn: parent
                text: "Open Settings"
                font.pixelSize: 28
                font.family: ThemeManager.getFont("ui")
                font.bold: true
                color: "#ffffff"
            }

            MouseArea {
                id: settingsBtnArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    navBar.currentIndex = 3
                    navBar.sectionChanged("Settings")
                }
            }
        }
    }

    // ─── Main Layout ───
    ColumnLayout {
        anchors.fill: parent
        spacing: 0
        visible: storePage.hasNetwork

        // ─── Top bar: Search + Sort ───
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 76
            color: "transparent"

            RowLayout {
                anchors.fill: parent
                spacing: 16

                // Search bar
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 60
                    radius: 14
                    color: ThemeManager.getColor("surface")
                    border.color: searchInput.activeFocus
                                  ? ThemeManager.getColor("focus")
                                  : Qt.rgba(1, 1, 1, 0.06)
                    border.width: searchInput.activeFocus ? 3 : 1

                    Behavior on border.color { ColorAnimation { duration: 150 } }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 20
                        anchors.rightMargin: 20
                        spacing: 14

                        // Search icon
                        Text {
                            text: "\u2315"
                            font.pixelSize: 32
                            color: ThemeManager.getColor("textSecondary")
                        }

                        TextInput {
                            id: searchInput
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            verticalAlignment: TextInput.AlignVCenter
                            font.pixelSize: 28
                            font.family: ThemeManager.getFont("body")
                            color: ThemeManager.getColor("textPrimary")
                            clip: true
                            selectByMouse: true

                            onAccepted: {
                                if (text.trim().length > 0) {
                                    storePage.searchQuery = text.trim()
                                    storePage.isSearching = true
                                    storePage.loadingSearch = true
                                    StoreApi.searchGames(text.trim())
                                } else {
                                    clearSearch()
                                }
                            }
                        }

                        // Placeholder
                        Text {
                            visible: searchInput.text === "" && !searchInput.activeFocus
                            text: "Search games..."
                            font.pixelSize: 28
                            font.family: ThemeManager.getFont("body")
                            color: ThemeManager.getColor("textSecondary")
                            anchors.verticalCenter: parent.verticalCenter
                            x: searchInput.x
                        }

                        // Clear button
                        Rectangle {
                            visible: searchInput.text.length > 0
                            Layout.preferredWidth: 48
                            Layout.preferredHeight: 48
                            radius: 24
                            color: clearSearchArea.containsMouse
                                   ? ThemeManager.getColor("hover") : "transparent"

                            Text {
                                anchors.centerIn: parent
                                text: "\u2715"
                                font.pixelSize: 24
                                color: ThemeManager.getColor("textSecondary")
                            }

                            MouseArea {
                                id: clearSearchArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: clearSearch()
                            }
                        }
                    }
                }

                // Sort chips
                Row {
                    spacing: 10
                    visible: !storePage.isSearching

                    Repeater {
                        model: sortOptions

                        Rectangle {
                            width: sortChipText.width + 40
                            height: 56
                            radius: 12
                            color: currentSort === modelData.value
                                   ? ThemeManager.getColor("primary")
                                   : ThemeManager.getColor("surface")
                            border.color: sortChipArea.containsMouse && currentSort !== modelData.value
                                          ? ThemeManager.getColor("focus") : "transparent"
                            border.width: sortChipArea.containsMouse && currentSort !== modelData.value ? 2 : 0

                            Behavior on color { ColorAnimation { duration: 150 } }

                            Text {
                                id: sortChipText
                                anchors.centerIn: parent
                                text: modelData.label
                                font.pixelSize: 24
                                font.family: ThemeManager.getFont("ui")
                                font.bold: currentSort === modelData.value
                                color: currentSort === modelData.value
                                       ? "#ffffff"
                                       : ThemeManager.getColor("textSecondary")
                            }

                            MouseArea {
                                id: sortChipArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    currentSort = modelData.value
                                    currentPage = 0
                                    storePage.loadingTopDeals = true
                                    StoreApi.fetchDeals(modelData.value, 0, 30)
                                }
                            }
                        }
                    }
                }
            }
        }

        Item { height: 16; Layout.fillWidth: true }

        // ─── Content Area ───
        Flickable {
            id: mainFlickable
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentHeight: mainContent.height
            clip: true
            flickableDirection: Flickable.VerticalFlick
            boundsBehavior: Flickable.StopAtBounds

            ScrollBar.vertical: ScrollBar {
                policy: ScrollBar.AsNeeded
            }

            ColumnLayout {
                id: mainContent
                width: mainFlickable.width
                spacing: 32

                // ═══════════════════════════════
                // Search Results Mode
                // ═══════════════════════════════
                ColumnLayout {
                    visible: storePage.isSearching
                    Layout.fillWidth: true
                    spacing: 20

                    // Search header
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 16

                        Text {
                            text: loadingSearch
                                  ? "Searching..."
                                  : "Results for \"" + searchQuery + "\""
                            font.pixelSize: 36
                            font.family: ThemeManager.getFont("heading")
                            font.bold: true
                            color: ThemeManager.getColor("textPrimary")
                        }

                        Text {
                            visible: !loadingSearch && searchResults.length > 0
                            text: searchResults.length + " games found"
                            font.pixelSize: 24
                            font.family: ThemeManager.getFont("body")
                            color: ThemeManager.getColor("textSecondary")
                        }

                        Item { Layout.fillWidth: true }

                        Rectangle {
                            Layout.preferredWidth: backLabel.width + 40
                            Layout.preferredHeight: 56
                            radius: 12
                            color: ThemeManager.getColor("surface")
                            border.color: backBtnArea.containsMouse
                                          ? ThemeManager.getColor("focus") : "transparent"
                            border.width: backBtnArea.containsMouse ? 2 : 0

                            Text {
                                id: backLabel
                                anchors.centerIn: parent
                                text: "Back to Store"
                                font.pixelSize: 24
                                font.family: ThemeManager.getFont("ui")
                                font.bold: true
                                color: ThemeManager.getColor("textPrimary")
                            }

                            MouseArea {
                                id: backBtnArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: clearSearch()
                            }
                        }
                    }

                    // Loading spinner
                    ColumnLayout {
                        visible: loadingSearch
                        Layout.alignment: Qt.AlignHCenter
                        Layout.topMargin: 60
                        spacing: 16

                        Item {
                            Layout.alignment: Qt.AlignHCenter
                            Layout.preferredWidth: 72
                            Layout.preferredHeight: 72

                            Rectangle {
                                anchors.centerIn: parent
                                width: 72
                                height: 72
                                radius: 36
                                color: "transparent"
                                border.width: 5
                                border.color: Qt.rgba(1, 1, 1, 0.1)

                                Rectangle {
                                    width: 72
                                    height: 72
                                    radius: 36
                                    color: "transparent"
                                    border.width: 5
                                    border.color: "transparent"

                                    Rectangle {
                                        width: 18
                                        height: 5
                                        radius: 2
                                        color: ThemeManager.getColor("primary")
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        anchors.top: parent.top
                                    }
                                    Rectangle {
                                        width: 5
                                        height: 18
                                        radius: 2
                                        color: ThemeManager.getColor("primary")
                                        anchors.verticalCenter: parent.verticalCenter
                                        anchors.right: parent.right
                                    }

                                    RotationAnimation on rotation {
                                        from: 0
                                        to: 360
                                        duration: 1200
                                        loops: Animation.Infinite
                                        running: loadingSearch
                                    }
                                }
                            }
                        }

                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: "Searching game stores..."
                            font.pixelSize: 28
                            font.family: ThemeManager.getFont("body")
                            color: ThemeManager.getColor("textSecondary")
                        }
                    }

                    // No results
                    ColumnLayout {
                        visible: !loadingSearch && searchResults.length === 0 && searchQuery !== ""
                        Layout.alignment: Qt.AlignHCenter
                        Layout.topMargin: 60
                        spacing: 12

                        Text {
                            text: "No games found"
                            font.pixelSize: 36
                            font.family: ThemeManager.getFont("heading")
                            font.bold: true
                            color: ThemeManager.getColor("textPrimary")
                            Layout.alignment: Qt.AlignHCenter
                        }

                        Text {
                            text: "Try a different search term"
                            font.pixelSize: 24
                            font.family: ThemeManager.getFont("body")
                            color: ThemeManager.getColor("textSecondary")
                            Layout.alignment: Qt.AlignHCenter
                        }
                    }

                    // Search results grid
                    Flow {
                        visible: !loadingSearch && searchResults.length > 0
                        Layout.fillWidth: true
                        spacing: 16

                        Repeater {
                            model: searchResults

                            StoreGameCard {
                                width: Math.floor((mainFlickable.width - 64) / 3)
                                height: width * 0.55
                                gameTitle: modelData.title || ""
                                headerImage: modelData.headerImage || modelData.thumb || ""
                                salePrice: modelData.cheapest || ""
                                normalPrice: ""
                                savings: ""
                                metacriticScore: ""
                                steamRatingText: ""
                                steamAppID: modelData.steamAppID || ""
                                gameID: modelData.gameID || ""

                                onClicked: {
                                    detailPopup.open(modelData)
                                }
                            }
                        }
                    }
                }

                // ═══════════════════════════════
                // Normal Store Mode
                // ═══════════════════════════════

                // ─── Hero Banner (Featured Deal) ───
                Rectangle {
                    id: heroBanner
                    visible: !storePage.isSearching && topDeals.length > 0
                    Layout.fillWidth: true
                    Layout.preferredHeight: 420
                    radius: 20
                    clip: true
                    color: ThemeManager.getColor("surface")

                    property var featuredDeal: topDeals.length > 0 ? topDeals[0] : null
                    property int featuredIndex: 0

                    // Auto-rotate featured game
                    Timer {
                        id: heroRotateTimer
                        interval: 8000
                        running: !storePage.isSearching && topDeals.length > 1 && storePage.visible
                        repeat: true
                        onTriggered: {
                            heroBanner.featuredIndex = (heroBanner.featuredIndex + 1) % Math.min(topDeals.length, 5)
                            heroBanner.featuredDeal = topDeals[heroBanner.featuredIndex]
                        }
                    }

                    // Background image
                    Image {
                        id: heroImage
                        anchors.fill: parent
                        source: heroBanner.featuredDeal ? heroBanner.featuredDeal.headerImage : ""
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        cache: true
                        opacity: status === Image.Ready ? 1.0 : 0.0
                        Behavior on opacity { NumberAnimation { duration: 500 } }
                    }

                    // Gradient overlays
                    Rectangle {
                        anchors.fill: parent
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, 0.85) }
                            GradientStop { position: 0.5; color: Qt.rgba(0, 0, 0, 0.4) }
                            GradientStop { position: 1.0; color: "transparent" }
                        }
                    }

                    Rectangle {
                        anchors.fill: parent
                        gradient: Gradient {
                            GradientStop { position: 0.0; color: "transparent" }
                            GradientStop { position: 0.8; color: Qt.rgba(0, 0, 0, 0.5) }
                            GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.8) }
                        }
                    }

                    // Themed accent glow at top
                    Rectangle {
                        anchors.top: parent.top
                        anchors.left: parent.left
                        anchors.right: parent.right
                        height: 4
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0.0; color: ThemeManager.getColor("primary") }
                            GradientStop { position: 0.5; color: ThemeManager.getColor("accent") }
                            GradientStop { position: 1.0; color: ThemeManager.getColor("secondary") }
                        }
                    }

                    // Featured content
                    ColumnLayout {
                        anchors.left: parent.left
                        anchors.bottom: parent.bottom
                        anchors.leftMargin: 40
                        anchors.bottomMargin: 36
                        anchors.right: parent.horizontalCenter
                        spacing: 10

                        // Featured badge
                        Rectangle {
                            Layout.preferredWidth: featuredLabel.width + 24
                            Layout.preferredHeight: 38
                            radius: 8
                            color: ThemeManager.getColor("primary")

                            Text {
                                id: featuredLabel
                                anchors.centerIn: parent
                                text: "FEATURED DEAL"
                                font.pixelSize: 22
                                font.family: ThemeManager.getFont("ui")
                                font.bold: true
                                color: "#ffffff"
                                font.letterSpacing: 1.2
                            }
                        }

                        // Game title
                        Text {
                            text: heroBanner.featuredDeal ? heroBanner.featuredDeal.title : ""
                            font.pixelSize: 48
                            font.family: ThemeManager.getFont("heading")
                            font.bold: true
                            color: "#ffffff"
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }

                        // Rating
                        Text {
                            visible: heroBanner.featuredDeal &&
                                     heroBanner.featuredDeal.steamRatingText !== "" &&
                                     heroBanner.featuredDeal.steamRatingText !== "null"
                            text: heroBanner.featuredDeal ? heroBanner.featuredDeal.steamRatingText : ""
                            font.pixelSize: 24
                            font.family: ThemeManager.getFont("body")
                            color: ThemeManager.getColor("textSecondary")
                        }

                        // Price row
                        RowLayout {
                            spacing: 14

                            Rectangle {
                                visible: {
                                    if (!heroBanner.featuredDeal) return false
                                    var s = parseFloat(heroBanner.featuredDeal.savings)
                                    return !isNaN(s) && s > 0
                                }
                                Layout.preferredWidth: heroDiscText.width + 24
                                Layout.preferredHeight: 44
                                radius: 10
                                color: "#4ade80"

                                Text {
                                    id: heroDiscText
                                    anchors.centerIn: parent
                                    text: heroBanner.featuredDeal
                                          ? "-" + Math.round(parseFloat(heroBanner.featuredDeal.savings)) + "%"
                                          : ""
                                    font.pixelSize: 28
                                    font.bold: true
                                    color: "#0a0a0a"
                                }
                            }

                            Text {
                                visible: {
                                    if (!heroBanner.featuredDeal) return false
                                    var s = parseFloat(heroBanner.featuredDeal.savings)
                                    return !isNaN(s) && s > 0
                                }
                                text: heroBanner.featuredDeal ? "$" + heroBanner.featuredDeal.normalPrice : ""
                                font.pixelSize: 30
                                font.family: ThemeManager.getFont("ui")
                                color: ThemeManager.getColor("textSecondary")
                                font.strikeout: true
                            }

                            Text {
                                text: {
                                    if (!heroBanner.featuredDeal) return ""
                                    if (heroBanner.featuredDeal.salePrice === "0.00") return "FREE"
                                    return "$" + heroBanner.featuredDeal.salePrice
                                }
                                font.pixelSize: 44
                                font.family: ThemeManager.getFont("ui")
                                font.bold: true
                                color: "#4ade80"
                            }
                        }
                    }

                    // Navigation dots
                    Row {
                        anchors.bottom: parent.bottom
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottomMargin: 16
                        spacing: 12
                        visible: topDeals.length > 1

                        Repeater {
                            model: Math.min(topDeals.length, 5)

                            Rectangle {
                                width: heroBanner.featuredIndex === index ? 36 : 16
                                height: 16
                                radius: 8
                                color: heroBanner.featuredIndex === index
                                       ? ThemeManager.getColor("primary")
                                       : Qt.rgba(1, 1, 1, 0.3)

                                Behavior on width { NumberAnimation { duration: 200 } }
                                Behavior on color { ColorAnimation { duration: 200 } }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        heroBanner.featuredIndex = index
                                        heroBanner.featuredDeal = topDeals[index]
                                        heroRotateTimer.restart()
                                    }
                                }
                            }
                        }
                    }

                    // Clickable overlay
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        z: -1
                        onClicked: {
                            if (heroBanner.featuredDeal)
                                detailPopup.open(heroBanner.featuredDeal)
                        }
                    }
                }

                // Hero loading placeholder
                Rectangle {
                    visible: !storePage.isSearching && loadingTopDeals
                    Layout.fillWidth: true
                    Layout.preferredHeight: 420
                    radius: 20
                    color: ThemeManager.getColor("surface")

                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: 16

                        // Spinning ring
                        Item {
                            Layout.alignment: Qt.AlignHCenter
                            Layout.preferredWidth: 72
                            Layout.preferredHeight: 72

                            Rectangle {
                                anchors.centerIn: parent
                                width: 72
                                height: 72
                                radius: 36
                                color: "transparent"
                                border.width: 5
                                border.color: Qt.rgba(1, 1, 1, 0.1)

                                Rectangle {
                                    width: 72
                                    height: 72
                                    radius: 36
                                    color: "transparent"
                                    border.width: 5
                                    border.color: "transparent"

                                    Rectangle {
                                        width: 18
                                        height: 5
                                        radius: 2
                                        color: ThemeManager.getColor("primary")
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        anchors.top: parent.top
                                    }
                                    Rectangle {
                                        width: 5
                                        height: 18
                                        radius: 2
                                        color: ThemeManager.getColor("primary")
                                        anchors.verticalCenter: parent.verticalCenter
                                        anchors.right: parent.right
                                    }

                                    RotationAnimation on rotation {
                                        from: 0
                                        to: 360
                                        duration: 1200
                                        loops: Animation.Infinite
                                        running: loadingTopDeals
                                    }
                                }
                            }
                        }

                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: "Loading deals..."
                            font.pixelSize: 28
                            font.family: ThemeManager.getFont("body")
                            color: ThemeManager.getColor("textSecondary")
                        }
                    }
                }

                // ─── Error State (deals failed to load) ───
                ColumnLayout {
                    visible: !storePage.isSearching && !loadingTopDeals && topDeals.length === 0 && topDealsError !== ""
                    Layout.fillWidth: true
                    Layout.preferredHeight: 320
                    spacing: 16

                    Item { Layout.fillHeight: true }

                    Text {
                        text: "Failed to load deals"
                        font.pixelSize: 36
                        font.family: ThemeManager.getFont("heading")
                        font.bold: true
                        color: ThemeManager.getColor("textPrimary")
                        Layout.alignment: Qt.AlignHCenter
                    }

                    Text {
                        text: topDealsError
                        font.pixelSize: 24
                        font.family: ThemeManager.getFont("body")
                        color: ThemeManager.getColor("textSecondary")
                        Layout.alignment: Qt.AlignHCenter
                        wrapMode: Text.WordWrap
                        Layout.maximumWidth: 500
                        horizontalAlignment: Text.AlignHCenter
                    }

                    Rectangle {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.preferredWidth: retryLabel.width + 48
                        Layout.preferredHeight: 56
                        radius: 12
                        color: retryArea.containsMouse
                               ? ThemeManager.getColor("primary")
                               : ThemeManager.getColor("surface")
                        border.color: ThemeManager.getColor("primary")
                        border.width: 2

                        Behavior on color { ColorAnimation { duration: 150 } }

                        Text {
                            id: retryLabel
                            anchors.centerIn: parent
                            text: "Retry"
                            font.pixelSize: 24
                            font.family: ThemeManager.getFont("ui")
                            font.bold: true
                            color: retryArea.containsMouse
                                   ? "#ffffff"
                                   : ThemeManager.getColor("textPrimary")
                        }

                        MouseArea {
                            id: retryArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                storePage.topDealsError = ""
                                storePage.recentDealsError = ""
                                storePage.loadingTopDeals = true
                                storePage.loadingRecentDeals = true
                                storePage.currentPage = 0
                                StoreApi.fetchDeals(storePage.currentSort, 0, 30)
                                StoreApi.fetchRecentDeals(20)
                            }
                        }
                    }

                    Item { Layout.fillHeight: true }
                }

                // ─── Trending Deals Section (horizontal scroll) ───
                ColumnLayout {
                    visible: !storePage.isSearching && recentDeals.length > 0
                    Layout.fillWidth: true
                    spacing: 16

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 12

                        // Accent dot
                        Rectangle {
                            Layout.preferredWidth: 6
                            Layout.preferredHeight: 28
                            radius: 3
                            color: ThemeManager.getColor("accent")
                        }

                        Text {
                            text: "Trending Now"
                            font.pixelSize: 36
                            font.family: ThemeManager.getFont("heading")
                            font.bold: true
                            color: ThemeManager.getColor("textPrimary")
                        }

                        Item { Layout.fillWidth: true }

                        // Scroll arrows
                        Rectangle {
                            Layout.preferredWidth: 56
                            Layout.preferredHeight: 56
                            radius: 12
                            color: trendLeftArea.containsMouse
                                   ? ThemeManager.getColor("hover") : ThemeManager.getColor("surface")

                            Text {
                                anchors.centerIn: parent
                                text: "<"
                                font.pixelSize: 28
                                font.bold: true
                                color: ThemeManager.getColor("textPrimary")
                            }

                            MouseArea {
                                id: trendLeftArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: trendingList.flick(800, 0)
                            }
                        }

                        Rectangle {
                            Layout.preferredWidth: 56
                            Layout.preferredHeight: 56
                            radius: 12
                            color: trendRightArea.containsMouse
                                   ? ThemeManager.getColor("hover") : ThemeManager.getColor("surface")

                            Text {
                                anchors.centerIn: parent
                                text: ">"
                                font.pixelSize: 28
                                font.bold: true
                                color: ThemeManager.getColor("textPrimary")
                            }

                            MouseArea {
                                id: trendRightArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: trendingList.flick(-800, 0)
                            }
                        }
                    }

                    ListView {
                        id: trendingList
                        Layout.fillWidth: true
                        Layout.preferredHeight: 280
                        orientation: ListView.Horizontal
                        spacing: 16
                        clip: true
                        model: recentDeals
                        boundsBehavior: Flickable.StopAtBounds

                        delegate: StoreGameCard {
                            width: 420
                            height: 260
                            gameTitle: modelData.title || ""
                            headerImage: modelData.headerImage || modelData.thumb || ""
                            salePrice: modelData.salePrice || ""
                            normalPrice: modelData.normalPrice || ""
                            savings: modelData.savings || ""
                            metacriticScore: modelData.metacriticScore || ""
                            steamRatingText: modelData.steamRatingText || ""
                            steamAppID: modelData.steamAppID || ""
                            gameID: modelData.gameID || ""
                            storeID: modelData.storeID || ""
                            dealRating: modelData.dealRating || ""

                            onClicked: detailPopup.open(modelData)
                        }
                    }
                }

                // ─── Top Deals Grid ───
                ColumnLayout {
                    visible: !storePage.isSearching && topDeals.length > 0
                    Layout.fillWidth: true
                    spacing: 16

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 12

                        Rectangle {
                            Layout.preferredWidth: 6
                            Layout.preferredHeight: 28
                            radius: 3
                            color: ThemeManager.getColor("primary")
                        }

                        Text {
                            text: {
                                switch (currentSort) {
                                    case "Deal Rating": return "Top Deals"
                                    case "Price":       return "Lowest Prices"
                                    case "Metacritic":  return "Highest Rated"
                                    case "Reviews":     return "Most Reviewed"
                                    case "recent":      return "Newest Deals"
                                    default:            return "Deals"
                                }
                            }
                            font.pixelSize: 36
                            font.family: ThemeManager.getFont("heading")
                            font.bold: true
                            color: ThemeManager.getColor("textPrimary")
                        }

                        Text {
                            text: topDeals.length + " deals"
                            font.pixelSize: 24
                            font.family: ThemeManager.getFont("body")
                            color: ThemeManager.getColor("textSecondary")
                        }

                        Item { Layout.fillWidth: true }
                    }

                    // Grid of deal cards
                    Flow {
                        Layout.fillWidth: true
                        spacing: 16

                        Repeater {
                            // Skip first deal (shown in hero) for "Deal Rating" sort
                            model: {
                                if (currentSort === "Deal Rating" && topDeals.length > 1)
                                    return topDeals.slice(1)
                                return topDeals
                            }

                            StoreGameCard {
                                width: Math.floor((mainFlickable.width - 48) / 3)
                                height: width * 0.55
                                gameTitle: modelData.title || ""
                                headerImage: modelData.headerImage || modelData.thumb || ""
                                salePrice: modelData.salePrice || ""
                                normalPrice: modelData.normalPrice || ""
                                savings: modelData.savings || ""
                                metacriticScore: modelData.metacriticScore || ""
                                steamRatingText: modelData.steamRatingText || ""
                                steamAppID: modelData.steamAppID || ""
                                gameID: modelData.gameID || ""
                                storeID: modelData.storeID || ""
                                dealRating: modelData.dealRating || ""

                                onClicked: detailPopup.open(modelData)
                            }
                        }
                    }

                    // Load more button
                    Rectangle {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.preferredWidth: loadMoreLabel.width + 56
                        Layout.preferredHeight: 56
                        Layout.topMargin: 12
                        radius: 12
                        color: loadMoreArea.containsMouse
                               ? ThemeManager.getColor("primary")
                               : ThemeManager.getColor("surface")
                        border.color: loadMoreArea.containsMouse
                                      ? "transparent"
                                      : Qt.rgba(ThemeManager.getColor("primary").r,
                                                ThemeManager.getColor("primary").g,
                                                ThemeManager.getColor("primary").b, 0.4)
                        border.width: 2

                        Behavior on color { ColorAnimation { duration: 200 } }

                        Text {
                            id: loadMoreLabel
                            anchors.centerIn: parent
                            text: "Load More Deals"
                            font.pixelSize: 24
                            font.family: ThemeManager.getFont("ui")
                            font.bold: true
                            color: loadMoreArea.containsMouse
                                   ? "#ffffff"
                                   : ThemeManager.getColor("textPrimary")
                        }

                        MouseArea {
                            id: loadMoreArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                currentPage++
                                storePage.appendNextDeals = true
                                storePage.loadingTopDeals = true
                                StoreApi.fetchDeals(currentSort, currentPage, 30)
                            }
                        }
                    }
                }

                // ─── IGDB Status / Setup ───

                // Active state: IGDB credentials are available (built-in or user-configured)
                Rectangle {
                    visible: !storePage.isSearching && StoreApi.hasIGDBCredentials()
                    Layout.fillWidth: true
                    Layout.preferredHeight: 64
                    radius: 12
                    color: ThemeManager.getColor("surface")

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 20
                        anchors.rightMargin: 20
                        spacing: 14

                        Rectangle {
                            Layout.preferredWidth: 12
                            Layout.preferredHeight: 12
                            radius: 6
                            color: "#4ade80"
                        }

                        Text {
                            text: "IGDB"
                            font.pixelSize: 24
                            font.family: ThemeManager.getFont("ui")
                            font.bold: true
                            color: ThemeManager.getColor("textPrimary")
                        }

                        Text {
                            text: StoreApi.hasBuiltInIGDBCredentials()
                                  ? "Active (built-in)" : "Active (custom)"
                            font.pixelSize: 22
                            font.family: ThemeManager.getFont("ui")
                            color: ThemeManager.getColor("textSecondary")
                        }

                        Text {
                            text: "Game descriptions, screenshots & ratings enabled"
                            font.pixelSize: 22
                            font.family: ThemeManager.getFont("body")
                            color: ThemeManager.getColor("textSecondary")
                            opacity: 0.7
                        }

                        Item { Layout.fillWidth: true }

                        // Reset to built-in (only if user overrode and built-in exists)
                        Rectangle {
                            visible: StoreApi.hasBuiltInIGDBCredentials() && !StoreApi.hasBuiltInIGDBCredentials()
                            Layout.preferredWidth: resetLabel.width + 28
                            Layout.preferredHeight: 40
                            radius: 8
                            color: "transparent"
                            border.color: Qt.rgba(1, 1, 1, 0.12)
                            border.width: 1

                            Text {
                                id: resetLabel
                                anchors.centerIn: parent
                                text: "Reset to built-in"
                                font.pixelSize: 22
                                font.family: ThemeManager.getFont("ui")
                                color: ThemeManager.getColor("textSecondary")
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: StoreApi.clearIGDBCredentials()
                            }
                        }
                    }
                }

                // Setup state: No credentials available, prompt user
                Rectangle {
                    visible: !storePage.isSearching && !StoreApi.hasIGDBCredentials()
                    Layout.fillWidth: true
                    Layout.preferredHeight: igdbSetupCol.height + 40
                    radius: 14
                    color: ThemeManager.getColor("surface")
                    border.color: Qt.rgba(ThemeManager.getColor("accent").r,
                                          ThemeManager.getColor("accent").g,
                                          ThemeManager.getColor("accent").b, 0.3)
                    border.width: 1

                    ColumnLayout {
                        id: igdbSetupCol
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 20
                        spacing: 12

                        RowLayout {
                            spacing: 12

                            Text {
                                text: "Enhance with IGDB"
                                font.pixelSize: 28
                                font.family: ThemeManager.getFont("heading")
                                font.bold: true
                                color: ThemeManager.getColor("textPrimary")
                            }

                            Rectangle {
                                Layout.preferredWidth: optLabel.width + 16
                                Layout.preferredHeight: 28
                                radius: 6
                                color: ThemeManager.getColor("accent")

                                Text {
                                    id: optLabel
                                    anchors.centerIn: parent
                                    text: "OPTIONAL"
                                    font.pixelSize: 18
                                    font.bold: true
                                    color: "#0a0a0a"
                                    font.letterSpacing: 0.8
                                }
                            }
                        }

                        Text {
                            text: "Add your Twitch developer credentials to get rich game descriptions, " +
                                  "screenshots, and ratings from IGDB. Register at dev.twitch.tv"
                            font.pixelSize: 24
                            font.family: ThemeManager.getFont("body")
                            color: ThemeManager.getColor("textSecondary")
                            wrapMode: Text.WordWrap
                            Layout.fillWidth: true
                        }

                        Text {
                            text: "Credentials are encrypted on disk and bound to this device."
                            font.pixelSize: 22
                            font.family: ThemeManager.getFont("ui")
                            color: ThemeManager.getColor("textSecondary")
                            opacity: 0.6
                        }

                        RowLayout {
                            spacing: 12

                            // Client ID input
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 56
                                radius: 10
                                color: ThemeManager.getColor("hover")
                                border.color: igdbClientIdInput.activeFocus
                                              ? ThemeManager.getColor("focus") : "transparent"
                                border.width: igdbClientIdInput.activeFocus ? 3 : 0

                                TextInput {
                                    id: igdbClientIdInput
                                    anchors.fill: parent
                                    anchors.margins: 14
                                    verticalAlignment: TextInput.AlignVCenter
                                    font.pixelSize: 24
                                    font.family: ThemeManager.getFont("body")
                                    color: ThemeManager.getColor("textPrimary")
                                    clip: true
                                }

                                Text {
                                    anchors.fill: parent
                                    anchors.margins: 14
                                    verticalAlignment: Text.AlignVCenter
                                    visible: igdbClientIdInput.text === "" && !igdbClientIdInput.activeFocus
                                    text: "Client ID"
                                    font.pixelSize: 24
                                    font.family: ThemeManager.getFont("body")
                                    color: ThemeManager.getColor("textSecondary")
                                }
                            }

                            // Client Secret input
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 56
                                radius: 10
                                color: ThemeManager.getColor("hover")
                                border.color: igdbSecretInput.activeFocus
                                              ? ThemeManager.getColor("focus") : "transparent"
                                border.width: igdbSecretInput.activeFocus ? 3 : 0

                                TextInput {
                                    id: igdbSecretInput
                                    anchors.fill: parent
                                    anchors.margins: 14
                                    verticalAlignment: TextInput.AlignVCenter
                                    font.pixelSize: 24
                                    font.family: ThemeManager.getFont("body")
                                    color: ThemeManager.getColor("textPrimary")
                                    echoMode: TextInput.Password
                                    clip: true
                                }

                                Text {
                                    anchors.fill: parent
                                    anchors.margins: 14
                                    verticalAlignment: Text.AlignVCenter
                                    visible: igdbSecretInput.text === "" && !igdbSecretInput.activeFocus
                                    text: "Client Secret"
                                    font.pixelSize: 24
                                    font.family: ThemeManager.getFont("body")
                                    color: ThemeManager.getColor("textSecondary")
                                }
                            }

                            // Save button
                            Rectangle {
                                Layout.preferredWidth: saveBtnLabel.width + 40
                                Layout.preferredHeight: 56
                                radius: 10
                                color: (igdbClientIdInput.text.length > 0 && igdbSecretInput.text.length > 0)
                                       ? ThemeManager.getColor("accent")
                                       : ThemeManager.getColor("surface")

                                Text {
                                    id: saveBtnLabel
                                    anchors.centerIn: parent
                                    text: "Save"
                                    font.pixelSize: 24
                                    font.family: ThemeManager.getFont("ui")
                                    font.bold: true
                                    color: (igdbClientIdInput.text.length > 0 && igdbSecretInput.text.length > 0)
                                           ? "#0a0a0a" : ThemeManager.getColor("textSecondary")
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        if (igdbClientIdInput.text.length > 0 &&
                                            igdbSecretInput.text.length > 0) {
                                            StoreApi.setIGDBCredentials(
                                                igdbClientIdInput.text.trim(),
                                                igdbSecretInput.text.trim())
                                            igdbClientIdInput.text = ""
                                            igdbSecretInput.text = ""
                                        }
                                    }
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

    // ─── Detail Popup ───
    GameStoreDetailPopup {
        id: detailPopup
        anchors.fill: parent
    }

    // ─── Helper Functions ───
    function clearSearch() {
        searchInput.text = ""
        storePage.searchQuery = ""
        storePage.isSearching = false
        storePage.searchResults = []
    }
}
