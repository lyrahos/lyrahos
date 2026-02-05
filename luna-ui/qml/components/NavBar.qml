import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Rectangle {
    id: navBar
    color: ThemeManager.getColor("surface")

    signal sectionChanged(string section)

    property int currentIndex: 0

    // FIX #16: Use text labels instead of emoji. In production, replace
    // with SVG icons from resources/icons/ for consistent rendering in gamescope.
    readonly property var sections: [
        { name: "Games",    icon: "[G]", section: "Games" },
        { name: "Store",    icon: "[S]", section: "Store" },
        { name: "Media",    icon: "[M]", section: "Media" },
        { name: "Settings", icon: "[*]", section: "Settings" }
    ]

    Column {
        anchors.fill: parent
        anchors.topMargin: 40
        spacing: 8

        Text {
            text: "LUNA"
            font.pixelSize: 28
            font.family: ThemeManager.getFont("heading")
            font.bold: true
            color: ThemeManager.getColor("primary")
            anchors.horizontalCenter: parent.horizontalCenter
            bottomPadding: 30
        }

        Repeater {
            model: sections

            // FIX #15: Use explicit width instead of anchors inside Column
            Rectangle {
                width: navBar.width - 16
                height: 56
                x: 8  // Center manually instead of using anchors
                radius: 8
                color: currentIndex === index
                       ? Qt.rgba(ThemeManager.getColor("primary").r,
                                 ThemeManager.getColor("primary").g,
                                 ThemeManager.getColor("primary").b, 0.2)
                       : "transparent"
                border.color: currentIndex === index ? ThemeManager.getColor("focus") : "transparent"
                border.width: currentIndex === index ? 2 : 0

                Row {
                    anchors.centerIn: parent
                    spacing: 12

                    Text {
                        text: modelData.icon
                        font.pixelSize: 16
                        font.bold: true
                        color: currentIndex === index
                               ? ThemeManager.getColor("primary")
                               : ThemeManager.getColor("textSecondary")
                    }
                    Text {
                        text: modelData.name
                        font.pixelSize: ThemeManager.getFontSize("medium")
                        font.family: ThemeManager.getFont("body")
                        color: currentIndex === index
                               ? ThemeManager.getColor("textPrimary")
                               : ThemeManager.getColor("textSecondary")
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        currentIndex = index
                        sectionChanged(modelData.section)
                    }
                }

                Behavior on color { ColorAnimation { duration: 150 } }
            }
        }
    }
}
