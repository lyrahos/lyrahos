import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../components"

Rectangle {
    id: gamesRoot
    color: "transparent"

    property int activeTab: 0   // 0 = My Games, 1 = Game Stores
    onActiveTabChanged: if (activeTab === 0) refreshGames()

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
                    model: ["My Games", "Game Stores"]

                    Rectangle {
                        width: 160
                        height: tabRow.height
                        color: "transparent"

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
                            cursorShape: Qt.PointingHandCursor
                            onClicked: activeTab = index
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

                    delegate: GameCard {
                        gameTitle: model.title
                        coverArt: model.coverArtUrl || ""
                        isFavorite: model.isFavorite || false
                        isInstalled: model.isInstalled !== undefined ? model.isInstalled : true
                        gameId: model.id
                        appId: model.appId || ""
                        downloadProgress: model.downloadProgress !== undefined ? model.downloadProgress : -1.0
                        installError: model.installError !== undefined ? model.installError : ""

                        onPlayClicked: function(id) {
                            GameManager.launchGame(id)
                        }
                        onCancelClicked: function(appId) {
                            GameManager.cancelDownload(appId)
                        }
                    }

                    ScrollBar.vertical: ScrollBar {
                        policy: ScrollBar.AsNeeded
                    }
                }
            }

            // ─── Tab 1: Game Stores ───
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
                                var networks = GameManager.getWifiNetworks()
                                for (var i = 0; i < networks.length; i++)
                                    wifiListModel.append(networks[i])
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
                                        var networks = GameManager.getWifiNetworks()
                                        for (var i = 0; i < networks.length; i++)
                                            wifiListModel.append(networks[i])
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
                                            wifiPasswordField.forceActiveFocus()
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
                                border.color: steamCardArea.containsMouse
                                              ? ThemeManager.getColor("focus") : "transparent"
                                border.width: steamCardArea.containsMouse ? 2 : 0

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
                            }

                            // ── GOG (placeholder) ──
                            Rectangle {
                                width: 220
                                height: 72
                                radius: 12
                                color: Qt.rgba(ThemeManager.getColor("surface").r,
                                               ThemeManager.getColor("surface").g,
                                               ThemeManager.getColor("surface").b, 0.4)

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
                            }

                            // ── Heroic (placeholder) ──
                            Rectangle {
                                width: 220
                                height: 72
                                radius: 12
                                color: Qt.rgba(ThemeManager.getColor("surface").r,
                                               ThemeManager.getColor("surface").g,
                                               ThemeManager.getColor("surface").b, 0.4)

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

                                    // Scan library
                                    Rectangle {
                                        Layout.preferredWidth: scanLibLabel.width + 28
                                        Layout.preferredHeight: 36
                                        radius: 8
                                        color: ThemeManager.getColor("primary")

                                        Text {
                                            id: scanLibLabel
                                            anchors.centerIn: parent
                                            text: "Scan Library"
                                            font.pixelSize: ThemeManager.getFontSize("small")
                                            font.family: ThemeManager.getFont("body")
                                            font.bold: true
                                            color: "white"
                                        }

                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                GameManager.scanAllStores()
                                                refreshGames()
                                            }
                                        }
                                    }

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
        }
    }

    // ── Steam Setup Wizard ──
    SteamSetupWizard {
        id: steamSetupWizard
    }

    // ── Load games on startup and when store scan completes ──
    // When luna-ui restarts after Steam login (via luna-session),
    // Component.onCompleted fires and picks up newly imported games.
    // Also auto-resume the setup wizard if we returned from Steam login.
    Component.onCompleted: {
        refreshGames()

        // Check if we're returning from a Steam login (step 1 of wizard).
        // The wizard sets "__setup_pending__" as API key before launching Steam.
        if (GameManager.getSteamApiKey() === "__setup_pending__") {
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
                    border.color: credInput.activeFocus
                                  ? ThemeManager.getColor("focus") : "transparent"
                    border.width: credInput.activeFocus ? 2 : 0

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
                                }
                            }
                        }
                    }

                    Rectangle {
                        Layout.preferredWidth: cancelCredLabel.width + 32
                        Layout.preferredHeight: 40
                        radius: 8
                        color: ThemeManager.getColor("surface")
                        border.color: Qt.rgba(1, 1, 1, 0.15)
                        border.width: 1

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
            credInput.forceActiveFocus()
        }

        function onGameLaunched(gameId, gameTitle) {
            launchOverlay.gameTitle = gameTitle
            launchOverlay.isError = false
            launchOverlay.errorMessage = ""
            launchOverlay.visible = true
            launchDismissTimer.restart()
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
