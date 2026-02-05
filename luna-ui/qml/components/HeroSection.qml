import QtQuick
import QtQuick.Controls

Rectangle {
    id: heroSection
    height: 300
    color: "transparent"

    property string gameTitle: ""
    property string backgroundArt: ""
    property int gameId: -1

    signal playClicked(int id)

    Image {
        anchors.fill: parent
        source: backgroundArt || ""
        fillMode: Image.PreserveAspectCrop
        opacity: 0.6
    }

    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: "transparent" }
            GradientStop { position: 1.0; color: ThemeManager.getColor("background") }
        }
    }

    Column {
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.margins: 32
        spacing: 12

        Text {
            text: gameTitle
            font.pixelSize: ThemeManager.getFontSize("xlarge")
            font.family: ThemeManager.getFont("heading")
            font.bold: true
            color: ThemeManager.getColor("textPrimary")
        }

        Rectangle {
            width: 120
            height: 40
            radius: 8
            color: ThemeManager.getColor("primary")

            Text {
                anchors.centerIn: parent
                text: "Play"
                font.pixelSize: 16
                font.bold: true
                color: "white"
            }

            MouseArea {
                anchors.fill: parent
                onClicked: playClicked(gameId)
            }
        }
    }
}
