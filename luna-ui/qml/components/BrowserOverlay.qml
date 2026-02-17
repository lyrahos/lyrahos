import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// ─── BrowserOverlay ───
// Transparent overlay shown when an external browser (Brave/Chromium) is
// active.  Captures controller input and routes it to BrowserBridge
// (CDP WebSocket → browser page).  When a text field is focused in the
// browser, the VirtualKeyboard is displayed.

Item {
    id: overlay
    anchors.fill: parent
    visible: BrowserBridge.active
    z: 8000   // below VirtualKeyboard (9999) but above everything else

    // Re-grab focus whenever we become visible
    onVisibleChanged: {
        if (visible) overlay.forceActiveFocus()
    }

    signal closed()

    // ─── Status bar at top ───
    Rectangle {
        id: statusBar
        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.topMargin: 12
        width: statusRow.width + 40
        height: 44
        radius: 22
        color: Qt.rgba(0, 0, 0, 0.7)
        z: 1

        RowLayout {
            id: statusRow
            anchors.centerIn: parent
            spacing: 10

            // Connection indicator dot
            Rectangle {
                width: 10; height: 10; radius: 5
                color: BrowserBridge.connected ? "#2ecc71" : "#e74c3c"
                Behavior on color { ColorAnimation { duration: 300 } }
            }

            Text {
                text: {
                    if (!BrowserBridge.connected) return "Connecting to browser..."
                    return "Controller active  |  B = Back  |  A = Select"
                }
                font.pixelSize: 18
                font.family: ThemeManager.getFont("ui")
                color: "#ffffff"
            }
        }

        // Auto-hide after 4 seconds
        Timer {
            id: hideStatusTimer
            interval: 4000
            running: overlay.visible && BrowserBridge.connected
            onTriggered: statusFade.start()
        }

        NumberAnimation {
            id: statusFade
            target: statusBar
            property: "opacity"
            to: 0
            duration: 500
        }

        // Show again on any navigation
        function show() {
            statusFade.stop()
            statusBar.opacity = 1.0
            hideStatusTimer.restart()
        }
    }

    // ─── Controller key handler ───
    Keys.onPressed: function(event) {
        // Show the status bar on any input
        statusBar.show()

        switch (event.key) {
        case Qt.Key_Up:
            BrowserBridge.navigate("up")
            event.accepted = true
            break
        case Qt.Key_Down:
            BrowserBridge.navigate("down")
            event.accepted = true
            break
        case Qt.Key_Left:
            BrowserBridge.navigate("left")
            event.accepted = true
            break
        case Qt.Key_Right:
            BrowserBridge.navigate("right")
            event.accepted = true
            break
        case Qt.Key_Return:
        case Qt.Key_Enter:
            BrowserBridge.confirmElement()
            event.accepted = true
            break
        case Qt.Key_Escape:
            // B button — go back in browser; long-press could close overlay
            BrowserBridge.goBack()
            event.accepted = true
            break
        case Qt.Key_PageUp:
            BrowserBridge.scrollPage("up")
            event.accepted = true
            break
        case Qt.Key_PageDown:
            BrowserBridge.scrollPage("down")
            event.accepted = true
            break
        // F12 / system menu → close browser and return to Luna-UI
        case Qt.Key_F12:
            overlay.closed()
            event.accepted = true
            break
        }
    }

    // ─── Virtual Keyboard for browser text fields ───
    VirtualKeyboard {
        id: browserVirtualKeyboard
        anchors.fill: parent

        onAccepted: function(typedText) {
            BrowserBridge.sendText(typedText)
            overlay.forceActiveFocus()
        }
        onCancelled: {
            overlay.forceActiveFocus()
        }
    }

    // ─── React to BrowserBridge text field detection ───
    Connections {
        target: BrowserBridge

        function onTextInputRequested(currentValue, isPassword) {
            browserVirtualKeyboard.placeholderText = isPassword
                ? "Enter password..." : "Type here..."
            browserVirtualKeyboard.open(currentValue, isPassword)
        }

        function onBrowserClosed() {
            browserVirtualKeyboard.close()
            overlay.closed()
        }

        function onActiveChanged() {
            if (BrowserBridge.active) {
                overlay.forceActiveFocus()
            }
        }
    }
}
