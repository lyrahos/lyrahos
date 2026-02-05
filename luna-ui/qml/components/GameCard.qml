import QtQuick
import QtQuick.Controls
import Qt5Compat.GraphicalEffects   // FIX #42: Import for OpacityMask

Rectangle {
    id: card
    width: 180
    height: 270
    radius: 12
    color: ThemeManager.getColor("surface")
    border.color: focus ? ThemeManager.getColor("focus") : "transparent"
    border.width: focus ? 2 : 0

    property string gameTitle: ""
    property string coverArt: ""
    property bool isFavorite: false
    property int gameId: -1

    signal playClicked(int id)
    signal favoriteClicked(int id)

    // FIX #8: Image doesn't have a radius property. Use layer + OpacityMask.
    Image {
        id: coverImage
        anchors.fill: parent
        anchors.margins: 4
        source: coverArt || ""
        fillMode: Image.PreserveAspectCrop
        visible: false  // Hidden; rendered via OpacityMask
    }

    Rectangle {
        id: coverMask
        anchors.fill: coverImage
        radius: 8
        visible: false
    }

    OpacityMask {
        anchors.fill: coverImage
        source: coverImage
        maskSource: coverMask
        visible: coverImage.status === Image.Ready
    }

    // Placeholder if no art loaded
    Rectangle {
        visible: coverImage.status !== Image.Ready
        anchors.fill: parent
        anchors.margins: 4
        radius: 8
        color: ThemeManager.getColor("surface")
        Text {
            anchors.centerIn: parent
            text: gameTitle.length > 0 ? gameTitle.charAt(0).toUpperCase() : "?"
            font.pixelSize: 48
            font.bold: true
            color: ThemeManager.getColor("primary")
        }
    }

    // Title overlay at bottom
    Rectangle {
        anchors.bottom: parent.bottom
        width: parent.width
        height: 48
        radius: 8
        color: Qt.rgba(0, 0, 0, 0.7)

        Text {
            anchors.centerIn: parent
            text: gameTitle
            font.pixelSize: 12
            font.family: ThemeManager.getFont("body")
            color: ThemeManager.getColor("textPrimary")
            elide: Text.ElideRight
            width: parent.width - 16
            horizontalAlignment: Text.AlignHCenter
        }
    }

    // Favorite indicator
    Text {
        visible: isFavorite
        text: "*"
        font.pixelSize: 20
        font.bold: true
        color: "#FFD700"
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: 8
    }

    // Hover effect: scale 1.05x
    scale: mouseArea.containsMouse ? 1.05 : 1.0
    Behavior on scale { NumberAnimation { duration: 150 } }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        onClicked: playClicked(gameId)
    }
}
