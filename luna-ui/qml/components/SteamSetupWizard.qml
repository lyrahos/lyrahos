import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtWebEngine

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
    property bool apiKeyScraping: false
    property string apiKeyScrapeErrorMsg: ""
    property bool apiKeyBrowserOpen: false
    property string detectedApiKey: ""
    property bool showManualInput: false

    // Sub-states for step 3 (SteamCMD)
    property string steamCmdPromptType: ""  // "password" or "steamguard"
    property bool steamCmdWaiting: false
    property bool steamCmdAwaitingGuard: false  // true after password submitted, before guard prompt
    property bool steamCmdVerifyingGuard: false // true after guard code submitted, waiting for result
    property string steamCmdError: ""

    // Click blocker
    MouseArea { anchors.fill: parent; onClicked: {} }

    // Signal connections
    Connections {
        target: GameManager

        // Legacy signal handlers (kept for compatibility but no longer
        // used — the embedded WebEngineView handles API key detection
        // directly via JavaScript polling).
        function onApiKeyScraped(key) {
            wizard.apiKeyScraping = false
            wizard.detectedApiKey = key
            apiKeyConfirmOverlay.overlayKey = key
            apiKeyConfirmOverlay.visible = true
        }

        function onApiKeyScrapeError(error) {
            wizard.apiKeyScraping = false
            wizard.apiKeyScrapeErrorMsg = error
            wizard.showManualInput = true
        }

        function onSteamCmdSetupCredentialNeeded(promptType) {
            wizard.steamCmdPromptType = promptType
            wizard.steamCmdWaiting = false
            wizard.steamCmdAwaitingGuard = false
            wizard.steamCmdVerifyingGuard = false
            wizard.steamCmdError = ""
            setupCredInput.text = ""
            if (promptType === "password") {
                setupCredInput.forceActiveFocus()
            }
        }

        function onSteamCmdSetupLoginSuccess() {
            wizard.steamCmdWaiting = false
            wizard.steamCmdAwaitingGuard = false
            wizard.steamCmdVerifyingGuard = false
            wizard.steamCmdError = ""
            wizard.currentStep = 4
            GameManager.scanAllStores()
            GameManager.fetchSteamOwnedGames()
        }

        function onSteamCmdSetupLoginError(error) {
            wizard.steamCmdWaiting = false
            wizard.steamCmdAwaitingGuard = false
            wizard.steamCmdVerifyingGuard = false
            wizard.steamCmdError = error
        }
    }

    function reset() {
        currentStep = 0
        apiKeyScraping = false
        apiKeyScrapeErrorMsg = ""
        apiKeyBrowserOpen = false
        detectedApiKey = ""
        showManualInput = false
        steamCmdPromptType = ""
        steamCmdWaiting = false
        steamCmdAwaitingGuard = false
        steamCmdError = ""
        setupCredInput.text = ""
        manualKeyInput.text = ""
    }

    function open() {
        reset()
        // Smart step skipping: jump to the first incomplete step.
        // This prevents forcing the user through already-completed steps
        // (e.g., re-entering an API key they already saved).
        if (GameManager.isSteamAvailable()) {
            // Start downloading SteamCMD in the background so it's ready
            // by the time the user reaches step 3.
            if (!GameManager.isSteamCmdAvailable()) {
                GameManager.downloadSteamCmd()
            }
            if (GameManager.hasSteamApiKey() && GameManager.isSteamCmdAvailable()) {
                // Everything is done — show the "done" step
                currentStep = 4
            } else if (GameManager.hasSteamApiKey()) {
                // API key saved, just need SteamCMD
                currentStep = 3
            } else {
                // Need API key
                currentStep = 2
            }
        }
        // If Steam is not available (not logged in), stay at step 0
        visible = true
    }

    function close() {
        GameManager.closeApiKeyBrowser()
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
                                // IMPORTANT: Only set the marker if no real key exists.
                                // If the user already has an API key (re-running setup
                                // for a different reason), don't overwrite it.
                                if (!GameManager.hasSteamApiKey()) {
                                    GameManager.setSteamApiKey("__setup_pending__")
                                }
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
                    visible: !wizard.apiKeyBrowserOpen && wizard.detectedApiKey === "" && !wizard.showManualInput
                    text: "Luna needs a free Steam API key to detect all your games (including uninstalled ones).\n\nClick below to open the Steam API key page. You may need to log in to Steam first. Once the page shows your key, Luna will detect it automatically."
                    font.pixelSize: ThemeManager.getFontSize("medium")
                    font.family: ThemeManager.getFont("body")
                    color: ThemeManager.getColor("textSecondary")
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                }

                // "Get API Key" button — opens the embedded browser
                Rectangle {
                    visible: !wizard.apiKeyBrowserOpen && wizard.detectedApiKey === "" && !wizard.showManualInput
                    Layout.preferredWidth: openBrowserLabel.width + 40
                    Layout.preferredHeight: 44
                    radius: 8
                    color: ThemeManager.getColor("primary")

                    Text {
                        id: openBrowserLabel
                        anchors.centerIn: parent
                        text: "Get API Key"
                        font.pixelSize: ThemeManager.getFontSize("medium")
                        font.family: ThemeManager.getFont("body")
                        font.bold: true
                        color: "white"
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            wizard.apiKeyBrowserOpen = true
                            apiKeyWebView.url = "https://steamcommunity.com/dev/apikey"
                        }
                    }
                }

                // ── Key detected! Confirmation ──
                Rectangle {
                    visible: wizard.detectedApiKey !== "" && !wizard.showManualInput
                    Layout.fillWidth: true
                    Layout.preferredHeight: apiKeyConfirmCol.height + 32
                    radius: 12
                    color: Qt.rgba(ThemeManager.getColor("accent").r,
                                   ThemeManager.getColor("accent").g,
                                   ThemeManager.getColor("accent").b, 0.1)
                    border.color: ThemeManager.getColor("accent")
                    border.width: 1

                    ColumnLayout {
                        id: apiKeyConfirmCol
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 16
                        spacing: 12

                        Text {
                            text: "Found your API key!"
                            font.pixelSize: ThemeManager.getFontSize("medium")
                            font.family: ThemeManager.getFont("body")
                            font.bold: true
                            color: ThemeManager.getColor("accent")
                        }

                        Text {
                            text: "Is this your API key?"
                            font.pixelSize: ThemeManager.getFontSize("small")
                            font.family: ThemeManager.getFont("body")
                            color: ThemeManager.getColor("textPrimary")
                        }

                        // Show masked key
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 40
                            radius: 8
                            color: ThemeManager.getColor("hover")

                            Text {
                                anchors.centerIn: parent
                                text: {
                                    var k = wizard.detectedApiKey
                                    if (k.length > 12)
                                        return k.substring(0, 8) + "..." + k.substring(k.length - 4)
                                    return k
                                }
                                font.pixelSize: ThemeManager.getFontSize("medium")
                                font.family: "monospace"
                                color: ThemeManager.getColor("accent")
                            }
                        }

                        RowLayout {
                            spacing: 10

                            Rectangle {
                                Layout.preferredWidth: yesKeyLabel.width + 32
                                Layout.preferredHeight: 40
                                radius: 8
                                color: ThemeManager.getColor("accent")

                                Text {
                                    id: yesKeyLabel
                                    anchors.centerIn: parent
                                    text: "Yes, use this key"
                                    font.pixelSize: ThemeManager.getFontSize("small")
                                    font.family: ThemeManager.getFont("body")
                                    font.bold: true
                                    color: "white"
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        apiKeyWebView.url = "about:blank"
                                        wizard.apiKeyBrowserOpen = false
                                        GameManager.setSteamApiKey(wizard.detectedApiKey)
                                        wizard.currentStep = 3
                                    }
                                }
                            }

                            Rectangle {
                                Layout.preferredWidth: noKeyLabel.width + 32
                                Layout.preferredHeight: 40
                                radius: 8
                                color: "transparent"
                                border.color: Qt.rgba(1, 1, 1, 0.15)
                                border.width: 1

                                Text {
                                    id: noKeyLabel
                                    anchors.centerIn: parent
                                    text: "No, enter manually"
                                    font.pixelSize: ThemeManager.getFontSize("small")
                                    font.family: ThemeManager.getFont("body")
                                    color: ThemeManager.getColor("textSecondary")
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        wizard.detectedApiKey = ""
                                        wizard.showManualInput = true
                                        manualKeyInput.forceActiveFocus()
                                    }
                                }
                            }
                        }
                    }
                }

                // ── Manual fallback (shown after scrape fails or user clicks "No") ──
                ColumnLayout {
                    visible: wizard.showManualInput && wizard.detectedApiKey === ""
                    spacing: 10
                    Layout.fillWidth: true

                    // Error message from auto-detection
                    Text {
                        visible: wizard.apiKeyScrapeErrorMsg !== ""
                        text: wizard.apiKeyScrapeErrorMsg
                        font.pixelSize: ThemeManager.getFontSize("small")
                        font.family: ThemeManager.getFont("body")
                        color: "#ff6b6b"
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }

                    Text {
                        text: "Visit steamcommunity.com/dev/apikey in a browser,\ncopy your key, and paste it below:"
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
                                    var key = text.trim()
                                    GameManager.setSteamApiKey(key)
                                    wizard.currentStep = 3
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

                    // Save button
                    Rectangle {
                        visible: manualKeyInput.text.trim().length >= 20
                        Layout.preferredWidth: saveManualKeyLabel.width + 32
                        Layout.preferredHeight: 40
                        radius: 8
                        color: ThemeManager.getColor("accent")

                        Text {
                            id: saveManualKeyLabel
                            anchors.centerIn: parent
                            text: "Save Key"
                            font.pixelSize: ThemeManager.getFontSize("small")
                            font.family: ThemeManager.getFont("body")
                            font.bold: true
                            color: "white"
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                var key = manualKeyInput.text.trim()
                                GameManager.setSteamApiKey(key)
                                wizard.currentStep = 3
                            }
                        }
                    }

                    // Retry auto-detect button
                    Rectangle {
                        Layout.preferredWidth: retryDetectLabel.width + 32
                        Layout.preferredHeight: 36
                        radius: 8
                        color: "transparent"
                        border.color: Qt.rgba(1, 1, 1, 0.12)
                        border.width: 1

                        Text {
                            id: retryDetectLabel
                            anchors.centerIn: parent
                            text: "Retry auto-detect"
                            font.pixelSize: ThemeManager.getFontSize("small")
                            font.family: ThemeManager.getFont("body")
                            color: ThemeManager.getColor("textSecondary")
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                wizard.showManualInput = false
                                wizard.apiKeyScrapeErrorMsg = ""
                                wizard.apiKeyBrowserOpen = true
                                apiKeyWebView.url = "https://steamcommunity.com/dev/apikey"
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

                    // Skip button
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

                // Waiting spinner text (only shown before password prompt, not after)
                Text {
                    visible: wizard.steamCmdWaiting && wizard.steamCmdPromptType === "" && !wizard.steamCmdAwaitingGuard && !wizard.steamCmdVerifyingGuard
                    text: "Starting SteamCMD..."
                    font.pixelSize: ThemeManager.getFontSize("medium")
                    font.family: ThemeManager.getFont("body")
                    color: ThemeManager.getColor("primary")

                    SequentialAnimation on opacity {
                        running: wizard.steamCmdWaiting && !wizard.steamCmdVerifyingGuard
                        loops: Animation.Infinite
                        NumberAnimation { to: 0.4; duration: 800 }
                        NumberAnimation { to: 1.0; duration: 800 }
                    }
                }

                // Post-guard-code: logging in message
                Text {
                    visible: wizard.steamCmdVerifyingGuard
                    text: "Logging in..."
                    font.pixelSize: ThemeManager.getFontSize("medium")
                    font.family: ThemeManager.getFont("body")
                    color: ThemeManager.getColor("primary")

                    SequentialAnimation on opacity {
                        running: wizard.steamCmdVerifyingGuard
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
                                        // After password, show "approve on your phone" message
                                        wizard.steamCmdPromptType = ""
                                        wizard.steamCmdAwaitingGuard = true
                                        wizard.steamCmdWaiting = false
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
                                    // After password, show "approve on your phone" message
                                    wizard.steamCmdPromptType = ""
                                    wizard.steamCmdAwaitingGuard = true
                                    wizard.steamCmdWaiting = false
                                }
                            }
                        }
                    }
                }

                // ── Post-password: approve on your phone message ──
                ColumnLayout {
                    visible: wizard.steamCmdAwaitingGuard && wizard.steamCmdPromptType === ""
                    spacing: 10
                    Layout.fillWidth: true

                    Text {
                        text: "Approve the login in your Steam app"
                        font.pixelSize: ThemeManager.getFontSize("medium")
                        font.family: ThemeManager.getFont("body")
                        font.bold: true
                        color: ThemeManager.getColor("textPrimary")
                    }

                    Text {
                        text: "Password sent. Waiting for SteamCMD..."
                        font.pixelSize: ThemeManager.getFontSize("small")
                        font.family: ThemeManager.getFont("body")
                        color: ThemeManager.getColor("textSecondary")
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }

                    Text {
                        text: "Waiting..."
                        font.pixelSize: ThemeManager.getFontSize("medium")
                        font.family: ThemeManager.getFont("body")
                        color: ThemeManager.getColor("primary")

                        SequentialAnimation on opacity {
                            running: wizard.steamCmdAwaitingGuard
                            loops: Animation.Infinite
                            NumberAnimation { to: 0.4; duration: 1000 }
                            NumberAnimation { to: 1.0; duration: 1000 }
                        }
                    }
                }

                // Steam Guard / Authenticator prompt
                ColumnLayout {
                    visible: wizard.steamCmdPromptType === "steamguard"
                    spacing: 10
                    Layout.fillWidth: true

                    Text {
                        text: "Enter your Steam Guard code"
                        font.pixelSize: ThemeManager.getFontSize("medium")
                        font.family: ThemeManager.getFont("body")
                        font.bold: true
                        color: ThemeManager.getColor("textPrimary")
                    }

                    Text {
                        text: "SteamCMD needs a code to finish logging in.\n\nSteam Mobile App: open the app and look for the 5-character code in the Steam Guard section.\n\nEmail-based Steam Guard: check your email for the 5-character code from Steam."
                        font.pixelSize: ThemeManager.getFontSize("small")
                        font.family: ThemeManager.getFont("body")
                        color: ThemeManager.getColor("textSecondary")
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }

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
                                focus: wizard.steamCmdPromptType === "steamguard"
                                onAccepted: {
                                    if (text.length > 0) {
                                        GameManager.provideSteamCmdSetupCredential(text)
                                        text = ""
                                        wizard.steamCmdPromptType = ""
                                        wizard.steamCmdWaiting = true
                                        wizard.steamCmdVerifyingGuard = true
                                    }
                                }
                            }

                            Text {
                                anchors.fill: parent
                                anchors.margins: 12
                                verticalAlignment: Text.AlignVCenter
                                visible: guardCodeInput.text === "" && !guardCodeInput.activeFocus
                                text: "Enter code..."
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
                                        wizard.steamCmdVerifyingGuard = true
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
                                GameManager.restartSteam()
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

    // ── Embedded browser for Steam API key page ──
    // Loads the Steam API key page inside Luna UI. A JS timer polls
    // the DOM for the 32-char hex key. When found, the confirmation
    // overlay appears directly on top — no window management needed.
    Rectangle {
        id: apiKeyBrowser
        visible: wizard.apiKeyBrowserOpen && wizard.currentStep === 2
        anchors.fill: parent
        z: 250
        color: ThemeManager.getColor("background")

        // Header bar
        Rectangle {
            id: browserHeader
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: 50
            color: ThemeManager.getColor("surface")
            z: 1

            Text {
                anchors.centerIn: parent
                text: "Steam API Key"
                font.pixelSize: ThemeManager.getFontSize("medium")
                font.bold: true
                font.family: ThemeManager.getFont("heading")
                color: ThemeManager.getColor("textPrimary")
            }

            // "Enter Manually" button
            Rectangle {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.rightMargin: 14
                width: manualEntryLabel.width + 28
                height: 34
                radius: 8
                color: "transparent"
                border.color: Qt.rgba(1, 1, 1, 0.15)
                border.width: 1

                Text {
                    id: manualEntryLabel
                    anchors.centerIn: parent
                    text: "Enter Manually"
                    font.pixelSize: ThemeManager.getFontSize("small")
                    font.family: ThemeManager.getFont("body")
                    color: ThemeManager.getColor("textSecondary")
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        wizard.apiKeyBrowserOpen = false
                        apiKeyPollTimer.stop()
                        apiKeyWebView.url = "about:blank"
                        wizard.showManualInput = true
                    }
                }
            }
        }

        WebEngineView {
            id: apiKeyWebView
            anchors.top: browserHeader.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            url: "about:blank"

            onLoadingChanged: function(loadRequest) {
                if (loadRequest.status === WebEngineView.LoadSucceededStatus) {
                    apiKeyPollTimer.start()
                }
            }
        }

        // Poll the page for a 32-char hex API key every 2 seconds
        Timer {
            id: apiKeyPollTimer
            interval: 2000
            repeat: true
            onTriggered: {
                apiKeyWebView.runJavaScript(
                    "(function() {" +
                    "  var text = document.body.innerText || '';" +
                    "  var m = text.match(/Key[:\\s]+([A-Fa-f0-9]{32})/);" +
                    "  if (m) return m[1].toUpperCase();" +
                    "  m = text.match(/([A-Fa-f0-9]{32})/);" +
                    "  if (m) return m[1].toUpperCase();" +
                    "  return null;" +
                    "})()",
                    function(result) {
                        if (result && result.length === 32) {
                            apiKeyPollTimer.stop()
                            apiKeyConfirmOverlay.overlayKey = result
                            apiKeyConfirmOverlay.visible = true
                        }
                    }
                )
            }
        }
    }

    // ── API Key confirmation overlay ──
    // Appears on top of the embedded browser when a key is detected.
    // The browser stays visible behind the semi-transparent backdrop.
    Rectangle {
        id: apiKeyConfirmOverlay
        visible: false
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.85)
        z: 300

        property string overlayKey: ""

        MouseArea { anchors.fill: parent; onClicked: {} }

        Rectangle {
            anchors.centerIn: parent
            width: 420
            height: 260
            radius: 16
            color: ThemeManager.getColor("surface")
            border.color: ThemeManager.getColor("accent")
            border.width: 2

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 24
                spacing: 14

                Text {
                    text: "Found your API key!"
                    font.pixelSize: 20
                    font.bold: true
                    color: ThemeManager.getColor("accent")
                }

                Text {
                    text: "Is this your Steam API key?"
                    font.pixelSize: 14
                    color: ThemeManager.getColor("textPrimary")
                }

                // Show masked key
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 40
                    radius: 8
                    color: ThemeManager.getColor("hover")

                    Text {
                        anchors.centerIn: parent
                        text: {
                            var k = apiKeyConfirmOverlay.overlayKey
                            if (k.length > 12)
                                return k.substring(0, 8) + "..." + k.substring(k.length - 4)
                            return k
                        }
                        font.pixelSize: 15
                        font.family: "monospace"
                        color: ThemeManager.getColor("accent")
                    }
                }

                Item { Layout.fillHeight: true }

                RowLayout {
                    spacing: 10
                    Layout.fillWidth: true

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 44
                        radius: 8
                        color: ThemeManager.getColor("accent")

                        Text {
                            anchors.centerIn: parent
                            text: "Yes, use this key"
                            font.pixelSize: 14
                            font.bold: true
                            color: "white"
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                apiKeyConfirmOverlay.visible = false
                                apiKeyWebView.url = "about:blank"
                                GameManager.setSteamApiKey(apiKeyConfirmOverlay.overlayKey)
                                wizard.detectedApiKey = apiKeyConfirmOverlay.overlayKey
                                wizard.apiKeyBrowserOpen = false
                                wizard.currentStep = 3
                            }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 44
                        radius: 8
                        color: "transparent"
                        border.color: Qt.rgba(1, 1, 1, 0.15)
                        border.width: 1

                        Text {
                            anchors.centerIn: parent
                            text: "No"
                            font.pixelSize: 14
                            color: ThemeManager.getColor("textSecondary")
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                apiKeyConfirmOverlay.visible = false
                                apiKeyWebView.url = "about:blank"
                                wizard.detectedApiKey = ""
                                wizard.apiKeyBrowserOpen = false
                                wizard.showManualInput = true
                            }
                        }
                    }
                }
            }
        }
    }
}
