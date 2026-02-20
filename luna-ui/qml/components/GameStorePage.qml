import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtWebEngine

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

    // ─── Embedded Store Browser ───
    property bool storeBrowserOpen: false
    property string storeBrowserTitle: ""
    property bool storeBrowserInputActive: false

    // Sort options
    property var sortOptions: [
        { label: "Best Deals",  value: "Deal Rating" },
        { label: "Lowest Price", value: "Price" },
        { label: "Highest Metacritic", value: "Metacritic" },
        { label: "Best Reviews", value: "Reviews" },
        { label: "Newest",      value: "recent" }
    ]

    // ─── Keyboard Navigation ───
    // Zones: "searchBar", "sortChips", "hero", "trending", "dealsGrid", "loadMore"
    // Search mode zones: "searchBar", "backToStore", "searchResults"
    property string navZone: ""
    property int sortChipFocusIndex: 0
    property int heroDotFocusIndex: 0
    property int trendingFocusIndex: 0
    property int dealGridFocusIndex: 0
    property int searchResultFocusIndex: 0
    property bool hasKeyboardFocus: false

    signal requestNavFocus()

    // Direct key handler — ensures controller events are processed
    // even if parent-chain propagation through Loader/StackLayout fails
    Keys.onPressed: function(event) {
        handleStoreKeys(event)
    }

    function gainFocus() {
        hasKeyboardFocus = true
        // Start at hero if available, else search bar
        if (isSearching) {
            navZone = "searchResults"
            searchResultFocusIndex = 0
        } else if (topDeals.length > 0) {
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

    // Navigate to the next zone down
    function nextZone() {
        if (isSearching) {
            switch (navZone) {
            case "searchBar": navZone = "backToStore"; break
            case "backToStore":
                if (searchResults.length > 0) { navZone = "searchResults"; searchResultFocusIndex = 0 }
                break
            case "searchResults": break // bottom
            }
        } else {
            switch (navZone) {
            case "searchBar": navZone = "sortChips"; sortChipFocusIndex = 0; break
            case "sortChips":
                if (topDeals.length > 0) { navZone = "hero"; heroDotFocusIndex = heroBanner.featuredIndex }
                break
            case "hero":
                if (recentDeals.length > 0) { navZone = "trending"; trendingFocusIndex = 0 }
                else if (topDeals.length > 1) { navZone = "dealsGrid"; dealGridFocusIndex = 0 }
                break
            case "trending":
                if (topDeals.length > 1 || (currentSort !== "Deal Rating" && topDeals.length > 0)) {
                    navZone = "dealsGrid"; dealGridFocusIndex = 0
                }
                break
            case "dealsGrid": navZone = "loadMore"; break
            case "loadMore": break // bottom
            }
        }
    }

    // Navigate to the previous zone up
    function prevZone() {
        if (isSearching) {
            switch (navZone) {
            case "searchBar": break // top — parent handles going to tab bar
            case "backToStore": navZone = "searchBar"; break
            case "searchResults": navZone = "backToStore"; break
            }
        } else {
            switch (navZone) {
            case "searchBar": break // top
            case "sortChips": navZone = "searchBar"; break
            case "hero":
                navZone = "sortChips"
                // Find the index of the currently active sort chip
                for (var i = 0; i < sortOptions.length; i++) {
                    if (sortOptions[i].value === currentSort) { sortChipFocusIndex = i; break }
                }
                break
            case "trending": navZone = "hero"; break
            case "dealsGrid":
                if (recentDeals.length > 0) navZone = "trending"
                else navZone = "hero"
                break
            case "loadMore": navZone = "dealsGrid"; break
            }
        }
    }

    function handleStoreKeys(event) {
        // If store browser is open, it handles input via Connections
        if (storeBrowserOpen) {
            event.accepted = true
            return
        }

        // If virtual keyboard is open, it handles its own keys
        if (storeVirtualKeyboard.visible) {
            event.accepted = true
            return
        }

        // If detail popup is open, let it handle keys
        if (detailPopup.visible) {
            detailPopup.handleKeys(event)
            event.accepted = true
            return
        }

        switch (navZone) {
        case "searchBar": handleSearchBarKeys(event); break
        case "sortChips": handleSortChipKeys(event); break
        case "hero": handleHeroKeys(event); break
        case "trending": handleTrendingKeys(event); break
        case "dealsGrid": handleDealsGridKeys(event); break
        case "loadMore": handleLoadMoreKeys(event); break
        case "backToStore": handleBackToStoreKeys(event); break
        case "searchResults": handleSearchResultsKeys(event); break
        }
    }

    function handleSearchBarKeys(event) {
        switch (event.key) {
        case Qt.Key_Left:
            requestNavFocus()
            event.accepted = true
            break
        case Qt.Key_Down:
            searchInput.focus = false
            nextZone()
            storePage.forceActiveFocus()
            event.accepted = true
            break
        case Qt.Key_Return:
        case Qt.Key_Enter:
            // Open virtual keyboard instead of focusing raw TextInput
            // (directly focusing TextInput freezes controller navigation)
            storeVirtualKeyboard.placeholderText = "Search games..."
            storeVirtualKeyboard.open(searchInput.text)
            event.accepted = true
            break
        }
    }

    function handleSortChipKeys(event) {
        switch (event.key) {
        case Qt.Key_Left:
            if (sortChipFocusIndex > 0) sortChipFocusIndex--
            else requestNavFocus()
            event.accepted = true
            break
        case Qt.Key_Right:
            if (sortChipFocusIndex < sortOptions.length - 1) sortChipFocusIndex++
            event.accepted = true
            break
        case Qt.Key_Up: prevZone(); event.accepted = true; break
        case Qt.Key_Down: nextZone(); event.accepted = true; break
        case Qt.Key_Return:
        case Qt.Key_Enter:
            var opt = sortOptions[sortChipFocusIndex]
            currentSort = opt.value
            currentPage = 0
            storePage.loadingTopDeals = true
            StoreApi.fetchDeals(opt.value, 0, 30)
            event.accepted = true
            break
        }
    }

    function handleHeroKeys(event) {
        var dotCount = Math.min(topDeals.length, 5)
        switch (event.key) {
        case Qt.Key_Left:
            if (heroDotFocusIndex > 0) {
                heroDotFocusIndex--
                heroBanner.featuredIndex = heroDotFocusIndex
                heroBanner.featuredDeal = topDeals[heroDotFocusIndex]
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
                heroBanner.featuredDeal = topDeals[heroDotFocusIndex]
                heroRotateTimer.restart()
            }
            event.accepted = true
            break
        case Qt.Key_Up: prevZone(); event.accepted = true; break
        case Qt.Key_Down: nextZone(); event.accepted = true; break
        case Qt.Key_Return:
        case Qt.Key_Enter:
            if (heroBanner.featuredDeal) detailPopup.open(heroBanner.featuredDeal)
            event.accepted = true
            break
        }
    }

    function handleTrendingKeys(event) {
        switch (event.key) {
        case Qt.Key_Left:
            if (trendingFocusIndex > 0) trendingFocusIndex--
            else requestNavFocus()
            event.accepted = true
            break
        case Qt.Key_Right:
            if (trendingFocusIndex < recentDeals.length - 1) trendingFocusIndex++
            event.accepted = true
            break
        case Qt.Key_Up: prevZone(); event.accepted = true; break
        case Qt.Key_Down: nextZone(); event.accepted = true; break
        case Qt.Key_Return:
        case Qt.Key_Enter:
            if (trendingFocusIndex >= 0 && trendingFocusIndex < recentDeals.length)
                detailPopup.open(recentDeals[trendingFocusIndex])
            event.accepted = true
            break
        }
    }

    function handleDealsGridKeys(event) {
        var gridDeals = (currentSort === "Deal Rating" && topDeals.length > 1) ? topDeals.slice(1) : topDeals
        var cols = Math.max(1, Math.floor(mainFlickable.width / (Math.floor((mainFlickable.width - 48) / 3) + 16)))
        if (cols < 1) cols = 3
        var count = gridDeals.length
        var idx = dealGridFocusIndex

        switch (event.key) {
        case Qt.Key_Left:
            if (idx % cols === 0) requestNavFocus()
            else dealGridFocusIndex = idx - 1
            event.accepted = true
            break
        case Qt.Key_Right:
            if (idx < count - 1) dealGridFocusIndex = idx + 1
            event.accepted = true
            break
        case Qt.Key_Up:
            if (idx - cols < 0) prevZone()
            else dealGridFocusIndex = idx - cols
            event.accepted = true
            break
        case Qt.Key_Down:
            if (idx + cols >= count) nextZone()
            else dealGridFocusIndex = idx + cols
            event.accepted = true
            break
        case Qt.Key_Return:
        case Qt.Key_Enter:
            if (idx >= 0 && idx < count) detailPopup.open(gridDeals[idx])
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
            StoreApi.fetchDeals(currentSort, currentPage, 30)
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
            clearSearch()
            event.accepted = true
            break
        }
    }

    function handleSearchResultsKeys(event) {
        var cols = 3
        var count = searchResults.length
        var idx = searchResultFocusIndex

        switch (event.key) {
        case Qt.Key_Left:
            if (idx % cols === 0) requestNavFocus()
            else searchResultFocusIndex = idx - 1
            event.accepted = true
            break
        case Qt.Key_Right:
            if (idx < count - 1) searchResultFocusIndex = idx + 1
            event.accepted = true
            break
        case Qt.Key_Up:
            if (idx - cols < 0) prevZone()
            else searchResultFocusIndex = idx - cols
            event.accepted = true
            break
        case Qt.Key_Down:
            if (idx + cols < count) searchResultFocusIndex = idx + cols
            event.accepted = true
            break
        case Qt.Key_Return:
        case Qt.Key_Enter:
            if (idx >= 0 && idx < count) detailPopup.open(searchResults[idx])
            event.accepted = true
            break
        }
    }

    // Ensure focused items in grids/trending are scrolled into view
    onDealGridFocusIndexChanged: if (navZone === "dealsGrid") ensureDealVisible(dealGridFocusIndex)
    onTrendingFocusIndexChanged: if (navZone === "trending") ensureTrendingVisible(trendingFocusIndex)

    function ensureDealVisible(idx) {
        // Scroll mainFlickable so the focused deal card is visible
        var cardW = Math.floor((mainFlickable.width - 48) / 3)
        var cardH = cardW * 0.55
        var cols = 3
        var row = Math.floor(idx / cols)
        // Approximate Y position of the deals grid within mainContent
        var gridY = dealsGridSection.y + (row * (cardH + 16))
        var viewTop = mainFlickable.contentY
        var viewBottom = viewTop + mainFlickable.height
        if (gridY < viewTop) mainFlickable.contentY = gridY - 20
        else if (gridY + cardH > viewBottom) mainFlickable.contentY = gridY + cardH - mainFlickable.height + 20
    }

    function ensureTrendingVisible(idx) {
        var targetX = idx * (420 + 16)
        var viewLeft = trendingList.contentX
        var viewRight = viewLeft + trendingList.width
        if (targetX < viewLeft) trendingList.contentX = targetX - 10
        else if (targetX + 420 > viewRight) trendingList.contentX = targetX + 420 - trendingList.width + 10
    }

    // Scroll the main Flickable so the active navZone is visible on screen
    onNavZoneChanged: if (hasKeyboardFocus) ensureZoneVisible()

    function ensureZoneVisible() {
        var targetY = -1
        var targetH = 0

        switch (navZone) {
        case "hero":
            targetY = heroBanner.y
            targetH = heroBanner.height
            break
        case "trending":
            targetY = trendingSection.y
            targetH = trendingSection.height
            break
        case "dealsGrid":
            targetY = dealsGridSection.y
            targetH = Math.min(dealsGridSection.height, mainFlickable.height)
            break
        case "loadMore":
            // loadMore is at the bottom of dealsGridSection
            targetY = dealsGridSection.y + dealsGridSection.height - 56
            targetH = 56
            break
        default:
            // searchBar, sortChips are above the Flickable; scroll to top
            mainFlickable.contentY = 0
            return
        }

        if (targetY < 0) return

        var viewTop = mainFlickable.contentY
        var viewBottom = viewTop + mainFlickable.height

        if (targetY < viewTop) {
            mainFlickable.contentY = Math.max(0, targetY - 20)
        } else if (targetY + targetH > viewBottom) {
            mainFlickable.contentY = targetY + targetH - mainFlickable.height + 20
        }
    }

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
                    border.color: (searchInput.activeFocus || (hasKeyboardFocus && navZone === "searchBar"))
                                  ? ThemeManager.getColor("focus")
                                  : Qt.rgba(1, 1, 1, 0.06)
                    border.width: (searchInput.activeFocus || (hasKeyboardFocus && navZone === "searchBar")) ? 3 : 1

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
                            property bool isKbFocused: hasKeyboardFocus && navZone === "sortChips" && sortChipFocusIndex === index
                            width: sortChipText.width + 40
                            height: 56
                            radius: 12
                            color: currentSort === modelData.value
                                   ? ThemeManager.getColor("primary")
                                   : ThemeManager.getColor("surface")
                            border.color: (sortChipArea.containsMouse || isKbFocused)
                                          ? ThemeManager.getColor("focus") : "transparent"
                            border.width: (sortChipArea.containsMouse || isKbFocused) ? 3 : 0

                            Behavior on color { ColorAnimation { duration: 150 } }
                            Behavior on border.color { ColorAnimation { duration: 150 } }

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
                            property bool isKbFocused: hasKeyboardFocus && navZone === "backToStore"
                            Layout.preferredWidth: backLabel.width + 40
                            Layout.preferredHeight: 56
                            radius: 12
                            color: ThemeManager.getColor("surface")
                            border.color: (backBtnArea.containsMouse || isKbFocused)
                                          ? ThemeManager.getColor("focus") : "transparent"
                            border.width: (backBtnArea.containsMouse || isKbFocused) ? 3 : 0
                            Behavior on border.color { ColorAnimation { duration: 150 } }

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
                            text: "Searching IGDB & price sources..."
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
                            text: "No Windows/Linux games with pricing found. Try a different search term."
                            font.pixelSize: 24
                            font.family: ThemeManager.getFont("body")
                            color: ThemeManager.getColor("textSecondary")
                            Layout.alignment: Qt.AlignHCenter
                            wrapMode: Text.WordWrap
                            Layout.maximumWidth: 500
                            horizontalAlignment: Text.AlignHCenter
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
                                headerImage: modelData.headerImage || modelData.coverUrl || modelData.thumb || ""
                                salePrice: modelData.salePrice || modelData.cheapestPrice || ""
                                normalPrice: ""
                                savings: modelData.savings || ""
                                metacriticScore: ""
                                steamRatingText: modelData.genres || ""
                                steamAppID: modelData.steamAppID || ""
                                gameID: modelData.cheapSharkGameID || ""
                                isKeyboardFocused: hasKeyboardFocus && navZone === "searchResults" && searchResultFocusIndex === index

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
                    border.color: (hasKeyboardFocus && navZone === "hero")
                                  ? ThemeManager.getColor("focus") : "transparent"
                    border.width: (hasKeyboardFocus && navZone === "hero") ? 3 : 0
                    Behavior on border.color { ColorAnimation { duration: 150 } }

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
                        source: heroBanner.featuredDeal
                                ? (heroBanner.featuredDeal.heroImage || heroBanner.featuredDeal.headerImage)
                                : ""
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
                    id: trendingSection
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
                            isKeyboardFocused: hasKeyboardFocus && navZone === "trending" && trendingFocusIndex === index

                            onClicked: detailPopup.open(modelData)
                        }
                    }
                }

                // ─── Top Deals Grid ───
                ColumnLayout {
                    id: dealsGridSection
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
                                isKeyboardFocused: hasKeyboardFocus && navZone === "dealsGrid" && dealGridFocusIndex === index

                                onClicked: detailPopup.open(modelData)
                            }
                        }
                    }

                    // Load more button
                    Rectangle {
                        property bool isKbFocused: hasKeyboardFocus && navZone === "loadMore"
                        Layout.alignment: Qt.AlignHCenter
                        Layout.preferredWidth: loadMoreLabel.width + 56
                        Layout.preferredHeight: 56
                        Layout.topMargin: 12
                        radius: 12
                        color: (loadMoreArea.containsMouse || isKbFocused)
                               ? ThemeManager.getColor("primary")
                               : ThemeManager.getColor("surface")
                        border.color: (loadMoreArea.containsMouse || isKbFocused)
                                      ? ThemeManager.getColor("focus")
                                      : Qt.rgba(ThemeManager.getColor("primary").r,
                                                ThemeManager.getColor("primary").g,
                                                ThemeManager.getColor("primary").b, 0.4)
                        border.width: (loadMoreArea.containsMouse || isKbFocused) ? 3 : 2

                        Behavior on color { ColorAnimation { duration: 200 } }
                        Behavior on border.color { ColorAnimation { duration: 150 } }

                        Text {
                            id: loadMoreLabel
                            anchors.centerIn: parent
                            text: "Load More Deals"
                            font.pixelSize: 24
                            font.family: ThemeManager.getFont("ui")
                            font.bold: true
                            color: (loadMoreArea.containsMouse || parent.isKbFocused)
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
                            text: "IGDB-powered search, descriptions, screenshots & ratings enabled"
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
                            text: "Add your Twitch developer credentials to enable IGDB-powered search " +
                                  "with rich game descriptions, screenshots, and platform filtering. " +
                                  "Register at dev.twitch.tv"
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

        onOpenDealUrl: function(url, storeName) {
            console.log("[store-browser] opening deal URL:", url, "store:", storeName)
            storePage.storeBrowserTitle = storeName || "Store"
            storeBrowserWebView.url = url
            storePage.storeBrowserOpen = true
        }
    }

    // ─── Embedded Store Browser ───
    // Navigation overlay script – identical to the one in SteamSetupWizard.
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
        var tag = el.tagName.toLowerCase();
        if (tag !== 'input' && tag !== 'textarea' && tag !== 'select'
            && tag !== 'img' && tag !== 'video') {
            try {
                var range = document.createRange();
                range.selectNodeContents(el);
                var tr = range.getBoundingClientRect();
                if (tr.width > 0 && tr.height > 0
                    && tr.width < r.width * 0.75) {
                    r = tr;
                }
            } catch(e) {}
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
    console.log('__luna:nav-ready count:' + elements.length);
    return 'ready:' + elements.length;
})();
"

    // Controller → Embedded Store Browser navigation
    Connections {
        target: ControllerManager
        enabled: storePage.storeBrowserOpen && !storeBrowserVK.visible
        function onActionTriggered(action) {
            function logResult(result) {
                console.log("[store-browser] nav result:", result)
            }
            switch (action) {
            case "navigate_up":
                storeBrowserWebView.runJavaScript("window.__lunaNav && window.__lunaNav.move('up')", logResult)
                break
            case "navigate_down":
                storeBrowserWebView.runJavaScript("window.__lunaNav && window.__lunaNav.move('down')", logResult)
                break
            case "navigate_left":
                storeBrowserWebView.runJavaScript("window.__lunaNav && window.__lunaNav.move('left')", logResult)
                break
            case "navigate_right":
                storeBrowserWebView.runJavaScript("window.__lunaNav && window.__lunaNav.move('right')", logResult)
                break
            case "confirm":
                storeBrowserWebView.runJavaScript(
                    "window.__lunaNav && window.__lunaNav.activate()",
                    function(result) {
                        console.log("[store-browser] activate result:", result)
                        if (result && result.toString().indexOf("input:") === 0) {
                            var parts = result.toString().split(":")
                            var inputType = parts[1] || "text"
                            var currentVal = parts.slice(2).join(":")
                            var isPassword = (inputType === "password")
                            storePage.storeBrowserInputActive = true
                            storeBrowserVK.placeholderText = isPassword ? "Enter password..." : "Type here..."
                            storeBrowserVK.open(currentVal, isPassword)
                        }
                    })
                break
            case "scroll_up":
                storeBrowserWebView.runJavaScript("window.__lunaNav && window.__lunaNav.scrollPage('up')", logResult)
                break
            case "scroll_down":
                storeBrowserWebView.runJavaScript("window.__lunaNav && window.__lunaNav.scrollPage('down')", logResult)
                break
            case "back":
                console.log("[store-browser] closing browser")
                storePage.storeBrowserOpen = false
                break
            default:
                break
            }
        }
    }

    Rectangle {
        id: storeBrowserOverlay
        visible: storePage.storeBrowserOpen
        anchors.fill: parent
        z: 600
        color: ThemeManager.getColor("background")

        // Header bar
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

            // Back hint
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

        // SharedBrowserProfile is a QWebEngineProfile created in C++
        // (main.cpp) with storageName "luna-browser" passed to the
        // constructor, guaranteeing disk persistence from the start.
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
                console.log("[store-browser] loadingChanged:",
                            loadRequest.status === WebEngineView.LoadSucceededStatus ? "SUCCESS" :
                            loadRequest.status === WebEngineView.LoadFailedStatus ? "FAILED" :
                            "status=" + loadRequest.status,
                            "url:", loadRequest.url)
                if (loadRequest.status === WebEngineView.LoadSucceededStatus) {
                    storeBrowserNavInjectTimer.restart()
                }
            }
            onJavaScriptConsoleMessage: function(level, message, lineNumber, sourceID) {
                console.log("[store-browser-js]", message)
            }
        }

        Timer {
            id: storeBrowserNavInjectTimer
            interval: 800
            repeat: false
            onTriggered: {
                console.log("[store-browser] injecting navigation overlay")
                storeBrowserWebView.runJavaScript(storePage.navOverlayScript,
                    function(result) {
                        console.log("[store-browser] nav inject result:", result)
                    })
            }
        }
    }

    // ─── Virtual Keyboard for Store Browser ───
    VirtualKeyboard {
        id: storeBrowserVK
        anchors.fill: parent
        z: 700

        onAccepted: function(typedText) {
            if (storePage.storeBrowserInputActive) {
                storePage.storeBrowserInputActive = false
                var escaped = typedText.replace(/\\/g, '\\\\').replace(/'/g, "\\'")
                storeBrowserWebView.runJavaScript(
                    "window.__lunaNav && window.__lunaNav.setText('" + escaped + "')",
                    function(result) {
                        console.log("[store-browser] setText result:", result)
                    })
            }
            storePage.forceActiveFocus()
        }

        onCancelled: {
            storePage.storeBrowserInputActive = false
            storePage.forceActiveFocus()
        }
    }

    // ─── Virtual Keyboard for Search ───
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

        onCancelled: {
            navZone = "searchBar"
            storePage.forceActiveFocus()
        }
    }

    // ─── Helper Functions ───
    function clearSearch() {
        searchInput.text = ""
        storePage.searchQuery = ""
        storePage.isSearching = false
        storePage.searchResults = []
    }
}
