import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Rectangle {
    color: "transparent"

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 24
        spacing: 24

        Text {
            text: "Settings"
            font.pixelSize: ThemeManager.getFontSize("xlarge")
            font.family: ThemeManager.getFont("heading")
            font.bold: true
            color: ThemeManager.getColor("textPrimary")
        }

        // Switch to Desktop Mode
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 72
            radius: 12
            color: ThemeManager.getColor("surface")
            border.color: switchArea.containsMouse
                          ? ThemeManager.getColor("focus") : "transparent"
            border.width: switchArea.containsMouse ? 2 : 0

            focus: true
            Keys.onReturnPressed: switchToDesktop()
            Keys.onEnterPressed: switchToDesktop()

            RowLayout {
                anchors.fill: parent
                anchors.margins: 16
                spacing: 16

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4

                    Text {
                        text: "Switch to Lyrah Desktop"
                        font.pixelSize: ThemeManager.getFontSize("medium")
                        font.family: ThemeManager.getFont("body")
                        font.bold: true
                        color: ThemeManager.getColor("textPrimary")
                    }
                    Text {
                        text: "Exit Luna Mode and switch to KDE Plasma desktop"
                        font.pixelSize: ThemeManager.getFontSize("small")
                        font.family: ThemeManager.getFont("body")
                        color: ThemeManager.getColor("textSecondary")
                    }
                }

                Rectangle {
                    Layout.preferredWidth: 40
                    Layout.preferredHeight: 40
                    radius: 20
                    color: ThemeManager.getColor("primary")

                    Text {
                        anchors.centerIn: parent
                        text: ">"
                        font.pixelSize: 20
                        font.bold: true
                        color: "white"
                    }
                }
            }

            MouseArea {
                id: switchArea
                anchors.fill: parent
                hoverEnabled: true
                onClicked: switchToDesktop()
            }

            Behavior on border.color { ColorAnimation { duration: 150 } }
        }

        // Placeholder for future settings
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 72
            radius: 12
            color: ThemeManager.getColor("surface")

            RowLayout {
                anchors.fill: parent
                anchors.margins: 16

                Text {
                    text: "Theme"
                    font.pixelSize: ThemeManager.getFontSize("medium")
                    font.family: ThemeManager.getFont("body")
                    color: ThemeManager.getColor("textPrimary")
                }
                Item { Layout.fillWidth: true }
                Text {
                    text: "Nebula Dark"
                    font.pixelSize: ThemeManager.getFontSize("small")
                    color: ThemeManager.getColor("textSecondary")
                }
            }
        }

        Item { Layout.fillHeight: true }
    }

    function switchToDesktop() {
        // Quit luna-ui → gamescope exits → session ends → SDDM returns.
        // User can then select Desktop Mode from the SDDM login screen.
        Qt.quit()
    }
}
