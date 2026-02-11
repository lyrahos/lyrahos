import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../components"

Rectangle {
    id: gamesRoot
    color: "transparent"

    property int activeTab: 0   // 0 = My Games, 1 = Game Stores

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
                        gameId: model.id

                        onPlayClicked: function(id) {
                            GameManager.launchGame(id)
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
                            Layout.bottomMargin: 8
                        }

                        // ─── Steam Store Card ───
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 120
                            radius: 12
                            color: ThemeManager.getColor("surface")
                            border.color: steamArea.containsMouse
                                          ? ThemeManager.getColor("focus") : "transparent"
                            border.width: steamArea.containsMouse ? 2 : 0

                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: 20
                                spacing: 20

                                // Steam icon placeholder
                                Rectangle {
                                    Layout.preferredWidth: 64
                                    Layout.preferredHeight: 64
                                    radius: 12
                                    color: "#1b2838"

                                    Text {
                                        anchors.centerIn: parent
                                        text: "S"
                                        font.pixelSize: 32
                                        font.bold: true
                                        color: "#66c0f4"
                                    }
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 6

                                    Text {
                                        text: "Steam"
                                        font.pixelSize: ThemeManager.getFontSize("large")
                                        font.family: ThemeManager.getFont("body")
                                        font.bold: true
                                        color: ThemeManager.getColor("textPrimary")
                                    }

                                    Text {
                                        id: steamStatus
                                        font.pixelSize: ThemeManager.getFontSize("small")
                                        font.family: ThemeManager.getFont("body")
                                        color: ThemeManager.getColor("textSecondary")
                                        text: {
                                            if (!GameManager.isSteamInstalled())
                                                return "Not installed"
                                            if (GameManager.isSteamAvailable())
                                                return "Connected — library detected"
                                            return "Installed — log in to import games"
                                        }
                                    }
                                }

                                // Action button
                                Rectangle {
                                    Layout.preferredWidth: steamBtnText.width + 32
                                    Layout.preferredHeight: 40
                                    radius: 8
                                    color: {
                                        if (!GameManager.isSteamInstalled())
                                            return ThemeManager.getColor("textSecondary")
                                        if (GameManager.isSteamAvailable())
                                            return ThemeManager.getColor("primary")
                                        return "#1b2838"
                                    }

                                    Text {
                                        id: steamBtnText
                                        anchors.centerIn: parent
                                        font.pixelSize: ThemeManager.getFontSize("small")
                                        font.family: ThemeManager.getFont("body")
                                        font.bold: true
                                        color: "white"
                                        text: {
                                            if (!GameManager.isSteamInstalled())
                                                return "Not Available"
                                            if (GameManager.isSteamAvailable())
                                                return "Scan Library"
                                            return "Log In"
                                        }
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: GameManager.isSteamInstalled()
                                                     ? Qt.PointingHandCursor : Qt.ArrowCursor
                                        onClicked: {
                                            if (!GameManager.isSteamInstalled())
                                                return
                                            if (GameManager.isSteamAvailable()) {
                                                // Rescan Steam library
                                                GameManager.scanAllStores()
                                                refreshGames()
                                                activeTab = 0
                                            } else {
                                                // Exit luna-ui and signal luna-session
                                                // to launch Steam directly as gamescope's
                                                // child. luna-session restarts luna-ui
                                                // when Steam exits.
                                                GameManager.launchSteamLogin()
                                            }
                                        }
                                    }
                                }
                            }

                            MouseArea {
                                id: steamArea
                                anchors.fill: parent
                                z: -1
                                hoverEnabled: true
                                acceptedButtons: Qt.NoButton
                            }

                            Behavior on border.color { ColorAnimation { duration: 150 } }
                        }

                        // ─── More stores coming soon ───
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 80
                            radius: 12
                            color: Qt.rgba(ThemeManager.getColor("surface").r,
                                           ThemeManager.getColor("surface").g,
                                           ThemeManager.getColor("surface").b, 0.4)

                            Text {
                                anchors.centerIn: parent
                                text: "More stores coming soon (Epic, GOG, Lutris, Heroic)"
                                font.pixelSize: ThemeManager.getFontSize("small")
                                font.family: ThemeManager.getFont("body")
                                color: ThemeManager.getColor("textSecondary")
                            }
                        }

                        Item { Layout.fillHeight: true }
                    }
                }
            }
        }
    }

    // ── Load games on startup and when store scan completes ──
    // When luna-ui restarts after Steam login (via luna-session),
    // Component.onCompleted fires and picks up newly imported games.
    Component.onCompleted: refreshGames()

    Connections {
        target: GameManager
        function onGamesUpdated() { refreshGames() }
    }

    function refreshGames() {
        gamesModel.clear()
        var games = GameManager.getGames()
        for (var i = 0; i < games.length; i++) {
            gamesModel.append(games[i])
        }
    }
}
