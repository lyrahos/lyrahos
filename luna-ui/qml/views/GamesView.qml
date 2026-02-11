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

                // Refresh network status when tab becomes visible
                Timer {
                    id: networkCheckTimer
                    interval: 3000
                    running: activeTab === 1
                    repeat: true
                    onTriggered: gameStoresTab.hasNetwork = GameManager.isNetworkAvailable()
                }
                Component.onCompleted: hasNetwork = GameManager.isNetworkAvailable()

                // ─── Offline state ───
                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: 16
                    visible: !gameStoresTab.hasNetwork

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
