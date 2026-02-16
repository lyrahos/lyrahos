import QtQuick
import QtQuick.Controls

Rectangle {
    id: card
    width: 180
    height: 270
    radius: 12
    color: ThemeManager.getColor("surface")

    // Purple outline when keyboard-focused OR mouse-hovered
    border.color: (isKeyboardFocused || mouseArea.containsMouse)
                  ? ThemeManager.getColor("focus") : "transparent"
    border.width: (isKeyboardFocused || mouseArea.containsMouse) ? 2 : 0

    property string gameTitle: ""
    property string coverArt: ""
    property bool isFavorite: false
    property bool isInstalled: true
    property int gameId: -1
    property string appId: ""
    property double downloadProgress: -1.0  // -1 = not downloading, 0..1 = progress
    property string installError: ""        // non-empty = error during install
    property bool isKeyboardFocused: false  // Set by parent grid when this card is selected via keyboard

    signal playClicked(int id)
    signal favoriteClicked(int id)
    signal cancelClicked(string appId)
    signal cardHovered()

    // Resolve cover art through ArtworkManager (handles caching + async download)
    property string resolvedArt: {
        if (!coverArt || coverArt.length === 0) return ""
        var cached = ArtworkManager.getCoverArt(gameId, coverArt)
        return cached || ""
    }

    // When ArtworkManager finishes downloading, update the source
    Connections {
        target: ArtworkManager
        function onArtworkReady(readyGameId, localPath) {
            if (readyGameId === gameId) {
                coverImage.source = "file://" + localPath
            }
        }
    }

    // Retry timer — if image fails, retry a few times with backoff
    Timer {
        id: retryTimer
        property int attempt: 0
        interval: 3000
        onTriggered: {
            if (attempt < 3 && coverImage.status === Image.Error) {
                // Force QML Image to re-request by toggling source
                var src = coverImage.source
                coverImage.source = ""
                coverImage.source = src
                attempt++
                interval = interval * 2
                start()
            }
        }
    }

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
            source: {
                if (resolvedArt.length > 0) {
                    // Local paths need file:// prefix, URLs stay as-is
                    if (resolvedArt.startsWith("/"))
                        return "file://" + resolvedArt
                    return resolvedArt
                }
                // Fall back to direct URL (QML can load http:// natively)
                if (coverArt && coverArt.length > 0)
                    return coverArt
                return ""
            }
            // Always use PreserveAspectFit so artwork is never zoomed or
            // cropped. Some Steam games have non-standard cover art sizes
            // that look wrong when AspectCrop zooms into a tiny slice.
            // For proper 600x900 library images the card is nearly
            // exactly 2:3, so the fit is virtually identical to crop.
            fillMode: Image.PreserveAspectFit
            visible: status === Image.Ready
            opacity: isInstalled ? 1.0 : (downloadProgress >= 0 ? 0.7 : 0.5)
            asynchronous: true
            cache: true

            onStatusChanged: {
                if (status === Image.Error && retryTimer.attempt < 3) {
                    retryTimer.start()
                }
            }
        }

        // Placeholder if no art loaded
        Rectangle {
            visible: coverImage.status !== Image.Ready
            anchors.fill: parent
            color: ThemeManager.getColor("surface")
            opacity: isInstalled ? 1.0 : (downloadProgress >= 0 ? 0.7 : 0.5)

            Text {
                anchors.centerIn: parent
                text: gameTitle.length > 0 ? gameTitle.charAt(0).toUpperCase() : "?"
                font.pixelSize: 48
                font.bold: true
                color: ThemeManager.getColor("primary")
            }
        }

        // Download progress bar overlay
        Rectangle {
            id: downloadOverlay
            visible: downloadProgress >= 0
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 6
            color: Qt.rgba(0, 0, 0, 0.5)
            radius: 3

            Rectangle {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: parent.width * Math.max(0, downloadProgress)
                radius: 3
                color: ThemeManager.getColor("accent")

                Behavior on width { NumberAnimation { duration: 300 } }
            }
        }
    }

    // Title overlay at bottom
    Rectangle {
        anchors.bottom: parent.bottom
        width: parent.width
        height: isInstalled ? 48 : 64
        radius: 8
        color: Qt.rgba(0, 0, 0, 0.7)

        Column {
            anchors.centerIn: parent
            spacing: 2

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: gameTitle
                font.pixelSize: 12
                font.family: ThemeManager.getFont("body")
                color: ThemeManager.getColor("textPrimary")
                elide: Text.ElideRight
                width: card.width - 16
                horizontalAlignment: Text.AlignHCenter
            }

            Text {
                visible: !isInstalled
                anchors.horizontalCenter: parent.horizontalCenter
                text: {
                    if (installError.length > 0)
                        return "Error"
                    if (downloadProgress >= 0)
                        return "Installing " + Math.round(downloadProgress * 100) + "%"
                    return "Install"
                }
                font.pixelSize: 10
                font.family: ThemeManager.getFont("body")
                color: {
                    if (installError.length > 0)
                        return "#ff6b6b"
                    if (downloadProgress >= 0)
                        return ThemeManager.getColor("accent")
                    return ThemeManager.getColor("primary")
                }
                horizontalAlignment: Text.AlignHCenter
            }
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

    // Hover/focus effect: scale 1.05x
    scale: (mouseArea.containsMouse || isKeyboardFocused) ? 1.05 : 1.0
    Behavior on scale { NumberAnimation { duration: 150 } }
    Behavior on border.color { ColorAnimation { duration: 150 } }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onEntered: cardHovered()
        onClicked: function(mouse) {
            if (mouse.button === Qt.RightButton && downloadProgress >= 0) {
                // Right-click on an active download → cancel
                cancelClicked(appId)
            } else {
                playClicked(gameId)
            }
        }
    }
}
