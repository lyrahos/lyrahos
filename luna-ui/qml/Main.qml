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
    property bool pendingContentFocus: false

    function enterContent() {
        focusZone = "content"
        navBar.focus = false
        if (contentLoader.status === Loader.Loading) {
            pendingContentFocus = true
            return
        }
        pendingContentFocus = false
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

        // Back button (B / Escape) returns to NavBar from any content view.
        // Content views that handle Escape internally (e.g. SettingsView expanded
        // panels, GameStore detail popup) accept the event so it won't reach here.
        Keys.onEscapePressed: function(event) {
            if (root.focusZone === "content") {
                root.enterNav()
                event.accepted = true
            }
        }

        // D-Pad Left fallback: if a content view doesn't consume the Left
        // key (e.g. already at the left edge of a grid, or a view with no
        // horizontal navigation), navigate back to the sidebar.
        Keys.onLeftPressed: function(event) {
            if (root.focusZone === "content") {
                root.enterNav()
                event.accepted = true
            }
        }

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
                    // Connect the view's requestNavFocus signal to enterNav().
                    // In Qt6 QML, typeof for signals returns "function", not
                    // "object", so use "in" to check for the signal's existence.
                    if (item && "requestNavFocus" in item) {
                        item.requestNavFocus.connect(root.enterNav)
                    }
                    if (root.pendingContentFocus) {
                        root.pendingContentFocus = false
                        root.enterContent()
                    }
                }
            }
        }

        // ─── Browser Controller Overlay ───
        // Shown when an external browser is launched (e.g. for Steam API key).
        // Captures controller input and relays it to the browser via CDP.
        BrowserOverlay {
            id: browserOverlay
            onClosed: {
                BrowserBridge.setActive(false)
                GameManager.closeApiKeyBrowser()
                root.enterNav()
            }
        }
    }
}
