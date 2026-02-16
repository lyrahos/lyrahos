import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Rectangle {
    id: navBar
    color: ThemeManager.getColor("surface")

    signal sectionChanged(string section)

    property int currentIndex: 0

    // Accept keyboard focus
    focus: true
    activeFocusOnTab: true

    readonly property var sections: [
        { name: "Games",    section: "Games" },
        { name: "Browse Apps", section: "Store" },
        { name: "My Apps",    section: "Media" },
        { name: "Settings", section: "Settings" }
    ]

    // Keyboard navigation: Up/Down to move, Enter/Right to select
    Keys.onUpPressed: {
        if (currentIndex > 0) {
            currentIndex--
            sectionChanged(sections[currentIndex].section)
        }
    }
    Keys.onDownPressed: {
        if (currentIndex < sections.length - 1) {
            currentIndex++
            sectionChanged(sections[currentIndex].section)
        }
    }
    Keys.onReturnPressed: sectionChanged(sections[currentIndex].section)
    Keys.onEnterPressed: sectionChanged(sections[currentIndex].section)

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

                Text {
                    anchors.centerIn: parent
                    text: modelData.name
                    font.pixelSize: ThemeManager.getFontSize("medium")
                    font.family: ThemeManager.getFont("body")
                    font.bold: currentIndex === index
                    color: currentIndex === index
                           ? ThemeManager.getColor("textPrimary")
                           : ThemeManager.getColor("textSecondary")
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
