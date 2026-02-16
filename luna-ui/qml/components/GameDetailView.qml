import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Rectangle {
    id: detailView
    color: ThemeManager.getColor("background")

    property var gameData: null
    property bool controllerEditorOpen: false
    property int gameProfileId: -1

    signal backClicked()
    signal playClicked(int id)
    signal favoriteClicked(int id)

    function findOrCreateGameProfile() {
        if (!gameData) return
        // Look for existing game profile
        var profiles = ProfileResolver.getProfiles("game")
        for (var i = 0; i < profiles.length; i++) {
            if (profiles[i].gameId === gameData.id) {
                gameProfileId = profiles[i].id
                return
            }
        }
        // Create one
        var family = ControllerManager.controllerFamily || "any"
        gameProfileId = ProfileResolver.createProfile(
            gameData.title + " Profile", "game", family,
            gameData.storeSource || "", gameData.id)
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 24
        spacing: 16
        visible: !controllerEditorOpen

        // Back button
        Text {
            text: "< Back"
            font.pixelSize: 16
            color: ThemeManager.getColor("primary")
            MouseArea {
                anchors.fill: parent
                onClicked: backClicked()
            }
        }

        // Game title
        Text {
            text: gameData ? gameData.title : ""
            font.pixelSize: ThemeManager.getFontSize("xlarge")
            font.family: ThemeManager.getFont("heading")
            font.bold: true
            color: ThemeManager.getColor("textPrimary")
        }

        // Action buttons row
        RowLayout {
            spacing: 12

            // Play button
            Rectangle {
                width: 200
                height: 50
                radius: 8
                color: ThemeManager.getColor("primary")

                Text {
                    anchors.centerIn: parent
                    text: "Play"
                    font.pixelSize: 18
                    font.bold: true
                    color: "white"
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: if (gameData) playClicked(gameData.id)
                }
            }

            // Controller profile button
            Rectangle {
                width: controllerBtnText.width + 32
                height: 50
                radius: 8
                color: controllerBtnArea.containsMouse
                       ? Qt.rgba(ThemeManager.getColor("secondary").r,
                                 ThemeManager.getColor("secondary").g,
                                 ThemeManager.getColor("secondary").b, 0.2)
                       : ThemeManager.getColor("surface")
                border.color: controllerBtnArea.containsMouse
                              ? ThemeManager.getColor("secondary") : Qt.rgba(1, 1, 1, 0.1)
                border.width: 1

                Text {
                    id: controllerBtnText
                    anchors.centerIn: parent
                    text: "Controller"
                    font.pixelSize: 16
                    color: ThemeManager.getColor("secondary")
                }

                MouseArea {
                    id: controllerBtnArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        findOrCreateGameProfile()
                        controllerEditorOpen = true
                    }
                }

                Behavior on color { ColorAnimation { duration: 150 } }
            }
        }

        Item { Layout.fillHeight: true }
    }

    // Controller profile editor overlay
    ControllerProfileEditor {
        visible: controllerEditorOpen
        anchors.fill: parent
        anchors.margins: 24
        profileId: gameProfileId
        profileName: gameData ? gameData.title + " Controls" : "Game Controls"
        isDefault: false
        onBackRequested: controllerEditorOpen = false
    }
}
