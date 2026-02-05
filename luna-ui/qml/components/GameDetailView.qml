import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Rectangle {
    id: detailView
    color: ThemeManager.getColor("background")

    property var gameData: null

    signal backClicked()
    signal playClicked(int id)
    signal favoriteClicked(int id)

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 24
        spacing: 16

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

        Item { Layout.fillHeight: true }
    }
}
