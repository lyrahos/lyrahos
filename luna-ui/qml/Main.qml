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

    // Track which zone has focus: "nav" or "content"
    property string focusZone: "nav"

    function enterContent() {
        focusZone = "content"
        navBar.focus = false
        if (contentLoader.item && typeof contentLoader.item.gainFocus === "function") {
            contentLoader.item.gainFocus()
        }
    }

    function enterNav() {
        focusZone = "nav"
        if (contentLoader.item && typeof contentLoader.item.loseFocus === "function") {
            contentLoader.item.loseFocus()
        }
        navBar.forceActiveFocus()
    }

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
                focus: true
                onSectionChanged: function(section) {
                    contentLoader.source = "views/" + section + "View.qml"
                }
                onEnterContent: root.enterContent()
            }

            Loader {
                id: contentLoader
                Layout.fillWidth: true
                Layout.fillHeight: true
                source: "views/GamesView.qml"

                onLoaded: {
                    if (item && typeof item.requestNavFocus === "object") {
                        // Connect the content view's "go back to nav" signal
                        item.requestNavFocus.connect(root.enterNav)
                    }
                }
            }
        }
    }
}
