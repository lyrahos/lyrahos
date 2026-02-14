import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// Full-screen modal wizard for first-time Steam setup.
// Step 1: Intro explaining the multi-login process
// Step 2: Steam client login → API key retrieval via browser
// Step 3: SteamCMD login with password + authenticator approval
Rectangle {
    id: wizard
    anchors.fill: parent
    color: Qt.rgba(0, 0, 0, 0.8)
    z: 200
    visible: false

    property int currentStep: 0  // 0=intro, 1=steam-login, 2=api-key, 3=steamcmd-login, 4=done

    // Sub-states for step 2 (API key)
    property bool apiKeyBrowserOpen: false
    property string detectedApiKey: ""
    property bool showManualInput: false

    // Sub-states for step 3 (SteamCMD)
    property string steamCmdPromptType: ""  // "password" or "steamguard"
    property bool steamCmdWaiting: false
    property string steamCmdError: ""

    // Click blocker
    MouseArea { anchors.fill: parent; onClicked: {} }

    // Signal connections
    Connections {
        target: GameManager

        function onApiKeyScrapeError(error) {
            // Scrape can't access browser session — fall back to clipboard/manual
            wizard.showManualInput = true
        }

        function onSteamCmdSetupCredentialNeeded(promptType) {
            wizard.steamCmdPromptType = promptType
            wizard.steamCmdWaiting = false
            wizard.steamCmdError = ""
            setupCredInput.text = ""
            setupCredInput.forceActiveFocus()
        }

        function onSteamCmdSetupLoginSuccess() {
            wizard.steamCmdWaiting = false
            wizard.steamCmdError = ""
            wizard.currentStep = 4
        }

        function onSteamCmdSetupLoginError(error) {
            wizard.steamCmdWaiting = false
            wizard.steamCmdError = error
        }
    }

    // Clipboard polling timer for API key detection
    Timer {
        id: clipboardPoller
        interval: 1500
        repeat: true
        running: wizard.visible && wizard.currentStep === 2 && wizard.apiKeyBrowserOpen
        onTriggered: {
            // Check if an API key file appeared (user might have pasted via another path)
            if (GameManager.hasSteamApiKey()) {
                wizard.detectedApiKey = GameManager.getSteamApiKey()
                clipboardPoller.stop()
            }
        }
    }

    function reset() {
        currentStep = 0
        apiKeyBrowserOpen = false
        detectedApiKey = ""
        showManualInput = false
        steamCmdPromptType = ""
        steamCmdWaiting = false
        steamCmdError = ""
        setupCredInput.text = ""
        manualKeyInput.text = ""
    }

    function open() {
        reset()
        // If Steam is already available (logged in), skip to step 2
        if (GameManager.isSteamAvailable()) {
            // If API key also already set, skip to step 3
            if (GameManager.hasSteamApiKey()) {
                currentStep = 3
            } else {
                currentStep = 2
            }
        }
        visible = true
    }

    function close() {
        GameManager.cancelSteamCmdSetup()
        visible = false
    }

    // ── Modal card ──
    Rectangle {
        anchors.centerIn: parent
        width: 520
        height: wizardContent.height + 64
        radius: 20
        color: ThemeManager.getColor("surface")

        // Subtle top accent bar
        Rectangle {
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: 4
            radius: 20
            color: ThemeManager.getColor("primary")

            Rectangle {
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                height: 2
                color: ThemeManager.getColor("primary")
            }
        }

        ColumnLayout {
            id: wizardContent
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 32
            anchors.topMargin: 28
            spacing: 16

            // ── Step indicator ──
            RowLayout {
                Layout.fillWidth: true
                Layout.bottomMargin: 8
                spacing: 8

                Repeater {
                    model: ["Login", "API Key", "SteamCMD"]

                    RowLayout {
                        spacing: 8

                        Rectangle {
                            width: 28
                            height: 28
                            radius: 14
                            color: {
                                var stepNum = index + 1
                                if (wizard.currentStep === 0) return ThemeManager.getColor("hover")
                                if (wizard.currentStep >= stepNum + 1 || wizard.currentStep === 4)
                                    return ThemeManager.getColor("accent")
                                if ((wizard.currentStep === 1 && stepNum === 1) ||
                                    (wizard.currentStep === 2 && stepNum === 2) ||
                                    (wizard.currentStep === 3 && stepNum === 3))
                                    return ThemeManager.getColor("primary")
                                return ThemeManager.getColor("hover")
                            }

                            Text {
                                anchors.centerIn: parent
                                text: {
                                    var stepNum = index + 1
                                    if (wizard.currentStep >= stepNum + 1 || wizard.currentStep === 4)
                                        return "\u2713"
                                    return stepNum.toString()
                                }
                                font.pixelSize: 13
                                font.bold: true
                                color: "white"
                            }

                            Behavior on color { ColorAnimation { duration: 200 } }
                        }

                        Text {
                            text: modelData
                            font.pixelSize: ThemeManager.getFontSize("small")
                            font.family: ThemeManager.getFont("body")
                            font.bold: {
                                return (wizard.currentStep === 1 && index === 0) ||
                                       (wizard.currentStep === 2 && index === 1) ||
                                       (wizard.currentStep === 3 && index === 2)
                            }
                            color: ThemeManager.getColor("textSecondary")
                        }

                        // Spacer line between steps
                        Rectangle {
                            visible: index < 2
                            Layout.preferredWidth: 24
                            Layout.preferredHeight: 2
                            color: {
                                var stepNum = index + 1
                                if (wizard.currentStep >= stepNum + 1 || wizard.currentStep === 4)
                                    return ThemeManager.getColor("accent")
                                return Qt.rgba(1, 1, 1, 0.1)
                            }
                            Behavior on color { ColorAnimation { duration: 200 } }
                        }
                    }
                }

                Item { Layout.fillWidth: true }
            }

            // ═══════════════════════════════════════
            // STEP 0: Intro
            // ═══════════════════════════════════════
            ColumnLayout {
                visible: wizard.currentStep === 0
                spacing: 12
                Layout.fillWidth: true

                Text {
                    text: "Steam Setup"
                    font.pixelSize: ThemeManager.getFontSize("xlarge")
                    font.family: ThemeManager.getFont("heading")
                    font.bold: true
                    color: ThemeManager.getColor("textPrimary")
                }

                Text {
                    text: "We'll walk you through connecting Steam to Luna. This is a one-time setup — you won't need to do it again."
                    font.pixelSize: ThemeManager.getFontSize("medium")
                    font.family: ThemeManager.getFont("body")
                    color: ThemeManager.getColor("textSecondary")
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                }

                Item { height: 4 }

                // Step previews
                Repeater {
                    model: [
                        { num: "1", title: "Log in to Steam", desc: "Steam will open so you can sign in. It'll close when done." },
                        { num: "2", title: "Get your API key", desc: "A browser opens to grab a free key so Luna can see your game library." },
                        { num: "3", title: "Connect SteamCMD", desc: "Enter your password once so games can download in the background." }
                    ]

                    RowLayout {
                        spacing: 12
                        Layout.fillWidth: true

                        Rectangle {
                            Layout.preferredWidth: 32
                            Layout.preferredHeight: 32
                            radius: 16
                            color: ThemeManager.getColor("hover")

                            Text {
                                anchors.centerIn: parent
                                text: modelData.num
                                font.pixelSize: 14
                                font.bold: true
                                color: ThemeManager.getColor("primary")
                            }
                        }

                        ColumnLayout {
                            spacing: 2
                            Layout.fillWidth: true

                            Text {
                                text: modelData.title
                                font.pixelSize: ThemeManager.getFontSize("medium")
                                font.family: ThemeManager.getFont("body")
                                font.bold: true
                                color: ThemeManager.getColor("textPrimary")
                            }
                            Text {
                                text: modelData.desc
                                font.pixelSize: ThemeManager.getFontSize("small")
                                font.family: ThemeManager.getFont("body")
                                color: ThemeManager.getColor("textSecondary")
                                wrapMode: Text.WordWrap
                                Layout.fillWidth: true
                            }
                        }
                    }
                }

                Item { height: 8 }

                // Buttons
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    Item { Layout.fillWidth: true }

                    Rectangle {
                        Layout.preferredWidth: cancelIntroLabel.width + 32
                        Layout.preferredHeight: 44
                        radius: 8
                        color: "transparent"
                        border.color: Qt.rgba(1, 1, 1, 0.15)
                        border.width: 1

                        Text {
                            id: cancelIntroLabel
                            anchors.centerIn: parent
                            text: "Cancel"
                            font.pixelSize: ThemeManager.getFontSize("small")
                            font.family: ThemeManager.getFont("body")
                            color: ThemeManager.getColor("textSecondary")
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: wizard.close()
                        }
                    }

                    Rectangle {
                        Layout.preferredWidth: nextIntroLabel.width + 40
                        Layout.preferredHeight: 44
                        radius: 8
                        color: ThemeManager.getColor("primary")

                        Text {
                            id: nextIntroLabel
                            anchors.centerIn: parent
                            text: "Next"
                            font.pixelSize: ThemeManager.getFontSize("medium")
                            font.family: ThemeManager.getFont("body")
                            font.bold: true
                            color: "white"
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                wizard.currentStep = 1
                            }
                        }
                    }
                }
            }

            // ═══════════════════════════════════════
            // STEP 1: Steam Client Login
            // ═══════════════════════════════════════
            ColumnLayout {
                visible: wizard.currentStep === 1
                spacing: 12
                Layout.fillWidth: true

                Text {
                    text: "Log in to Steam"
                    font.pixelSize: ThemeManager.getFontSize("xlarge")
                    font.family: ThemeManager.getFont("heading")
                    font.bold: true
                    color: ThemeManager.getColor("textPrimary")
                }

                Text {
                    text: "Steam will open in full screen. Log in with your account, then close Steam to return here.\n\nLuna will restart automatically when Steam closes."
                    font.pixelSize: ThemeManager.getFontSize("medium")
                    font.family: ThemeManager.getFont("body")
                    color: ThemeManager.getColor("textSecondary")
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                }

                Item { height: 8 }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    Item { Layout.fillWidth: true }

                    Rectangle {
                        Layout.preferredWidth: backStep1Label.width + 32
                        Layout.preferredHeight: 44
                        radius: 8
                        color: "transparent"
                        border.color: Qt.rgba(1, 1, 1, 0.15)
                        border.width: 1

                        Text {
                            id: backStep1Label
                            anchors.centerIn: parent
                            text: "Back"
                            font.pixelSize: ThemeManager.getFontSize("small")
                            font.family: ThemeManager.getFont("body")
                            color: ThemeManager.getColor("textSecondary")
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: wizard.currentStep = 0
                        }
                    }

                    Rectangle {
                        Layout.preferredWidth: launchSteamLabel.width + 40
                        Layout.preferredHeight: 44
                        radius: 8
                        color: "#1b2838"

                        Text {
                            id: launchSteamLabel
                            anchors.centerIn: parent
                            text: "Open Steam"
                            font.pixelSize: ThemeManager.getFontSize("medium")
                            font.family: ThemeManager.getFont("body")
                            font.bold: true
                            color: "#66c0f4"
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                // This quits luna-ui; luna-session launches Steam,
                                // then restarts luna-ui. On restart, the wizard
                                // should auto-advance to step 2 if Steam is available.
                                // We save a flag so the wizard knows to reopen.
                                GameManager.setSteamApiKey("__setup_pending__")
                                GameManager.launchSteamLogin()
                            }
                        }
                    }
                }
            }

            // ═══════════════════════════════════════
            // STEP 2: API Key
            // ═══════════════════════════════════════
            ColumnLayout {
                visible: wizard.currentStep === 2
                spacing: 12
                Layout.fillWidth: true

                Text {
                    text: "Get Your Steam API Key"
                    font.pixelSize: ThemeManager.getFontSize("xlarge")
                    font.family: ThemeManager.getFont("heading")
                    font.bold: true
                    color: ThemeManager.getColor("textPrimary")
                }

                Text {
                    text: "Luna needs a free Steam API key to detect all your games (including uninstalled ones).\n\nA browser will open to the Steam API key page. Register a key if you don't have one, then copy it."
                    font.pixelSize: ThemeManager.getFontSize("medium")
                    font.family: ThemeManager.getFont("body")
                    color: ThemeManager.getColor("textSecondary")
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                }

                // Open browser button
                Rectangle {
                    visible: !wizard.apiKeyBrowserOpen
                    Layout.preferredWidth: openBrowserLabel.width + 40
                    Layout.preferredHeight: 44
                    radius: 8
                    color: "#1b2838"

                    Text {
                        id: openBrowserLabel
                        anchors.centerIn: parent
                        text: "Open Browser"
                        font.pixelSize: ThemeManager.getFontSize("medium")
                        font.family: ThemeManager.getFont("body")
                        font.bold: true
                        color: "#66c0f4"
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            GameManager.openApiKeyInBrowser()
                            wizard.apiKeyBrowserOpen = true
                            wizard.showManualInput = true
                        }
                    }
                }

                // After browser is open — show paste field
                ColumnLayout {
                    visible: wizard.apiKeyBrowserOpen
                    spacing: 10
                    Layout.fillWidth: true

                    Text {
                        text: "Paste your API key below:"
                        font.pixelSize: ThemeManager.getFontSize("small")
                        font.family: ThemeManager.getFont("body")
                        color: ThemeManager.getColor("textSecondary")
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 44
                        radius: 8
                        color: ThemeManager.getColor("hover")
                        border.color: manualKeyInput.activeFocus
                                      ? ThemeManager.getColor("focus") : "transparent"
                        border.width: manualKeyInput.activeFocus ? 2 : 0

                        Behavior on border.color { ColorAnimation { duration: 150 } }

                        TextInput {
                            id: manualKeyInput
                            anchors.fill: parent
                            anchors.margins: 12
                            verticalAlignment: TextInput.AlignVCenter
                            font.pixelSize: ThemeManager.getFontSize("medium")
                            font.family: "monospace"
                            color: ThemeManager.getColor("textPrimary")
                            clip: true
                            onAccepted: {
                                if (text.trim().length >= 20) {
                                    wizard.detectedApiKey = text.trim()
                                }
                            }
                        }

                        Text {
                            anchors.fill: parent
                            anchors.margins: 12
                            verticalAlignment: Text.AlignVCenter
                            visible: manualKeyInput.text === "" && !manualKeyInput.activeFocus
                            text: "Paste your Steam API key here..."
                            font.pixelSize: ThemeManager.getFontSize("medium")
                            font.family: ThemeManager.getFont("body")
                            color: ThemeManager.getColor("textSecondary")
                        }
                    }

                    // Confirmation when key is detected/entered
                    Rectangle {
                        visible: wizard.detectedApiKey !== "" || manualKeyInput.text.trim().length >= 20
                        Layout.fillWidth: true
                        Layout.preferredHeight: 60
                        radius: 8
                        color: Qt.rgba(ThemeManager.getColor("accent").r,
                                       ThemeManager.getColor("accent").g,
                                       ThemeManager.getColor("accent").b, 0.1)
                        border.color: ThemeManager.getColor("accent")
                        border.width: 1

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: 12
                            spacing: 10

                            Text {
                                text: "Is this your API key?"
                                font.pixelSize: ThemeManager.getFontSize("small")
                                font.family: ThemeManager.getFont("body")
                                color: ThemeManager.getColor("textPrimary")
                            }

                            Text {
                                text: {
                                    var k = wizard.detectedApiKey || manualKeyInput.text.trim()
                                    if (k.length > 12)
                                        return k.substring(0, 8) + "..." + k.substring(k.length - 4)
                                    return k
                                }
                                font.pixelSize: ThemeManager.getFontSize("small")
                                font.family: "monospace"
                                color: ThemeManager.getColor("accent")
                                Layout.fillWidth: true
                            }

                            Rectangle {
                                Layout.preferredWidth: yesKeyLabel.width + 24
                                Layout.preferredHeight: 32
                                radius: 6
                                color: ThemeManager.getColor("accent")

                                Text {
                                    id: yesKeyLabel
                                    anchors.centerIn: parent
                                    text: "Yes"
                                    font.pixelSize: ThemeManager.getFontSize("small")
                                    font.family: ThemeManager.getFont("body")
                                    font.bold: true
                                    color: "white"
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        var key = wizard.detectedApiKey || manualKeyInput.text.trim()
                                        GameManager.setSteamApiKey(key)
                                        wizard.currentStep = 3
                                    }
                                }
                            }

                            Rectangle {
                                Layout.preferredWidth: noKeyLabel.width + 24
                                Layout.preferredHeight: 32
                                radius: 6
                                color: "transparent"
                                border.color: Qt.rgba(1, 1, 1, 0.15)
                                border.width: 1

                                Text {
                                    id: noKeyLabel
                                    anchors.centerIn: parent
                                    text: "No"
                                    font.pixelSize: ThemeManager.getFontSize("small")
                                    font.family: ThemeManager.getFont("body")
                                    color: ThemeManager.getColor("textSecondary")
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        wizard.detectedApiKey = ""
                                        manualKeyInput.text = ""
                                        manualKeyInput.forceActiveFocus()
                                    }
                                }
                            }
                        }
                    }
                }

                Item { height: 4 }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    Item { Layout.fillWidth: true }

                    Rectangle {
                        Layout.preferredWidth: backStep2Label.width + 32
                        Layout.preferredHeight: 44
                        radius: 8
                        color: "transparent"
                        border.color: Qt.rgba(1, 1, 1, 0.15)
                        border.width: 1

                        Text {
                            id: backStep2Label
                            anchors.centerIn: parent
                            text: "Back"
                            font.pixelSize: ThemeManager.getFontSize("small")
                            font.family: ThemeManager.getFont("body")
                            color: ThemeManager.getColor("textSecondary")
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: wizard.currentStep = 0
                        }
                    }

                    // Skip button (if user already has key or wants to skip)
                    Rectangle {
                        visible: !GameManager.hasSteamApiKey() || GameManager.getSteamApiKey() === "__setup_pending__"
                        Layout.preferredWidth: skipApiLabel.width + 32
                        Layout.preferredHeight: 44
                        radius: 8
                        color: "transparent"
                        border.color: Qt.rgba(1, 1, 1, 0.08)
                        border.width: 1

                        Text {
                            id: skipApiLabel
                            anchors.centerIn: parent
                            text: "Skip for now"
                            font.pixelSize: ThemeManager.getFontSize("small")
                            font.family: ThemeManager.getFont("body")
                            color: ThemeManager.getColor("textSecondary")
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                // Clear the pending marker if set
                                if (GameManager.getSteamApiKey() === "__setup_pending__")
                                    GameManager.setSteamApiKey("")
                                wizard.currentStep = 3
                            }
                        }
                    }
                }
            }

            // ═══════════════════════════════════════
            // STEP 3: SteamCMD Login
            // ═══════════════════════════════════════
            ColumnLayout {
                visible: wizard.currentStep === 3
                spacing: 12
                Layout.fillWidth: true

                Text {
                    text: "Connect SteamCMD"
                    font.pixelSize: ThemeManager.getFontSize("xlarge")
                    font.family: ThemeManager.getFont("heading")
                    font.bold: true
                    color: ThemeManager.getColor("textPrimary")
                }

                Text {
                    visible: wizard.steamCmdPromptType === ""
                    text: "SteamCMD lets Luna install games in the background without opening Steam.\n\nYou'll enter your password once, then approve the login on your Steam Authenticator app. After that, it's saved forever."
                    font.pixelSize: ThemeManager.getFontSize("medium")
                    font.family: ThemeManager.getFont("body")
                    color: ThemeManager.getColor("textSecondary")
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                }

                // Start login button (before any prompt)
                Rectangle {
                    visible: wizard.steamCmdPromptType === "" && !wizard.steamCmdWaiting
                    Layout.preferredWidth: startLoginLabel.width + 40
                    Layout.preferredHeight: 44
                    radius: 8
                    color: ThemeManager.getColor("primary")

                    Text {
                        id: startLoginLabel
                        anchors.centerIn: parent
                        text: "Start Login"
                        font.pixelSize: ThemeManager.getFontSize("medium")
                        font.family: ThemeManager.getFont("body")
                        font.bold: true
                        color: "white"
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            wizard.steamCmdWaiting = true
                            wizard.steamCmdError = ""
                            GameManager.loginSteamCmd()
                        }
                    }
                }

                // Waiting spinner text
                Text {
                    visible: wizard.steamCmdWaiting && wizard.steamCmdPromptType === ""
                    text: "Starting SteamCMD..."
                    font.pixelSize: ThemeManager.getFontSize("medium")
                    font.family: ThemeManager.getFont("body")
                    color: ThemeManager.getColor("primary")

                    SequentialAnimation on opacity {
                        running: wizard.steamCmdWaiting
                        loops: Animation.Infinite
                        NumberAnimation { to: 0.4; duration: 800 }
                        NumberAnimation { to: 1.0; duration: 800 }
                    }
                }

                // Password prompt
                ColumnLayout {
                    visible: wizard.steamCmdPromptType === "password"
                    spacing: 10
                    Layout.fillWidth: true

                    Text {
                        text: "Enter your Steam password:"
                        font.pixelSize: ThemeManager.getFontSize("medium")
                        font.family: ThemeManager.getFont("body")
                        font.bold: true
                        color: ThemeManager.getColor("textPrimary")
                    }

                    Text {
                        text: "Your password is sent directly to SteamCMD and is not stored by Luna."
                        font.pixelSize: ThemeManager.getFontSize("small")
                        font.family: ThemeManager.getFont("body")
                        color: ThemeManager.getColor("textSecondary")
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 44
                        radius: 8
                        color: ThemeManager.getColor("hover")
                        border.color: setupCredInput.activeFocus
                                      ? ThemeManager.getColor("focus") : "transparent"
                        border.width: setupCredInput.activeFocus ? 2 : 0
                        Behavior on border.color { ColorAnimation { duration: 150 } }

                        TextInput {
                            id: setupCredInput
                            anchors.fill: parent
                            anchors.margins: 12
                            verticalAlignment: TextInput.AlignVCenter
                            font.pixelSize: ThemeManager.getFontSize("medium")
                            font.family: ThemeManager.getFont("body")
                            color: ThemeManager.getColor("textPrimary")
                            echoMode: wizard.steamCmdPromptType === "password"
                                      ? TextInput.Password : TextInput.Normal
                            clip: true
                            onAccepted: {
                                if (text.length > 0) {
                                    GameManager.provideSteamCmdSetupCredential(text)
                                    text = ""
                                    if (wizard.steamCmdPromptType === "password") {
                                        // After password, expect Steam Guard next
                                        wizard.steamCmdPromptType = ""
                                        wizard.steamCmdWaiting = true
                                    }
                                }
                            }
                        }

                        Text {
                            anchors.fill: parent
                            anchors.margins: 12
                            verticalAlignment: Text.AlignVCenter
                            visible: setupCredInput.text === "" && !setupCredInput.activeFocus
                            text: "Enter password..."
                            font.pixelSize: ThemeManager.getFontSize("medium")
                            font.family: ThemeManager.getFont("body")
                            color: ThemeManager.getColor("textSecondary")
                        }
                    }

                    Rectangle {
                        Layout.preferredWidth: submitPassLabel.width + 32
                        Layout.preferredHeight: 40
                        radius: 8
                        color: ThemeManager.getColor("primary")

                        Text {
                            id: submitPassLabel
                            anchors.centerIn: parent
                            text: "Submit"
                            font.pixelSize: ThemeManager.getFontSize("small")
                            font.family: ThemeManager.getFont("body")
                            font.bold: true
                            color: "white"
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (setupCredInput.text.length > 0) {
                                    GameManager.provideSteamCmdSetupCredential(setupCredInput.text)
                                    setupCredInput.text = ""
                                    wizard.steamCmdPromptType = ""
                                    wizard.steamCmdWaiting = true
                                }
                            }
                        }
                    }
                }

                // Steam Guard / Authenticator prompt
                ColumnLayout {
                    visible: wizard.steamCmdPromptType === "steamguard"
                    spacing: 10
                    Layout.fillWidth: true

                    Text {
                        text: "Approve on Steam Authenticator"
                        font.pixelSize: ThemeManager.getFontSize("medium")
                        font.family: ThemeManager.getFont("body")
                        font.bold: true
                        color: ThemeManager.getColor("textPrimary")
                    }

                    Text {
                        text: "Open the Steam app on your phone and approve the login request.\n\nIf you use email-based Steam Guard instead, enter the code below:"
                        font.pixelSize: ThemeManager.getFontSize("small")
                        font.family: ThemeManager.getFont("body")
                        color: ThemeManager.getColor("textSecondary")
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }

                    // Pulsing "Waiting for approval..." text
                    Text {
                        text: "Waiting for approval..."
                        font.pixelSize: ThemeManager.getFontSize("medium")
                        font.family: ThemeManager.getFont("body")
                        color: ThemeManager.getColor("primary")

                        SequentialAnimation on opacity {
                            running: wizard.steamCmdPromptType === "steamguard"
                            loops: Animation.Infinite
                            NumberAnimation { to: 0.4; duration: 1000 }
                            NumberAnimation { to: 1.0; duration: 1000 }
                        }
                    }

                    // Email code fallback
                    RowLayout {
                        spacing: 10
                        Layout.fillWidth: true

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 44
                            radius: 8
                            color: ThemeManager.getColor("hover")
                            border.color: guardCodeInput.activeFocus
                                          ? ThemeManager.getColor("focus") : "transparent"
                            border.width: guardCodeInput.activeFocus ? 2 : 0
                            Behavior on border.color { ColorAnimation { duration: 150 } }

                            TextInput {
                                id: guardCodeInput
                                anchors.fill: parent
                                anchors.margins: 12
                                verticalAlignment: TextInput.AlignVCenter
                                font.pixelSize: ThemeManager.getFontSize("medium")
                                font.family: "monospace"
                                color: ThemeManager.getColor("textPrimary")
                                clip: true
                                onAccepted: {
                                    if (text.length > 0) {
                                        GameManager.provideSteamCmdSetupCredential(text)
                                        text = ""
                                        wizard.steamCmdPromptType = ""
                                        wizard.steamCmdWaiting = true
                                    }
                                }
                            }

                            Text {
                                anchors.fill: parent
                                anchors.margins: 12
                                verticalAlignment: Text.AlignVCenter
                                visible: guardCodeInput.text === "" && !guardCodeInput.activeFocus
                                text: "Or enter email code..."
                                font.pixelSize: ThemeManager.getFontSize("medium")
                                font.family: ThemeManager.getFont("body")
                                color: ThemeManager.getColor("textSecondary")
                            }
                        }

                        Rectangle {
                            Layout.preferredWidth: submitGuardLabel.width + 24
                            Layout.preferredHeight: 44
                            radius: 8
                            color: ThemeManager.getColor("primary")

                            Text {
                                id: submitGuardLabel
                                anchors.centerIn: parent
                                text: "Submit"
                                font.pixelSize: ThemeManager.getFontSize("small")
                                font.family: ThemeManager.getFont("body")
                                font.bold: true
                                color: "white"
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (guardCodeInput.text.length > 0) {
                                        GameManager.provideSteamCmdSetupCredential(guardCodeInput.text)
                                        guardCodeInput.text = ""
                                        wizard.steamCmdPromptType = ""
                                        wizard.steamCmdWaiting = true
                                    }
                                }
                            }
                        }
                    }
                }

                // Error message
                Text {
                    visible: wizard.steamCmdError !== ""
                    text: wizard.steamCmdError
                    font.pixelSize: ThemeManager.getFontSize("small")
                    font.family: ThemeManager.getFont("body")
                    color: "#ff6b6b"
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                }

                Item { height: 4 }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    Item { Layout.fillWidth: true }

                    Rectangle {
                        Layout.preferredWidth: backStep3Label.width + 32
                        Layout.preferredHeight: 44
                        radius: 8
                        color: "transparent"
                        border.color: Qt.rgba(1, 1, 1, 0.15)
                        border.width: 1

                        Text {
                            id: backStep3Label
                            anchors.centerIn: parent
                            text: "Back"
                            font.pixelSize: ThemeManager.getFontSize("small")
                            font.family: ThemeManager.getFont("body")
                            color: ThemeManager.getColor("textSecondary")
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                GameManager.cancelSteamCmdSetup()
                                wizard.steamCmdPromptType = ""
                                wizard.steamCmdWaiting = false
                                wizard.currentStep = 2
                            }
                        }
                    }

                    Rectangle {
                        Layout.preferredWidth: skipCmdLabel.width + 32
                        Layout.preferredHeight: 44
                        radius: 8
                        color: "transparent"
                        border.color: Qt.rgba(1, 1, 1, 0.08)
                        border.width: 1

                        Text {
                            id: skipCmdLabel
                            anchors.centerIn: parent
                            text: "Skip for now"
                            font.pixelSize: ThemeManager.getFontSize("small")
                            font.family: ThemeManager.getFont("body")
                            color: ThemeManager.getColor("textSecondary")
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                GameManager.cancelSteamCmdSetup()
                                wizard.close()
                            }
                        }
                    }
                }
            }

            // ═══════════════════════════════════════
            // STEP 4: Done!
            // ═══════════════════════════════════════
            ColumnLayout {
                visible: wizard.currentStep === 4
                spacing: 12
                Layout.fillWidth: true

                Text {
                    text: "You're All Set!"
                    font.pixelSize: ThemeManager.getFontSize("xlarge")
                    font.family: ThemeManager.getFont("heading")
                    font.bold: true
                    color: ThemeManager.getColor("accent")
                }

                Text {
                    text: "Steam is fully connected. Luna can now:\n\n  \u2022  See all your owned games\n  \u2022  Install games in the background\n  \u2022  Launch games directly\n\nYou won't need to log in again."
                    font.pixelSize: ThemeManager.getFontSize("medium")
                    font.family: ThemeManager.getFont("body")
                    color: ThemeManager.getColor("textSecondary")
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                }

                Item { height: 8 }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    Item { Layout.fillWidth: true }

                    Rectangle {
                        Layout.preferredWidth: doneLabel.width + 48
                        Layout.preferredHeight: 48
                        radius: 8
                        color: ThemeManager.getColor("primary")

                        Text {
                            id: doneLabel
                            anchors.centerIn: parent
                            text: "Start Playing"
                            font.pixelSize: ThemeManager.getFontSize("medium")
                            font.family: ThemeManager.getFont("body")
                            font.bold: true
                            color: "white"
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                GameManager.scanAllStores()
                                GameManager.fetchSteamOwnedGames()
                                wizard.close()
                            }
                        }
                    }
                }
            }
        }
    }
}
