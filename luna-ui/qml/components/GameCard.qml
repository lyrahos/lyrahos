import QtQuick
import QtQuick.Controls

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
    property bool isInstalled: true
    property real downloadProgress: 0.0   // 0-1 while downloading
    property int gameId: -1

    signal playClicked(int id)
    signal installClicked(int id)
    signal favoriteClicked(int id)

    // Rounded cover art using clip instead of Qt5Compat.GraphicalEffects
    Rectangle {
        id: coverContainer
        anchors.fill: parent
        anchors.margins: 4
        radius: 8
        clip: true
        color: "transparent"

        Image {
            id: coverImage
            anchors.fill: parent
            source: coverArt || ""
            fillMode: Image.PreserveAspectCrop
            visible: status === Image.Ready
        }

        // Placeholder if no art loaded
        Rectangle {
            visible: coverImage.status !== Image.Ready
            anchors.fill: parent
            color: ThemeManager.getColor("surface")

            Text {
                anchors.centerIn: parent
                text: gameTitle.length > 0 ? gameTitle.charAt(0).toUpperCase() : "?"
                font.pixelSize: 48
                font.bold: true
                color: ThemeManager.getColor("primary")
            }
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

    // Dim overlay for uninstalled games
    Rectangle {
        visible: !isInstalled && downloadProgress <= 0
        anchors.fill: parent
        radius: 12
        color: Qt.rgba(0, 0, 0, 0.35)
    }

    // Download badge — bottom-right corner
    Rectangle {
        visible: !isInstalled && downloadProgress <= 0
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.rightMargin: 12
        anchors.bottomMargin: 56   // above the title bar
        width: 30; height: 30
        radius: 15
        color: Qt.rgba(0, 0, 0, 0.7)
        border.color: ThemeManager.getColor("accent")
        border.width: 1.5

        // Down-arrow + tray drawn with Canvas for a crisp download icon
        Canvas {
            anchors.centerIn: parent
            width: 16; height: 16
            onPaint: {
                var ctx = getContext("2d")
                ctx.clearRect(0, 0, width, height)
                var c = ThemeManager.getColor("accent")
                ctx.strokeStyle = Qt.rgba(c.r, c.g, c.b, 1)
                ctx.lineWidth = 2
                ctx.lineCap = "round"
                ctx.lineJoin = "round"
                // Vertical shaft
                ctx.beginPath()
                ctx.moveTo(8, 1)
                ctx.lineTo(8, 10)
                ctx.stroke()
                // Arrow head
                ctx.beginPath()
                ctx.moveTo(4, 7)
                ctx.lineTo(8, 11)
                ctx.lineTo(12, 7)
                ctx.stroke()
                // Tray baseline
                ctx.beginPath()
                ctx.moveTo(2, 14)
                ctx.lineTo(14, 14)
                ctx.stroke()
            }
        }
    }

    // Download progress bar
    Rectangle {
        visible: !isInstalled && downloadProgress > 0
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        height: 4
        radius: 2
        color: Qt.rgba(0, 0, 0, 0.5)

        Rectangle {
            width: parent.width * downloadProgress
            height: parent.height
            radius: 2
            color: ThemeManager.getColor("primary")
            Behavior on width { NumberAnimation { duration: 300 } }
        }
    }

    // Hover effect: scale 1.05x
    scale: mouseArea.containsMouse ? 1.05 : 1.0
    Behavior on scale { NumberAnimation { duration: 150 } }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        onClicked: {
            if (isInstalled)
                playClicked(gameId)
            else
                installClicked(gameId)
        }
    }
}
