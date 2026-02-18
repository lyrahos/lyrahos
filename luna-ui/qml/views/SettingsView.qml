import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../components"

Rectangle {
    id: settingsRoot
    color: "transparent"

    // Signal to request focus back to NavBar
    signal requestNavFocus()

    // Controller / keyboard row navigation
    // 0 = Wi-Fi, 1 = Bluetooth, 2 = Audio, 3 = Controller,
    // 4 = Switch to Desktop, 5 = Log Out, 6 = Theme
    property int focusedRow: 0
    property int hoveredRow: -1
    readonly property int rowCount: 7

    // Controller profile editor state
    property bool controllerEditorOpen: false
    property int editingProfileId: -1
    property string editingProfileName: ""
    property bool editingProfileIsDefault: false

    // "rows" = navigating between settings rows
    // "expanded" = navigating inside an expanded WiFi/BT/Audio panel
    property string focusMode: "rows"
    property int wifiFocusIndex: 0
    property int btFocusIndex: 0
    property int audioFocusIndex: 0  // 0..outputCount-1 = outputs, outputCount.. = inputs

    function gainFocus() {
        focusedRow = 0
        focusMode = "rows"
        settingsRoot.forceActiveFocus()
    }

    function loseFocus() {
        focusedRow = -1
        focusMode = "rows"
    }

    Keys.onPressed: function(event) {
        // VirtualKeyboard handles its own keys
        if (settingsVirtualKeyboard.visible) {
            event.accepted = true
            return
        }
        // WiFi popup handles its own keys
        if (wifiPopupVisible) {
            handleWifiPopupKeys(event)
            return
        }
        if (focusMode === "rows") {
            handleRowKeys(event)
        } else if (focusMode === "expanded") {
            handleExpandedKeys(event)
        }
    }

    function handleRowKeys(event) {
        switch (event.key) {
        case Qt.Key_Up:
            if (focusedRow > 0) focusedRow--
            event.accepted = true
            break
        case Qt.Key_Down:
            if (focusedRow < rowCount - 1) focusedRow++
            event.accepted = true
            break
        case Qt.Key_Left:
            requestNavFocus()
            event.accepted = true
            break
        case Qt.Key_Return:
        case Qt.Key_Enter:
            activateRow(focusedRow)
            event.accepted = true
            break
        }
    }

    function handleExpandedKeys(event) {
        switch (event.key) {
        case Qt.Key_Escape:
            // Collapse and go back to row navigation
            exitExpanded()
            event.accepted = true
            break
        default:
            if (focusedRow === 1) handleBtExpandedKeys(event)
            else if (focusedRow === 2) handleAudioExpandedKeys(event)
            else if (focusedRow === 3) handleControllerExpandedKeys(event)
            break
        }
    }

    function exitExpanded() {
        focusMode = "rows"
        settingsRoot.forceActiveFocus()
    }

    // ─── WiFi popup navigation ───
    function handleWifiPopupKeys(event) {
        if (wifiPopupState === "list") {
            var count = settingsWifiModel.count
            switch (event.key) {
            case Qt.Key_Up:
                if (wifiFocusIndex > 0) wifiFocusIndex--
                event.accepted = true
                break
            case Qt.Key_Down:
                if (wifiFocusIndex < count - 1) wifiFocusIndex++
                event.accepted = true
                break
            case Qt.Key_Escape:
            case Qt.Key_Left:
                closeWifiPopup()
                event.accepted = true
                break
            case Qt.Key_Return:
            case Qt.Key_Enter:
                if (count > 0 && wifiFocusIndex >= 0 && wifiFocusIndex < count) {
                    var net = settingsWifiModel.get(wifiFocusIndex)
                    if (net && net.ssid !== connectedSsid) {
                        selectedSsid = net.ssid
                        if (net.security === "" || net.security === "--") {
                            wifiConnecting = true
                            wifiPopupState = "connecting"
                            GameManager.connectToWifi(net.ssid, "")
                        } else {
                            settingsVirtualKeyboard.placeholderText = "Enter password for " + net.ssid + "..."
                            settingsVirtualKeyboard.open("", true)
                        }
                    }
                }
                event.accepted = true
                break
            }
        } else if (wifiPopupState === "done") {
            // Any key dismisses the result
            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter
                    || event.key === Qt.Key_Escape) {
                closeWifiPopup()
                event.accepted = true
            }
        } else {
            // scanning / connecting — Escape cancels
            if (event.key === Qt.Key_Escape) {
                closeWifiPopup()
                event.accepted = true
            }
        }
    }

    // ─── Bluetooth expanded navigation ───
    function handleBtExpandedKeys(event) {
        var count = settingsBtModel.count
        switch (event.key) {
        case Qt.Key_Up:
            if (btFocusIndex > 0) btFocusIndex--
            else exitExpanded()
            event.accepted = true
            break
        case Qt.Key_Down:
            if (btFocusIndex < count - 1) btFocusIndex++
            event.accepted = true
            break
        case Qt.Key_Left:
            exitExpanded()
            event.accepted = true
            break
        case Qt.Key_Return:
        case Qt.Key_Enter:
            if (count > 0 && btFocusIndex >= 0 && btFocusIndex < count) {
                var dev = settingsBtModel.get(btFocusIndex)
                if (dev) {
                    // Check if already connected
                    var alreadyConnected = false
                    for (var i = 0; i < connectedBtDevices.length; i++) {
                        if (connectedBtDevices[i].address === dev.address) {
                            alreadyConnected = true
                            break
                        }
                    }
                    if (!alreadyConnected) {
                        btConnecting = true
                        btStatus = "Connecting to " + dev.name + "..."
                        GameManager.connectBluetooth(dev.address)
                    }
                }
            }
            event.accepted = true
            break
        }
    }

    // ─── Audio expanded navigation ───
    // audioFocusIndex spans: 0..outputCount-1 = output devices, outputCount..total-1 = input devices
    function handleAudioExpandedKeys(event) {
        var outCount = audioOutputDevices.length
        var inCount = audioInputDevices.length
        var totalCount = outCount + inCount

        switch (event.key) {
        case Qt.Key_Up:
            if (audioFocusIndex > 0) audioFocusIndex--
            else exitExpanded()
            event.accepted = true
            break
        case Qt.Key_Down:
            if (audioFocusIndex < totalCount - 1) audioFocusIndex++
            event.accepted = true
            break
        case Qt.Key_Left:
            exitExpanded()
            event.accepted = true
            break
        case Qt.Key_Return:
        case Qt.Key_Enter:
            if (audioFocusIndex < outCount) {
                // Output device
                var outDev = audioOutputDevices[audioFocusIndex]
                if (outDev && outDev.name !== currentAudioOutput)
                    GameManager.setAudioOutputDevice(outDev.name)
            } else if (audioFocusIndex < totalCount) {
                // Input device
                var inDev = audioInputDevices[audioFocusIndex - outCount]
                if (inDev && inDev.name !== currentAudioInput)
                    GameManager.setAudioInputDevice(inDev.name)
            }
            event.accepted = true
            break
        }
    }

    function openWifiPopup() {
        wifiPopupVisible = true
        wifiPopupState = "scanning"
        wifiStatus = ""
        wifiResultMessage = ""
        selectedSsid = ""
        wifiFocusIndex = 0
        wifiScanning = true
        settingsWifiModel.clear()
        GameManager.scanWifiNetworks()
    }

    function closeWifiPopup() {
        wifiPopupVisible = false
        wifiPopupState = "scanning"
        selectedSsid = ""
        wifiStatus = ""
        settingsRoot.forceActiveFocus()
    }

    function activateRow(row) {
        switch (row) {
        case 0:
            openWifiPopup()
            break
        case 1:
            if (!btExpanded) {
                btExpanded = true
                btStatus = ""
                btScanning = true
                settingsBtModel.clear()
                GameManager.scanBluetoothDevices()
                btFocusIndex = 0
                focusMode = "expanded"
            } else {
                btFocusIndex = 0
                focusMode = "expanded"
            }
            break
        case 2:
            if (!audioExpanded) {
                audioExpanded = true
                refreshAudioDevices()
                audioFocusIndex = 0
                focusMode = "expanded"
            } else {
                audioFocusIndex = 0
                focusMode = "expanded"
            }
            break
        case 3:
            // Controller — expand to show profile list
            if (!controllerExpanded) {
                controllerExpanded = true
                refreshControllerProfiles()
                controllerFocusIndex = 0
                focusMode = "expanded"
            } else {
                controllerFocusIndex = 0
                focusMode = "expanded"
            }
            break
        case 4: switchToDesktop(); break
        case 5: GameManager.logout(); break
        // case 6: theme — placeholder, no action yet
        }
    }

    // WiFi state
    property string connectedSsid: ""
    property bool wifiPopupVisible: false
    property string wifiPopupState: "scanning"  // scanning, list, connecting, done
    property bool wifiScanning: false
    property bool wifiConnecting: false
    property bool wifiDisconnecting: false
    property string wifiStatus: ""
    property string wifiResultMessage: ""
    property bool wifiResultSuccess: false
    property string selectedSsid: ""

    // Bluetooth state
    property bool btExpanded: false
    property bool btScanning: false
    property bool btConnecting: false
    property string btStatus: ""
    property var connectedBtDevices: []

    // Audio state
    property bool audioExpanded: false
    property string currentAudioOutput: ""
    property string currentAudioInput: ""
    property var audioOutputDevices: []
    property var audioInputDevices: []

    // Controller state
    property bool controllerExpanded: false
    property int controllerFocusIndex: 0
    property var controllerProfiles: []

    function refreshControllerProfiles() {
        controllerProfiles = ProfileResolver.getProfiles()
    }

    // Controller expanded navigation
    function handleControllerExpandedKeys(event) {
        var count = controllerProfiles.length
        switch (event.key) {
        case Qt.Key_Up:
            if (controllerFocusIndex > 0) controllerFocusIndex--
            else exitExpanded()
            event.accepted = true
            break
        case Qt.Key_Down:
            if (controllerFocusIndex < count - 1) controllerFocusIndex++
            event.accepted = true
            break
        case Qt.Key_Left:
            exitExpanded()
            event.accepted = true
            break
        case Qt.Key_Return:
        case Qt.Key_Enter:
            if (count > 0 && controllerFocusIndex >= 0 && controllerFocusIndex < count) {
                var profile = controllerProfiles[controllerFocusIndex]
                openProfileEditor(profile.id, profile.name, profile.isDefault)
            }
            event.accepted = true
            break
        }
    }

    function openProfileEditor(profileId, name, isDefault) {
        editingProfileId = profileId
        editingProfileName = name
        editingProfileIsDefault = isDefault
        controllerEditorOpen = true
    }

    function closeProfileEditor() {
        controllerEditorOpen = false
        editingProfileId = -1
        refreshControllerProfiles()
        settingsRoot.forceActiveFocus()
    }

    Component.onCompleted: {
        refreshWifiStatus()
        refreshBtStatus()
    }

    function refreshWifiStatus() {
        connectedSsid = GameManager.getConnectedWifi()
    }

    function refreshBtStatus() {
        connectedBtDevices = GameManager.getConnectedBluetoothDevices()
    }

    function refreshAudioDevices() {
        audioOutputDevices = GameManager.getAudioOutputDevices()
        audioInputDevices = GameManager.getAudioInputDevices()
        currentAudioOutput = GameManager.getDefaultAudioOutput()
        currentAudioInput = GameManager.getDefaultAudioInput()
    }

    Connections {
        target: GameManager
        function onWifiConnectResult(success, message) {
            wifiConnecting = false
            wifiResultSuccess = success
            wifiResultMessage = success
                ? "Connected to " + selectedSsid
                : message
            wifiPopupState = "done"
            // Always refresh — a failed attempt may have changed connection state
            refreshWifiStatus()
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
            if (wifiPopupVisible) wifiPopupState = "list"
        }
        function onBluetoothDevicesScanned(devices) {
            btScanning = false
            settingsBtModel.clear()
            for (var i = 0; i < devices.length; i++)
                settingsBtModel.append(devices[i])
        }
        function onBluetoothConnectResult(success, message) {
            btConnecting = false
            if (success) {
                btStatus = "Connected!"
                refreshBtStatus()
            } else {
                btStatus = "Failed: " + message
            }
        }
        function onBluetoothDisconnectResult(success, message) {
            if (success) {
                btStatus = "Disconnected"
                refreshBtStatus()
            } else {
                btStatus = "Failed: " + message
            }
        }
        function onAudioOutputSet(success, message) {
            if (success) refreshAudioDevices()
        }
        function onAudioInputSet(success, message) {
            if (success) refreshAudioDevices()
        }
    }

    // Refresh connection status periodically
    Timer {
        interval: 5000
        running: true
        repeat: true
        onTriggered: {
            refreshWifiStatus()
            refreshBtStatus()
        }
    }

    Flickable {
        anchors.fill: parent
        anchors.margins: 24
        contentHeight: settingsCol.height
        clip: true
        boundsBehavior: Flickable.StopAtBounds

    ColumnLayout {
        id: settingsCol
        width: parent.width
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
            Layout.preferredHeight: wifiRowLayout.height + 32
            radius: 12
            color: ThemeManager.getColor("surface")
            border.color: (focusedRow === 0 || hoveredRow === 0)
                          ? ThemeManager.getColor("focus") : "transparent"
            border.width: (focusedRow === 0 || hoveredRow === 0) ? 2 : 0

            Behavior on border.color { ColorAnimation { duration: 150 } }

            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                z: -1
                onEntered: { hoveredRow = 0; focusedRow = 0; settingsRoot.forceActiveFocus() }
                onExited: hoveredRow = -1
                onClicked: { focusedRow = 0; activateRow(0) }
            }

            RowLayout {
                id: wifiRowLayout
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 16
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

                // Open Networks arrow
                Text {
                    text: ">"
                    font.pixelSize: 18
                    font.bold: true
                    color: ThemeManager.getColor("textSecondary")
                }
            }
        }

        // ── Bluetooth Section ──
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: btCol.height + 32
            radius: 12
            color: ThemeManager.getColor("surface")
            border.color: (focusedRow === 1 || hoveredRow === 1)
                          ? ThemeManager.getColor("focus") : "transparent"
            border.width: (focusedRow === 1 || hoveredRow === 1) ? 2 : 0

            Behavior on border.color { ColorAnimation { duration: 150 } }

            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                z: -1
                onEntered: { hoveredRow = 1; focusedRow = 1; settingsRoot.forceActiveFocus() }
                onExited: hoveredRow = -1
                onClicked: { focusedRow = 1; activateRow(1) }
            }

            ColumnLayout {
                id: btCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 16
                spacing: 12

                // Header row
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 4

                        Text {
                            text: "Bluetooth"
                            font.pixelSize: ThemeManager.getFontSize("medium")
                            font.family: ThemeManager.getFont("body")
                            font.bold: true
                            color: ThemeManager.getColor("textPrimary")
                        }

                        Text {
                            text: {
                                if (connectedBtDevices.length === 0) return "No devices connected"
                                var names = []
                                for (var i = 0; i < connectedBtDevices.length; i++)
                                    names.push(connectedBtDevices[i].name)
                                return "Connected to " + names.join(", ")
                            }
                            font.pixelSize: ThemeManager.getFontSize("small")
                            font.family: ThemeManager.getFont("body")
                            color: connectedBtDevices.length > 0
                                   ? ThemeManager.getColor("accent")
                                   : ThemeManager.getColor("textSecondary")
                        }
                    }

                    // Expand/collapse arrow
                    Rectangle {
                        Layout.preferredWidth: 40
                        Layout.preferredHeight: 40
                        radius: 20
                        color: expandBtArea.containsMouse
                               ? ThemeManager.getColor("hover")
                               : "transparent"

                        Text {
                            anchors.centerIn: parent
                            text: btExpanded ? "v" : ">"
                            font.pixelSize: 18
                            font.bold: true
                            color: ThemeManager.getColor("textPrimary")
                        }

                        MouseArea {
                            id: expandBtArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                btExpanded = !btExpanded
                                if (btExpanded) {
                                    btStatus = ""
                                    btScanning = true
                                    settingsBtModel.clear()
                                    GameManager.scanBluetoothDevices()
                                }
                            }
                        }
                    }
                }

                // ── Expanded Bluetooth device list ──
                ColumnLayout {
                    visible: btExpanded
                    Layout.fillWidth: true
                    spacing: 8

                    // Status message
                    Text {
                        visible: btStatus !== ""
                        text: btStatus
                        font.pixelSize: ThemeManager.getFontSize("small")
                        font.family: ThemeManager.getFont("body")
                        color: btStatus.startsWith("Failed")
                               ? "#ff6b6b"
                               : btStatus === "Connected!" || btStatus === "Disconnected"
                                 ? ThemeManager.getColor("accent")
                                 : ThemeManager.getColor("textSecondary")
                    }

                    // Refresh button
                    RowLayout {
                        Layout.fillWidth: true

                        Text {
                            text: "Available Devices"
                            font.pixelSize: ThemeManager.getFontSize("small")
                            font.family: ThemeManager.getFont("body")
                            font.bold: true
                            color: ThemeManager.getColor("textSecondary")
                            Layout.fillWidth: true
                        }

                        Rectangle {
                            visible: !btScanning
                            Layout.preferredWidth: btRefreshLabel.width + 24
                            Layout.preferredHeight: 32
                            radius: 8
                            color: btRefreshArea.containsMouse
                                   ? ThemeManager.getColor("hover")
                                   : "transparent"

                            Text {
                                id: btRefreshLabel
                                anchors.centerIn: parent
                                text: "Refresh"
                                font.pixelSize: ThemeManager.getFontSize("small")
                                font.family: ThemeManager.getFont("body")
                                color: ThemeManager.getColor("primary")
                            }

                            MouseArea {
                                id: btRefreshArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    btScanning = true
                                    settingsBtModel.clear()
                                    GameManager.scanBluetoothDevices()
                                }
                            }
                        }
                    }

                    // Scanning spinner
                    RowLayout {
                        visible: btScanning
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
                                        running: btScanning
                                    }
                                }
                            }
                        }

                        Text {
                            text: "Scanning for devices..."
                            font.pixelSize: ThemeManager.getFontSize("small")
                            font.family: ThemeManager.getFont("body")
                            color: ThemeManager.getColor("textSecondary")

                            SequentialAnimation on opacity {
                                running: btScanning
                                loops: Animation.Infinite
                                NumberAnimation { to: 0.4; duration: 600 }
                                NumberAnimation { to: 1.0; duration: 600 }
                            }
                        }
                    }

                    // Device list
                    ListView {
                        id: settingsBtList
                        Layout.fillWidth: true
                        Layout.preferredHeight: Math.min(settingsBtModel.count * 54, 270)
                        clip: true
                        spacing: 4
                        model: ListModel { id: settingsBtModel }

                        delegate: Rectangle {
                            required property int index
                            required property string address
                            required property string name

                            property bool isKbFocused: focusMode === "expanded" && focusedRow === 1 && btFocusIndex === index

                            width: settingsBtList.width
                            height: 50
                            radius: 10

                            property bool isConnected: {
                                for (var i = 0; i < connectedBtDevices.length; i++) {
                                    if (connectedBtDevices[i].address === address)
                                        return true
                                }
                                return false
                            }

                            color: (btItemArea.containsMouse || isKbFocused)
                                   ? Qt.rgba(ThemeManager.getColor("primary").r,
                                             ThemeManager.getColor("primary").g,
                                             ThemeManager.getColor("primary").b, 0.15)
                                   : ThemeManager.getColor("hover")
                            border.color: isConnected
                                          ? ThemeManager.getColor("accent")
                                          : (btItemArea.containsMouse || isKbFocused)
                                            ? ThemeManager.getColor("focus") : "transparent"
                            border.width: (isConnected || btItemArea.containsMouse || isKbFocused) ? 2 : 0

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 16
                                anchors.rightMargin: 16
                                spacing: 12

                                Text {
                                    text: name
                                    font.pixelSize: ThemeManager.getFontSize("small")
                                    font.family: ThemeManager.getFont("body")
                                    font.bold: isConnected
                                    color: ThemeManager.getColor("textPrimary")
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                }

                                // "Connected" badge or "Connect" action
                                Text {
                                    visible: isConnected
                                    text: "Connected"
                                    font.pixelSize: ThemeManager.getFontSize("small")
                                    font.family: ThemeManager.getFont("body")
                                    color: ThemeManager.getColor("accent")
                                }

                                // Disconnect button for connected devices
                                Rectangle {
                                    visible: isConnected
                                    Layout.preferredWidth: btDisconnLabel.width + 16
                                    Layout.preferredHeight: 30
                                    radius: 6
                                    color: "transparent"
                                    border.color: btDisconnArea.containsMouse
                                                  ? "#ff6b6b" : Qt.rgba(1, 1, 1, 0.15)
                                    border.width: 1

                                    Text {
                                        id: btDisconnLabel
                                        anchors.centerIn: parent
                                        text: "Disconnect"
                                        font.pixelSize: ThemeManager.getFontSize("small")
                                        font.family: ThemeManager.getFont("body")
                                        color: btDisconnArea.containsMouse
                                               ? "#ff6b6b"
                                               : ThemeManager.getColor("textSecondary")
                                    }

                                    MouseArea {
                                        id: btDisconnArea
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: GameManager.disconnectBluetooth(address)
                                    }
                                }

                                Text {
                                    visible: !isConnected
                                    text: address
                                    font.pixelSize: ThemeManager.getFontSize("small")
                                    font.family: ThemeManager.getFont("body")
                                    color: ThemeManager.getColor("textSecondary")
                                }
                            }

                            MouseArea {
                                id: btItemArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (isConnected) return
                                    btConnecting = true
                                    btStatus = "Connecting to " + name + "..."
                                    GameManager.connectBluetooth(address)
                                }
                            }

                            Behavior on color { ColorAnimation { duration: 120 } }
                            Behavior on border.color { ColorAnimation { duration: 120 } }
                        }
                    }

                    // Connecting indicator
                    Text {
                        visible: btConnecting
                        text: btStatus
                        font.pixelSize: ThemeManager.getFontSize("small")
                        font.family: ThemeManager.getFont("body")
                        color: ThemeManager.getColor("primary")

                        SequentialAnimation on opacity {
                            running: btConnecting
                            loops: Animation.Infinite
                            NumberAnimation { to: 0.4; duration: 600 }
                            NumberAnimation { to: 1.0; duration: 600 }
                        }
                    }
                }
            }
        }

        // ── Audio Section ──
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: audioCol.height + 32
            radius: 12
            color: ThemeManager.getColor("surface")
            border.color: (focusedRow === 2 || hoveredRow === 2)
                          ? ThemeManager.getColor("focus") : "transparent"
            border.width: (focusedRow === 2 || hoveredRow === 2) ? 2 : 0

            Behavior on border.color { ColorAnimation { duration: 150 } }

            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                z: -1
                onEntered: { hoveredRow = 2; focusedRow = 2; settingsRoot.forceActiveFocus() }
                onExited: hoveredRow = -1
                onClicked: { focusedRow = 2; activateRow(2) }
            }

            ColumnLayout {
                id: audioCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 16
                spacing: 12

                // Header row
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 4

                        Text {
                            text: "Audio"
                            font.pixelSize: ThemeManager.getFontSize("medium")
                            font.family: ThemeManager.getFont("body")
                            font.bold: true
                            color: ThemeManager.getColor("textPrimary")
                        }

                        Text {
                            text: {
                                // Find description for current output
                                for (var i = 0; i < audioOutputDevices.length; i++) {
                                    if (audioOutputDevices[i].name === currentAudioOutput)
                                        return audioOutputDevices[i].description
                                }
                                return "Default"
                            }
                            font.pixelSize: ThemeManager.getFontSize("small")
                            font.family: ThemeManager.getFont("body")
                            color: ThemeManager.getColor("textSecondary")
                        }
                    }

                    // Expand/collapse arrow
                    Rectangle {
                        Layout.preferredWidth: 40
                        Layout.preferredHeight: 40
                        radius: 20
                        color: expandAudioArea.containsMouse
                               ? ThemeManager.getColor("hover")
                               : "transparent"

                        Text {
                            anchors.centerIn: parent
                            text: audioExpanded ? "v" : ">"
                            font.pixelSize: 18
                            font.bold: true
                            color: ThemeManager.getColor("textPrimary")
                        }

                        MouseArea {
                            id: expandAudioArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                audioExpanded = !audioExpanded
                                if (audioExpanded) refreshAudioDevices()
                            }
                        }
                    }
                }

                // ── Expanded Audio device selection ──
                ColumnLayout {
                    visible: audioExpanded
                    Layout.fillWidth: true
                    spacing: 12

                    // ── Output (Speakers / Headset) ──
                    Text {
                        text: "Output"
                        font.pixelSize: ThemeManager.getFontSize("small")
                        font.family: ThemeManager.getFont("body")
                        font.bold: true
                        color: ThemeManager.getColor("textSecondary")
                    }

                    ListView {
                        id: audioOutputList
                        Layout.fillWidth: true
                        Layout.preferredHeight: Math.max(audioOutputDevices.length * 54, 0)
                        clip: true
                        spacing: 4
                        interactive: false
                        model: audioOutputDevices

                        delegate: Rectangle {
                            required property var modelData
                            required property int index

                            property bool isKbFocused: focusMode === "expanded" && focusedRow === 2 && audioFocusIndex === index

                            width: audioOutputList.width
                            height: 50
                            radius: 10

                            property bool isCurrent: modelData.name === currentAudioOutput

                            color: (audioOutArea.containsMouse || isKbFocused)
                                   ? Qt.rgba(ThemeManager.getColor("primary").r,
                                             ThemeManager.getColor("primary").g,
                                             ThemeManager.getColor("primary").b, 0.15)
                                   : ThemeManager.getColor("hover")
                            border.color: isCurrent
                                          ? ThemeManager.getColor("accent")
                                          : (audioOutArea.containsMouse || isKbFocused)
                                            ? ThemeManager.getColor("focus") : "transparent"
                            border.width: (isCurrent || audioOutArea.containsMouse || isKbFocused) ? 2 : 0

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 16
                                anchors.rightMargin: 16
                                spacing: 12

                                Text {
                                    text: modelData.description
                                    font.pixelSize: ThemeManager.getFontSize("small")
                                    font.family: ThemeManager.getFont("body")
                                    font.bold: isCurrent
                                    color: ThemeManager.getColor("textPrimary")
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                }

                                Text {
                                    visible: isCurrent
                                    text: "Active"
                                    font.pixelSize: ThemeManager.getFontSize("small")
                                    font.family: ThemeManager.getFont("body")
                                    color: ThemeManager.getColor("accent")
                                }
                            }

                            MouseArea {
                                id: audioOutArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (!isCurrent)
                                        GameManager.setAudioOutputDevice(modelData.name)
                                }
                            }

                            Behavior on color { ColorAnimation { duration: 120 } }
                            Behavior on border.color { ColorAnimation { duration: 120 } }
                        }
                    }

                    // ── Input (Microphone) ──
                    Text {
                        text: "Microphone"
                        font.pixelSize: ThemeManager.getFontSize("small")
                        font.family: ThemeManager.getFont("body")
                        font.bold: true
                        color: ThemeManager.getColor("textSecondary")
                    }

                    ListView {
                        id: audioInputList
                        Layout.fillWidth: true
                        Layout.preferredHeight: Math.max(audioInputDevices.length * 54, 0)
                        clip: true
                        spacing: 4
                        interactive: false
                        model: audioInputDevices

                        delegate: Rectangle {
                            required property var modelData
                            required property int index

                            property bool isKbFocused: focusMode === "expanded" && focusedRow === 2 && audioFocusIndex === (audioOutputDevices.length + index)

                            width: audioInputList.width
                            height: 50
                            radius: 10

                            property bool isCurrent: modelData.name === currentAudioInput

                            color: (audioInArea.containsMouse || isKbFocused)
                                   ? Qt.rgba(ThemeManager.getColor("primary").r,
                                             ThemeManager.getColor("primary").g,
                                             ThemeManager.getColor("primary").b, 0.15)
                                   : ThemeManager.getColor("hover")
                            border.color: isCurrent
                                          ? ThemeManager.getColor("accent")
                                          : (audioInArea.containsMouse || isKbFocused)
                                            ? ThemeManager.getColor("focus") : "transparent"
                            border.width: (isCurrent || audioInArea.containsMouse || isKbFocused) ? 2 : 0

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 16
                                anchors.rightMargin: 16
                                spacing: 12

                                Text {
                                    text: modelData.description
                                    font.pixelSize: ThemeManager.getFontSize("small")
                                    font.family: ThemeManager.getFont("body")
                                    font.bold: isCurrent
                                    color: ThemeManager.getColor("textPrimary")
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                }

                                Text {
                                    visible: isCurrent
                                    text: "Active"
                                    font.pixelSize: ThemeManager.getFontSize("small")
                                    font.family: ThemeManager.getFont("body")
                                    color: ThemeManager.getColor("accent")
                                }
                            }

                            MouseArea {
                                id: audioInArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (!isCurrent)
                                        GameManager.setAudioInputDevice(modelData.name)
                                }
                            }

                            Behavior on color { ColorAnimation { duration: 120 } }
                            Behavior on border.color { ColorAnimation { duration: 120 } }
                        }
                    }

                    // Hint when no devices found
                    Text {
                        visible: audioOutputDevices.length === 0 && audioInputDevices.length === 0
                        text: "No audio devices found"
                        font.pixelSize: ThemeManager.getFontSize("small")
                        font.family: ThemeManager.getFont("body")
                        color: ThemeManager.getColor("textSecondary")
                    }
                }
            }
        }

        // ── Controller Section ──
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: controllerCol.height + 32
            radius: 12
            color: ThemeManager.getColor("surface")
            border.color: (focusedRow === 3 || hoveredRow === 3)
                          ? ThemeManager.getColor("focus") : "transparent"
            border.width: (focusedRow === 3 || hoveredRow === 3) ? 2 : 0

            Behavior on border.color { ColorAnimation { duration: 150 } }

            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                z: -1
                onEntered: { hoveredRow = 3; focusedRow = 3; settingsRoot.forceActiveFocus() }
                onExited: hoveredRow = -1
                onClicked: { focusedRow = 3; activateRow(3) }
            }

            ColumnLayout {
                id: controllerCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 16
                spacing: 12

                // Header row
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 4

                        Text {
                            text: "Controller"
                            font.pixelSize: ThemeManager.getFontSize("medium")
                            font.family: ThemeManager.getFont("body")
                            font.bold: true
                            color: ThemeManager.getColor("textPrimary")
                        }

                        Text {
                            text: ControllerManager.controllerConnected
                                  ? ControllerManager.controllerName + " (" + ControllerManager.controllerFamily + ")"
                                  : "No controller connected"
                            font.pixelSize: ThemeManager.getFontSize("small")
                            font.family: ThemeManager.getFont("body")
                            color: ControllerManager.controllerConnected
                                   ? ThemeManager.getColor("accent")
                                   : ThemeManager.getColor("textSecondary")
                        }
                    }

                    // Expand/collapse arrow
                    Rectangle {
                        Layout.preferredWidth: 40
                        Layout.preferredHeight: 40
                        radius: 20
                        color: expandControllerArea.containsMouse
                               ? ThemeManager.getColor("hover")
                               : "transparent"

                        Text {
                            anchors.centerIn: parent
                            text: controllerExpanded ? "v" : ">"
                            font.pixelSize: 18
                            font.bold: true
                            color: ThemeManager.getColor("textPrimary")
                        }

                        MouseArea {
                            id: expandControllerArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                controllerExpanded = !controllerExpanded
                                if (controllerExpanded) refreshControllerProfiles()
                            }
                        }
                    }
                }

                // ── Expanded controller profile list ──
                ColumnLayout {
                    visible: controllerExpanded && !controllerEditorOpen
                    Layout.fillWidth: true
                    spacing: 8

                    // Section headers for profile categories
                    Text {
                        text: "Profiles"
                        font.pixelSize: ThemeManager.getFontSize("small")
                        font.family: ThemeManager.getFont("body")
                        font.bold: true
                        color: ThemeManager.getColor("textSecondary")
                    }

                    // Profile list
                    ListView {
                        id: controllerProfileList
                        Layout.fillWidth: true
                        Layout.preferredHeight: Math.min(controllerProfiles.length * 60, 420)
                        clip: true
                        spacing: 4
                        model: controllerProfiles

                        delegate: Rectangle {
                            required property var modelData
                            required property int index

                            property bool isKbFocused: focusMode === "expanded" && focusedRow === 3
                                                       && controllerFocusIndex === index

                            width: controllerProfileList.width
                            height: 56
                            radius: 10
                            color: (controllerItemArea.containsMouse || isKbFocused)
                                   ? Qt.rgba(ThemeManager.getColor("primary").r,
                                             ThemeManager.getColor("primary").g,
                                             ThemeManager.getColor("primary").b, 0.15)
                                   : ThemeManager.getColor("hover")
                            border.color: (controllerItemArea.containsMouse || isKbFocused)
                                          ? ThemeManager.getColor("focus") : "transparent"
                            border.width: (controllerItemArea.containsMouse || isKbFocused) ? 2 : 0

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 16
                                anchors.rightMargin: 16
                                spacing: 12

                                // Profile scope icon
                                Rectangle {
                                    Layout.preferredWidth: 36
                                    Layout.preferredHeight: 36
                                    radius: 8
                                    color: Qt.rgba(ThemeManager.getColor("primary").r,
                                                   ThemeManager.getColor("primary").g,
                                                   ThemeManager.getColor("primary").b, 0.15)

                                    Text {
                                        anchors.centerIn: parent
                                        text: {
                                            var scope = modelData.scope
                                            if (scope === "global") return "G"
                                            if (scope === "family") return "F"
                                            if (scope === "client") return "C"
                                            if (scope === "game") return "#"
                                            return "?"
                                        }
                                        font.pixelSize: 14
                                        font.bold: true
                                        color: ThemeManager.getColor("primary")
                                    }
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 2

                                    Text {
                                        text: modelData.name
                                        font.pixelSize: ThemeManager.getFontSize("small")
                                        font.family: ThemeManager.getFont("body")
                                        font.bold: true
                                        color: ThemeManager.getColor("textPrimary")
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                    }

                                    Text {
                                        text: {
                                            var parts = []
                                            parts.push(modelData.scope)
                                            if (modelData.controllerFamily && modelData.controllerFamily !== "any")
                                                parts.push(modelData.controllerFamily)
                                            if (modelData.isDefault) parts.push("built-in")
                                            return parts.join(" · ")
                                        }
                                        font.pixelSize: 12
                                        font.family: ThemeManager.getFont("body")
                                        color: ThemeManager.getColor("textSecondary")
                                    }
                                }

                                // Default badge
                                Rectangle {
                                    visible: modelData.isDefault
                                    Layout.preferredWidth: defaultLabel.width + 16
                                    Layout.preferredHeight: 24
                                    radius: 12
                                    color: Qt.rgba(ThemeManager.getColor("accent").r,
                                                   ThemeManager.getColor("accent").g,
                                                   ThemeManager.getColor("accent").b, 0.15)

                                    Text {
                                        id: defaultLabel
                                        anchors.centerIn: parent
                                        text: "Default"
                                        font.pixelSize: 11
                                        font.family: ThemeManager.getFont("body")
                                        color: ThemeManager.getColor("accent")
                                    }
                                }
                            }

                            MouseArea {
                                id: controllerItemArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    openProfileEditor(modelData.id, modelData.name, modelData.isDefault)
                                }
                            }

                            Behavior on color { ColorAnimation { duration: 120 } }
                            Behavior on border.color { ColorAnimation { duration: 120 } }
                        }
                    }

                    // Create new profile button
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 44
                        radius: 10
                        color: newProfileArea.containsMouse
                               ? Qt.rgba(ThemeManager.getColor("primary").r,
                                         ThemeManager.getColor("primary").g,
                                         ThemeManager.getColor("primary").b, 0.15)
                               : ThemeManager.getColor("hover")
                        border.color: newProfileArea.containsMouse
                                      ? ThemeManager.getColor("focus") : "transparent"
                        border.width: newProfileArea.containsMouse ? 1 : 0

                        Text {
                            anchors.centerIn: parent
                            text: "+ Create Custom Profile"
                            font.pixelSize: ThemeManager.getFontSize("small")
                            font.family: ThemeManager.getFont("body")
                            color: ThemeManager.getColor("primary")
                        }

                        MouseArea {
                            id: newProfileArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                var id = ProfileResolver.createProfile(
                                    "Custom Profile", "global",
                                    ControllerManager.controllerFamily || "any")
                                if (id > 0) {
                                    refreshControllerProfiles()
                                    openProfileEditor(id, "Custom Profile", false)
                                }
                            }
                        }
                    }
                    // Export all profiles button
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 44
                        radius: 10
                        color: exportArea.containsMouse
                               ? Qt.rgba(ThemeManager.getColor("secondary").r,
                                         ThemeManager.getColor("secondary").g,
                                         ThemeManager.getColor("secondary").b, 0.15)
                               : ThemeManager.getColor("hover")
                        border.color: exportArea.containsMouse
                                      ? ThemeManager.getColor("secondary") : "transparent"
                        border.width: exportArea.containsMouse ? 1 : 0

                        Text {
                            anchors.centerIn: parent
                            text: "Export All Profiles to ~/.config/luna-ui/profiles/"
                            font.pixelSize: ThemeManager.getFontSize("small")
                            font.family: ThemeManager.getFont("body")
                            color: ThemeManager.getColor("secondary")
                        }

                        MouseArea {
                            id: exportArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                ProfileResolver.exportAllProfiles()
                                exportStatus.visible = true
                                exportStatusTimer.restart()
                            }
                        }
                    }

                    // Export status message
                    Text {
                        id: exportStatus
                        visible: false
                        text: "Profiles exported successfully"
                        font.pixelSize: ThemeManager.getFontSize("small")
                        font.family: ThemeManager.getFont("body")
                        color: ThemeManager.getColor("accent")

                        Timer {
                            id: exportStatusTimer
                            interval: 3000
                            onTriggered: exportStatus.visible = false
                        }
                    }
                }

                // ── Embedded profile editor ──
                ControllerProfileEditor {
                    visible: controllerExpanded && controllerEditorOpen
                    Layout.fillWidth: true
                    Layout.preferredHeight: 600
                    profileId: editingProfileId
                    profileName: editingProfileName
                    isDefault: editingProfileIsDefault
                    onBackRequested: closeProfileEditor()
                }
            }
        }

        // ── Switch to Desktop Mode ──
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 72
            radius: 12
            color: ThemeManager.getColor("surface")
            border.color: (switchArea.containsMouse || focusedRow === 4 || hoveredRow === 4)
                          ? ThemeManager.getColor("focus") : "transparent"
            border.width: (switchArea.containsMouse || focusedRow === 4 || hoveredRow === 4) ? 2 : 0

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
                onEntered: { focusedRow = 4; settingsRoot.forceActiveFocus() }
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
            border.color: (logoutArea.containsMouse || focusedRow === 5 || hoveredRow === 5)
                          ? "#ff6b6b" : "transparent"
            border.width: (logoutArea.containsMouse || focusedRow === 5 || hoveredRow === 5) ? 2 : 0

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
                    color: (logoutArea.containsMouse || focusedRow === 5 || hoveredRow === 5)
                           ? "#ff6b6b" : Qt.rgba(1, 0.42, 0.42, 0.15)

                    Text {
                        anchors.centerIn: parent
                        text: "\u23FB"
                        font.pixelSize: 18
                        font.bold: true
                        color: (logoutArea.containsMouse || focusedRow === 5 || hoveredRow === 5)
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
                onEntered: { focusedRow = 5; settingsRoot.forceActiveFocus() }
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
            border.color: (focusedRow === 6 || hoveredRow === 6)
                          ? ThemeManager.getColor("focus") : "transparent"
            border.width: (focusedRow === 6 || hoveredRow === 6) ? 2 : 0

            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                z: -1
                onEntered: { hoveredRow = 6; focusedRow = 6; settingsRoot.forceActiveFocus() }
                onExited: hoveredRow = -1
                onClicked: { focusedRow = 6; activateRow(6) }
            }

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
    } // Flickable

    function switchToDesktop() {
        GameManager.switchToDesktop()
    }

    // ─── Wi-Fi Network Popup ───
    Rectangle {
        id: wifiPopup
        visible: wifiPopupVisible
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.7)
        z: 500

        MouseArea { anchors.fill: parent; onClicked: {} } // block clicks behind

        Rectangle {
            anchors.centerIn: parent
            width: 500
            height: wifiPopupCol.height + 48
            radius: 16
            color: ThemeManager.getColor("surface")

            ColumnLayout {
                id: wifiPopupCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 24
                spacing: 16

                // Title row
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12

                    Text {
                        text: "Wi-Fi Networks"
                        font.pixelSize: ThemeManager.getFontSize("large")
                        font.family: ThemeManager.getFont("heading")
                        font.bold: true
                        color: ThemeManager.getColor("textPrimary")
                        Layout.fillWidth: true
                    }

                    // Refresh button (only in list state)
                    Rectangle {
                        visible: wifiPopupState === "list"
                        Layout.preferredWidth: popupRefreshLabel.width + 24
                        Layout.preferredHeight: 32
                        radius: 8
                        color: popupRefreshArea.containsMouse
                               ? ThemeManager.getColor("hover") : "transparent"

                        Text {
                            id: popupRefreshLabel
                            anchors.centerIn: parent
                            text: "Refresh"
                            font.pixelSize: ThemeManager.getFontSize("small")
                            font.family: ThemeManager.getFont("body")
                            color: ThemeManager.getColor("primary")
                        }

                        MouseArea {
                            id: popupRefreshArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                wifiPopupState = "scanning"
                                wifiScanning = true
                                settingsWifiModel.clear()
                                GameManager.scanWifiNetworks()
                            }
                        }
                    }

                    // Close button
                    Rectangle {
                        visible: wifiPopupState !== "connecting"
                        Layout.preferredWidth: 32
                        Layout.preferredHeight: 32
                        radius: 16
                        color: popupCloseArea.containsMouse
                               ? ThemeManager.getColor("hover") : "transparent"

                        Text {
                            anchors.centerIn: parent
                            text: "X"
                            font.pixelSize: 14
                            font.bold: true
                            color: ThemeManager.getColor("textSecondary")
                        }

                        MouseArea {
                            id: popupCloseArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: closeWifiPopup()
                        }
                    }
                }

                // ── Scanning state ──
                RowLayout {
                    visible: wifiPopupState === "scanning"
                    Layout.fillWidth: true
                    Layout.preferredHeight: 64
                    spacing: 12
                    Layout.alignment: Qt.AlignHCenter

                    Item {
                        Layout.preferredWidth: 28
                        Layout.preferredHeight: 28
                        Layout.alignment: Qt.AlignVCenter

                        Rectangle {
                            anchors.centerIn: parent
                            width: 26
                            height: 26
                            radius: 13
                            color: "transparent"
                            border.width: 3
                            border.color: Qt.rgba(1, 1, 1, 0.08)

                            Rectangle {
                                width: 26
                                height: 26
                                radius: 13
                                color: "transparent"
                                border.width: 3
                                border.color: "transparent"

                                Rectangle {
                                    width: 10
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
                                    running: wifiPopupState === "scanning"
                                }
                            }
                        }
                    }

                    Text {
                        text: "Scanning for networks..."
                        font.pixelSize: ThemeManager.getFontSize("medium")
                        font.family: ThemeManager.getFont("body")
                        color: ThemeManager.getColor("textSecondary")

                        SequentialAnimation on opacity {
                            running: wifiPopupState === "scanning"
                            loops: Animation.Infinite
                            NumberAnimation { to: 0.4; duration: 600 }
                            NumberAnimation { to: 1.0; duration: 600 }
                        }
                    }
                }

                // ── List state ──
                ListView {
                    id: wifiPopupList
                    visible: wifiPopupState === "list"
                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.min(settingsWifiModel.count * 54, 324)
                    clip: true
                    spacing: 4
                    model: ListModel { id: settingsWifiModel }

                    delegate: Rectangle {
                        property bool isKbFocused: wifiPopupState === "list" && wifiFocusIndex === index
                        width: wifiPopupList.width
                        height: 50
                        radius: 10
                        color: (wifiPopupItemArea.containsMouse || isKbFocused)
                               ? Qt.rgba(ThemeManager.getColor("primary").r,
                                         ThemeManager.getColor("primary").g,
                                         ThemeManager.getColor("primary").b, 0.15)
                               : ThemeManager.getColor("hover")
                        border.color: model.ssid === connectedSsid
                                      ? ThemeManager.getColor("accent")
                                      : (wifiPopupItemArea.containsMouse || isKbFocused)
                                        ? ThemeManager.getColor("focus") : "transparent"
                        border.width: (model.ssid === connectedSsid || wifiPopupItemArea.containsMouse || isKbFocused) ? 2 : 0

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 16
                            anchors.rightMargin: 16
                            spacing: 12

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
                            id: wifiPopupItemArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (model.ssid === connectedSsid) return
                                selectedSsid = model.ssid
                                if (model.security === "" || model.security === "--") {
                                    wifiConnecting = true
                                    wifiPopupState = "connecting"
                                    GameManager.connectToWifi(model.ssid, "")
                                } else {
                                    settingsVirtualKeyboard.placeholderText = "Enter password for " + model.ssid + "..."
                                    settingsVirtualKeyboard.open("", true)
                                }
                            }
                        }

                        Behavior on color { ColorAnimation { duration: 120 } }
                        Behavior on border.color { ColorAnimation { duration: 120 } }
                    }
                }

                // ── Connecting state ──
                ColumnLayout {
                    visible: wifiPopupState === "connecting"
                    Layout.fillWidth: true
                    Layout.preferredHeight: 100
                    spacing: 16
                    Layout.alignment: Qt.AlignHCenter

                    Item {
                        Layout.preferredWidth: 40
                        Layout.preferredHeight: 40
                        Layout.alignment: Qt.AlignHCenter

                        Rectangle {
                            anchors.centerIn: parent
                            width: 38
                            height: 38
                            radius: 19
                            color: "transparent"
                            border.width: 3
                            border.color: Qt.rgba(1, 1, 1, 0.08)

                            Rectangle {
                                width: 38
                                height: 38
                                radius: 19
                                color: "transparent"
                                border.width: 3
                                border.color: "transparent"

                                Rectangle {
                                    width: 14
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
                                    running: wifiPopupState === "connecting"
                                }
                            }
                        }
                    }

                    Text {
                        text: "Connecting to " + selectedSsid + "..."
                        font.pixelSize: ThemeManager.getFontSize("medium")
                        font.family: ThemeManager.getFont("body")
                        color: ThemeManager.getColor("textPrimary")
                        Layout.alignment: Qt.AlignHCenter

                        SequentialAnimation on opacity {
                            running: wifiPopupState === "connecting"
                            loops: Animation.Infinite
                            NumberAnimation { to: 0.4; duration: 600 }
                            NumberAnimation { to: 1.0; duration: 600 }
                        }
                    }
                }

                // ── Done state (success or error) ──
                ColumnLayout {
                    visible: wifiPopupState === "done"
                    Layout.fillWidth: true
                    spacing: 16
                    Layout.alignment: Qt.AlignHCenter

                    Text {
                        text: wifiResultSuccess ? "Connected!" : "Connection Failed"
                        font.pixelSize: ThemeManager.getFontSize("large")
                        font.family: ThemeManager.getFont("heading")
                        font.bold: true
                        color: wifiResultSuccess
                               ? ThemeManager.getColor("accent")
                               : "#ff6b6b"
                        Layout.alignment: Qt.AlignHCenter
                    }

                    Text {
                        text: wifiResultMessage
                        font.pixelSize: ThemeManager.getFontSize("small")
                        font.family: ThemeManager.getFont("body")
                        color: ThemeManager.getColor("textSecondary")
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                    }

                    Rectangle {
                        Layout.preferredWidth: dismissLabel.width + 48
                        Layout.preferredHeight: 40
                        Layout.alignment: Qt.AlignHCenter
                        Layout.topMargin: 4
                        radius: 8
                        color: dismissArea.containsMouse
                               ? ThemeManager.getColor("hover")
                               : ThemeManager.getColor("primary")

                        Text {
                            id: dismissLabel
                            anchors.centerIn: parent
                            text: "OK"
                            font.pixelSize: ThemeManager.getFontSize("small")
                            font.family: ThemeManager.getFont("body")
                            font.bold: true
                            color: "white"
                        }

                        MouseArea {
                            id: dismissArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: closeWifiPopup()
                        }
                    }
                }
            }
        }
    }

    // ─── Virtual Keyboard for WiFi password ───
    VirtualKeyboard {
        id: settingsVirtualKeyboard
        anchors.fill: parent
        z: 1000

        onAccepted: function(text) {
            if (text.length > 0 && !wifiConnecting && selectedSsid !== "") {
                wifiConnecting = true
                wifiPopupState = "connecting"
                GameManager.connectToWifi(selectedSsid, text)
            }
            settingsRoot.forceActiveFocus()
        }
        onCancelled: {
            // Go back to the network list
            if (wifiPopupVisible) wifiPopupState = "list"
            settingsRoot.forceActiveFocus()
        }
    }
}
