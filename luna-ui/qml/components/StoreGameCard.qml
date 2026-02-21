import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
    id: storeCard
    width: 200
    height: 340

    property string gameTitle: ""
    property string coverImage: ""
    property string headerImage: ""
    property string genres: ""
    property string developer: ""
    property string salePrice: ""
    property string normalPrice: ""
    property string savings: ""
    property string metacriticScore: ""
    property string steamRatingText: ""
    property string steamAppID: ""
    property string gameID: ""
    property string storeID: ""
    property string dealRating: ""
    property double rating: 0
    property bool isKeyboardFocused: false

    signal clicked()

    // Use cover image (IGDB portrait) as primary, fall back to header
    readonly property string displayImage: coverImage !== "" ? coverImage : headerImage

    // ─── Card Container ───
    Rectangle {
        id: cardBg
        anchors.fill: parent
        radius: 18
        color: "transparent"
        clip: true

        // Scale on hover/focus
        scale: (mouseArea.containsMouse || isKeyboardFocused) ? 1.03 : 1.0
        Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }

        // Cover art (portrait, fills card top area)
        Rectangle {
            id: coverContainer
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: parent.height - infoSection.height
            radius: 18
            clip: true
            color: ThemeManager.getColor("surface")

            Image {
                id: coverImg
                anchors.fill: parent
                source: displayImage
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: true
                sourceSize.width: storeCard.width * 2
                sourceSize.height: coverContainer.height * 2
                opacity: status === Image.Ready ? 1.0 : 0.0
                Behavior on opacity { NumberAnimation { duration: 400 } }
            }

            // Placeholder while loading
            Item {
                anchors.fill: parent
                visible: coverImg.status !== Image.Ready

                Rectangle {
                    anchors.fill: parent
                    color: ThemeManager.getColor("surface")
                    radius: 18
                }

                Text {
                    anchors.centerIn: parent
                    text: gameTitle.length > 0 ? gameTitle.charAt(0).toUpperCase() : "?"
                    font.pixelSize: 48
                    font.family: ThemeManager.getFont("heading")
                    font.bold: true
                    color: ThemeManager.getColor("primary")
                    opacity: 0.3
                }
            }

            // Subtle vignette at bottom for depth
            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: parent.height * 0.35
                gradient: Gradient {
                    GradientStop { position: 0.0; color: "transparent" }
                    GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.25) }
                }
            }

            // Discount badge (top-right, pill shape)
            Rectangle {
                visible: {
                    var s = parseFloat(savings)
                    return !isNaN(s) && s > 0
                }
                anchors.top: parent.top
                anchors.right: parent.right
                anchors.topMargin: 10
                anchors.rightMargin: 10
                width: discountText.width + 20
                height: 32
                radius: 16
                color: "#34c759"

                Text {
                    id: discountText
                    anchors.centerIn: parent
                    text: "-" + Math.round(parseFloat(savings)) + "%"
                    font.pixelSize: 18
                    font.family: ThemeManager.getFont("ui")
                    font.bold: true
                    color: "#ffffff"
                }
            }

            // Rating badge (top-left, small pill)
            Rectangle {
                visible: rating > 0
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.topMargin: 10
                anchors.leftMargin: 10
                width: ratingRow.width + 16
                height: 32
                radius: 16
                color: Qt.rgba(0, 0, 0, 0.65)

                Row {
                    id: ratingRow
                    anchors.centerIn: parent
                    spacing: 4

                    Text {
                        text: "\u2605"
                        font.pixelSize: 16
                        color: "#fbbf24"
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Text {
                        text: Math.round(rating)
                        font.pixelSize: 16
                        font.family: ThemeManager.getFont("ui")
                        font.bold: true
                        color: "#ffffff"
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
            }

            // Focus ring (drawn on top of cover)
            Rectangle {
                anchors.fill: parent
                radius: 18
                color: "transparent"
                border.color: (mouseArea.containsMouse || isKeyboardFocused)
                              ? ThemeManager.getColor("focus") : "transparent"
                border.width: (mouseArea.containsMouse || isKeyboardFocused) ? 3 : 0
                Behavior on border.color { ColorAnimation { duration: 200 } }
            }
        }

        // ─── Info Section (below cover) ───
        ColumnLayout {
            id: infoSection
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.leftMargin: 4
            anchors.rightMargin: 4
            anchors.topMargin: 10
            spacing: 3
            height: titleText.implicitHeight + subtitleText.implicitHeight + priceRow.height + 16

            // Game title
            Text {
                id: titleText
                Layout.fillWidth: true
                text: gameTitle
                font.pixelSize: 20
                font.family: ThemeManager.getFont("body")
                font.weight: Font.DemiBold
                color: ThemeManager.getColor("textPrimary")
                elide: Text.ElideRight
                maximumLineCount: 1
            }

            // Genre / Developer subtitle
            Text {
                id: subtitleText
                Layout.fillWidth: true
                text: {
                    if (genres !== "") return genres
                    if (developer !== "") return developer
                    return ""
                }
                visible: text !== ""
                font.pixelSize: 16
                font.family: ThemeManager.getFont("ui")
                color: ThemeManager.getColor("textSecondary")
                elide: Text.ElideRight
                maximumLineCount: 1
            }

            // Price row
            RowLayout {
                id: priceRow
                Layout.fillWidth: true
                spacing: 8

                // Sale price
                Text {
                    text: {
                        if (salePrice === "0.00") return "Free"
                        if (salePrice !== "") return "$" + salePrice
                        return ""
                    }
                    visible: salePrice !== ""
                    font.pixelSize: 18
                    font.family: ThemeManager.getFont("ui")
                    font.bold: true
                    color: {
                        if (salePrice === "0.00") return "#34c759"
                        var s = parseFloat(savings)
                        if (!isNaN(s) && s > 0) return "#34c759"
                        return ThemeManager.getColor("textPrimary")
                    }
                }

                // Strikethrough original
                Text {
                    visible: {
                        var s = parseFloat(savings)
                        return !isNaN(s) && s > 0
                    }
                    text: "$" + normalPrice
                    font.pixelSize: 16
                    font.family: ThemeManager.getFont("ui")
                    color: ThemeManager.getColor("textSecondary")
                    font.strikeout: true
                    opacity: 0.7
                }

                Item { Layout.fillWidth: true }
            }
        }
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: storeCard.clicked()
    }
}
