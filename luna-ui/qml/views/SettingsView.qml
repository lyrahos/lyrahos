import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Rectangle {
    id: settingsRoot
    color: "transparent"
    focus: true

    // Controller / keyboard row navigation
    // 0 = Wi-Fi, 1 = Switch to Desktop, 2 = Log Out, 3 = Theme
    property int focusedRow: 0
    readonly property int rowCount: 4

    Keys.onUpPressed: {
        if (focusedRow > 0) focusedRow--
    }
    Keys.onDownPressed: {
        if (focusedRow < rowCount - 1) focusedRow++
    }
    Keys.onReturnPressed: activateRow(focusedRow)
    Keys.onEnterPressed: activateRow(focusedRow)

    function activateRow(row) {
        switch (row) {
        case 0:
            wifiExpanded = !wifiExpanded
            if (wifiExpanded) {
                wifiStatus = ""
                selectedSsid = ""
                settingsWifiPasswordField.text = ""
                wifiScanning = true
                settingsWifiModel.clear()
                GameManager.scanWifiNetworks()
            }
            break
        case 1: switchToDesktop(); break
        case 2: GameManager.logout(); break
        // case 3: theme — placeholder, no action yet
        }
    }

    // WiFi state
    property string connectedSsid: ""
    property bool wifiExpanded: false
    property bool wifiScanning: false
    property bool wifiConnecting: false
    property bool wifiDisconnecting: false
    property string wifiStatus: ""
    property string selectedSsid: ""

    Component.onCompleted: refreshWifiStatus()

    function refreshWifiStatus() {
        connectedSsid = GameManager.getConnectedWifi()
    }

    Connections {
        target: GameManager
        function onWifiConnectResult(success, message) {
            wifiConnecting = false
            if (success) {
                wifiStatus = "Connected!"
                selectedSsid = ""
                settingsWifiPasswordField.text = ""
                refreshWifiStatus()
            } else {
                wifiStatus = "Failed: " + message
            }
        }
        function onWifiDisconnectResult(success, message) {
            wifiDisconnecting = false
            if (success) {
                wifiStatus = "Disconnected"
                refreshWifiStatus()
            } else {
                wifiStatus = "Failed: " + message
            }
        }
        function onWifiNetworksScanned(networks) {
            wifiScanning = false
            settingsWifiModel.clear()
            for (var i = 0; i < networks.length; i++)
                settingsWifiModel.append(networks[i])
        }
    }

    // Refresh connection status periodically
    Timer {
        interval: 5000
        running: true
        repeat: true
        onTriggered: refreshWifiStatus()
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 24
        spacing: 16

        Text {
            text: "Settings"
            font.pixelSize: ThemeManager.getFontSize("xlarge")
            font.family: ThemeManager.getFont("heading")
            font.bold: true
            color: ThemeManager.getColor("textPrimary")
        }

        // ── Wi-Fi Section ──
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: wifiCol.height + 32
            radius: 12
            color: ThemeManager.getColor("surface")
            border.color: focusedRow === 0
                          ? ThemeManager.getColor("focus") : "transparent"
            border.width: focusedRow === 0 ? 2 : 0

            Behavior on border.color { ColorAnimation { duration: 150 } }

            ColumnLayout {
                id: wifiCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 16
                spacing: 12

                // Header row: title + status + expand button
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 4

                        Text {
                            text: "Wi-Fi"
                            font.pixelSize: ThemeManager.getFontSize("medium")
                            font.family: ThemeManager.getFont("body")
                            font.bold: true
                            color: ThemeManager.getColor("textPrimary")
                        }

                        Text {
                            text: connectedSsid !== ""
                                  ? "Connected to " + connectedSsid
                                  : "Not connected"
                            font.pixelSize: ThemeManager.getFontSize("small")
                            font.family: ThemeManager.getFont("body")
                            color: connectedSsid !== ""
                                   ? ThemeManager.getColor("accent")
                                   : ThemeManager.getColor("textSecondary")
                        }
                    }

                    // Disconnect button (visible when connected)
                    Rectangle {
                        visible: connectedSsid !== "" && !wifiDisconnecting
                        Layout.preferredWidth: disconnectLabel.width + 24
                        Layout.preferredHeight: 36
                        radius: 8
                        color: "transparent"
                        border.color: disconnectArea.containsMouse
                                      ? "#ff6b6b" : Qt.rgba(1, 1, 1, 0.15)
                        border.width: 1

                        Text {
                            id: disconnectLabel
                            anchors.centerIn: parent
                            text: "Disconnect"
                            font.pixelSize: ThemeManager.getFontSize("small")
                            font.family: ThemeManager.getFont("body")
                            color: disconnectArea.containsMouse
                                   ? "#ff6b6b"
                                   : ThemeManager.getColor("textSecondary")
                        }

                        MouseArea {
                            id: disconnectArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                wifiDisconnecting = true
                                wifiStatus = "Disconnecting..."
                                GameManager.disconnectWifi()
                            }
                        }

                        Behavior on border.color { ColorAnimation { duration: 150 } }
                    }

                    // Disconnecting indicator
                    Text {
                        visible: wifiDisconnecting
                        text: "Disconnecting..."
                        font.pixelSize: ThemeManager.getFontSize("small")
                        font.family: ThemeManager.getFont("body")
                        color: ThemeManager.getColor("textSecondary")

                        SequentialAnimation on opacity {
                            running: wifiDisconnecting
                            loops: Animation.Infinite
                            NumberAnimation { to: 0.4; duration: 600 }
                            NumberAnimation { to: 1.0; duration: 600 }
                        }
                    }

                    // Expand/collapse arrow
                    Rectangle {
                        Layout.preferredWidth: 40
                        Layout.preferredHeight: 40
                        radius: 20
                        color: expandWifiArea.containsMouse
                               ? ThemeManager.getColor("hover")
                               : "transparent"

                        Text {
                            anchors.centerIn: parent
                            text: wifiExpanded ? "v" : ">"
                            font.pixelSize: 18
                            font.bold: true
                            color: ThemeManager.getColor("textPrimary")
                        }

                        MouseArea {
                            id: expandWifiArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                wifiExpanded = !wifiExpanded
                                if (wifiExpanded) {
                                    wifiStatus = ""
                                    selectedSsid = ""
                                    settingsWifiPasswordField.text = ""
                                    wifiScanning = true
                                    settingsWifiModel.clear()
                                    GameManager.scanWifiNetworks()
                                }
                            }
                        }
                    }
                }

                // ── Expanded WiFi network list ──
                ColumnLayout {
                    visible: wifiExpanded
                    Layout.fillWidth: true
                    spacing: 8

                    // Status message
                    Text {
                        visible: wifiStatus !== ""
                        text: wifiStatus
                        font.pixelSize: ThemeManager.getFontSize("small")
                        font.family: ThemeManager.getFont("body")
                        color: wifiStatus.startsWith("Failed")
                               ? "#ff6b6b"
                               : wifiStatus === "Connected!" || wifiStatus === "Disconnected"
                                 ? ThemeManager.getColor("accent")
                                 : ThemeManager.getColor("textSecondary")
                    }

                    // Refresh button
                    RowLayout {
                        Layout.fillWidth: true

                        Text {
                            text: "Available Networks"
                            font.pixelSize: ThemeManager.getFontSize("small")
                            font.family: ThemeManager.getFont("body")
                            font.bold: true
                            color: ThemeManager.getColor("textSecondary")
                            Layout.fillWidth: true
                        }

                        Rectangle {
                            visible: !wifiScanning
                            Layout.preferredWidth: settingsRefreshLabel.width + 24
                            Layout.preferredHeight: 32
                            radius: 8
                            color: settingsRefreshArea.containsMouse
                                   ? ThemeManager.getColor("hover")
                                   : "transparent"

                            Text {
                                id: settingsRefreshLabel
                                anchors.centerIn: parent
                                text: "Refresh"
                                font.pixelSize: ThemeManager.getFontSize("small")
                                font.family: ThemeManager.getFont("body")
                                color: ThemeManager.getColor("primary")
                            }

                            MouseArea {
                                id: settingsRefreshArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    wifiScanning = true
                                    settingsWifiModel.clear()
                                    GameManager.scanWifiNetworks()
                                }
                            }
                        }
                    }

                    // Scanning spinner
                    RowLayout {
                        visible: wifiScanning
                        Layout.fillWidth: true
                        Layout.preferredHeight: 48
                        spacing: 12

                        Item {
                            Layout.preferredWidth: 24
                            Layout.preferredHeight: 24
                            Layout.alignment: Qt.AlignVCenter

                            Rectangle {
                                anchors.centerIn: parent
                                width: 22
                                height: 22
                                radius: 11
                                color: "transparent"
                                border.width: 3
                                border.color: Qt.rgba(1, 1, 1, 0.08)

                                Rectangle {
                                    width: 22
                                    height: 22
                                    radius: 11
                                    color: "transparent"
                                    border.width: 3
                                    border.color: "transparent"

                                    Rectangle {
                                        width: 8
                                        height: 3
                                        radius: 1.5
                                        color: ThemeManager.getColor("primary")
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        anchors.top: parent.top
                                    }

                                    RotationAnimation on rotation {
                                        from: 0; to: 360
                                        duration: 1000
                                        loops: Animation.Infinite
                                        running: wifiScanning
                                    }
                                }
                            }
                        }

                        Text {
                            text: "Scanning for networks..."
                            font.pixelSize: ThemeManager.getFontSize("small")
                            font.family: ThemeManager.getFont("body")
                            color: ThemeManager.getColor("textSecondary")

                            SequentialAnimation on opacity {
                                running: wifiScanning
                                loops: Animation.Infinite
                                NumberAnimation { to: 0.4; duration: 600 }
                                NumberAnimation { to: 1.0; duration: 600 }
                            }
                        }
                    }

                    // Network list
                    ListView {
                        id: settingsWifiList
                        Layout.fillWidth: true
                        Layout.preferredHeight: Math.min(settingsWifiModel.count * 54, 270)
                        clip: true
                        spacing: 4
                        model: ListModel { id: settingsWifiModel }

                        delegate: Rectangle {
                            width: settingsWifiList.width
                            height: 50
                            radius: 10
                            color: settingsWifiItemArea.containsMouse
                                   ? Qt.rgba(ThemeManager.getColor("primary").r,
                                             ThemeManager.getColor("primary").g,
                                             ThemeManager.getColor("primary").b, 0.15)
                                   : ThemeManager.getColor("hover")
                            border.color: model.ssid === connectedSsid
                                          ? ThemeManager.getColor("accent")
                                          : settingsWifiItemArea.containsMouse
                                            ? ThemeManager.getColor("focus") : "transparent"
                            border.width: (model.ssid === connectedSsid || settingsWifiItemArea.containsMouse) ? 1 : 0

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 16
                                anchors.rightMargin: 16
                                spacing: 12

                                // Signal strength
                                Text {
                                    text: model.signal > 70 ? "|||" :
                                          model.signal > 40 ? "|| " : "|  "
                                    font.pixelSize: 14
                                    font.family: "monospace"
                                    font.bold: true
                                    color: model.signal > 70
                                           ? ThemeManager.getColor("accent")
                                           : model.signal > 40
                                             ? ThemeManager.getColor("secondary")
                                             : ThemeManager.getColor("textSecondary")
                                }

                                Text {
                                    text: model.ssid
                                    font.pixelSize: ThemeManager.getFontSize("small")
                                    font.family: ThemeManager.getFont("body")
                                    font.bold: model.ssid === connectedSsid
                                    color: ThemeManager.getColor("textPrimary")
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                }

                                // "Connected" badge
                                Text {
                                    visible: model.ssid === connectedSsid
                                    text: "Connected"
                                    font.pixelSize: ThemeManager.getFontSize("small")
                                    font.family: ThemeManager.getFont("body")
                                    color: ThemeManager.getColor("accent")
                                }

                                Text {
                                    visible: model.security !== "" && model.security !== "--"
                                             && model.ssid !== connectedSsid
                                    text: model.security
                                    font.pixelSize: ThemeManager.getFontSize("small")
                                    font.family: ThemeManager.getFont("body")
                                    color: ThemeManager.getColor("textSecondary")
                                }
                            }

                            MouseArea {
                                id: settingsWifiItemArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (model.ssid === connectedSsid) return
                                    selectedSsid = model.ssid
                                    settingsWifiPasswordField.text = ""
                                    wifiStatus = ""
                                    if (model.security === "" || model.security === "--") {
                                        // Open network — connect immediately
                                        wifiConnecting = true
                                        wifiStatus = "Connecting to " + model.ssid + "..."
                                        GameManager.connectToWifi(model.ssid, "")
                                    } else {
                                        settingsWifiPasswordField.forceActiveFocus()
                                    }
                                }
                            }

                            Behavior on color { ColorAnimation { duration: 120 } }
                            Behavior on border.color { ColorAnimation { duration: 120 } }
                        }
                    }

                    // Password input (visible when a secured network is selected)
                    Rectangle {
                        visible: selectedSsid !== "" && !wifiConnecting
                        Layout.fillWidth: true
                        Layout.preferredHeight: 48
                        radius: 10
                        color: ThemeManager.getColor("hover")

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: 8
                            spacing: 8

                            Text {
                                text: selectedSsid
                                font.pixelSize: ThemeManager.getFontSize("small")
                                font.family: ThemeManager.getFont("body")
                                font.bold: true
                                color: ThemeManager.getColor("textPrimary")
                                Layout.preferredWidth: 140
                                elide: Text.ElideRight
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                radius: 8
                                color: ThemeManager.getColor("surface")
                                border.color: settingsWifiPasswordField.activeFocus
                                              ? ThemeManager.getColor("focus") : "transparent"
                                border.width: settingsWifiPasswordField.activeFocus ? 2 : 0

                                Behavior on border.color { ColorAnimation { duration: 150 } }

                                TextInput {
                                    id: settingsWifiPasswordField
                                    anchors.fill: parent
                                    anchors.margins: 8
                                    verticalAlignment: TextInput.AlignVCenter
                                    font.pixelSize: ThemeManager.getFontSize("small")
                                    font.family: ThemeManager.getFont("body")
                                    color: ThemeManager.getColor("textPrimary")
                                    echoMode: TextInput.Password
                                    clip: true
                                    onAccepted: {
                                        if (text.length > 0 && !wifiConnecting) {
                                            wifiConnecting = true
                                            wifiStatus = "Connecting to " + selectedSsid + "..."
                                            GameManager.connectToWifi(selectedSsid, text)
                                        }
                                    }
                                }

                                Text {
                                    anchors.fill: parent
                                    anchors.margins: 8
                                    verticalAlignment: Text.AlignVCenter
                                    visible: settingsWifiPasswordField.text === ""
                                             && !settingsWifiPasswordField.activeFocus
                                    text: "Enter password..."
                                    font.pixelSize: ThemeManager.getFontSize("small")
                                    font.family: ThemeManager.getFont("body")
                                    color: ThemeManager.getColor("textSecondary")
                                }
                            }

                            Rectangle {
                                Layout.preferredWidth: settingsConnectLabel.width + 24
                                Layout.fillHeight: true
                                radius: 8
                                color: ThemeManager.getColor("primary")

                                Text {
                                    id: settingsConnectLabel
                                    anchors.centerIn: parent
                                    text: "Connect"
                                    font.pixelSize: ThemeManager.getFontSize("small")
                                    font.family: ThemeManager.getFont("body")
                                    font.bold: true
                                    color: "white"
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        if (settingsWifiPasswordField.text.length > 0
                                                && !wifiConnecting) {
                                            wifiConnecting = true
                                            wifiStatus = "Connecting to " + selectedSsid + "..."
                                            GameManager.connectToWifi(
                                                selectedSsid,
                                                settingsWifiPasswordField.text)
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Connecting indicator
                    Text {
                        visible: wifiConnecting
                        text: wifiStatus
                        font.pixelSize: ThemeManager.getFontSize("small")
                        font.family: ThemeManager.getFont("body")
                        color: ThemeManager.getColor("primary")

                        SequentialAnimation on opacity {
                            running: wifiConnecting
                            loops: Animation.Infinite
                            NumberAnimation { to: 0.4; duration: 600 }
                            NumberAnimation { to: 1.0; duration: 600 }
                        }
                    }
                }
            }
        }

        // ── Switch to Desktop Mode ──
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 72
            radius: 12
            color: ThemeManager.getColor("surface")
            border.color: (switchArea.containsMouse || focusedRow === 1)
                          ? ThemeManager.getColor("focus") : "transparent"
            border.width: (switchArea.containsMouse || focusedRow === 1) ? 2 : 0

            RowLayout {
                anchors.fill: parent
                anchors.margins: 16
                spacing: 16

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
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
                    Layout.alignment: Qt.AlignVCenter
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
                cursorShape: Qt.PointingHandCursor
                onClicked: switchToDesktop()
            }

            Behavior on border.color { ColorAnimation { duration: 150 } }
        }

        // ── Log Out ──
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 72
            radius: 12
            color: ThemeManager.getColor("surface")
            border.color: (logoutArea.containsMouse || focusedRow === 2)
                          ? "#ff6b6b" : "transparent"
            border.width: (logoutArea.containsMouse || focusedRow === 2) ? 2 : 0

            RowLayout {
                anchors.fill: parent
                anchors.margins: 16
                spacing: 16

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    spacing: 4

                    Text {
                        text: "Log Out"
                        font.pixelSize: ThemeManager.getFontSize("medium")
                        font.family: ThemeManager.getFont("body")
                        font.bold: true
                        color: ThemeManager.getColor("textPrimary")
                    }
                    Text {
                        text: "Save session and return to login screen"
                        font.pixelSize: ThemeManager.getFontSize("small")
                        font.family: ThemeManager.getFont("body")
                        color: ThemeManager.getColor("textSecondary")
                    }
                }

                Rectangle {
                    Layout.preferredWidth: 40
                    Layout.preferredHeight: 40
                    Layout.alignment: Qt.AlignVCenter
                    radius: 20
                    color: (logoutArea.containsMouse || focusedRow === 2)
                           ? "#ff6b6b" : Qt.rgba(1, 0.42, 0.42, 0.15)

                    Text {
                        anchors.centerIn: parent
                        text: "\u23FB"
                        font.pixelSize: 18
                        font.bold: true
                        color: (logoutArea.containsMouse || focusedRow === 2)
                               ? "white" : "#ff6b6b"
                    }

                    Behavior on color { ColorAnimation { duration: 150 } }
                }
            }

            MouseArea {
                id: logoutArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: GameManager.logout()
            }

            Behavior on border.color { ColorAnimation { duration: 150 } }
        }

        // Theme (placeholder)
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 72
            radius: 12
            color: ThemeManager.getColor("surface")
            border.color: focusedRow === 3
                          ? ThemeManager.getColor("focus") : "transparent"
            border.width: focusedRow === 3 ? 2 : 0

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

            Behavior on border.color { ColorAnimation { duration: 150 } }
        }

        Item { Layout.fillHeight: true }
    }

    function switchToDesktop() {
        GameManager.switchToDesktop()
    }
}
