import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Rectangle {
    id: navBar
    color: ThemeManager.getColor("surface")

    signal sectionChanged(string section)
    signal enterContent()

    property int currentIndex: 0
    property int hoveredIndex: -1

    // Accept keyboard focus
    focus: true
    activeFocusOnTab: true

    readonly property var sections: [
        { name: "Games",    section: "Games" },
        { name: "Browse Apps", section: "Store" },
        { name: "My Apps",    section: "Media" },
        { name: "Settings", section: "Settings" }
    ]

    // Keyboard navigation: Up/Down to move, Enter/Right to select and enter content
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
    Keys.onReturnPressed: enterContent()
    Keys.onEnterPressed: enterContent()
    Keys.onRightPressed: enterContent()

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
                id: navItem
                width: navBar.width - 16
                height: 56
                x: 8  // Center manually instead of using anchors
                radius: 8

                property bool isSelected: currentIndex === index
                property bool isHovered: hoveredIndex === index

                color: isSelected
                       ? Qt.rgba(ThemeManager.getColor("primary").r,
                                 ThemeManager.getColor("primary").g,
                                 ThemeManager.getColor("primary").b, 0.2)
                       : isHovered
                         ? Qt.rgba(ThemeManager.getColor("primary").r,
                                   ThemeManager.getColor("primary").g,
                                   ThemeManager.getColor("primary").b, 0.1)
                         : "transparent"
                border.color: (isSelected || isHovered)
                              ? ThemeManager.getColor("focus") : "transparent"
                border.width: (isSelected || isHovered) ? 2 : 0

                Text {
                    anchors.centerIn: parent
                    text: modelData.name
                    font.pixelSize: ThemeManager.getFontSize("medium")
                    font.family: ThemeManager.getFont("body")
                    font.bold: isSelected
                    color: isSelected
                           ? ThemeManager.getColor("textPrimary")
                           : ThemeManager.getColor("textSecondary")
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onEntered: hoveredIndex = index
                    onExited: hoveredIndex = -1
                    onClicked: {
                        currentIndex = index
                        sectionChanged(modelData.section)
                    }
                }

                Behavior on color { ColorAnimation { duration: 150 } }
                Behavior on border.color { ColorAnimation { duration: 150 } }
            }
        }
    }
}
