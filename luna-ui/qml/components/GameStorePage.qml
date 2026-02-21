import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtWebEngine

Item {
    id: storePage

    // ─── State ───
    property var featuredGames: []
    property var newReleases: []
    property var topRated: []
    property var topDeals: []
    property var recentDeals: []
    property var searchResults: []
    property bool isSearching: false
    property bool loadingFeatured: true
    property bool loadingNewReleases: true
    property bool loadingTopRated: true
    property bool loadingTopDeals: true
    property bool loadingRecentDeals: true
    property bool loadingSearch: false
    property string searchQuery: ""
    property int currentPage: 0
    property bool hasNetwork: GameManager.isNetworkAvailable()
    property bool appendNextDeals: false

    // ─── Embedded Store Browser ───
    property bool storeBrowserOpen: false
    property string storeBrowserTitle: ""
    property bool storeBrowserInputActive: false

    // ─── Keyboard Navigation ───
    // Zones: "searchBar", "hero", "newReleases", "topRated", "deals", "trending", "loadMore"
    // Search mode: "searchBar", "backToStore", "searchResults"
    property string navZone: ""
    property int heroDotFocusIndex: 0
    property int newReleaseFocusIndex: 0
    property int topRatedFocusIndex: 0
    property int dealsFocusIndex: 0
    property int trendingFocusIndex: 0
    property int searchResultFocusIndex: 0
    property bool hasKeyboardFocus: false

    signal requestNavFocus()

    Keys.onPressed: function(event) {
        handleStoreKeys(event)
    }

    function gainFocus() {
        hasKeyboardFocus = true
        if (isSearching) {
            navZone = "searchResults"
            searchResultFocusIndex = 0
        } else if (featuredGames.length > 0) {
            navZone = "hero"
        } else {
            navZone = "searchBar"
        }
        storePage.forceActiveFocus()
    }

    function loseFocus() {
        hasKeyboardFocus = false
        navZone = ""
    }

    function nextZone() {
        if (isSearching) {
            switch (navZone) {
            case "searchBar": navZone = "backToStore"; break
            case "backToStore":
                if (searchResults.length > 0) { navZone = "searchResults"; searchResultFocusIndex = 0 }
                break
            case "searchResults": break
            }
        } else {
            switch (navZone) {
            case "searchBar":
                if (featuredGames.length > 0) { navZone = "hero"; heroDotFocusIndex = heroBanner.featuredIndex }
                else if (newReleases.length > 0) { navZone = "newReleases"; newReleaseFocusIndex = 0 }
                break
            case "hero":
                if (newReleases.length > 0) { navZone = "newReleases"; newReleaseFocusIndex = 0 }
                else if (topRated.length > 0) { navZone = "topRated"; topRatedFocusIndex = 0 }
                break
            case "newReleases":
                if (topRated.length > 0) { navZone = "topRated"; topRatedFocusIndex = 0 }
                else if (topDeals.length > 0) { navZone = "deals"; dealsFocusIndex = 0 }
                break
            case "topRated":
                if (topDeals.length > 0) { navZone = "deals"; dealsFocusIndex = 0 }
                else if (recentDeals.length > 0) { navZone = "trending"; trendingFocusIndex = 0 }
                break
            case "deals":
                if (recentDeals.length > 0) { navZone = "trending"; trendingFocusIndex = 0 }
                else navZone = "loadMore"
                break
            case "trending": navZone = "loadMore"; break
            case "loadMore": break
            }
        }
    }

    function prevZone() {
        if (isSearching) {
            switch (navZone) {
            case "searchBar": break
            case "backToStore": navZone = "searchBar"; break
            case "searchResults": navZone = "backToStore"; break
            }
        } else {
            switch (navZone) {
            case "searchBar": break
            case "hero": navZone = "searchBar"; break
            case "newReleases":
                if (featuredGames.length > 0) navZone = "hero"
                else navZone = "searchBar"
                break
            case "topRated":
                if (newReleases.length > 0) navZone = "newReleases"
                else if (featuredGames.length > 0) navZone = "hero"
                else navZone = "searchBar"
                break
            case "deals":
                if (topRated.length > 0) navZone = "topRated"
                else if (newReleases.length > 0) navZone = "newReleases"
                else navZone = "hero"
                break
            case "trending":
                if (topDeals.length > 0) navZone = "deals"
                else navZone = "topRated"
                break
            case "loadMore":
                if (recentDeals.length > 0) navZone = "trending"
                else if (topDeals.length > 0) navZone = "deals"
                break
            }
        }
    }

    function handleStoreKeys(event) {
        if (storeBrowserOpen) { event.accepted = true; return }
        if (storeVirtualKeyboard.visible) { event.accepted = true; return }
        if (detailPopup.visible) { detailPopup.handleKeys(event); event.accepted = true; return }

        switch (navZone) {
        case "searchBar": handleSearchBarKeys(event); break
        case "hero": handleHeroKeys(event); break
        case "newReleases": handleHScrollKeys(event, "newReleases", newReleases, newReleaseFocusIndex, function(i) { newReleaseFocusIndex = i }); break
        case "topRated": handleHScrollKeys(event, "topRated", topRated, topRatedFocusIndex, function(i) { topRatedFocusIndex = i }); break
        case "deals": handleHScrollKeys(event, "deals", topDeals, dealsFocusIndex, function(i) { dealsFocusIndex = i }); break
        case "trending": handleHScrollKeys(event, "trending", recentDeals, trendingFocusIndex, function(i) { trendingFocusIndex = i }); break
        case "loadMore": handleLoadMoreKeys(event); break
        case "backToStore": handleBackToStoreKeys(event); break
        case "searchResults": handleSearchResultsKeys(event); break
        }
    }

    function handleSearchBarKeys(event) {
        switch (event.key) {
        case Qt.Key_Left: requestNavFocus(); event.accepted = true; break
        case Qt.Key_Down:
            searchInput.focus = false
            nextZone()
            storePage.forceActiveFocus()
            event.accepted = true
            break
        case Qt.Key_Return:
        case Qt.Key_Enter:
            storeVirtualKeyboard.placeholderText = "Search games..."
            storeVirtualKeyboard.open(searchInput.text)
            event.accepted = true
            break
        }
    }

    function handleHeroKeys(event) {
        var dotCount = Math.min(featuredGames.length, 5)
        switch (event.key) {
        case Qt.Key_Left:
            if (heroDotFocusIndex > 0) {
                heroDotFocusIndex--
                heroBanner.featuredIndex = heroDotFocusIndex
                heroBanner.featuredGame = featuredGames[heroDotFocusIndex]
                heroRotateTimer.restart()
            } else {
                requestNavFocus()
            }
            event.accepted = true
            break
        case Qt.Key_Right:
            if (heroDotFocusIndex < dotCount - 1) {
                heroDotFocusIndex++
                heroBanner.featuredIndex = heroDotFocusIndex
                heroBanner.featuredGame = featuredGames[heroDotFocusIndex]
                heroRotateTimer.restart()
            }
            event.accepted = true
            break
        case Qt.Key_Up: prevZone(); event.accepted = true; break
        case Qt.Key_Down: nextZone(); event.accepted = true; break
        case Qt.Key_Return:
        case Qt.Key_Enter:
            if (heroBanner.featuredGame) detailPopup.open(heroBanner.featuredGame)
            event.accepted = true
            break
        }
    }

    // Generic handler for horizontal scroll sections
    function handleHScrollKeys(event, zone, dataArray, focusIdx, setIdx) {
        switch (event.key) {
        case Qt.Key_Left:
            if (focusIdx > 0) setIdx(focusIdx - 1)
            else requestNavFocus()
            event.accepted = true
            break
        case Qt.Key_Right:
            if (focusIdx < dataArray.length - 1) setIdx(focusIdx + 1)
            event.accepted = true
            break
        case Qt.Key_Up: prevZone(); event.accepted = true; break
        case Qt.Key_Down: nextZone(); event.accepted = true; break
        case Qt.Key_Return:
        case Qt.Key_Enter:
            if (focusIdx >= 0 && focusIdx < dataArray.length)
                detailPopup.open(dataArray[focusIdx])
            event.accepted = true
            break
        }
    }

    function handleLoadMoreKeys(event) {
        switch (event.key) {
        case Qt.Key_Up: prevZone(); event.accepted = true; break
        case Qt.Key_Left: requestNavFocus(); event.accepted = true; break
        case Qt.Key_Return:
        case Qt.Key_Enter:
            currentPage++
            storePage.appendNextDeals = true
            storePage.loadingTopDeals = true
            StoreApi.fetchDeals("Deal Rating", currentPage, 30)
            event.accepted = true
            break
        }
    }

    function handleBackToStoreKeys(event) {
        switch (event.key) {
        case Qt.Key_Up: prevZone(); event.accepted = true; break
        case Qt.Key_Down: nextZone(); event.accepted = true; break
        case Qt.Key_Left: requestNavFocus(); event.accepted = true; break
        case Qt.Key_Return:
        case Qt.Key_Enter:
            clearSearch(); event.accepted = true; break
        }
    }

    function handleSearchResultsKeys(event) {
        var cols = Math.max(1, Math.floor((mainFlickable.width - 80) / 220))
        var count = searchResults.length
        var idx = searchResultFocusIndex

        switch (event.key) {
        case Qt.Key_Left:
            if (idx % cols === 0) requestNavFocus()
            else searchResultFocusIndex = idx - 1
            event.accepted = true; break
        case Qt.Key_Right:
            if (idx < count - 1) searchResultFocusIndex = idx + 1
            event.accepted = true; break
        case Qt.Key_Up:
            if (idx - cols < 0) prevZone()
            else searchResultFocusIndex = idx - cols
            event.accepted = true; break
        case Qt.Key_Down:
            if (idx + cols < count) searchResultFocusIndex = idx + cols
            event.accepted = true; break
        case Qt.Key_Return:
        case Qt.Key_Enter:
            if (idx >= 0 && idx < count) detailPopup.open(searchResults[idx])
            event.accepted = true; break
        }
    }

    // Auto-scroll horizontal ListViews to show focused card
    onNewReleaseFocusIndexChanged: if (newReleasesList.visible) newReleasesList.positionViewAtIndex(newReleaseFocusIndex, ListView.Contain)
    onTopRatedFocusIndexChanged: if (topRatedList.visible) topRatedList.positionViewAtIndex(topRatedFocusIndex, ListView.Contain)
    onDealsFocusIndexChanged: if (dealsList.visible) dealsList.positionViewAtIndex(dealsFocusIndex, ListView.Contain)
    onTrendingFocusIndexChanged: if (trendingList.visible) trendingList.positionViewAtIndex(trendingFocusIndex, ListView.Contain)

    // Scroll focused items into view
    onNavZoneChanged: if (hasKeyboardFocus) ensureZoneVisible()

    function ensureZoneVisible() {
        var targetY = -1
        var targetH = 0
        switch (navZone) {
        case "hero": targetY = heroBanner.y; targetH = heroBanner.height; break
        case "newReleases": targetY = newReleasesSection.y; targetH = newReleasesSection.height; break
        case "topRated": targetY = topRatedSection.y; targetH = topRatedSection.height; break
        case "deals": targetY = dealsSection.y; targetH = dealsSection.height; break
        case "trending": targetY = trendingSection.y; targetH = trendingSection.height; break
        case "loadMore": targetY = loadMoreBtn.y; targetH = loadMoreBtn.height; break
        default: mainFlickable.contentY = 0; return
        }
        if (targetY < 0) return
        var viewTop = mainFlickable.contentY
        var viewBottom = viewTop + mainFlickable.height
        if (targetY < viewTop) mainFlickable.contentY = Math.max(0, targetY - 20)
        else if (targetY + targetH > viewBottom) mainFlickable.contentY = targetY + targetH - mainFlickable.height + 20
    }

    // Network check
    Timer {
        id: storeNetworkCheck
        interval: 3000
        running: storePage.visible
        repeat: true
        onTriggered: {
            var wasOffline = !storePage.hasNetwork
            storePage.hasNetwork = GameManager.isNetworkAvailable()
            if (wasOffline && storePage.hasNetwork) loadAllData()
        }
    }

    function loadAllData() {
        loadingFeatured = true
        loadingNewReleases = true
        loadingTopRated = true
        loadingTopDeals = true
        loadingRecentDeals = true
        StoreApi.fetchIGDBFeatured()
        StoreApi.fetchIGDBNewReleases()
        StoreApi.fetchIGDBTopRated()
        StoreApi.fetchDeals("Deal Rating", 0, 20)
        StoreApi.fetchRecentDeals(20)
    }

    Component.onCompleted: {
        hasNetwork = GameManager.isNetworkAvailable()
        if (hasNetwork) loadAllData()
    }

    // ─── API Connections ───
    Connections {
        target: StoreApi

        function onIgdbFeaturedReady(games) {
            storePage.featuredGames = games
            storePage.loadingFeatured = false
        }
        function onIgdbFeaturedError(error) {
            storePage.loadingFeatured = false
            console.warn("IGDB featured failed:", error)
        }
        function onIgdbNewReleasesReady(games) {
            storePage.newReleases = games
            storePage.loadingNewReleases = false
        }
        function onIgdbNewReleasesError(error) {
            storePage.loadingNewReleases = false
        }
        function onIgdbTopRatedReady(games) {
            storePage.topRated = games
            storePage.loadingTopRated = false
        }
        function onIgdbTopRatedError(error) {
            storePage.loadingTopRated = false
        }
        function onDealsReady(deals) {
            if (storePage.isSearching) return
            if (storePage.appendNextDeals) {
                storePage.topDeals = storePage.topDeals.concat(deals)
                storePage.appendNextDeals = false
            } else {
                storePage.topDeals = deals
            }
            storePage.loadingTopDeals = false
        }
        function onDealsError(error) {
            storePage.loadingTopDeals = false
            storePage.appendNextDeals = false
        }
        function onRecentDealsReady(deals) {
            storePage.recentDeals = deals
            storePage.loadingRecentDeals = false
        }
        function onRecentDealsError(error) {
            storePage.loadingRecentDeals = false
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
            font.pixelSize: 44
            font.family: ThemeManager.getFont("heading")
            font.bold: true
            color: ThemeManager.getColor("textPrimary")
            Layout.alignment: Qt.AlignHCenter
        }

        Text {
            text: "Connect to the internet to browse games"
            font.pixelSize: 26
            font.family: ThemeManager.getFont("body")
            color: ThemeManager.getColor("textSecondary")
            Layout.alignment: Qt.AlignHCenter
        }
    }

    // ═══════════════════════════════════════════
    // ─── MAIN LAYOUT ───
    // ═══════════════════════════════════════════
    ColumnLayout {
        anchors.fill: parent
        spacing: 0
        visible: storePage.hasNetwork

        // ─── Search Bar (Apple-style pill) ───
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 72
            Layout.leftMargin: 40
            Layout.rightMargin: 40

            Rectangle {
                id: searchBarBg
                anchors.centerIn: parent
                width: Math.min(parent.width, 680)
                height: 52
                radius: 26
                color: Qt.rgba(ThemeManager.getColor("surface").r,
                               ThemeManager.getColor("surface").g,
                               ThemeManager.getColor("surface").b, 0.85)
                border.color: (searchInput.activeFocus || (hasKeyboardFocus && navZone === "searchBar"))
                              ? ThemeManager.getColor("focus")
                              : Qt.rgba(ThemeManager.getColor("surface").r,
                                       ThemeManager.getColor("surface").g,
                                       ThemeManager.getColor("surface").b, 0.5)
                border.width: (searchInput.activeFocus || (hasKeyboardFocus && navZone === "searchBar")) ? 2 : 1
                Behavior on border.color { ColorAnimation { duration: 150 } }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 22
                    anchors.rightMargin: 22
                    spacing: 12

                    Text {
                        text: "\u2315"
                        font.pixelSize: 26
                        color: ThemeManager.getColor("textSecondary")
                        opacity: 0.6
                    }

                    TextInput {
                        id: searchInput
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        verticalAlignment: TextInput.AlignVCenter
                        font.pixelSize: 24
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

                    Text {
                        visible: searchInput.text === "" && !searchInput.activeFocus
                        text: "Search games..."
                        font.pixelSize: 24
                        font.family: ThemeManager.getFont("body")
                        color: ThemeManager.getColor("textSecondary")
                        opacity: 0.5
                        anchors.verticalCenter: parent.verticalCenter
                        x: searchInput.x
                    }

                    Rectangle {
                        visible: searchInput.text.length > 0
                        Layout.preferredWidth: 36
                        Layout.preferredHeight: 36
                        radius: 18
                        color: clearSearchArea.containsMouse ? ThemeManager.getColor("hover") : "transparent"

                        Text {
                            anchors.centerIn: parent
                            text: "\u2715"
                            font.pixelSize: 20
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
        }

        // ─── Content Area ───
        Flickable {
            id: mainFlickable
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentHeight: mainContent.height
            clip: true
            flickableDirection: Flickable.VerticalFlick
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

            ColumnLayout {
                id: mainContent
                width: mainFlickable.width
                spacing: 0

                // ═══════════════════════════════
                // Search Results Mode
                // ═══════════════════════════════
                ColumnLayout {
                    visible: storePage.isSearching
                    Layout.fillWidth: true
                    Layout.leftMargin: 40
                    Layout.rightMargin: 40
                    Layout.topMargin: 16
                    spacing: 20

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 16

                        Text {
                            text: loadingSearch ? "Searching..." : "Results for \u201C" + searchQuery + "\u201D"
                            font.pixelSize: 36
                            font.family: ThemeManager.getFont("heading")
                            font.bold: true
                            color: ThemeManager.getColor("textPrimary")
                        }

                        Text {
                            visible: !loadingSearch && searchResults.length > 0
                            text: searchResults.length + " games"
                            font.pixelSize: 22
                            font.family: ThemeManager.getFont("body")
                            color: ThemeManager.getColor("textSecondary")
                        }

                        Item { Layout.fillWidth: true }

                        Rectangle {
                            property bool isKbFocused: hasKeyboardFocus && navZone === "backToStore"
                            Layout.preferredWidth: backLabel.width + 36
                            Layout.preferredHeight: 44
                            radius: 22
                            color: (backBtnArea.containsMouse || isKbFocused)
                                   ? ThemeManager.getColor("hover") : ThemeManager.getColor("surface")
                            border.color: isKbFocused ? ThemeManager.getColor("focus") : "transparent"
                            border.width: isKbFocused ? 2 : 0

                            Text {
                                id: backLabel
                                anchors.centerIn: parent
                                text: "Back to Store"
                                font.pixelSize: 22
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

                    // Loading
                    Item {
                        visible: loadingSearch
                        Layout.fillWidth: true
                        Layout.preferredHeight: 200
                        Layout.alignment: Qt.AlignHCenter

                        ColumnLayout {
                            anchors.centerIn: parent
                            spacing: 16

                            Item {
                                Layout.alignment: Qt.AlignHCenter
                                Layout.preferredWidth: 56
                                Layout.preferredHeight: 56

                                Rectangle {
                                    anchors.centerIn: parent; width: 56; height: 56; radius: 28
                                    color: "transparent"; border.width: 4; border.color: Qt.rgba(1, 1, 1, 0.08)

                                    Rectangle {
                                        width: 56; height: 56; radius: 28
                                        color: "transparent"; border.width: 4; border.color: "transparent"

                                        Rectangle {
                                            width: 14; height: 4; radius: 2
                                            color: ThemeManager.getColor("primary")
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            anchors.top: parent.top
                                        }

                                        RotationAnimation on rotation {
                                            from: 0; to: 360; duration: 1000
                                            loops: Animation.Infinite; running: loadingSearch
                                        }
                                    }
                                }
                            }

                            Text {
                                Layout.alignment: Qt.AlignHCenter
                                text: "Searching IGDB..."
                                font.pixelSize: 24
                                font.family: ThemeManager.getFont("body")
                                color: ThemeManager.getColor("textSecondary")
                            }
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

                    // Search results grid (portrait cards)
                    Flow {
                        visible: !loadingSearch && searchResults.length > 0
                        Layout.fillWidth: true
                        spacing: 20

                        Repeater {
                            model: searchResults

                            StoreGameCard {
                                width: 200
                                height: 340
                                gameTitle: modelData.title || ""
                                coverImage: modelData.coverUrl || ""
                                headerImage: modelData.headerImage || modelData.heroImage || ""
                                genres: modelData.genres || ""
                                developer: modelData.developer || ""
                                salePrice: modelData.salePrice || modelData.cheapestPrice || ""
                                normalPrice: modelData.normalPrice || ""
                                savings: modelData.savings || ""
                                metacriticScore: modelData.metacriticScore || ""
                                steamRatingText: modelData.steamRatingText || ""
                                steamAppID: modelData.steamAppID || ""
                                gameID: modelData.cheapSharkGameID || ""
                                rating: modelData.rating || 0
                                isKeyboardFocused: hasKeyboardFocus && navZone === "searchResults" && searchResultFocusIndex === index

                                onClicked: detailPopup.open(modelData)
                            }
                        }
                    }

                    Item { Layout.preferredHeight: 32 }
                }

                // ═══════════════════════════════
                // Normal Store Mode (IGDB-first)
                // ═══════════════════════════════

                // ─── Hero Banner (Featured IGDB Game) ───
                Rectangle {
                    id: heroBanner
                    visible: !storePage.isSearching && (featuredGames.length > 0 || loadingFeatured)
                    Layout.fillWidth: true
                    Layout.preferredHeight: 480
                    Layout.leftMargin: 40
                    Layout.rightMargin: 40
                    Layout.topMargin: 8
                    radius: 24
                    clip: true
                    color: ThemeManager.getColor("surface")
                    border.color: (hasKeyboardFocus && navZone === "hero")
                                  ? ThemeManager.getColor("focus") : "transparent"
                    border.width: (hasKeyboardFocus && navZone === "hero") ? 3 : 0
                    Behavior on border.color { ColorAnimation { duration: 150 } }

                    property var featuredGame: featuredGames.length > 0 ? featuredGames[0] : null
                    property int featuredIndex: 0

                    Timer {
                        id: heroRotateTimer
                        interval: 7000
                        running: !storePage.isSearching && featuredGames.length > 1 && storePage.visible
                        repeat: true
                        onTriggered: {
                            heroBanner.featuredIndex = (heroBanner.featuredIndex + 1) % Math.min(featuredGames.length, 5)
                            heroBanner.featuredGame = featuredGames[heroBanner.featuredIndex]
                        }
                    }

                    // Background artwork/screenshot (IGDB)
                    Image {
                        id: heroImage
                        anchors.fill: parent
                        source: heroBanner.featuredGame
                                ? (heroBanner.featuredGame.heroImage || heroBanner.featuredGame.headerImage || "")
                                : ""
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        cache: true
                        opacity: status === Image.Ready ? 1.0 : 0.0
                        Behavior on opacity { NumberAnimation { duration: 600 } }
                    }

                    // Left gradient for text readability
                    Rectangle {
                        anchors.fill: parent
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, 0.88) }
                            GradientStop { position: 0.45; color: Qt.rgba(0, 0, 0, 0.4) }
                            GradientStop { position: 1.0; color: "transparent" }
                        }
                    }

                    // Bottom gradient
                    Rectangle {
                        anchors.fill: parent
                        gradient: Gradient {
                            GradientStop { position: 0.0; color: "transparent" }
                            GradientStop { position: 0.75; color: Qt.rgba(0, 0, 0, 0.3) }
                            GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.7) }
                        }
                    }

                    // Featured content
                    ColumnLayout {
                        anchors.left: parent.left
                        anchors.bottom: parent.bottom
                        anchors.leftMargin: 48
                        anchors.bottomMargin: 44
                        anchors.right: parent.horizontalCenter
                        spacing: 12

                        // "Featured" pill badge
                        Rectangle {
                            Layout.preferredWidth: featuredLabel.width + 28
                            Layout.preferredHeight: 34
                            radius: 17
                            color: ThemeManager.getColor("primary")

                            Text {
                                id: featuredLabel
                                anchors.centerIn: parent
                                text: "FEATURED"
                                font.pixelSize: 18
                                font.family: ThemeManager.getFont("ui")
                                font.bold: true
                                color: "#ffffff"
                                font.letterSpacing: 1.5
                            }
                        }

                        // Title
                        Text {
                            text: heroBanner.featuredGame ? heroBanner.featuredGame.title : ""
                            font.pixelSize: 52
                            font.family: ThemeManager.getFont("heading")
                            font.bold: true
                            color: "#ffffff"
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }

                        // Developer + Genre subtitle
                        Text {
                            visible: heroBanner.featuredGame !== null
                            text: {
                                if (!heroBanner.featuredGame) return ""
                                var parts = []
                                if (heroBanner.featuredGame.developer) parts.push(heroBanner.featuredGame.developer)
                                if (heroBanner.featuredGame.genres) parts.push(heroBanner.featuredGame.genres)
                                return parts.join("  \u2022  ")
                            }
                            font.pixelSize: 22
                            font.family: ThemeManager.getFont("body")
                            color: Qt.rgba(1, 1, 1, 0.7)
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }

                        // Rating + Release date
                        RowLayout {
                            spacing: 16
                            visible: heroBanner.featuredGame !== null

                            // Star rating
                            Row {
                                visible: heroBanner.featuredGame && heroBanner.featuredGame.rating > 0
                                spacing: 6

                                Text {
                                    text: "\u2605"
                                    font.pixelSize: 22
                                    color: "#fbbf24"
                                    anchors.verticalCenter: parent.verticalCenter
                                }

                                Text {
                                    text: heroBanner.featuredGame ? Math.round(heroBanner.featuredGame.rating) : ""
                                    font.pixelSize: 22
                                    font.family: ThemeManager.getFont("ui")
                                    font.bold: true
                                    color: "#ffffff"
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }

                            Text {
                                visible: heroBanner.featuredGame && heroBanner.featuredGame.releaseDate
                                text: heroBanner.featuredGame ? (heroBanner.featuredGame.releaseDate || "") : ""
                                font.pixelSize: 22
                                font.family: ThemeManager.getFont("ui")
                                color: Qt.rgba(1, 1, 1, 0.5)
                            }
                        }

                        // "View Game" button
                        Rectangle {
                            Layout.preferredWidth: viewBtnLabel.width + 48
                            Layout.preferredHeight: 48
                            Layout.topMargin: 6
                            radius: 24
                            color: heroViewArea.containsMouse
                                   ? Qt.lighter(ThemeManager.getColor("primary"), 1.15)
                                   : ThemeManager.getColor("primary")
                            Behavior on color { ColorAnimation { duration: 150 } }

                            Text {
                                id: viewBtnLabel
                                anchors.centerIn: parent
                                text: "View Game"
                                font.pixelSize: 22
                                font.family: ThemeManager.getFont("ui")
                                font.bold: true
                                color: "#ffffff"
                            }

                            MouseArea {
                                id: heroViewArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (heroBanner.featuredGame)
                                        detailPopup.open(heroBanner.featuredGame)
                                }
                            }
                        }
                    }

                    // Navigation dots
                    Row {
                        anchors.bottom: parent.bottom
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottomMargin: 20
                        spacing: 10
                        visible: featuredGames.length > 1

                        Repeater {
                            model: Math.min(featuredGames.length, 5)

                            Rectangle {
                                width: heroBanner.featuredIndex === index ? 32 : 10
                                height: 10
                                radius: 5
                                color: heroBanner.featuredIndex === index
                                       ? "#ffffff" : Qt.rgba(1, 1, 1, 0.35)
                                Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                                Behavior on color { ColorAnimation { duration: 200 } }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        heroBanner.featuredIndex = index
                                        heroBanner.featuredGame = featuredGames[index]
                                        heroRotateTimer.restart()
                                    }
                                }
                            }
                        }
                    }

                    // Click overlay
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        z: -1
                        onClicked: {
                            if (heroBanner.featuredGame) detailPopup.open(heroBanner.featuredGame)
                        }
                    }
                }

                // Hero loading placeholder
                Rectangle {
                    visible: !storePage.isSearching && loadingFeatured && featuredGames.length === 0
                    Layout.fillWidth: true
                    Layout.preferredHeight: 480
                    Layout.leftMargin: 40
                    Layout.rightMargin: 40
                    Layout.topMargin: 8
                    radius: 24
                    color: ThemeManager.getColor("surface")

                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: 16

                        Item {
                            Layout.alignment: Qt.AlignHCenter
                            Layout.preferredWidth: 56; Layout.preferredHeight: 56

                            Rectangle {
                                anchors.centerIn: parent; width: 56; height: 56; radius: 28
                                color: "transparent"; border.width: 4; border.color: Qt.rgba(1, 1, 1, 0.06)

                                Rectangle {
                                    width: 56; height: 56; radius: 28
                                    color: "transparent"; border.width: 4; border.color: "transparent"
                                    Rectangle { width: 14; height: 4; radius: 2; color: ThemeManager.getColor("primary"); anchors.horizontalCenter: parent.horizontalCenter; anchors.top: parent.top }
                                    RotationAnimation on rotation { from: 0; to: 360; duration: 1000; loops: Animation.Infinite; running: loadingFeatured }
                                }
                            }
                        }

                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: "Discovering games..."
                            font.pixelSize: 24; font.family: ThemeManager.getFont("body")
                            color: ThemeManager.getColor("textSecondary")
                        }
                    }
                }

                // ─── New & Noteworthy (IGDB New Releases) ───
                ColumnLayout {
                    id: newReleasesSection
                    visible: !storePage.isSearching && (newReleases.length > 0 || loadingNewReleases)
                    Layout.fillWidth: true
                    Layout.topMargin: 40
                    spacing: 16

                    // Section header
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.leftMargin: 40
                        Layout.rightMargin: 40
                        spacing: 0

                        Text {
                            text: "New & Noteworthy"
                            font.pixelSize: 34
                            font.family: ThemeManager.getFont("heading")
                            font.bold: true
                            color: ThemeManager.getColor("textPrimary")
                        }

                        Item { Layout.fillWidth: true }

                        // Scroll arrows
                        Row {
                            spacing: 8

                            Rectangle {
                                width: 44; height: 44; radius: 22
                                color: nrLeftArea.containsMouse ? ThemeManager.getColor("hover") : ThemeManager.getColor("surface")
                                Text { anchors.centerIn: parent; text: "\u276E"; font.pixelSize: 20; font.bold: true; color: ThemeManager.getColor("textSecondary") }
                                MouseArea { id: nrLeftArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: newReleasesList.flick(600, 0) }
                            }
                            Rectangle {
                                width: 44; height: 44; radius: 22
                                color: nrRightArea.containsMouse ? ThemeManager.getColor("hover") : ThemeManager.getColor("surface")
                                Text { anchors.centerIn: parent; text: "\u276F"; font.pixelSize: 20; font.bold: true; color: ThemeManager.getColor("textSecondary") }
                                MouseArea { id: nrRightArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: newReleasesList.flick(-600, 0) }
                            }
                        }
                    }

                    // Loading placeholder
                    Item {
                        visible: loadingNewReleases && newReleases.length === 0
                        Layout.fillWidth: true
                        Layout.preferredHeight: 340

                        Text {
                            anchors.centerIn: parent
                            text: "Loading new releases..."
                            font.pixelSize: 22; font.family: ThemeManager.getFont("body")
                            color: ThemeManager.getColor("textSecondary")
                        }
                    }

                    ListView {
                        id: newReleasesList
                        visible: newReleases.length > 0
                        Layout.fillWidth: true
                        Layout.preferredHeight: 340
                        Layout.leftMargin: 40
                        orientation: ListView.Horizontal
                        spacing: 20
                        clip: true
                        model: newReleases
                        boundsBehavior: Flickable.StopAtBounds

                        delegate: StoreGameCard {
                            width: 200
                            height: 340
                            gameTitle: modelData.title || ""
                            coverImage: modelData.coverUrl || ""
                            headerImage: modelData.headerImage || ""
                            genres: modelData.genres || ""
                            developer: modelData.developer || ""
                            salePrice: modelData.salePrice || modelData.cheapestPrice || ""
                            normalPrice: modelData.normalPrice || ""
                            savings: modelData.savings || ""
                            rating: modelData.rating || 0
                            isKeyboardFocused: hasKeyboardFocus && navZone === "newReleases" && newReleaseFocusIndex === index
                            onClicked: detailPopup.open(modelData)
                        }
                    }
                }

                // ─── Top Rated (IGDB Aggregated Rating) ───
                ColumnLayout {
                    id: topRatedSection
                    visible: !storePage.isSearching && (topRated.length > 0 || loadingTopRated)
                    Layout.fillWidth: true
                    Layout.topMargin: 40
                    spacing: 16

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.leftMargin: 40
                        Layout.rightMargin: 40
                        spacing: 0

                        Text {
                            text: "Top Rated"
                            font.pixelSize: 34
                            font.family: ThemeManager.getFont("heading")
                            font.bold: true
                            color: ThemeManager.getColor("textPrimary")
                        }

                        Item { Layout.fillWidth: true }

                        Row {
                            spacing: 8
                            Rectangle {
                                width: 44; height: 44; radius: 22
                                color: trLeftArea.containsMouse ? ThemeManager.getColor("hover") : ThemeManager.getColor("surface")
                                Text { anchors.centerIn: parent; text: "\u276E"; font.pixelSize: 20; font.bold: true; color: ThemeManager.getColor("textSecondary") }
                                MouseArea { id: trLeftArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: topRatedList.flick(600, 0) }
                            }
                            Rectangle {
                                width: 44; height: 44; radius: 22
                                color: trRightArea.containsMouse ? ThemeManager.getColor("hover") : ThemeManager.getColor("surface")
                                Text { anchors.centerIn: parent; text: "\u276F"; font.pixelSize: 20; font.bold: true; color: ThemeManager.getColor("textSecondary") }
                                MouseArea { id: trRightArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: topRatedList.flick(-600, 0) }
                            }
                        }
                    }

                    Item {
                        visible: loadingTopRated && topRated.length === 0
                        Layout.fillWidth: true; Layout.preferredHeight: 340
                        Text { anchors.centerIn: parent; text: "Loading top rated..."; font.pixelSize: 22; font.family: ThemeManager.getFont("body"); color: ThemeManager.getColor("textSecondary") }
                    }

                    ListView {
                        id: topRatedList
                        visible: topRated.length > 0
                        Layout.fillWidth: true
                        Layout.preferredHeight: 340
                        Layout.leftMargin: 40
                        orientation: ListView.Horizontal
                        spacing: 20
                        clip: true
                        model: topRated
                        boundsBehavior: Flickable.StopAtBounds

                        delegate: StoreGameCard {
                            width: 200; height: 340
                            gameTitle: modelData.title || ""
                            coverImage: modelData.coverUrl || ""
                            headerImage: modelData.headerImage || ""
                            genres: modelData.genres || ""
                            developer: modelData.developer || ""
                            salePrice: modelData.salePrice || ""
                            normalPrice: modelData.normalPrice || ""
                            savings: modelData.savings || ""
                            rating: modelData.rating || modelData.aggregatedRating || 0
                            isKeyboardFocused: hasKeyboardFocus && navZone === "topRated" && topRatedFocusIndex === index
                            onClicked: detailPopup.open(modelData)
                        }
                    }
                }

                // ─── Best Deals (CheapShark) ───
                ColumnLayout {
                    id: dealsSection
                    visible: !storePage.isSearching && (topDeals.length > 0 || loadingTopDeals)
                    Layout.fillWidth: true
                    Layout.topMargin: 40
                    spacing: 16

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.leftMargin: 40
                        Layout.rightMargin: 40
                        spacing: 0

                        Text {
                            text: "Best Deals"
                            font.pixelSize: 34
                            font.family: ThemeManager.getFont("heading")
                            font.bold: true
                            color: ThemeManager.getColor("textPrimary")
                        }

                        Item { Layout.fillWidth: true }

                        Row {
                            spacing: 8
                            Rectangle {
                                width: 44; height: 44; radius: 22
                                color: dlLeftArea.containsMouse ? ThemeManager.getColor("hover") : ThemeManager.getColor("surface")
                                Text { anchors.centerIn: parent; text: "\u276E"; font.pixelSize: 20; font.bold: true; color: ThemeManager.getColor("textSecondary") }
                                MouseArea { id: dlLeftArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: dealsList.flick(600, 0) }
                            }
                            Rectangle {
                                width: 44; height: 44; radius: 22
                                color: dlRightArea.containsMouse ? ThemeManager.getColor("hover") : ThemeManager.getColor("surface")
                                Text { anchors.centerIn: parent; text: "\u276F"; font.pixelSize: 20; font.bold: true; color: ThemeManager.getColor("textSecondary") }
                                MouseArea { id: dlRightArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: dealsList.flick(-600, 0) }
                            }
                        }
                    }

                    Item {
                        visible: loadingTopDeals && topDeals.length === 0
                        Layout.fillWidth: true; Layout.preferredHeight: 340
                        Text { anchors.centerIn: parent; text: "Loading deals..."; font.pixelSize: 22; font.family: ThemeManager.getFont("body"); color: ThemeManager.getColor("textSecondary") }
                    }

                    ListView {
                        id: dealsList
                        visible: topDeals.length > 0
                        Layout.fillWidth: true
                        Layout.preferredHeight: 340
                        Layout.leftMargin: 40
                        orientation: ListView.Horizontal
                        spacing: 20
                        clip: true
                        model: topDeals
                        boundsBehavior: Flickable.StopAtBounds

                        delegate: StoreGameCard {
                            width: 200; height: 340
                            gameTitle: modelData.title || ""
                            coverImage: modelData.capsuleImage || ""
                            headerImage: modelData.headerImage || modelData.thumb || ""
                            salePrice: modelData.salePrice || ""
                            normalPrice: modelData.normalPrice || ""
                            savings: modelData.savings || ""
                            metacriticScore: modelData.metacriticScore || ""
                            steamRatingText: modelData.steamRatingText || ""
                            steamAppID: modelData.steamAppID || ""
                            gameID: modelData.gameID || ""
                            isKeyboardFocused: hasKeyboardFocus && navZone === "deals" && dealsFocusIndex === index
                            onClicked: detailPopup.open(modelData)
                        }
                    }
                }

                // ─── Trending Now (Recent Deals) ───
                ColumnLayout {
                    id: trendingSection
                    visible: !storePage.isSearching && recentDeals.length > 0
                    Layout.fillWidth: true
                    Layout.topMargin: 40
                    spacing: 16

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.leftMargin: 40
                        Layout.rightMargin: 40
                        spacing: 0

                        Text {
                            text: "Trending Now"
                            font.pixelSize: 34
                            font.family: ThemeManager.getFont("heading")
                            font.bold: true
                            color: ThemeManager.getColor("textPrimary")
                        }

                        Item { Layout.fillWidth: true }

                        Row {
                            spacing: 8
                            Rectangle {
                                width: 44; height: 44; radius: 22
                                color: tLeftArea.containsMouse ? ThemeManager.getColor("hover") : ThemeManager.getColor("surface")
                                Text { anchors.centerIn: parent; text: "\u276E"; font.pixelSize: 20; font.bold: true; color: ThemeManager.getColor("textSecondary") }
                                MouseArea { id: tLeftArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: trendingList.flick(600, 0) }
                            }
                            Rectangle {
                                width: 44; height: 44; radius: 22
                                color: tRightArea.containsMouse ? ThemeManager.getColor("hover") : ThemeManager.getColor("surface")
                                Text { anchors.centerIn: parent; text: "\u276F"; font.pixelSize: 20; font.bold: true; color: ThemeManager.getColor("textSecondary") }
                                MouseArea { id: tRightArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: trendingList.flick(-600, 0) }
                            }
                        }
                    }

                    ListView {
                        id: trendingList
                        Layout.fillWidth: true
                        Layout.preferredHeight: 340
                        Layout.leftMargin: 40
                        orientation: ListView.Horizontal
                        spacing: 20
                        clip: true
                        model: recentDeals
                        boundsBehavior: Flickable.StopAtBounds

                        delegate: StoreGameCard {
                            width: 200; height: 340
                            gameTitle: modelData.title || ""
                            coverImage: modelData.capsuleImage || ""
                            headerImage: modelData.headerImage || modelData.thumb || ""
                            salePrice: modelData.salePrice || ""
                            normalPrice: modelData.normalPrice || ""
                            savings: modelData.savings || ""
                            metacriticScore: modelData.metacriticScore || ""
                            steamAppID: modelData.steamAppID || ""
                            isKeyboardFocused: hasKeyboardFocus && navZone === "trending" && trendingFocusIndex === index
                            onClicked: detailPopup.open(modelData)
                        }
                    }
                }

                // ─── Load More ───
                Rectangle {
                    id: loadMoreBtn
                    property bool isKbFocused: hasKeyboardFocus && navZone === "loadMore"
                    visible: !storePage.isSearching && topDeals.length > 0
                    Layout.alignment: Qt.AlignHCenter
                    Layout.preferredWidth: loadMoreLabel.width + 56
                    Layout.preferredHeight: 48
                    Layout.topMargin: 32
                    radius: 24
                    color: (loadMoreArea.containsMouse || isKbFocused)
                           ? ThemeManager.getColor("primary")
                           : "transparent"
                    border.color: (loadMoreArea.containsMouse || isKbFocused)
                                  ? ThemeManager.getColor("primary")
                                  : Qt.rgba(ThemeManager.getColor("primary").r,
                                            ThemeManager.getColor("primary").g,
                                            ThemeManager.getColor("primary").b, 0.4)
                    border.width: 2
                    Behavior on color { ColorAnimation { duration: 200 } }

                    Text {
                        id: loadMoreLabel
                        anchors.centerIn: parent
                        text: "Load More Deals"
                        font.pixelSize: 22
                        font.family: ThemeManager.getFont("ui")
                        font.bold: true
                        color: (loadMoreArea.containsMouse || loadMoreBtn.isKbFocused)
                               ? "#ffffff" : ThemeManager.getColor("textPrimary")
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
                            StoreApi.fetchDeals("Deal Rating", currentPage, 30)
                        }
                    }
                }

                // ─── IGDB Status ───
                Rectangle {
                    visible: !storePage.isSearching && StoreApi.hasIGDBCredentials()
                    Layout.fillWidth: true
                    Layout.preferredHeight: 52
                    Layout.leftMargin: 40
                    Layout.rightMargin: 40
                    Layout.topMargin: 32
                    radius: 14
                    color: Qt.rgba(ThemeManager.getColor("surface").r,
                                   ThemeManager.getColor("surface").g,
                                   ThemeManager.getColor("surface").b, 0.5)

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 20
                        anchors.rightMargin: 20
                        spacing: 12

                        Rectangle { Layout.preferredWidth: 8; Layout.preferredHeight: 8; radius: 4; color: "#34c759" }

                        Text {
                            text: "Powered by IGDB"
                            font.pixelSize: 20
                            font.family: ThemeManager.getFont("ui")
                            font.bold: true
                            color: ThemeManager.getColor("textSecondary")
                            opacity: 0.7
                        }

                        Text {
                            text: "Game data, artwork, screenshots & ratings from IGDB.com"
                            font.pixelSize: 20
                            font.family: ThemeManager.getFont("body")
                            color: ThemeManager.getColor("textSecondary")
                            opacity: 0.5
                        }

                        Item { Layout.fillWidth: true }
                    }
                }

                // ─── IGDB Setup (no credentials) ───
                Rectangle {
                    visible: !storePage.isSearching && !StoreApi.hasIGDBCredentials()
                    Layout.fillWidth: true
                    Layout.preferredHeight: igdbSetupCol.height + 40
                    Layout.leftMargin: 40
                    Layout.rightMargin: 40
                    Layout.topMargin: 32
                    radius: 18
                    color: ThemeManager.getColor("surface")
                    border.color: Qt.rgba(ThemeManager.getColor("accent").r,
                                          ThemeManager.getColor("accent").g,
                                          ThemeManager.getColor("accent").b, 0.2)
                    border.width: 1

                    ColumnLayout {
                        id: igdbSetupCol
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 24
                        spacing: 14

                        RowLayout {
                            spacing: 14

                            Text {
                                text: "Connect IGDB"
                                font.pixelSize: 28
                                font.family: ThemeManager.getFont("heading")
                                font.bold: true
                                color: ThemeManager.getColor("textPrimary")
                            }

                            Rectangle {
                                Layout.preferredWidth: optLabel.width + 18
                                Layout.preferredHeight: 26
                                radius: 13
                                color: ThemeManager.getColor("accent")

                                Text {
                                    id: optLabel
                                    anchors.centerIn: parent
                                    text: "OPTIONAL"
                                    font.pixelSize: 16
                                    font.bold: true
                                    color: "#0a0a0a"
                                    font.letterSpacing: 0.8
                                }
                            }
                        }

                        Text {
                            text: "Add your Twitch developer credentials to enable IGDB-powered browsing " +
                                  "with game artwork, screenshots, ratings, and developer info. " +
                                  "Register at dev.twitch.tv"
                            font.pixelSize: 22
                            font.family: ThemeManager.getFont("body")
                            color: ThemeManager.getColor("textSecondary")
                            wrapMode: Text.WordWrap
                            Layout.fillWidth: true
                            lineHeight: 1.4
                        }

                        RowLayout {
                            spacing: 12

                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 48
                                radius: 24
                                color: ThemeManager.getColor("hover")
                                border.color: igdbClientIdInput.activeFocus ? ThemeManager.getColor("focus") : "transparent"
                                border.width: igdbClientIdInput.activeFocus ? 2 : 0

                                TextInput {
                                    id: igdbClientIdInput
                                    anchors.fill: parent
                                    anchors.margins: 16
                                    verticalAlignment: TextInput.AlignVCenter
                                    font.pixelSize: 22
                                    font.family: ThemeManager.getFont("body")
                                    color: ThemeManager.getColor("textPrimary")
                                    clip: true
                                }
                                Text {
                                    anchors.fill: parent; anchors.margins: 16
                                    verticalAlignment: Text.AlignVCenter
                                    visible: igdbClientIdInput.text === "" && !igdbClientIdInput.activeFocus
                                    text: "Client ID"
                                    font.pixelSize: 22; font.family: ThemeManager.getFont("body")
                                    color: ThemeManager.getColor("textSecondary"); opacity: 0.5
                                }
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 48
                                radius: 24
                                color: ThemeManager.getColor("hover")
                                border.color: igdbSecretInput.activeFocus ? ThemeManager.getColor("focus") : "transparent"
                                border.width: igdbSecretInput.activeFocus ? 2 : 0

                                TextInput {
                                    id: igdbSecretInput
                                    anchors.fill: parent
                                    anchors.margins: 16
                                    verticalAlignment: TextInput.AlignVCenter
                                    font.pixelSize: 22
                                    font.family: ThemeManager.getFont("body")
                                    color: ThemeManager.getColor("textPrimary")
                                    echoMode: TextInput.Password
                                    clip: true
                                }
                                Text {
                                    anchors.fill: parent; anchors.margins: 16
                                    verticalAlignment: Text.AlignVCenter
                                    visible: igdbSecretInput.text === "" && !igdbSecretInput.activeFocus
                                    text: "Client Secret"
                                    font.pixelSize: 22; font.family: ThemeManager.getFont("body")
                                    color: ThemeManager.getColor("textSecondary"); opacity: 0.5
                                }
                            }

                            Rectangle {
                                Layout.preferredWidth: saveBtnLabel.width + 44
                                Layout.preferredHeight: 48
                                radius: 24
                                color: (igdbClientIdInput.text.length > 0 && igdbSecretInput.text.length > 0)
                                       ? ThemeManager.getColor("primary") : ThemeManager.getColor("surface")

                                Text {
                                    id: saveBtnLabel
                                    anchors.centerIn: parent
                                    text: "Save"
                                    font.pixelSize: 22
                                    font.family: ThemeManager.getFont("ui")
                                    font.bold: true
                                    color: (igdbClientIdInput.text.length > 0 && igdbSecretInput.text.length > 0)
                                           ? "#ffffff" : ThemeManager.getColor("textSecondary")
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        if (igdbClientIdInput.text.length > 0 && igdbSecretInput.text.length > 0) {
                                            StoreApi.setIGDBCredentials(igdbClientIdInput.text.trim(), igdbSecretInput.text.trim())
                                            igdbClientIdInput.text = ""
                                            igdbSecretInput.text = ""
                                            loadAllData()
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // Bottom spacer
                Item { Layout.preferredHeight: 48 }
            }
        }
    }

    // ─── Detail Popup ───
    GameStoreDetailPopup {
        id: detailPopup
        anchors.fill: parent

        onOpenDealUrl: function(url, storeName) {
            storePage.storeBrowserTitle = storeName || "Store"
            storeBrowserWebView.url = url
            storePage.storeBrowserOpen = true
        }
    }

    // ─── Embedded Store Browser ───
    readonly property string navOverlayScript: "
(function() {
    if (window.__lunaNav) return;
    var nav = {};
    var currentIndex = 0;
    var elements = [];
    var highlightEl = null;

    var SELECTORS = 'a[href], button, input, select, textarea, '
        + '[role=\"button\"], [role=\"link\"], [role=\"menuitem\"], '
        + '[tabindex]:not([tabindex=\"-1\"]), [onclick]';

    function isVisible(el) {
        if (!el || !el.getBoundingClientRect) return false;
        var r = el.getBoundingClientRect();
        if (r.width === 0 || r.height === 0) return false;
        var style = window.getComputedStyle(el);
        return style.display !== 'none'
            && style.visibility !== 'hidden'
            && style.opacity !== '0';
    }

    function getVisualRect(el) {
        var rects = el.getClientRects();
        var r = el.getBoundingClientRect();
        if (rects.length > 1) {
            var best = rects[0];
            var bestArea = best.width * best.height;
            for (var i = 1; i < rects.length; i++) {
                var a = rects[i].width * rects[i].height;
                if (a > bestArea) { best = rects[i]; bestArea = a; }
            }
            r = best;
        }
        if ((r.width < 16 || r.height < 16) && el.parentElement) {
            var pr = el.parentElement.getBoundingClientRect();
            if (pr.width >= r.width && pr.height >= r.height
                && pr.width < 500 && pr.height < 120) {
                r = pr;
            }
        }
        return r;
    }

    function scanElements() {
        var all = document.querySelectorAll(SELECTORS);
        elements = [];
        for (var i = 0; i < all.length; i++) {
            if (isVisible(all[i])) elements.push(all[i]);
        }
        if (currentIndex >= elements.length) currentIndex = 0;
    }

    function createHighlight() {
        if (highlightEl) return;
        highlightEl = document.createElement('div');
        highlightEl.id = '__luna-highlight';
        highlightEl.style.cssText =
            'position:fixed; pointer-events:none; z-index:999999; '
            + 'border:3px solid #9b59b6; border-radius:6px; '
            + 'box-shadow:0 0 12px rgba(155,89,182,0.6), inset 0 0 8px rgba(155,89,182,0.2); '
            + 'transition:all 0.15s ease; display:none;';
        document.documentElement.appendChild(highlightEl);
    }

    function updateHighlight() {
        if (!highlightEl) createHighlight();
        if (elements.length === 0) { highlightEl.style.display = 'none'; return; }
        var el = elements[currentIndex];
        if (!el) return;
        var r = getVisualRect(el);
        var pad = 3;
        highlightEl.style.left   = (r.left - pad) + 'px';
        highlightEl.style.top    = (r.top - pad)  + 'px';
        highlightEl.style.width  = (r.width + pad * 2) + 'px';
        highlightEl.style.height = (r.height + pad * 2) + 'px';
        highlightEl.style.display = 'block';
        el.scrollIntoView({ block: 'nearest', behavior: 'smooth' });
    }

    function findNearest(direction) {
        if (elements.length < 2) return currentIndex;
        var cur = elements[currentIndex];
        if (!cur) return currentIndex;
        var cr = getVisualRect(cur);
        var cx = cr.left + cr.width / 2;
        var cy = cr.top + cr.height / 2;
        var bestIdx = -1;
        var bestDist = Infinity;
        for (var i = 0; i < elements.length; i++) {
            if (i === currentIndex) continue;
            var er = getVisualRect(elements[i]);
            var ex = er.left + er.width / 2;
            var ey = er.top + er.height / 2;
            var dx = ex - cx;
            var dy = ey - cy;
            var inDirection = false;
            switch (direction) {
                case 'up':    inDirection = dy < -5; break;
                case 'down':  inDirection = dy > 5;  break;
                case 'left':  inDirection = dx < -5; break;
                case 'right': inDirection = dx > 5;  break;
            }
            if (!inDirection) continue;
            var dist;
            if (direction === 'up' || direction === 'down') {
                dist = Math.abs(dy) + Math.abs(dx) * 2;
            } else {
                dist = Math.abs(dx) + Math.abs(dy) * 2;
            }
            if (dist < bestDist) { bestDist = dist; bestIdx = i; }
        }
        return bestIdx >= 0 ? bestIdx : currentIndex;
    }

    nav.move = function(direction) {
        scanElements();
        if (elements.length === 0) return 'no-elements';
        currentIndex = findNearest(direction);
        updateHighlight();
        return 'moved:' + direction + ' idx:' + currentIndex + '/' + elements.length;
    };

    nav.activate = function() {
        scanElements();
        if (elements.length === 0) return 'no-elements';
        var el = elements[currentIndex];
        if (!el) return 'no-element';
        el.focus();
        el.click();
        var tag = el.tagName.toLowerCase();
        var type = (el.getAttribute('type') || 'text').toLowerCase();
        if (tag === 'input' && (type === 'text' || type === 'password'
                || type === 'email' || type === 'search' || type === 'url'
                || type === 'tel' || type === 'number')
            || tag === 'textarea') {
            return 'input:' + type + ':' + (el.value || '');
        }
        return 'clicked:' + el.tagName + ' ' + (el.textContent||'').substring(0,40);
    };

    nav.setText = function(text) {
        var el = document.activeElement;
        if (!el) return 'no-active';
        var nativeSetter = Object.getOwnPropertyDescriptor(
            window.HTMLInputElement.prototype, 'value'
        );
        if (!nativeSetter) nativeSetter = Object.getOwnPropertyDescriptor(
            window.HTMLTextAreaElement.prototype, 'value'
        );
        if (nativeSetter && nativeSetter.set) {
            nativeSetter.set.call(el, text);
        } else {
            el.value = text;
        }
        el.dispatchEvent(new Event('input', { bubbles: true }));
        el.dispatchEvent(new Event('change', { bubbles: true }));
        return 'set:' + text.length + ' chars';
    };

    nav.scrollPage = function(direction) {
        window.scrollBy(0, direction === 'up' ? -400 : 400);
        return 'scrolled:' + direction;
    };

    var observer = new MutationObserver(function() {
        var oldLen = elements.length;
        scanElements();
        if (elements.length !== oldLen) updateHighlight();
    });
    observer.observe(document.body, { childList: true, subtree: true });

    scanElements();
    if (elements.length > 0) updateHighlight();
    window.__lunaNav = nav;
    return 'ready:' + elements.length;
})();
"

    Connections {
        target: ControllerManager
        enabled: storePage.storeBrowserOpen && !storeBrowserVK.visible
        function onActionTriggered(action) {
            function logResult(result) { console.log("[store-browser] nav:", result) }
            switch (action) {
            case "navigate_up":    storeBrowserWebView.runJavaScript("window.__lunaNav && window.__lunaNav.move('up')", logResult); break
            case "navigate_down":  storeBrowserWebView.runJavaScript("window.__lunaNav && window.__lunaNav.move('down')", logResult); break
            case "navigate_left":  storeBrowserWebView.runJavaScript("window.__lunaNav && window.__lunaNav.move('left')", logResult); break
            case "navigate_right": storeBrowserWebView.runJavaScript("window.__lunaNav && window.__lunaNav.move('right')", logResult); break
            case "confirm":
                storeBrowserWebView.runJavaScript("window.__lunaNav && window.__lunaNav.activate()", function(result) {
                    if (result && result.toString().indexOf("input:") === 0) {
                        var parts = result.toString().split(":")
                        var inputType = parts[1] || "text"
                        var currentVal = parts.slice(2).join(":")
                        storePage.storeBrowserInputActive = true
                        storeBrowserVK.placeholderText = (inputType === "password") ? "Enter password..." : "Type here..."
                        storeBrowserVK.open(currentVal, inputType === "password")
                    }
                })
                break
            case "scroll_up":  storeBrowserWebView.runJavaScript("window.__lunaNav && window.__lunaNav.scrollPage('up')", logResult); break
            case "scroll_down": storeBrowserWebView.runJavaScript("window.__lunaNav && window.__lunaNav.scrollPage('down')", logResult); break
            case "back": storePage.storeBrowserOpen = false; break
            }
        }
    }

    Rectangle {
        id: storeBrowserOverlay
        visible: storePage.storeBrowserOpen
        anchors.fill: parent
        z: 600
        color: ThemeManager.getColor("background")

        Rectangle {
            id: storeBrowserHeader
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: 50
            color: ThemeManager.getColor("surface")
            z: 1

            Text {
                anchors.centerIn: parent
                text: storePage.storeBrowserTitle
                font.pixelSize: ThemeManager.getFontSize("medium")
                font.bold: true
                font.family: ThemeManager.getFont("heading")
                color: ThemeManager.getColor("textPrimary")
            }

            Text {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: 14
                text: "B  Back"
                font.pixelSize: ThemeManager.getFontSize("small")
                font.family: ThemeManager.getFont("body")
                color: ThemeManager.getColor("textSecondary")
            }
        }

        WebEngineView {
            id: storeBrowserWebView
            anchors.top: storeBrowserHeader.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            url: "about:blank"
            profile: SharedBrowserProfile
            settings.focusOnNavigationEnabled: false

            onLoadingChanged: function(loadRequest) {
                if (loadRequest.status === WebEngineView.LoadSucceededStatus)
                    storeBrowserNavInjectTimer.restart()
            }
        }

        Timer {
            id: storeBrowserNavInjectTimer
            interval: 800
            repeat: false
            onTriggered: {
                storeBrowserWebView.runJavaScript(storePage.navOverlayScript, function(result) {})
            }
        }
    }

    // Virtual Keyboard for Store Browser
    VirtualKeyboard {
        id: storeBrowserVK
        anchors.fill: parent
        z: 700

        onAccepted: function(typedText) {
            if (storePage.storeBrowserInputActive) {
                storePage.storeBrowserInputActive = false
                var escaped = typedText.replace(/\\/g, '\\\\').replace(/'/g, "\\'")
                storeBrowserWebView.runJavaScript("window.__lunaNav && window.__lunaNav.setText('" + escaped + "')", function(r) {})
            }
            storePage.forceActiveFocus()
        }
        onCancelled: { storePage.storeBrowserInputActive = false; storePage.forceActiveFocus() }
    }

    // Virtual Keyboard for Search
    VirtualKeyboard {
        id: storeVirtualKeyboard
        anchors.fill: parent

        onAccepted: function(typedText) {
            searchInput.text = typedText
            if (typedText.trim().length > 0) {
                storePage.searchQuery = typedText.trim()
                storePage.isSearching = true
                storePage.loadingSearch = true
                StoreApi.searchGames(typedText.trim())
                navZone = "backToStore"
            }
            storePage.forceActiveFocus()
        }
        onCancelled: { navZone = "searchBar"; storePage.forceActiveFocus() }
    }

    function clearSearch() {
        searchInput.text = ""
        storePage.searchQuery = ""
        storePage.isSearching = false
        storePage.searchResults = []
    }
}
