import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../components"

Rectangle {
    id: gamesRoot
    color: "transparent"

    // Signal to request focus back to NavBar
    signal requestNavFocus()

    property int activeTab: 0   // 0 = My Games, 1 = Clients, 2 = Game Store
    onActiveTabChanged: if (activeTab === 0) refreshGames()

    // Focus state: "tabs" = tab bar focused, "content" = content area focused
    property string focusState: "tabs"
    property int focusedTabIndex: 0
    property int hoveredTabIndex: -1

    // Clients tab focus
    property int clientsFocusIndex: 0
    readonly property int clientsItemCount: 4  // Steam, Epic, GOG, Heroic

    // Credential dialog controller focus: 0 = input, 1 = submit, 2 = cancel
    property int credDialogFocusIndex: 0

    function gainFocus() {
        focusState = "tabs"
        focusedTabIndex = activeTab
        gamesRoot.forceActiveFocus()
    }

    function loseFocus() {
        focusState = ""
        focusedTabIndex = -1
        // Clean up Game Store focus if active
        if (gameStoreLoader.item && typeof gameStoreLoader.item.loseFocus === "function")
            gameStoreLoader.item.loseFocus()
    }

    // Master keyboard handler
    Keys.onPressed: function(event) {
        // VirtualKeyboard handles its own keys
        if (gamesVirtualKeyboard.visible) {
            event.accepted = true
            return
        }
        // Credential dialog navigation
        if (credentialDialog.visible) {
            handleCredDialogKeys(event)
            return
        }
        if (focusState === "tabs") {
            handleTabKeys(event)
        } else if (focusState === "content") {
            handleContentKeys(event)
        }
    }

    function handleCredDialogKeys(event) {
        switch (event.key) {
        case Qt.Key_Up:
            if (credDialogFocusIndex > 0) credDialogFocusIndex--
            event.accepted = true
            break
        case Qt.Key_Down:
            if (credDialogFocusIndex < 2) credDialogFocusIndex++
            event.accepted = true
            break
        case Qt.Key_Left:
            if (credDialogFocusIndex === 2) credDialogFocusIndex = 1
            event.accepted = true
            break
        case Qt.Key_Right:
            if (credDialogFocusIndex === 1) credDialogFocusIndex = 2
            event.accepted = true
            break
        case Qt.Key_Return:
        case Qt.Key_Enter:
            if (credDialogFocusIndex === 0) {
                // Open virtual keyboard for credential input
                var isPassword = credentialDialog.promptType === "password"
                gamesVirtualKeyboard.placeholderText = isPassword
                    ? "Enter password..." : "Enter Steam Guard code..."
                gamesVirtualKeyboard.open("", isPassword)
                gamesVirtualKeyboard.targetField = "credential"
            } else if (credDialogFocusIndex === 1) {
                // Submit
                if (credInput.text.length > 0) {
                    GameManager.provideSteamCmdCredential(
                        credentialDialog.pendingAppId, credInput.text)
                    credInput.text = ""
                    credentialDialog.visible = false
                    gamesRoot.forceActiveFocus()
                }
            } else if (credDialogFocusIndex === 2) {
                // Cancel
                credInput.text = ""
                GameManager.cancelDownload(credentialDialog.pendingAppId)
                credentialDialog.visible = false
                gamesRoot.forceActiveFocus()
            }
            event.accepted = true
            break
        case Qt.Key_Escape:
            credInput.text = ""
            GameManager.cancelDownload(credentialDialog.pendingAppId)
            credentialDialog.visible = false
            gamesRoot.forceActiveFocus()
            event.accepted = true
            break
        }
    }

    function handleTabKeys(event) {
        switch (event.key) {
        case Qt.Key_Left:
            if (focusedTabIndex > 0) {
                focusedTabIndex--
                activeTab = focusedTabIndex
            } else {
                // At leftmost tab, go back to NavBar
                requestNavFocus()
            }
            event.accepted = true
            break
        case Qt.Key_Right:
            if (focusedTabIndex < 2) {
                focusedTabIndex++
                activeTab = focusedTabIndex
            }
            event.accepted = true
            break
        case Qt.Key_Down:
        case Qt.Key_Return:
        case Qt.Key_Enter:
            // Enter content area
            focusState = "content"
            enterContentArea()
            event.accepted = true
            break
        }
    }

    function handleContentKeys(event) {
        if (activeTab === 0) {
            // My Games grid
            handleMyGamesKeys(event)
        } else if (activeTab === 1) {
            // Clients
            handleClientsKeys(event)
        } else if (activeTab === 2) {
            // Game Store — GameStorePage handles its own keys via Keys.onPressed.
            // Only unhandled keys propagate here (Up at searchBar, Escape).
            var zone = gameStoreLoader.item ? gameStoreLoader.item.navZone : ""
            if (event.key === Qt.Key_Escape ||
                (event.key === Qt.Key_Up && (zone === "searchBar" || zone === ""))) {
                focusState = "tabs"
                focusedTabIndex = activeTab
                if (gameStoreLoader.item && typeof gameStoreLoader.item.loseFocus === "function")
                    gameStoreLoader.item.loseFocus()
                event.accepted = true
                return
            }
        }
    }

    function handleMyGamesKeys(event) {
        var cols = Math.floor(gameGrid.width / gameGrid.cellWidth)
        if (cols < 1) cols = 1
        var idx = gameGrid.currentIndex
        var count = gameGrid.count

        switch (event.key) {
        case Qt.Key_Left:
            if (idx <= 0 || idx % cols === 0) {
                // At left edge (or empty grid), go back to NavBar
                requestNavFocus()
            } else {
                gameGrid.currentIndex = idx - 1
            }
            event.accepted = true
            break
        case Qt.Key_Right:
            if (idx < count - 1) {
                gameGrid.currentIndex = idx + 1
            }
            event.accepted = true
            break
        case Qt.Key_Up:
            if (idx - cols < 0) {
                // At top row, go back to tab bar
                focusState = "tabs"
                focusedTabIndex = activeTab
            } else {
                gameGrid.currentIndex = idx - cols
            }
            event.accepted = true
            break
        case Qt.Key_Down:
            if (idx + cols < count) {
                gameGrid.currentIndex = idx + cols
            }
            event.accepted = true
            break
        case Qt.Key_Return:
        case Qt.Key_Enter:
            // Activate current game
            if (count > 0 && idx >= 0 && idx < count) {
                var game = gamesModel.get(idx)
                if (game) GameManager.launchGame(game.id)
            }
            event.accepted = true
            break
        }
    }

    function handleClientsKeys(event) {
        switch (event.key) {
        case Qt.Key_Left:
            if (clientsFocusIndex === 0) {
                requestNavFocus()
            } else {
                clientsFocusIndex--
            }
            event.accepted = true
            break
        case Qt.Key_Right:
            if (clientsFocusIndex < clientsItemCount - 1) {
                clientsFocusIndex++
            }
            event.accepted = true
            break
        case Qt.Key_Up:
            focusState = "tabs"
            focusedTabIndex = activeTab
            event.accepted = true
            break
        case Qt.Key_Down:
            // No further rows below clients cards
            event.accepted = true
            break
        case Qt.Key_Return:
        case Qt.Key_Enter:
            // Activate Steam card (index 0)
            if (clientsFocusIndex === 0) {
                if (!GameManager.isSteamInstalled()) return
                if (!GameManager.isSteamAvailable()) {
                    steamSetupWizard.open()
                } else {
                    gameStoresTab.steamSettingsOpen = !gameStoresTab.steamSettingsOpen
                }
            }
            event.accepted = true
            break
        }
    }

    function enterContentArea() {
        if (activeTab === 0) {
            // Focus the game grid
            if (gameGrid.count > 0) {
                gameGrid.currentIndex = 0
            }
        } else if (activeTab === 1) {
            clientsFocusIndex = 0
        } else if (activeTab === 2) {
            // Game Store — hand focus to GameStorePage
            if (gameStoreLoader.item && typeof gameStoreLoader.item.gainFocus === "function") {
                gameStoreLoader.item.gainFocus()
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 24
        spacing: 0

        // Header
        Text {
            text: "Games"
            font.pixelSize: ThemeManager.getFontSize("xlarge")
            font.family: ThemeManager.getFont("heading")
            font.bold: true
            color: ThemeManager.getColor("textPrimary")
            Layout.bottomMargin: 16
        }

        // ── Horizontal tab bar ──
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 48
            color: "transparent"

            Row {
                id: tabRow
                spacing: 0
                height: parent.height

                Repeater {
                    model: ["My Games", "Clients", "Game Store"]

                    Rectangle {
                        width: 140
                        height: tabRow.height
                        color: "transparent"

                        property bool isTabFocused: focusState === "tabs" && focusedTabIndex === index
                        property bool isTabHovered: hoveredTabIndex === index

                        // Purple outline when keyboard-focused or mouse-hovered on tab
                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: 2
                            radius: 6
                            color: "transparent"
                            border.color: (isTabFocused || isTabHovered)
                                          ? ThemeManager.getColor("focus") : "transparent"
                            border.width: (isTabFocused || isTabHovered) ? 2 : 0
                            Behavior on border.color { ColorAnimation { duration: 150 } }
                        }

                        Rectangle {
                            anchors.bottom: parent.bottom
                            width: parent.width
                            height: 3
                            color: activeTab === index
                                   ? ThemeManager.getColor("primary")
                                   : "transparent"
                            Behavior on color { ColorAnimation { duration: 150 } }
                        }

                        Text {
                            anchors.centerIn: parent
                            text: modelData
                            font.pixelSize: ThemeManager.getFontSize("medium")
                            font.family: ThemeManager.getFont("body")
                            font.bold: activeTab === index
                            color: activeTab === index
                                   ? ThemeManager.getColor("textPrimary")
                                   : ThemeManager.getColor("textSecondary")
                        }

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onEntered: {
                                hoveredTabIndex = index
                                focusedTabIndex = index
                                focusState = "tabs"
                                gamesRoot.forceActiveFocus()
                            }
                            onExited: hoveredTabIndex = -1
                            onClicked: {
                                activeTab = index
                                focusedTabIndex = index
                                focusState = "tabs"
                                gamesRoot.forceActiveFocus()
                            }
                        }
                    }
                }
            }

            // Subtle divider line under tabs
            Rectangle {
                anchors.bottom: parent.bottom
                width: parent.width
                height: 1
                color: Qt.rgba(1, 1, 1, 0.08)
            }
        }

        Item { height: 20; Layout.fillWidth: true }

        // ── Tab content ──
        StackLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            currentIndex: activeTab

            // ─── Tab 0: My Games ───
            Item {
                id: myGamesTab

                // Empty state
                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: 16
                    visible: gameGrid.count === 0

                    Text {
                        text: "No games found"
                        font.pixelSize: ThemeManager.getFontSize("large")
                        font.family: ThemeManager.getFont("body")
                        color: ThemeManager.getColor("textSecondary")
                        Layout.alignment: Qt.AlignHCenter
                    }

                    Text {
                        text: "Go to Game Stores to connect your accounts"
                        font.pixelSize: ThemeManager.getFontSize("small")
                        font.family: ThemeManager.getFont("body")
                        color: ThemeManager.getColor("textSecondary")
                        Layout.alignment: Qt.AlignHCenter
                    }

                    Rectangle {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.preferredWidth: 200
                        Layout.preferredHeight: 44
                        radius: 8
                        color: ThemeManager.getColor("primary")

                        Text {
                            anchors.centerIn: parent
                            text: "Browse Stores"
                            font.pixelSize: ThemeManager.getFontSize("medium")
                            font.family: ThemeManager.getFont("body")
                            font.bold: true
                            color: "white"
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: activeTab = 1
                        }
                    }
                }

                // Games grid
                GridView {
                    id: gameGrid
                    anchors.fill: parent
                    cellWidth: 200
                    cellHeight: 290
                    clip: true
                    model: ListModel { id: gamesModel }
                    highlight: Item {}  // We handle highlight in delegate
                    highlightFollowsCurrentItem: false
                    currentIndex: -1

                    delegate: GameCard {
                        gameTitle: model.title
                        coverArt: model.coverArtUrl || ""
                        isFavorite: model.isFavorite || false
                        isInstalled: model.isInstalled !== undefined ? model.isInstalled : true
                        gameId: model.id
                        appId: model.appId || ""
                        downloadProgress: model.downloadProgress !== undefined ? model.downloadProgress : -1.0
                        installError: model.installError !== undefined ? model.installError : ""

                        // Keyboard focus: this card is focused when it's the grid's current item and we're in content mode
                        isKeyboardFocused: gameGrid.currentIndex === index && focusState === "content" && activeTab === 0

                        onPlayClicked: function(id) {
                            GameManager.launchGame(id)
                        }
                        onCancelClicked: function(appId) {
                            GameManager.cancelDownload(appId)
                        }
                        onCardHovered: {
                            gameGrid.currentIndex = index
                            focusState = "content"
                            gamesRoot.forceActiveFocus()
                        }
                    }

                    ScrollBar.vertical: ScrollBar {
                        policy: ScrollBar.AsNeeded
                    }
                }
            }

            // ─── Tab 1: Clients ───
            Item {
                id: gameStoresTab

                property bool hasNetwork: GameManager.isNetworkAvailable()
                property bool showWifiPanel: false
                property string wifiStatus: ""
                property bool wifiConnecting: false
                property string steamFetchStatus: ""
                property bool steamFetching: false
                property bool steamSettingsOpen: false

                // Refresh network status when tab becomes visible
                Timer {
                    id: networkCheckTimer
                    interval: 3000
                    running: activeTab === 1
                    repeat: true
                    onTriggered: {
                        gameStoresTab.hasNetwork = GameManager.isNetworkAvailable()
                        if (gameStoresTab.hasNetwork)
                            gameStoresTab.showWifiPanel = false
                    }
                }
                Component.onCompleted: hasNetwork = GameManager.isNetworkAvailable()

                Connections {
                    target: GameManager
                    function onWifiNetworksScanned(networks) {
                        wifiListModel.clear()
                        for (var i = 0; i < networks.length; i++)
                            wifiListModel.append(networks[i])
                    }
                    function onWifiConnectResult(success, message) {
                        gameStoresTab.wifiConnecting = false
                        if (success) {
                            gameStoresTab.wifiStatus = "Connected!"
                            gameStoresTab.hasNetwork = GameManager.isNetworkAvailable()
                        } else {
                            gameStoresTab.wifiStatus = "Failed: " + message
                        }
                    }
                    function onSteamOwnedGamesFetched(gamesFound) {
                        gameStoresTab.steamFetching = false
                        gameStoresTab.steamFetchStatus = "Found " + gamesFound + " owned games!"
                        refreshGames()
                    }
                    function onSteamOwnedGamesFetchError(error) {
                        gameStoresTab.steamFetching = false
                        gameStoresTab.steamFetchStatus = "Error: " + error
                    }
                }

                // ─── Offline: initial message ───
                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: 16
                    visible: !gameStoresTab.hasNetwork && !gameStoresTab.showWifiPanel

                    Text {
                        text: "No Internet Connection"
                        font.pixelSize: ThemeManager.getFontSize("large")
                        font.family: ThemeManager.getFont("heading")
                        font.bold: true
                        color: ThemeManager.getColor("textPrimary")
                        Layout.alignment: Qt.AlignHCenter
                    }

                    Text {
                        text: "Please connect to Wi-Fi!"
                        font.pixelSize: ThemeManager.getFontSize("medium")
                        font.family: ThemeManager.getFont("body")
                        color: ThemeManager.getColor("textSecondary")
                        Layout.alignment: Qt.AlignHCenter
                    }

                    Text {
                        text: "A network connection is required to log in and install games."
                        font.pixelSize: ThemeManager.getFontSize("small")
                        font.family: ThemeManager.getFont("body")
                        color: ThemeManager.getColor("textSecondary")
                        Layout.alignment: Qt.AlignHCenter
                    }

                    Rectangle {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.preferredWidth: 220
                        Layout.preferredHeight: 44
                        radius: 8
                        color: ThemeManager.getColor("primary")

                        Text {
                            anchors.centerIn: parent
                            text: "Connect to Wi-Fi"
                            font.pixelSize: ThemeManager.getFontSize("medium")
                            font.family: ThemeManager.getFont("body")
                            font.bold: true
                            color: "white"
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                gameStoresTab.wifiStatus = ""
                                gameStoresTab.showWifiPanel = true
                                wifiListModel.clear()
                                GameManager.scanWifiNetworks()
                            }
                        }
                    }
                }

                // ─── Offline: Wi-Fi network picker ───
                Rectangle {
                    anchors.fill: parent
                    visible: !gameStoresTab.hasNetwork && gameStoresTab.showWifiPanel
                    color: "transparent"

                    ColumnLayout {
                        anchors.fill: parent
                        spacing: 12

                        // Header row
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 12

                            Rectangle {
                                Layout.preferredWidth: 80
                                Layout.preferredHeight: 40
                                radius: 12
                                color: ThemeManager.getColor("surface")
                                border.color: backBtnArea.containsMouse
                                              ? ThemeManager.getColor("focus") : "transparent"
                                border.width: backBtnArea.containsMouse ? 2 : 0

                                Text {
                                    anchors.centerIn: parent
                                    text: "< Back"
                                    font.pixelSize: ThemeManager.getFontSize("small")
                                    font.family: ThemeManager.getFont("body")
                                    font.bold: true
                                    color: ThemeManager.getColor("textPrimary")
                                }

                                MouseArea {
                                    id: backBtnArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        gameStoresTab.showWifiPanel = false
                                        wifiPasswordField.text = ""
                                        wifiSelectedSsid.text = ""
                                    }
                                }

                                Behavior on border.color { ColorAnimation { duration: 150 } }
                            }

                            Text {
                                text: "Wi-Fi Networks"
                                font.pixelSize: ThemeManager.getFontSize("large")
                                font.family: ThemeManager.getFont("heading")
                                font.bold: true
                                color: ThemeManager.getColor("textPrimary")
                                Layout.fillWidth: true
                            }

                            Rectangle {
                                Layout.preferredWidth: 100
                                Layout.preferredHeight: 40
                                radius: 12
                                color: ThemeManager.getColor("surface")
                                border.color: refreshBtnArea.containsMouse
                                              ? ThemeManager.getColor("focus") : "transparent"
                                border.width: refreshBtnArea.containsMouse ? 2 : 0

                                Text {
                                    anchors.centerIn: parent
                                    text: "Refresh"
                                    font.pixelSize: ThemeManager.getFontSize("small")
                                    font.family: ThemeManager.getFont("body")
                                    font.bold: true
                                    color: ThemeManager.getColor("textPrimary")
                                }

                                MouseArea {
                                    id: refreshBtnArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        wifiListModel.clear()
                                        GameManager.scanWifiNetworks()
                                    }
                                }

                                Behavior on border.color { ColorAnimation { duration: 150 } }
                            }
                        }

                        // Status message
                        Text {
                            visible: gameStoresTab.wifiStatus !== ""
                            text: gameStoresTab.wifiStatus
                            font.pixelSize: ThemeManager.getFontSize("small")
                            font.family: ThemeManager.getFont("body")
                            color: gameStoresTab.wifiStatus.startsWith("Failed")
                                   ? "#ff6b6b" : ThemeManager.getColor("accent")
                        }

                        // Network list
                        ListView {
                            id: wifiListView
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            clip: true
                            spacing: 6
                            model: ListModel { id: wifiListModel }

                            delegate: Rectangle {
                                width: wifiListView.width
                                height: 60
                                radius: 12
                                color: wifiItemArea.containsMouse
                                       ? Qt.rgba(ThemeManager.getColor("primary").r,
                                                 ThemeManager.getColor("primary").g,
                                                 ThemeManager.getColor("primary").b, 0.2)
                                       : ThemeManager.getColor("surface")
                                border.color: wifiItemArea.containsMouse
                                              ? ThemeManager.getColor("focus") : "transparent"
                                border.width: wifiItemArea.containsMouse ? 2 : 0

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 20
                                    anchors.rightMargin: 20
                                    spacing: 16

                                    // Signal strength indicator
                                    Text {
                                        text: model.signal > 70 ? "|||" :
                                              model.signal > 40 ? "|| " : "|  "
                                        font.pixelSize: 16
                                        font.family: "monospace"
                                        font.bold: true
                                        color: model.signal > 70
                                               ? ThemeManager.getColor("accent")
                                               : model.signal > 40
                                                 ? ThemeManager.getColor("secondary")
                                                 : ThemeManager.getColor("textSecondary")
                                    }

                                    Text {
                                        text: model.ssid
                                        font.pixelSize: ThemeManager.getFontSize("medium")
                                        font.family: ThemeManager.getFont("body")
                                        font.bold: true
                                        color: ThemeManager.getColor("textPrimary")
                                        Layout.fillWidth: true
                                    }

                                    Text {
                                        visible: model.security !== "" && model.security !== "--"
                                        text: model.security
                                        font.pixelSize: ThemeManager.getFontSize("small")
                                        font.family: ThemeManager.getFont("body")
                                        color: ThemeManager.getColor("textSecondary")
                                    }
                                }

                                MouseArea {
                                    id: wifiItemArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        wifiSelectedSsid.text = model.ssid
                                        wifiPasswordField.text = ""
                                        gameStoresTab.wifiStatus = ""
                                        if (model.security === "" || model.security === "--") {
                                            gameStoresTab.wifiConnecting = true
                                            gameStoresTab.wifiStatus = "Connecting..."
                                            GameManager.connectToWifi(model.ssid, "")
                                        } else {
                                            gamesVirtualKeyboard.placeholderText = "Enter WiFi password..."
                                            gamesVirtualKeyboard.open("", true)
                                            gamesVirtualKeyboard.targetField = "wifi"
                                        }
                                    }
                                }

                                Behavior on color { ColorAnimation { duration: 150 } }
                                Behavior on border.color { ColorAnimation { duration: 150 } }
                            }
                        }

                        // Password input bar (visible when a secured network is selected)
                        Rectangle {
                            visible: wifiSelectedSsid.text !== ""
                            Layout.fillWidth: true
                            Layout.preferredHeight: 56
                            radius: 12
                            color: ThemeManager.getColor("surface")

                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: 10
                                spacing: 10

                                Text {
                                    text: wifiSelectedSsid.text
                                    font.pixelSize: ThemeManager.getFontSize("small")
                                    font.family: ThemeManager.getFont("body")
                                    font.bold: true
                                    color: ThemeManager.getColor("textPrimary")
                                    Layout.preferredWidth: 160
                                    elide: Text.ElideRight
                                }

                                // Hidden text to store the selected SSID
                                Text {
                                    id: wifiSelectedSsid
                                    visible: false
                                    text: ""
                                }

                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    radius: 8
                                    color: ThemeManager.getColor("hover")
                                    border.color: wifiPasswordField.activeFocus
                                                  ? ThemeManager.getColor("focus")
                                                  : "transparent"
                                    border.width: wifiPasswordField.activeFocus ? 2 : 0

                                    Behavior on border.color { ColorAnimation { duration: 150 } }

                                    TextInput {
                                        id: wifiPasswordField
                                        anchors.fill: parent
                                        anchors.margins: 10
                                        verticalAlignment: TextInput.AlignVCenter
                                        font.pixelSize: ThemeManager.getFontSize("medium")
                                        font.family: ThemeManager.getFont("body")
                                        color: ThemeManager.getColor("textPrimary")
                                        echoMode: TextInput.Password
                                        clip: true
                                        onAccepted: {
                                            if (text.length > 0 && !gameStoresTab.wifiConnecting) {
                                                gameStoresTab.wifiConnecting = true
                                                gameStoresTab.wifiStatus = "Connecting..."
                                                GameManager.connectToWifi(wifiSelectedSsid.text, text)
                                            }
                                        }
                                    }

                                    Text {
                                        anchors.fill: parent
                                        anchors.margins: 10
                                        verticalAlignment: Text.AlignVCenter
                                        visible: wifiPasswordField.text === "" && !wifiPasswordField.activeFocus
                                        text: "Enter password..."
                                        font.pixelSize: ThemeManager.getFontSize("medium")
                                        font.family: ThemeManager.getFont("body")
                                        color: ThemeManager.getColor("textSecondary")
                                    }
                                }

                                Rectangle {
                                    Layout.preferredWidth: connectBtnLabel.width + 32
                                    Layout.fillHeight: true
                                    radius: 8
                                    color: gameStoresTab.wifiConnecting
                                           ? ThemeManager.getColor("textSecondary")
                                           : ThemeManager.getColor("primary")
                                    border.color: connectBtnArea.containsMouse && !gameStoresTab.wifiConnecting
                                                  ? ThemeManager.getColor("focus") : "transparent"
                                    border.width: connectBtnArea.containsMouse && !gameStoresTab.wifiConnecting ? 2 : 0

                                    Behavior on border.color { ColorAnimation { duration: 150 } }

                                    Text {
                                        id: connectBtnLabel
                                        anchors.centerIn: parent
                                        text: gameStoresTab.wifiConnecting ? "Connecting..." : "Connect"
                                        font.pixelSize: ThemeManager.getFontSize("small")
                                        font.family: ThemeManager.getFont("body")
                                        font.bold: true
                                        color: "white"
                                    }

                                    MouseArea {
                                        id: connectBtnArea
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            if (wifiPasswordField.text.length > 0
                                                    && !gameStoresTab.wifiConnecting) {
                                                gameStoresTab.wifiConnecting = true
                                                gameStoresTab.wifiStatus = "Connecting..."
                                                GameManager.connectToWifi(
                                                    wifiSelectedSsid.text,
                                                    wifiPasswordField.text)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // ─── Online: store cards ───
                Flickable {
                    anchors.fill: parent
                    contentHeight: storesColumn.height
                    clip: true
                    visible: gameStoresTab.hasNetwork

                    ColumnLayout {
                        id: storesColumn
                        width: parent.width
                        spacing: 16

                        Text {
                            text: "Connect your game stores to import your library"
                            font.pixelSize: ThemeManager.getFontSize("small")
                            font.family: ThemeManager.getFont("body")
                            color: ThemeManager.getColor("textSecondary")
                            Layout.bottomMargin: 4
                        }

                        // ─── Store cards row ───
                        Flow {
                            Layout.fillWidth: true
                            spacing: 12

                            // ── Steam ──
                            Rectangle {
                                width: 220
                                height: 72
                                radius: 12
                                color: ThemeManager.getColor("surface")
                                border.color: (steamCardArea.containsMouse || (focusState === "content" && activeTab === 1 && clientsFocusIndex === 0))
                                              ? ThemeManager.getColor("focus") : "transparent"
                                border.width: (steamCardArea.containsMouse || (focusState === "content" && activeTab === 1 && clientsFocusIndex === 0)) ? 2 : 0

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.margins: 12
                                    spacing: 12

                                    // Icon
                                    Rectangle {
                                        Layout.preferredWidth: 44
                                        Layout.preferredHeight: 44
                                        radius: 10
                                        color: "#1b2838"

                                        Text {
                                            anchors.centerIn: parent
                                            text: "S"
                                            font.pixelSize: 22
                                            font.bold: true
                                            color: "#66c0f4"
                                        }
                                    }

                                    // Name + status
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 2

                                        Text {
                                            text: "Steam"
                                            font.pixelSize: ThemeManager.getFontSize("medium")
                                            font.family: ThemeManager.getFont("body")
                                            font.bold: true
                                            color: ThemeManager.getColor("textPrimary")
                                        }

                                        RowLayout {
                                            spacing: 5

                                            Rectangle {
                                                Layout.preferredWidth: 8
                                                Layout.preferredHeight: 8
                                                radius: 4
                                                color: {
                                                    if (!GameManager.isSteamInstalled())
                                                        return ThemeManager.getColor("textSecondary")
                                                    if (GameManager.isSteamAvailable())
                                                        return ThemeManager.getColor("accent")
                                                    return "#ff6b6b"
                                                }
                                            }

                                            Text {
                                                text: {
                                                    if (!GameManager.isSteamInstalled())
                                                        return "Not installed"
                                                    if (GameManager.isSteamSetupComplete())
                                                        return "Ready"
                                                    if (GameManager.isSteamAvailable())
                                                        return "Connected"
                                                    return "Not set up"
                                                }
                                                font.pixelSize: ThemeManager.getFontSize("small")
                                                font.family: ThemeManager.getFont("body")
                                                color: ThemeManager.getColor("textSecondary")
                                            }
                                        }
                                    }

                                    // Settings gear
                                    Rectangle {
                                        visible: GameManager.isSteamInstalled()
                                        Layout.preferredWidth: 32
                                        Layout.preferredHeight: 32
                                        radius: 8
                                        color: steamGearArea.containsMouse
                                               ? ThemeManager.getColor("hover") : "transparent"

                                        Text {
                                            anchors.centerIn: parent
                                            text: "\u2699"
                                            font.pixelSize: 18
                                            color: ThemeManager.getColor("textSecondary")
                                        }

                                        MouseArea {
                                            id: steamGearArea
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: gameStoresTab.steamSettingsOpen = !gameStoresTab.steamSettingsOpen
                                        }
                                    }
                                }

                                MouseArea {
                                    id: steamCardArea
                                    anchors.fill: parent
                                    z: -1
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onEntered: {
                                        clientsFocusIndex = 0
                                        focusState = "content"
                                        gamesRoot.forceActiveFocus()
                                    }
                                    onClicked: {
                                        if (!GameManager.isSteamInstalled())
                                            return
                                        if (!GameManager.isSteamAvailable()) {
                                            steamSetupWizard.open()
                                        } else {
                                            gameStoresTab.steamSettingsOpen = !gameStoresTab.steamSettingsOpen
                                        }
                                    }
                                }

                                Behavior on border.color { ColorAnimation { duration: 150 } }
                            }

                            // ── Epic (placeholder) ──
                            Rectangle {
                                width: 220
                                height: 72
                                radius: 12
                                color: Qt.rgba(ThemeManager.getColor("surface").r,
                                               ThemeManager.getColor("surface").g,
                                               ThemeManager.getColor("surface").b, 0.4)
                                border.color: (epicCardArea.containsMouse || (focusState === "content" && activeTab === 1 && clientsFocusIndex === 1))
                                              ? ThemeManager.getColor("focus") : "transparent"
                                border.width: (epicCardArea.containsMouse || (focusState === "content" && activeTab === 1 && clientsFocusIndex === 1)) ? 2 : 0

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.margins: 12
                                    spacing: 12

                                    Rectangle {
                                        Layout.preferredWidth: 44
                                        Layout.preferredHeight: 44
                                        radius: 10
                                        color: "#2a2a2a"

                                        Text {
                                            anchors.centerIn: parent
                                            text: "E"
                                            font.pixelSize: 22
                                            font.bold: true
                                            color: "#888"
                                        }
                                    }

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 2

                                        Text {
                                            text: "Epic"
                                            font.pixelSize: ThemeManager.getFontSize("medium")
                                            font.family: ThemeManager.getFont("body")
                                            font.bold: true
                                            color: ThemeManager.getColor("textSecondary")
                                        }

                                        Text {
                                            text: "Coming soon"
                                            font.pixelSize: ThemeManager.getFontSize("small")
                                            font.family: ThemeManager.getFont("body")
                                            color: ThemeManager.getColor("textSecondary")
                                        }
                                    }
                                }

                                MouseArea {
                                    id: epicCardArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    onEntered: {
                                        clientsFocusIndex = 1
                                        focusState = "content"
                                        gamesRoot.forceActiveFocus()
                                    }
                                }

                                Behavior on border.color { ColorAnimation { duration: 150 } }
                            }

                            // ── GOG (placeholder) ──
                            Rectangle {
                                width: 220
                                height: 72
                                radius: 12
                                color: Qt.rgba(ThemeManager.getColor("surface").r,
                                               ThemeManager.getColor("surface").g,
                                               ThemeManager.getColor("surface").b, 0.4)
                                border.color: (gogCardArea.containsMouse || (focusState === "content" && activeTab === 1 && clientsFocusIndex === 2))
                                              ? ThemeManager.getColor("focus") : "transparent"
                                border.width: (gogCardArea.containsMouse || (focusState === "content" && activeTab === 1 && clientsFocusIndex === 2)) ? 2 : 0

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.margins: 12
                                    spacing: 12

                                    Rectangle {
                                        Layout.preferredWidth: 44
                                        Layout.preferredHeight: 44
                                        radius: 10
                                        color: "#2a2a2a"

                                        Text {
                                            anchors.centerIn: parent
                                            text: "G"
                                            font.pixelSize: 22
                                            font.bold: true
                                            color: "#888"
                                        }
                                    }

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 2

                                        Text {
                                            text: "GOG"
                                            font.pixelSize: ThemeManager.getFontSize("medium")
                                            font.family: ThemeManager.getFont("body")
                                            font.bold: true
                                            color: ThemeManager.getColor("textSecondary")
                                        }

                                        Text {
                                            text: "Coming soon"
                                            font.pixelSize: ThemeManager.getFontSize("small")
                                            font.family: ThemeManager.getFont("body")
                                            color: ThemeManager.getColor("textSecondary")
                                        }
                                    }
                                }

                                MouseArea {
                                    id: gogCardArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    onEntered: {
                                        clientsFocusIndex = 2
                                        focusState = "content"
                                        gamesRoot.forceActiveFocus()
                                    }
                                }

                                Behavior on border.color { ColorAnimation { duration: 150 } }
                            }

                            // ── Heroic (placeholder) ──
                            Rectangle {
                                width: 220
                                height: 72
                                radius: 12
                                color: Qt.rgba(ThemeManager.getColor("surface").r,
                                               ThemeManager.getColor("surface").g,
                                               ThemeManager.getColor("surface").b, 0.4)
                                border.color: (heroicCardArea.containsMouse || (focusState === "content" && activeTab === 1 && clientsFocusIndex === 3))
                                              ? ThemeManager.getColor("focus") : "transparent"
                                border.width: (heroicCardArea.containsMouse || (focusState === "content" && activeTab === 1 && clientsFocusIndex === 3)) ? 2 : 0

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.margins: 12
                                    spacing: 12

                                    Rectangle {
                                        Layout.preferredWidth: 44
                                        Layout.preferredHeight: 44
                                        radius: 10
                                        color: "#2a2a2a"

                                        Text {
                                            anchors.centerIn: parent
                                            text: "H"
                                            font.pixelSize: 22
                                            font.bold: true
                                            color: "#888"
                                        }
                                    }

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 2

                                        Text {
                                            text: "Heroic"
                                            font.pixelSize: ThemeManager.getFontSize("medium")
                                            font.family: ThemeManager.getFont("body")
                                            font.bold: true
                                            color: ThemeManager.getColor("textSecondary")
                                        }

                                        Text {
                                            text: "Coming soon"
                                            font.pixelSize: ThemeManager.getFontSize("small")
                                            font.family: ThemeManager.getFont("body")
                                            color: ThemeManager.getColor("textSecondary")
                                        }
                                    }
                                }

                                MouseArea {
                                    id: heroicCardArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    onEntered: {
                                        clientsFocusIndex = 3
                                        focusState = "content"
                                        gamesRoot.forceActiveFocus()
                                    }
                                }

                                Behavior on border.color { ColorAnimation { duration: 150 } }
                            }
                        }

                        // ─── Steam Settings Panel (expandable) ───
                        Rectangle {
                            visible: gameStoresTab.steamSettingsOpen && GameManager.isSteamInstalled()
                            Layout.fillWidth: true
                            Layout.preferredHeight: steamSettingsCol.height + 32
                            radius: 12
                            color: ThemeManager.getColor("surface")
                            border.color: Qt.rgba(ThemeManager.getColor("primary").r,
                                                  ThemeManager.getColor("primary").g,
                                                  ThemeManager.getColor("primary").b, 0.3)
                            border.width: 1

                            ColumnLayout {
                                id: steamSettingsCol
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.margins: 16
                                spacing: 12

                                // Header
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 10

                                    Text {
                                        text: "Steam Settings"
                                        font.pixelSize: ThemeManager.getFontSize("medium")
                                        font.family: ThemeManager.getFont("body")
                                        font.bold: true
                                        color: ThemeManager.getColor("textPrimary")
                                    }

                                    Item { Layout.fillWidth: true }

                                    // Close button
                                    Rectangle {
                                        Layout.preferredWidth: 28
                                        Layout.preferredHeight: 28
                                        radius: 6
                                        color: closeSettingsArea.containsMouse
                                               ? ThemeManager.getColor("hover") : "transparent"

                                        Text {
                                            anchors.centerIn: parent
                                            text: "\u2715"
                                            font.pixelSize: 14
                                            color: ThemeManager.getColor("textSecondary")
                                        }

                                        MouseArea {
                                            id: closeSettingsArea
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: gameStoresTab.steamSettingsOpen = false
                                        }
                                    }
                                }

                                // Separator
                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 1
                                    color: Qt.rgba(1, 1, 1, 0.06)
                                }

                                // SteamCMD status row
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 10

                                    Text {
                                        text: "SteamCMD"
                                        font.pixelSize: ThemeManager.getFontSize("small")
                                        font.family: ThemeManager.getFont("body")
                                        color: ThemeManager.getColor("textSecondary")
                                        Layout.preferredWidth: 100
                                    }

                                    Rectangle {
                                        Layout.preferredWidth: 8
                                        Layout.preferredHeight: 8
                                        radius: 4
                                        color: GameManager.isSteamCmdAvailable()
                                               ? ThemeManager.getColor("accent") : "#ff6b6b"
                                    }

                                    Text {
                                        text: {
                                            if (GameManager.isSteamCmdAvailable()) {
                                                var user = GameManager.getSteamUsername()
                                                return user ? "Ready (" + user + ")" : "Ready"
                                            }
                                            return "Not configured"
                                        }
                                        font.pixelSize: ThemeManager.getFontSize("small")
                                        font.family: ThemeManager.getFont("body")
                                        color: ThemeManager.getColor("textPrimary")
                                        Layout.fillWidth: true
                                    }

                                    // Re-run setup wizard
                                    Rectangle {
                                        visible: !GameManager.isSteamSetupComplete()
                                        Layout.preferredWidth: setupBtnLabel.width + 24
                                        Layout.preferredHeight: 32
                                        radius: 6
                                        color: "#1b2838"

                                        Text {
                                            id: setupBtnLabel
                                            anchors.centerIn: parent
                                            text: "Run Setup"
                                            font.pixelSize: ThemeManager.getFontSize("small")
                                            font.family: ThemeManager.getFont("body")
                                            font.bold: true
                                            color: "#66c0f4"
                                        }

                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: steamSetupWizard.open()
                                        }
                                    }
                                }

                                // API Key status row
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 10

                                    Text {
                                        text: "API Key"
                                        font.pixelSize: ThemeManager.getFontSize("small")
                                        font.family: ThemeManager.getFont("body")
                                        color: ThemeManager.getColor("textSecondary")
                                        Layout.preferredWidth: 100
                                    }

                                    Rectangle {
                                        Layout.preferredWidth: 8
                                        Layout.preferredHeight: 8
                                        radius: 4
                                        color: GameManager.hasSteamApiKey()
                                               ? ThemeManager.getColor("accent") : "#ff6b6b"
                                    }

                                    Text {
                                        text: GameManager.hasSteamApiKey() ? "Configured" : "Not set"
                                        font.pixelSize: ThemeManager.getFontSize("small")
                                        font.family: ThemeManager.getFont("body")
                                        color: ThemeManager.getColor("textPrimary")
                                        Layout.fillWidth: true
                                    }

                                    Rectangle {
                                        visible: GameManager.hasSteamApiKey()
                                        Layout.preferredWidth: changeKeyLabel.width + 24
                                        Layout.preferredHeight: 32
                                        radius: 6
                                        color: "transparent"
                                        border.color: Qt.rgba(1, 1, 1, 0.12)
                                        border.width: 1

                                        Text {
                                            id: changeKeyLabel
                                            anchors.centerIn: parent
                                            text: "Change"
                                            font.pixelSize: ThemeManager.getFontSize("small")
                                            font.family: ThemeManager.getFont("body")
                                            color: ThemeManager.getColor("textSecondary")
                                        }

                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: GameManager.setSteamApiKey("")
                                        }
                                    }
                                }

                                // Steam ID row
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 10

                                    Text {
                                        text: "Steam ID"
                                        font.pixelSize: ThemeManager.getFontSize("small")
                                        font.family: ThemeManager.getFont("body")
                                        color: ThemeManager.getColor("textSecondary")
                                        Layout.preferredWidth: 100
                                    }

                                    Text {
                                        text: {
                                            var sid = GameManager.getDetectedSteamId()
                                            return sid ? sid : "Not detected"
                                        }
                                        font.pixelSize: ThemeManager.getFontSize("small")
                                        font.family: "monospace"
                                        color: ThemeManager.getColor("textPrimary")
                                        Layout.fillWidth: true
                                    }
                                }

                                // Separator
                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 1
                                    color: Qt.rgba(1, 1, 1, 0.06)
                                }

                                // Action buttons row
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 10

                                    // Fetch owned games (requires API key)
                                    Rectangle {
                                        visible: GameManager.hasSteamApiKey()
                                        Layout.preferredWidth: fetchLabel.width + 28
                                        Layout.preferredHeight: 36
                                        radius: 8
                                        color: gameStoresTab.steamFetching
                                               ? ThemeManager.getColor("textSecondary")
                                               : "#1b2838"

                                        Text {
                                            id: fetchLabel
                                            anchors.centerIn: parent
                                            text: gameStoresTab.steamFetching
                                                  ? "Fetching..."
                                                  : "Fetch All Owned Games"
                                            font.pixelSize: ThemeManager.getFontSize("small")
                                            font.family: ThemeManager.getFont("body")
                                            font.bold: true
                                            color: "white"
                                        }

                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: gameStoresTab.steamFetching
                                                         ? Qt.ArrowCursor : Qt.PointingHandCursor
                                            onClicked: {
                                                if (!gameStoresTab.steamFetching) {
                                                    gameStoresTab.steamFetching = true
                                                    gameStoresTab.steamFetchStatus = "Fetching owned games..."
                                                    GameManager.fetchSteamOwnedGames()
                                                }
                                            }
                                        }
                                    }

                                    Item { Layout.fillWidth: true }

                                    // Status text
                                    Text {
                                        visible: gameStoresTab.steamFetchStatus !== ""
                                        text: gameStoresTab.steamFetchStatus
                                        font.pixelSize: ThemeManager.getFontSize("small")
                                        font.family: ThemeManager.getFont("body")
                                        color: gameStoresTab.steamFetchStatus.startsWith("Error")
                                               ? "#ff6b6b" : ThemeManager.getColor("accent")
                                    }
                                }
                            }
                        }

                        Item { Layout.fillHeight: true }
                    }
                }
            }

            // ─── Tab 2: Game Store ───
            Item {
                id: gameStoreTab

                Loader {
                    id: gameStoreLoader
                    anchors.fill: parent
                    source: "../components/GameStorePage.qml"
                    active: activeTab === 2

                    onLoaded: {
                        if (item) {
                            item.requestNavFocus.connect(gamesRoot.requestNavFocus)
                        }
                    }
                }
            }
        }
    }

    // ── Steam Setup Wizard ──
    SteamSetupWizard {
        id: steamSetupWizard
        onClosed: gamesRoot.forceActiveFocus()
    }

    // ── Virtual Keyboard for WiFi password + credential dialogs ──
    VirtualKeyboard {
        id: gamesVirtualKeyboard
        anchors.fill: parent
        z: 1000

        property string targetField: ""  // "wifi" or "credential"

        onAccepted: function(text) {
            if (targetField === "wifi") {
                wifiPasswordField.text = text
                if (text.length > 0 && !gameStoresTab.wifiConnecting) {
                    gameStoresTab.wifiConnecting = true
                    gameStoresTab.wifiStatus = "Connecting..."
                    GameManager.connectToWifi(wifiSelectedSsid.text, text)
                }
            } else if (targetField === "credential") {
                credInput.text = text
            }
            targetField = ""
            gamesRoot.forceActiveFocus()
        }
        onCancelled: {
            targetField = ""
            gamesRoot.forceActiveFocus()
        }
    }

    // ── Load games on startup and when store scan completes ──
    // When luna-ui restarts after Steam login (via luna-session),
    // Component.onCompleted fires and picks up newly imported games.
    // Also auto-resume the setup wizard if we returned from Steam login.
    Component.onCompleted: {
        refreshGames()

        // Pre-start Steam silently so game launches are instant with no UI
        GameManager.ensureSteamRunning()

        // Check if we're returning from a Steam login (step 1 of wizard).
        // Two scenarios:
        // A) User had no API key yet: marker is "__setup_pending__" → clear and resume wizard
        // B) User already had a saved key (re-ran setup): key is preserved, but we
        //    still need to detect the "just returned from Steam login" state.
        var currentKey = GameManager.getSteamApiKey()
        if (currentKey === "__setup_pending__") {
            GameManager.setSteamApiKey("")  // Clear the marker
            if (GameManager.isSteamAvailable()) {
                // Steam login succeeded — jump to API key step
                steamSetupWizard.open()
            }
        }
    }

    // ── SteamCMD credential prompt dialog ──
    Rectangle {
        id: credentialDialog
        visible: false
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.7)
        z: 100

        property string pendingAppId: ""
        property string promptType: ""  // "password" or "steamguard"

        MouseArea { anchors.fill: parent; onClicked: {} } // block clicks behind

        Rectangle {
            anchors.centerIn: parent
            width: 420
            height: credDialogCol.height + 48
            radius: 16
            color: ThemeManager.getColor("surface")

            ColumnLayout {
                id: credDialogCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 24
                spacing: 12

                Text {
                    text: credentialDialog.promptType === "password"
                          ? "Steam Password Required"
                          : "Steam Guard Code Required"
                    font.pixelSize: ThemeManager.getFontSize("large")
                    font.family: ThemeManager.getFont("heading")
                    font.bold: true
                    color: ThemeManager.getColor("textPrimary")
                }

                Text {
                    text: credentialDialog.promptType === "password"
                          ? "SteamCMD needs your password for first-time login.\nCredentials are cached after the first successful login."
                          : "Enter the Steam Guard code sent to your email or authenticator app."
                    font.pixelSize: ThemeManager.getFontSize("small")
                    font.family: ThemeManager.getFont("body")
                    color: ThemeManager.getColor("textSecondary")
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 44
                    radius: 8
                    color: ThemeManager.getColor("hover")
                    border.color: (credInput.activeFocus || credDialogFocusIndex === 0)
                                  ? ThemeManager.getColor("focus") : "transparent"
                    border.width: (credInput.activeFocus || credDialogFocusIndex === 0) ? 3 : 0

                    Behavior on border.color { ColorAnimation { duration: 150 } }

                    TextInput {
                        id: credInput
                        anchors.fill: parent
                        anchors.margins: 12
                        verticalAlignment: TextInput.AlignVCenter
                        font.pixelSize: ThemeManager.getFontSize("medium")
                        font.family: ThemeManager.getFont("body")
                        color: ThemeManager.getColor("textPrimary")
                        echoMode: credentialDialog.promptType === "password"
                                  ? TextInput.Password : TextInput.Normal
                        clip: true
                        onAccepted: {
                            if (text.length > 0) {
                                GameManager.provideSteamCmdCredential(
                                    credentialDialog.pendingAppId, text)
                                text = ""
                                credentialDialog.visible = false
                                gamesRoot.forceActiveFocus()
                            }
                        }
                    }

                    Text {
                        anchors.fill: parent
                        anchors.margins: 12
                        verticalAlignment: Text.AlignVCenter
                        visible: credInput.text === "" && !credInput.activeFocus
                        text: credentialDialog.promptType === "password"
                              ? "Enter password..." : "Enter code..."
                        font.pixelSize: ThemeManager.getFontSize("medium")
                        font.family: ThemeManager.getFont("body")
                        color: ThemeManager.getColor("textSecondary")
                    }
                }

                RowLayout {
                    spacing: 10

                    Rectangle {
                        Layout.preferredWidth: submitCredLabel.width + 32
                        Layout.preferredHeight: 40
                        radius: 8
                        color: ThemeManager.getColor("primary")
                        border.color: credDialogFocusIndex === 1
                                      ? ThemeManager.getColor("focus") : "transparent"
                        border.width: credDialogFocusIndex === 1 ? 3 : 0

                        Behavior on border.color { ColorAnimation { duration: 150 } }

                        Text {
                            id: submitCredLabel
                            anchors.centerIn: parent
                            text: "Submit"
                            font.pixelSize: ThemeManager.getFontSize("small")
                            font.family: ThemeManager.getFont("body")
                            font.bold: true
                            color: "white"
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (credInput.text.length > 0) {
                                    GameManager.provideSteamCmdCredential(
                                        credentialDialog.pendingAppId, credInput.text)
                                    credInput.text = ""
                                    credentialDialog.visible = false
                                    gamesRoot.forceActiveFocus()
                                }
                            }
                        }
                    }

                    Rectangle {
                        Layout.preferredWidth: cancelCredLabel.width + 32
                        Layout.preferredHeight: 40
                        radius: 8
                        color: ThemeManager.getColor("surface")
                        border.color: credDialogFocusIndex === 2
                                      ? ThemeManager.getColor("focus")
                                      : Qt.rgba(1, 1, 1, 0.15)
                        border.width: credDialogFocusIndex === 2 ? 3 : 1

                        Behavior on border.color { ColorAnimation { duration: 150 } }

                        Text {
                            id: cancelCredLabel
                            anchors.centerIn: parent
                            text: "Cancel"
                            font.pixelSize: ThemeManager.getFontSize("small")
                            font.family: ThemeManager.getFont("body")
                            color: ThemeManager.getColor("textSecondary")
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                credInput.text = ""
                                GameManager.cancelDownload(credentialDialog.pendingAppId)
                                credentialDialog.visible = false
                                gamesRoot.forceActiveFocus()
                            }
                        }
                    }
                }
            }
        }
    }

    // ── Game Launch Overlay ──
    Rectangle {
        id: launchOverlay
        visible: false
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.85)
        z: 200

        property string gameTitle: ""
        property bool isError: false
        property string errorMessage: ""

        MouseArea { anchors.fill: parent; onClicked: {} } // block clicks behind

        ColumnLayout {
            anchors.centerIn: parent
            spacing: 20
            width: 400

            // Spinner (visible during loading, not during error)
            Item {
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: 64
                Layout.preferredHeight: 64
                visible: !launchOverlay.isError

                Rectangle {
                    id: spinnerRing
                    anchors.centerIn: parent
                    width: 56
                    height: 56
                    radius: 28
                    color: "transparent"
                    border.width: 4
                    border.color: Qt.rgba(1, 1, 1, 0.1)

                    Rectangle {
                        width: 56
                        height: 56
                        radius: 28
                        color: "transparent"
                        border.width: 4
                        border.color: "transparent"

                        // Arc segment
                        Rectangle {
                            width: 14
                            height: 4
                            radius: 2
                            color: ThemeManager.getColor("primary")
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.top: parent.top
                        }
                        Rectangle {
                            width: 4
                            height: 14
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
                            running: launchOverlay.visible && !launchOverlay.isError
                        }
                    }
                }
            }

            // Error icon (visible during error)
            Rectangle {
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: 56
                Layout.preferredHeight: 56
                radius: 28
                color: Qt.rgba(1, 0.3, 0.3, 0.15)
                visible: launchOverlay.isError

                Text {
                    anchors.centerIn: parent
                    text: "!"
                    font.pixelSize: 28
                    font.bold: true
                    color: "#ff6b6b"
                }
            }

            // Title text
            Text {
                Layout.alignment: Qt.AlignHCenter
                text: launchOverlay.isError
                      ? "Launch Failed"
                      : "Starting Game..."
                font.pixelSize: ThemeManager.getFontSize("xlarge")
                font.family: ThemeManager.getFont("heading")
                font.bold: true
                color: launchOverlay.isError
                       ? "#ff6b6b"
                       : ThemeManager.getColor("textPrimary")
            }

            // Game name
            Text {
                Layout.alignment: Qt.AlignHCenter
                text: launchOverlay.gameTitle
                font.pixelSize: ThemeManager.getFontSize("large")
                font.family: ThemeManager.getFont("body")
                color: ThemeManager.getColor("textSecondary")
                elide: Text.ElideRight
                Layout.maximumWidth: 380
                horizontalAlignment: Text.AlignHCenter
            }

            // Error message (only visible on error)
            Text {
                Layout.alignment: Qt.AlignHCenter
                visible: launchOverlay.isError && launchOverlay.errorMessage !== ""
                text: launchOverlay.errorMessage
                font.pixelSize: ThemeManager.getFontSize("small")
                font.family: ThemeManager.getFont("body")
                color: ThemeManager.getColor("textSecondary")
                wrapMode: Text.WordWrap
                Layout.maximumWidth: 360
                horizontalAlignment: Text.AlignHCenter
            }

            // Dismiss button (visible on error)
            Rectangle {
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: dismissLabel.width + 40
                Layout.preferredHeight: 40
                radius: 8
                visible: launchOverlay.isError
                color: dismissBtnArea.containsMouse
                       ? ThemeManager.getColor("hover")
                       : ThemeManager.getColor("surface")
                border.color: dismissBtnArea.containsMouse
                              ? ThemeManager.getColor("focus") : Qt.rgba(1, 1, 1, 0.15)
                border.width: dismissBtnArea.containsMouse ? 2 : 1

                Text {
                    id: dismissLabel
                    anchors.centerIn: parent
                    text: "Dismiss"
                    font.pixelSize: ThemeManager.getFontSize("small")
                    font.family: ThemeManager.getFont("body")
                    font.bold: true
                    color: ThemeManager.getColor("textPrimary")
                }

                MouseArea {
                    id: dismissBtnArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: launchOverlay.visible = false
                }

                Behavior on border.color { ColorAnimation { duration: 150 } }
            }
        }

        // Auto-dismiss timer for successful launches
        Timer {
            id: launchDismissTimer
            interval: 5000
            onTriggered: {
                if (!launchOverlay.isError) {
                    launchOverlay.visible = false
                }
            }
        }
    }

    Connections {
        target: GameManager
        function onGamesUpdated() { refreshGames() }

        function onDownloadStarted(appId, gameId) {
            // Find the game in the model and set its progress to 0
            for (var i = 0; i < gamesModel.count; i++) {
                if (gamesModel.get(i).id === gameId) {
                    gamesModel.setProperty(i, "downloadProgress", 0.0)
                    gamesModel.setProperty(i, "installError", "")
                    break
                }
            }
        }

        function onDownloadProgressChanged(appId, progress) {
            // Update progress for the matching game
            for (var i = 0; i < gamesModel.count; i++) {
                if (gamesModel.get(i).appId === appId) {
                    gamesModel.setProperty(i, "downloadProgress", progress)
                    if (progress < 0) {
                        gamesModel.setProperty(i, "installError", "")
                    }
                    break
                }
            }
        }

        function onDownloadComplete(appId, gameId) {
            // Mark as installed and clear download progress
            for (var i = 0; i < gamesModel.count; i++) {
                if (gamesModel.get(i).id === gameId) {
                    gamesModel.setProperty(i, "isInstalled", true)
                    gamesModel.setProperty(i, "downloadProgress", -1.0)
                    gamesModel.setProperty(i, "installError", "")
                    break
                }
            }
        }

        function onInstallError(appId, error) {
            // Show error on the matching game card
            for (var i = 0; i < gamesModel.count; i++) {
                if (gamesModel.get(i).appId === appId) {
                    gamesModel.setProperty(i, "installError", error)
                    gamesModel.setProperty(i, "downloadProgress", -1.0)
                    break
                }
            }
        }

        function onSteamCmdCredentialNeeded(appId, promptType) {
            credentialDialog.pendingAppId = appId
            credentialDialog.promptType = promptType
            credentialDialog.visible = true
            credDialogFocusIndex = 0
            gamesRoot.forceActiveFocus()
        }

        function onGameLaunched(gameId, gameTitle) {
            // Show Luna's loading circle while the game starts.
            // This replaces Steam's "Preparing to launch..." dialog
            // (suppressed via SteamNoOverlayUIDrawing env var).
            launchOverlay.gameTitle = gameTitle
            launchOverlay.isError = false
            launchOverlay.errorMessage = ""
            launchOverlay.visible = true
            launchDismissTimer.start()

            // Load game-specific controller profile context
            var game = GameManager.getGameById(gameId)
            if (game) {
                ControllerManager.setGameContext(game.storeSource || "", gameId)
            }
        }

        function onGameExited(gameId) {
            // Revert to UI navigation controller profile
            ControllerManager.clearGameContext()
        }

        function onGameLaunchError(gameId, gameTitle, error) {
            launchOverlay.gameTitle = gameTitle
            launchOverlay.isError = true
            launchOverlay.errorMessage = error
            launchOverlay.visible = true
            launchDismissTimer.stop()
        }
    }

    function refreshGames() {
        gamesModel.clear()
        var games = GameManager.getGames()
        for (var i = 0; i < games.length; i++) {
            games[i].downloadProgress = GameManager.isDownloading(games[i].appId)
                ? GameManager.getDownloadProgress(games[i].appId)
                : -1.0
            games[i].installError = ""
            gamesModel.append(games[i])
        }
    }
}
