import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Rectangle {
    id: storeCard
    width: 240
    height: 160
    radius: 16
    color: ThemeManager.getColor("cardBackground")
    clip: true

    property string gameTitle: ""
    property string headerImage: ""
    property string salePrice: ""
    property string normalPrice: ""
    property string savings: ""
    property string metacriticScore: ""
    property string steamRatingText: ""
    property string steamAppID: ""
    property string gameID: ""
    property string storeID: ""
    property string dealRating: ""

    signal clicked()

    // Background image
    Image {
        id: bgImage
        anchors.fill: parent
        source: headerImage
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: true
        opacity: status === Image.Ready ? 1.0 : 0.0
        sourceSize.width: storeCard.width * 2
        sourceSize.height: storeCard.height * 2

        Behavior on opacity { NumberAnimation { duration: 300 } }
    }

    // Placeholder when image hasn't loaded or failed
    Rectangle {
        anchors.fill: parent
        visible: bgImage.status !== Image.Ready
        color: ThemeManager.getColor("surface")

        Text {
            anchors.centerIn: parent
            text: gameTitle.length > 0 ? gameTitle.charAt(0).toUpperCase() : "?"
            font.pixelSize: 56
            font.bold: true
            color: ThemeManager.getColor("primary")
            opacity: 0.5
        }
    }

    // Gradient overlay for text readability
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: "transparent" }
            GradientStop { position: 0.3; color: "transparent" }
            GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.9) }
        }
    }

    // Hover glow overlay
    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(ThemeManager.getColor("primary").r,
                       ThemeManager.getColor("primary").g,
                       ThemeManager.getColor("primary").b, 0.0)
        opacity: mouseArea.containsMouse ? 0.15 : 0.0
        Behavior on opacity { NumberAnimation { duration: 200 } }
    }

    // Discount badge (top-right)
    Rectangle {
        visible: {
            var s = parseFloat(savings)
            return !isNaN(s) && s > 0
        }
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.topMargin: 12
        anchors.rightMargin: 12
        width: discountText.width + 28
        height: 44
        radius: 10
        color: "#4ade80"

        Text {
            id: discountText
            anchors.centerIn: parent
            text: "-" + Math.round(parseFloat(savings)) + "%"
            font.pixelSize: 24
            font.family: ThemeManager.getFont("ui")
            font.bold: true
            color: "#0a0a0a"
        }
    }

    // Metacritic badge (top-left)
    Rectangle {
        visible: metacriticScore !== "" && metacriticScore !== "0"
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.topMargin: 12
        anchors.leftMargin: 12
        width: 56
        height: 56
        radius: 10
        color: {
            var score = parseInt(metacriticScore)
            if (score >= 75) return Qt.rgba(0.29, 0.85, 0.37, 0.9)
            if (score >= 50) return Qt.rgba(1.0, 0.82, 0.24, 0.9)
            return Qt.rgba(1.0, 0.42, 0.42, 0.9)
        }

        Text {
            anchors.centerIn: parent
            text: metacriticScore
            font.pixelSize: 24
            font.family: ThemeManager.getFont("ui")
            font.bold: true
            color: "#0a0a0a"
        }
    }

    // Bottom content: title + price
    ColumnLayout {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 16
        spacing: 6

        // Game title
        Text {
            Layout.fillWidth: true
            text: gameTitle
            font.pixelSize: 28
            font.family: ThemeManager.getFont("body")
            font.bold: true
            color: "#ffffff"
            elide: Text.ElideRight
            maximumLineCount: 1
        }

        // Price row
        RowLayout {
            spacing: 12

            // Strikethrough original price
            Text {
                visible: {
                    var s = parseFloat(savings)
                    return !isNaN(s) && s > 0
                }
                text: "$" + normalPrice
                font.pixelSize: 24
                font.family: ThemeManager.getFont("ui")
                color: ThemeManager.getColor("textSecondary")
                font.strikeout: true
            }

            // Sale price
            Text {
                text: {
                    if (salePrice === "0.00") return "FREE"
                    return "$" + salePrice
                }
                font.pixelSize: 28
                font.family: ThemeManager.getFont("ui")
                font.bold: true
                color: {
                    if (salePrice === "0.00") return "#4ade80"
                    var s = parseFloat(savings)
                    if (!isNaN(s) && s > 0) return "#4ade80"
                    return ThemeManager.getColor("textPrimary")
                }
            }

            Item { Layout.fillWidth: true }

            // Steam rating
            Text {
                visible: steamRatingText !== "" && steamRatingText !== "null"
                text: steamRatingText
                font.pixelSize: 22
                font.family: ThemeManager.getFont("ui")
                color: ThemeManager.getColor("textSecondary")
                opacity: 0.8
            }
        }
    }

    // Hover effect
    scale: mouseArea.containsMouse ? 1.04 : 1.0
    Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

    // Focus border
    border.color: mouseArea.containsMouse
                  ? ThemeManager.getColor("focus")
                  : "transparent"
    border.width: mouseArea.containsMouse ? 3 : 0
    Behavior on border.color { ColorAnimation { duration: 150 } }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: storeCard.clicked()
    }
}
