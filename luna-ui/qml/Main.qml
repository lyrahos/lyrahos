import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "components"       // FIX #27: Import component directory
import "views"            // FIX #27: Import views directory

ApplicationWindow {
    id: root
    visible: true
    width: 1920
    height: 1080
    title: "Luna UI"
    flags: Qt.FramelessWindowHint
    visibility: Window.FullScreen

    Rectangle {
        anchors.fill: parent
        color: ThemeManager.getColor("background")

        RowLayout {
            anchors.fill: parent
            spacing: 0

            NavBar {
                id: navBar
                Layout.preferredWidth: ThemeManager.getLayoutValue("sidebarWidth") || 220
                Layout.fillHeight: true
                onSectionChanged: function(section) {
                    contentLoader.source = "views/" + section + "View.qml"
                }
            }

            Loader {
                id: contentLoader
                Layout.fillWidth: true
                Layout.fillHeight: true
                source: "views/GamesView.qml"
            }
        }
    }
}
