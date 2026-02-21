import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtWebEngine

// Full-screen modal wizard for first-time Epic Games setup via Legendary.
// Step 0: Intro explaining the setup process
// Step 1: Install Legendary (auto-downloads via pip if needed)
// Step 2: Login to Epic Games (browser-based OAuth via Legendary)
// Step 3: Fetch game library
// Step 4: Done
//
// Fully controller-navigable: D-pad moves between items,
// A/Enter activates, B/Escape goes back or closes.
Rectangle {
    id: epicWizard
    anchors.fill: parent
    color: Qt.rgba(0, 0, 0, 0.85)
    z: 200
    visible: false

    signal closed()

    property int currentStep: 0
    property bool legendaryInstalling: false
    property bool loginInProgress: false
    property bool fetchingLibrary: false
    property string errorMessage: ""
    property int gamesFound: 0

    // Embedded browser for Epic login
    property bool epicBrowserOpen: false
    property bool browserInputActive: false
    property bool awaitingPolicyAcceptance: false
    property bool browserHeaderFocused: false

    // Controller focus
    property int wizFocusIndex: 0

    function open() {
        currentStep = 0
        errorMessage = ""
        gamesFound = 0
        legendaryInstalling = false
        loginInProgress = false
        fetchingLibrary = false
        epicBrowserOpen = false
        browserInputActive = false
        awaitingPolicyAcceptance = false
        browserHeaderFocused = false
        wizFocusIndex = 0
        visible = true
        epicWizard.forceActiveFocus()
    }

    function close() {
        epicBrowserOpen = false
        browserInputActive = false
        awaitingPolicyAcceptance = false
        browserHeaderFocused = false
        epicLoginWebView.url = "about:blank"
        epicPopupWebView.url = "about:blank"
        epicPopupWebView.visible = false
        visible = false
        closed()
    }

    // Helper: returns the popup view when visible, else the main login view
    function activeWebView() {
        return epicPopupWebView.visible ? epicPopupWebView : epicLoginWebView
    }

    onCurrentStepChanged: {
        wizFocusIndex = 0
        errorMessage = ""
        if (visible) epicWizard.forceActiveFocus()
    }

    onVisibleChanged: {
        if (visible) {
            wizFocusIndex = 0
            epicWizard.forceActiveFocus()
        }
    }

    function wizFocusCount() {
        switch (currentStep) {
        case 0: return 2  // Cancel, Next
        case 1:
            if (legendaryInstalling) return 1  // Cancel only
            if (GameManager.isEpicAvailable()) return 2  // Back, Next
            return 3  // Install, Back, Skip
        case 2:
            if (epicBrowserOpen) return 0  // Browser handles its own navigation
            if (loginInProgress) return 1  // Cancel only
            if (GameManager.isEpicLoggedIn()) return 2  // Back, Next
            return 3  // Login, Back, Skip
        case 3:
            if (fetchingLibrary) return 1  // just waiting
            return 2  // Back, Continue
        case 4: return 1  // Done
        }
        return 0
    }

    function isWizFocused(idx) {
        return epicWizard.visible && !epicBrowserOpen && wizFocusIndex === idx
    }

    // Signal connections
    Connections {
        target: GameManager

        function onLegendaryInstalled() {
            legendaryInstalling = false
            errorMessage = ""
            // Auto-advance to login step
            currentStep = 2
        }

        function onLegendaryInstallError(error) {
            legendaryInstalling = false
            errorMessage = error
        }

        function onEpicLoginSuccess() {
            loginInProgress = false
            errorMessage = ""
            // Auto-advance to library fetch
            currentStep = 3
            // Auto-start fetch
            fetchingLibrary = true
            GameManager.fetchEpicLibrary()
        }

        function onEpicLoginError(error) {
            loginInProgress = false
            errorMessage = error
        }

        function onEpicLibraryFetched(count) {
            fetchingLibrary = false
            gamesFound = count
            errorMessage = ""
            // Auto-advance to done
            currentStep = 4
        }

        function onEpicLibraryFetchError(error) {
            fetchingLibrary = false
            errorMessage = error
        }
    }

    // Keyboard / controller navigation
    Keys.onPressed: function(event) {
        // When awaiting privacy policy acceptance, allow keyboard shortcuts
        // to reach the Retry Login and Close buttons in the browser header.
        if (epicBrowserOpen && currentStep === 2 && awaitingPolicyAcceptance) {
            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                console.log("[epic-browser] Keyboard: Retry Login after privacy policy")
                epicWizard.browserHeaderFocused = false
                epicWizard.awaitingPolicyAcceptance = false
                epicLoginWebView.url = GameManager.getEpicLoginUrl()
                event.accepted = true
                return
            }
            if (event.key === Qt.Key_Escape) {
                epicWizard.browserHeaderFocused = false
                epicLoginWebView.url = "about:blank"
                epicPopupWebView.url = "about:blank"
                epicPopupWebView.visible = false
                epicWizard.epicBrowserOpen = false
                event.accepted = true
                return
            }
            return
        }
        // When the embedded browser is open, it handles its own navigation
        // via ControllerManager connections; skip wizard key handling.
        if (epicBrowserOpen && currentStep === 2) return
        if (epicBrowserVK.visible) return

        var count = wizFocusCount()

        switch (event.key) {
        case Qt.Key_Left:
            if (wizFocusIndex > 0) wizFocusIndex--
            event.accepted = true
            break
        case Qt.Key_Right:
            if (wizFocusIndex < count - 1) wizFocusIndex++
            event.accepted = true
            break
        case Qt.Key_Up:
            if (wizFocusIndex > 0) wizFocusIndex--
            event.accepted = true
            break
        case Qt.Key_Down:
            if (wizFocusIndex < count - 1) wizFocusIndex++
            event.accepted = true
            break
        case Qt.Key_Return:
        case Qt.Key_Enter:
            activateCurrentButton()
            event.accepted = true
            break
        case Qt.Key_Escape:
            if (currentStep === 0 || currentStep === 4) {
                close()
            } else {
                currentStep--
            }
            event.accepted = true
            break
        }
    }

    function activateCurrentButton() {
        switch (currentStep) {
        case 0:
            if (wizFocusIndex === 0) close()       // Cancel
            else if (wizFocusIndex === 1) {         // Next
                if (GameManager.isEpicAvailable()) {
                    currentStep = 2  // Skip install, go to login
                } else {
                    currentStep = 1
                }
            }
            break
        case 1:
            if (legendaryInstalling) {
                // Cancel not really possible during pip install
                break
            }
            if (GameManager.isEpicAvailable()) {
                if (wizFocusIndex === 0) currentStep = 0       // Back
                else if (wizFocusIndex === 1) currentStep = 2  // Next
            } else {
                if (wizFocusIndex === 0) {                     // Install
                    legendaryInstalling = true
                    errorMessage = ""
                    GameManager.ensureLegendary()
                }
                else if (wizFocusIndex === 1) currentStep = 0  // Back
                else if (wizFocusIndex === 2) currentStep = 2  // Skip
            }
            break
        case 2:
            if (loginInProgress || epicBrowserOpen) break
            if (GameManager.isEpicLoggedIn()) {
                if (wizFocusIndex === 0) currentStep = 1       // Back
                else if (wizFocusIndex === 1) {                // Next
                    currentStep = 3
                    fetchingLibrary = true
                    GameManager.fetchEpicLibrary()
                }
            } else {
                if (wizFocusIndex === 0) {                     // Login
                    errorMessage = ""
                    epicLoginWebView.url = GameManager.getEpicLoginUrl()
                    epicBrowserOpen = true
                }
                else if (wizFocusIndex === 1) currentStep = 1  // Back
                else if (wizFocusIndex === 2) close()          // Skip
            }
            break
        case 3:
            if (fetchingLibrary) break
            if (wizFocusIndex === 0) currentStep = 2           // Back
            else if (wizFocusIndex === 1) currentStep = 4      // Continue
            break
        case 4:
            close()
            break
        }
    }

    // Block clicks behind the wizard
    MouseArea { anchors.fill: parent; onClicked: {} }

    // ── Main content card ──
    Rectangle {
        anchors.centerIn: parent
        width: Math.min(parent.width - 80, 600)
        height: contentCol.height + 80
        radius: 20
        color: ThemeManager.getColor("surface")
        border.color: Qt.rgba(ThemeManager.getColor("primary").r,
                              ThemeManager.getColor("primary").g,
                              ThemeManager.getColor("primary").b, 0.3)
        border.width: 1

        ColumnLayout {
            id: contentCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 40
            spacing: 20

            // ── Step indicator ──
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Repeater {
                    model: 5
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 4
                        radius: 2
                        color: index <= epicWizard.currentStep
                               ? "#7c3aed" : Qt.rgba(1, 1, 1, 0.1)
                        Behavior on color { ColorAnimation { duration: 200 } }
                    }
                }
            }

            // ── Step 0: Intro ──
            ColumnLayout {
                visible: currentStep === 0
                spacing: 16

                // Epic Games icon
                Rectangle {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.preferredWidth: 72
                    Layout.preferredHeight: 72
                    radius: 16
                    color: "#2a2a2a"

                    Text {
                        anchors.centerIn: parent
                        text: "E"
                        font.pixelSize: 36
                        font.bold: true
                        color: "white"
                    }
                }

                Text {
                    text: "Epic Games Setup"
                    font.pixelSize: ThemeManager.getFontSize("xlarge")
                    font.family: ThemeManager.getFont("heading")
                    font.bold: true
                    color: ThemeManager.getColor("textPrimary")
                    Layout.alignment: Qt.AlignHCenter
                }

                Text {
                    text: "Connect your Epic Games account to see your games\n" +
                          "in Luna and install them directly."
                    font.pixelSize: ThemeManager.getFontSize("medium")
                    font.family: ThemeManager.getFont("body")
                    color: ThemeManager.getColor("textSecondary")
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                }

                Text {
                    text: "This wizard will:\n" +
                          "1. Install Legendary (open-source Epic Games client)\n" +
                          "2. Log in to your Epic Games account\n" +
                          "3. Import your game library"
                    font.pixelSize: ThemeManager.getFontSize("small")
                    font.family: ThemeManager.getFont("body")
                    color: ThemeManager.getColor("textSecondary")
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                    lineHeight: 1.4
                }

                // Buttons
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12

                    Rectangle {
                        Layout.preferredWidth: cancelIntroLabel.width + 32
                        Layout.preferredHeight: 44
                        radius: 10
                        color: "transparent"
                        border.color: isWizFocused(0) ? ThemeManager.getColor("focus")
                                                      : Qt.rgba(1, 1, 1, 0.12)
                        border.width: isWizFocused(0) ? 3 : 1

                        Text {
                            id: cancelIntroLabel
                            anchors.centerIn: parent
                            text: "Cancel"
                            font.pixelSize: ThemeManager.getFontSize("medium")
                            font.family: ThemeManager.getFont("body")
                            font.bold: true
                            color: ThemeManager.getColor("textSecondary")
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            hoverEnabled: true
                            onEntered: wizFocusIndex = 0
                            onClicked: close()
                        }

                        Behavior on border.color { ColorAnimation { duration: 150 } }
                    }

                    Item { Layout.fillWidth: true }

                    Rectangle {
                        Layout.preferredWidth: nextIntroLabel.width + 32
                        Layout.preferredHeight: 44
                        radius: 10
                        color: "#7c3aed"
                        border.color: isWizFocused(1) ? ThemeManager.getColor("focus") : "transparent"
                        border.width: isWizFocused(1) ? 3 : 0

                        Text {
                            id: nextIntroLabel
                            anchors.centerIn: parent
                            text: "Get Started"
                            font.pixelSize: ThemeManager.getFontSize("medium")
                            font.family: ThemeManager.getFont("body")
                            font.bold: true
                            color: "white"
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            hoverEnabled: true
                            onEntered: wizFocusIndex = 1
                            onClicked: {
                                if (GameManager.isEpicAvailable()) currentStep = 2
                                else currentStep = 1
                            }
                        }

                        Behavior on border.color { ColorAnimation { duration: 150 } }
                    }
                }
            }

            // ── Step 1: Install Legendary ──
            ColumnLayout {
                visible: currentStep === 1
                spacing: 16

                Text {
                    text: "Step 1: Install Legendary"
                    font.pixelSize: ThemeManager.getFontSize("xlarge")
                    font.family: ThemeManager.getFont("heading")
                    font.bold: true
                    color: ThemeManager.getColor("textPrimary")
                }

                Text {
                    text: GameManager.isEpicAvailable()
                          ? "Legendary is already installed and ready!"
                          : "Legendary is an open-source Epic Games Store client for Linux.\n" +
                            "It handles authentication, game downloads, and launching."
                    font.pixelSize: ThemeManager.getFontSize("medium")
                    font.family: ThemeManager.getFont("body")
                    color: ThemeManager.getColor("textSecondary")
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                }

                // Status indicator
                RowLayout {
                    spacing: 10

                    Rectangle {
                        Layout.preferredWidth: 10
                        Layout.preferredHeight: 10
                        radius: 5
                        color: GameManager.isEpicAvailable()
                               ? ThemeManager.getColor("accent")
                               : legendaryInstalling ? "#f59e0b" : "#ff6b6b"
                    }

                    Text {
                        text: GameManager.isEpicAvailable() ? "Installed"
                              : legendaryInstalling ? "Installing..."
                              : "Not installed"
                        font.pixelSize: ThemeManager.getFontSize("small")
                        font.family: ThemeManager.getFont("body")
                        color: ThemeManager.getColor("textPrimary")
                    }
                }

                // Error message
                Text {
                    visible: errorMessage !== ""
                    text: errorMessage
                    font.pixelSize: ThemeManager.getFontSize("small")
                    font.family: ThemeManager.getFont("body")
                    color: "#ff6b6b"
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                }

                // Buttons
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12

                    // If already installed: Back + Next
                    // If not installed: Install + Back + Skip
                    Rectangle {
                        visible: !GameManager.isEpicAvailable() && !legendaryInstalling
                        Layout.preferredWidth: installBtnLabel.width + 32
                        Layout.preferredHeight: 44
                        radius: 10
                        color: "#7c3aed"
                        border.color: isWizFocused(0) ? ThemeManager.getColor("focus") : "transparent"
                        border.width: isWizFocused(0) ? 3 : 0

                        Text {
                            id: installBtnLabel
                            anchors.centerIn: parent
                            text: "Install Legendary"
                            font.pixelSize: ThemeManager.getFontSize("medium")
                            font.family: ThemeManager.getFont("body")
                            font.bold: true
                            color: "white"
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            hoverEnabled: true
                            onEntered: wizFocusIndex = 0
                            onClicked: {
                                legendaryInstalling = true
                                errorMessage = ""
                                GameManager.ensureLegendary()
                            }
                        }

                        Behavior on border.color { ColorAnimation { duration: 150 } }
                    }

                    Rectangle {
                        property int myIdx: GameManager.isEpicAvailable() ? 0
                                          : legendaryInstalling ? 0 : 1
                        Layout.preferredWidth: backStep1Label.width + 32
                        Layout.preferredHeight: 44
                        radius: 10
                        color: "transparent"
                        border.color: isWizFocused(myIdx) && !legendaryInstalling
                                      ? ThemeManager.getColor("focus") : Qt.rgba(1, 1, 1, 0.12)
                        border.width: isWizFocused(myIdx) && !legendaryInstalling ? 3 : 1

                        Text {
                            id: backStep1Label
                            anchors.centerIn: parent
                            text: "Back"
                            font.pixelSize: ThemeManager.getFontSize("medium")
                            font.family: ThemeManager.getFont("body")
                            font.bold: true
                            color: ThemeManager.getColor("textSecondary")
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: legendaryInstalling ? Qt.ArrowCursor : Qt.PointingHandCursor
                            onClicked: if (!legendaryInstalling) currentStep = 0
                        }

                        Behavior on border.color { ColorAnimation { duration: 150 } }
                    }

                    Item { Layout.fillWidth: true }

                    Rectangle {
                        visible: GameManager.isEpicAvailable()
                        property int myIdx: 1
                        Layout.preferredWidth: nextStep1Label.width + 32
                        Layout.preferredHeight: 44
                        radius: 10
                        color: "#7c3aed"
                        border.color: isWizFocused(myIdx) ? ThemeManager.getColor("focus") : "transparent"
                        border.width: isWizFocused(myIdx) ? 3 : 0

                        Text {
                            id: nextStep1Label
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
                            onClicked: currentStep = 2
                        }

                        Behavior on border.color { ColorAnimation { duration: 150 } }
                    }

                    Rectangle {
                        visible: !GameManager.isEpicAvailable() && !legendaryInstalling
                        property int myIdx: 2
                        Layout.preferredWidth: skipStep1Label.width + 32
                        Layout.preferredHeight: 44
                        radius: 10
                        color: "transparent"
                        border.color: isWizFocused(myIdx) ? ThemeManager.getColor("focus")
                                                          : Qt.rgba(1, 1, 1, 0.12)
                        border.width: isWizFocused(myIdx) ? 3 : 1

                        Text {
                            id: skipStep1Label
                            anchors.centerIn: parent
                            text: "Skip"
                            font.pixelSize: ThemeManager.getFontSize("medium")
                            font.family: ThemeManager.getFont("body")
                            font.bold: true
                            color: ThemeManager.getColor("textSecondary")
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: currentStep = 2
                        }

                        Behavior on border.color { ColorAnimation { duration: 150 } }
                    }
                }
            }

            // ── Step 2: Login ──
            ColumnLayout {
                visible: currentStep === 2
                spacing: 16

                Text {
                    text: "Step 2: Log In to Epic Games"
                    font.pixelSize: ThemeManager.getFontSize("xlarge")
                    font.family: ThemeManager.getFont("heading")
                    font.bold: true
                    color: ThemeManager.getColor("textPrimary")
                }

                Text {
                    text: GameManager.isEpicLoggedIn()
                          ? "You are logged in as: " + GameManager.getEpicUsername()
                          : loginInProgress
                            ? "Logging in to Epic Games...\nPlease wait."
                            : "Click the button below to log in to your\n" +
                              "Epic Games account."
                    font.pixelSize: ThemeManager.getFontSize("medium")
                    font.family: ThemeManager.getFont("body")
                    color: ThemeManager.getColor("textSecondary")
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                }

                // Login status
                RowLayout {
                    spacing: 10

                    Rectangle {
                        Layout.preferredWidth: 10
                        Layout.preferredHeight: 10
                        radius: 5
                        color: GameManager.isEpicLoggedIn()
                               ? ThemeManager.getColor("accent")
                               : loginInProgress ? "#f59e0b" : "#ff6b6b"
                    }

                    Text {
                        text: GameManager.isEpicLoggedIn() ? "Logged in"
                              : loginInProgress ? "Waiting for login..."
                              : "Not logged in"
                        font.pixelSize: ThemeManager.getFontSize("small")
                        font.family: ThemeManager.getFont("body")
                        color: ThemeManager.getColor("textPrimary")
                    }
                }

                // Error message
                Text {
                    visible: errorMessage !== ""
                    text: errorMessage
                    font.pixelSize: ThemeManager.getFontSize("small")
                    font.family: ThemeManager.getFont("body")
                    color: "#ff6b6b"
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                }

                // Buttons
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12

                    Rectangle {
                        visible: !GameManager.isEpicLoggedIn() && !loginInProgress
                        Layout.preferredWidth: loginBtnLabel.width + 32
                        Layout.preferredHeight: 44
                        radius: 10
                        color: "#7c3aed"
                        border.color: isWizFocused(0) ? ThemeManager.getColor("focus") : "transparent"
                        border.width: isWizFocused(0) ? 3 : 0

                        Text {
                            id: loginBtnLabel
                            anchors.centerIn: parent
                            text: "Log In to Epic"
                            font.pixelSize: ThemeManager.getFontSize("medium")
                            font.family: ThemeManager.getFont("body")
                            font.bold: true
                            color: "white"
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            hoverEnabled: true
                            onEntered: wizFocusIndex = 0
                            onClicked: {
                                errorMessage = ""
                                epicLoginWebView.url = GameManager.getEpicLoginUrl()
                                epicBrowserOpen = true
                            }
                        }

                        Behavior on border.color { ColorAnimation { duration: 150 } }
                    }

                    Rectangle {
                        property int myIdx: GameManager.isEpicLoggedIn() ? 0
                                          : loginInProgress ? 0 : 1
                        Layout.preferredWidth: backStep2Label.width + 32
                        Layout.preferredHeight: 44
                        radius: 10
                        color: "transparent"
                        border.color: isWizFocused(myIdx) && !loginInProgress
                                      ? ThemeManager.getColor("focus") : Qt.rgba(1, 1, 1, 0.12)
                        border.width: isWizFocused(myIdx) && !loginInProgress ? 3 : 1

                        Text {
                            id: backStep2Label
                            anchors.centerIn: parent
                            text: "Back"
                            font.pixelSize: ThemeManager.getFontSize("medium")
                            font.family: ThemeManager.getFont("body")
                            font.bold: true
                            color: ThemeManager.getColor("textSecondary")
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: loginInProgress ? Qt.ArrowCursor : Qt.PointingHandCursor
                            onClicked: if (!loginInProgress) currentStep = 1
                        }

                        Behavior on border.color { ColorAnimation { duration: 150 } }
                    }

                    Item { Layout.fillWidth: true }

                    Rectangle {
                        visible: GameManager.isEpicLoggedIn()
                        property int myIdx: 1
                        Layout.preferredWidth: nextStep2Label.width + 32
                        Layout.preferredHeight: 44
                        radius: 10
                        color: "#7c3aed"
                        border.color: isWizFocused(myIdx) ? ThemeManager.getColor("focus") : "transparent"
                        border.width: isWizFocused(myIdx) ? 3 : 0

                        Text {
                            id: nextStep2Label
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
                                currentStep = 3
                                fetchingLibrary = true
                                GameManager.fetchEpicLibrary()
                            }
                        }

                        Behavior on border.color { ColorAnimation { duration: 150 } }
                    }

                    Rectangle {
                        visible: !GameManager.isEpicLoggedIn() && !loginInProgress
                        property int myIdx: 2
                        Layout.preferredWidth: skipStep2Label.width + 32
                        Layout.preferredHeight: 44
                        radius: 10
                        color: "transparent"
                        border.color: isWizFocused(myIdx) ? ThemeManager.getColor("focus")
                                                          : Qt.rgba(1, 1, 1, 0.12)
                        border.width: isWizFocused(myIdx) ? 3 : 1

                        Text {
                            id: skipStep2Label
                            anchors.centerIn: parent
                            text: "Skip"
                            font.pixelSize: ThemeManager.getFontSize("medium")
                            font.family: ThemeManager.getFont("body")
                            font.bold: true
                            color: ThemeManager.getColor("textSecondary")
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: close()
                        }

                        Behavior on border.color { ColorAnimation { duration: 150 } }
                    }
                }
            }

            // ── Step 3: Fetch Library ──
            ColumnLayout {
                visible: currentStep === 3
                spacing: 16

                Text {
                    text: "Step 3: Import Library"
                    font.pixelSize: ThemeManager.getFontSize("xlarge")
                    font.family: ThemeManager.getFont("heading")
                    font.bold: true
                    color: ThemeManager.getColor("textPrimary")
                }

                Text {
                    text: fetchingLibrary
                          ? "Fetching your Epic Games library...\nThis may take a moment."
                          : gamesFound > 0
                            ? "Found " + gamesFound + " games in your Epic Games library!"
                            : "Ready to import your Epic Games library."
                    font.pixelSize: ThemeManager.getFontSize("medium")
                    font.family: ThemeManager.getFont("body")
                    color: ThemeManager.getColor("textSecondary")
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                }

                // Status indicator
                RowLayout {
                    spacing: 10

                    Rectangle {
                        Layout.preferredWidth: 10
                        Layout.preferredHeight: 10
                        radius: 5
                        color: gamesFound > 0 ? ThemeManager.getColor("accent")
                               : fetchingLibrary ? "#f59e0b" : ThemeManager.getColor("textSecondary")
                    }

                    Text {
                        text: fetchingLibrary ? "Fetching..."
                              : gamesFound > 0 ? gamesFound + " games imported"
                              : "Waiting"
                        font.pixelSize: ThemeManager.getFontSize("small")
                        font.family: ThemeManager.getFont("body")
                        color: ThemeManager.getColor("textPrimary")
                    }
                }

                // Error message
                Text {
                    visible: errorMessage !== ""
                    text: errorMessage
                    font.pixelSize: ThemeManager.getFontSize("small")
                    font.family: ThemeManager.getFont("body")
                    color: "#ff6b6b"
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12

                    Rectangle {
                        visible: !fetchingLibrary
                        Layout.preferredWidth: backStep3Label.width + 32
                        Layout.preferredHeight: 44
                        radius: 10
                        color: "transparent"
                        border.color: isWizFocused(0) ? ThemeManager.getColor("focus")
                                                      : Qt.rgba(1, 1, 1, 0.12)
                        border.width: isWizFocused(0) ? 3 : 1

                        Text {
                            id: backStep3Label
                            anchors.centerIn: parent
                            text: "Back"
                            font.pixelSize: ThemeManager.getFontSize("medium")
                            font.family: ThemeManager.getFont("body")
                            font.bold: true
                            color: ThemeManager.getColor("textSecondary")
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: currentStep = 2
                        }

                        Behavior on border.color { ColorAnimation { duration: 150 } }
                    }

                    Item { Layout.fillWidth: true }

                    Rectangle {
                        visible: !fetchingLibrary
                        property int myIdx: 1
                        Layout.preferredWidth: continueStep3Label.width + 32
                        Layout.preferredHeight: 44
                        radius: 10
                        color: "#7c3aed"
                        border.color: isWizFocused(myIdx) ? ThemeManager.getColor("focus") : "transparent"
                        border.width: isWizFocused(myIdx) ? 3 : 0

                        Text {
                            id: continueStep3Label
                            anchors.centerIn: parent
                            text: "Continue"
                            font.pixelSize: ThemeManager.getFontSize("medium")
                            font.family: ThemeManager.getFont("body")
                            font.bold: true
                            color: "white"
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: currentStep = 4
                        }

                        Behavior on border.color { ColorAnimation { duration: 150 } }
                    }
                }
            }

            // ── Step 4: Done ──
            ColumnLayout {
                visible: currentStep === 4
                spacing: 16

                // Checkmark
                Rectangle {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.preferredWidth: 72
                    Layout.preferredHeight: 72
                    radius: 36
                    color: "#7c3aed"

                    Text {
                        anchors.centerIn: parent
                        text: "\u2713"
                        font.pixelSize: 36
                        font.bold: true
                        color: "white"
                    }
                }

                Text {
                    text: "Epic Games Setup Complete!"
                    font.pixelSize: ThemeManager.getFontSize("xlarge")
                    font.family: ThemeManager.getFont("heading")
                    font.bold: true
                    color: ThemeManager.getColor("textPrimary")
                    Layout.alignment: Qt.AlignHCenter
                }

                Text {
                    text: gamesFound > 0
                          ? "Found " + gamesFound + " games in your library.\n" +
                            "You can now browse, download, and play your Epic Games\n" +
                            "directly from Luna."
                          : "Your Epic Games account is connected.\n" +
                            "Your games will appear in the My Games tab."
                    font.pixelSize: ThemeManager.getFontSize("medium")
                    font.family: ThemeManager.getFont("body")
                    color: ThemeManager.getColor("textSecondary")
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                }

                Rectangle {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.preferredWidth: doneLabel.width + 48
                    Layout.preferredHeight: 48
                    radius: 12
                    color: "#7c3aed"
                    border.color: isWizFocused(0) ? ThemeManager.getColor("focus") : "transparent"
                    border.width: isWizFocused(0) ? 3 : 0

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
                        onClicked: close()
                    }

                    Behavior on border.color { ColorAnimation { duration: 150 } }
                }
            }
        }
    }

    // ─── Navigation overlay script for embedded WebEngineView ───
    // Injected into the page on each load.  Builds an interactive element
    // list, draws a purple highlight ring around the focused one, and
    // supports spatial (directional) navigation from the controller.
    readonly property string navOverlayScript: "
(function() {
    if (window.__lunaNav) return;
    var nav = {};
    var currentIndex = 0;
    var elements = [];
    var highlightEl = null;

    var SELECTORS = 'a[href], button, input, select, textarea, '
        + '[role=\"button\"], [role=\"link\"], [role=\"menuitem\"], '
        + '[tabindex]:not([tabindex=\"-1\"]), [onclick]';

    function isVisible(el) {
        if (!el || !el.getBoundingClientRect) return false;
        var r = el.getBoundingClientRect();
        if (r.width === 0 || r.height === 0) return false;
        var style = window.getComputedStyle(el);
        return style.display !== 'none'
            && style.visibility !== 'hidden'
            && style.opacity !== '0';
    }

    function getVisualRect(el) {
        var rects = el.getClientRects();
        var r = el.getBoundingClientRect();
        if (rects.length > 1) {
            var best = rects[0];
            var bestArea = best.width * best.height;
            for (var i = 1; i < rects.length; i++) {
                var a = rects[i].width * rects[i].height;
                if (a > bestArea) { best = rects[i]; bestArea = a; }
            }
            r = best;
        }
        if ((r.width < 16 || r.height < 16) && el.parentElement) {
            var pr = el.parentElement.getBoundingClientRect();
            if (pr.width >= r.width && pr.height >= r.height
                && pr.width < 500 && pr.height < 120) {
                r = pr;
            }
        }
        var tag = el.tagName.toLowerCase();
        if (tag !== 'input' && tag !== 'textarea' && tag !== 'select'
            && tag !== 'img' && tag !== 'video') {
            try {
                var range = document.createRange();
                range.selectNodeContents(el);
                var tr = range.getBoundingClientRect();
                if (tr.width > 0 && tr.height > 0
                    && tr.width < r.width * 0.75) {
                    r = tr;
                }
            } catch(e) {}
        }
        return r;
    }

    function scanElements() {
        var all = document.querySelectorAll(SELECTORS);
        elements = [];
        for (var i = 0; i < all.length; i++) {
            if (isVisible(all[i])) elements.push(all[i]);
        }
        if (currentIndex >= elements.length) currentIndex = 0;
    }

    function createHighlight() {
        if (highlightEl) return;
        highlightEl = document.createElement('div');
        highlightEl.id = '__luna-highlight';
        highlightEl.style.cssText =
            'position:fixed; pointer-events:none; z-index:999999; '
            + 'border:3px solid #9b59b6; border-radius:6px; '
            + 'box-shadow:0 0 12px rgba(155,89,182,0.6), inset 0 0 8px rgba(155,89,182,0.2); '
            + 'transition:all 0.15s ease; display:none;';
        document.documentElement.appendChild(highlightEl);
    }

    function updateHighlight() {
        if (!highlightEl) createHighlight();
        if (elements.length === 0) { highlightEl.style.display = 'none'; return; }
        var el = elements[currentIndex];
        if (!el) return;
        var r = getVisualRect(el);
        var pad = 3;
        highlightEl.style.left   = (r.left - pad) + 'px';
        highlightEl.style.top    = (r.top - pad)  + 'px';
        highlightEl.style.width  = (r.width + pad * 2) + 'px';
        highlightEl.style.height = (r.height + pad * 2) + 'px';
        highlightEl.style.display = 'block';
        el.scrollIntoView({ block: 'nearest', behavior: 'smooth' });
    }

    function findNearest(direction) {
        if (elements.length < 2) return currentIndex;
        var cur = elements[currentIndex];
        if (!cur) return currentIndex;
        var cr = getVisualRect(cur);
        var cx = cr.left + cr.width / 2;
        var cy = cr.top + cr.height / 2;
        var bestIdx = -1;
        var bestDist = Infinity;

        for (var i = 0; i < elements.length; i++) {
            if (i === currentIndex) continue;
            var er = getVisualRect(elements[i]);
            var ex = er.left + er.width / 2;
            var ey = er.top + er.height / 2;
            var dx = ex - cx;
            var dy = ey - cy;
            var inDirection = false;
            switch (direction) {
                case 'up':    inDirection = dy < -5; break;
                case 'down':  inDirection = dy > 5;  break;
                case 'left':  inDirection = dx < -5; break;
                case 'right': inDirection = dx > 5;  break;
            }
            if (!inDirection) continue;
            var dist;
            if (direction === 'up' || direction === 'down') {
                dist = Math.abs(dy) + Math.abs(dx) * 2;
            } else {
                dist = Math.abs(dx) + Math.abs(dy) * 2;
            }
            if (dist < bestDist) { bestDist = dist; bestIdx = i; }
        }
        return bestIdx >= 0 ? bestIdx : currentIndex;
    }

    nav.move = function(direction) {
        scanElements();
        if (elements.length === 0) return 'no-elements';
        var oldIndex = currentIndex;
        currentIndex = findNearest(direction);
        updateHighlight();
        if (oldIndex === currentIndex) return 'boundary:' + direction;
        return 'moved:' + direction + ' idx:' + currentIndex + '/' + elements.length;
    };

    nav.activate = function() {
        scanElements();
        if (elements.length === 0) return 'no-elements';
        var el = elements[currentIndex];
        if (!el) return 'no-element';
        el.focus();
        el.click();
        var tag = el.tagName.toLowerCase();
        var type = (el.getAttribute('type') || 'text').toLowerCase();
        if (tag === 'input' && (type === 'text' || type === 'password'
                || type === 'email' || type === 'search' || type === 'url'
                || type === 'tel' || type === 'number')
            || tag === 'textarea') {
            return 'input:' + type + ':' + (el.value || '');
        }
        return 'clicked:' + el.tagName + ' ' + (el.textContent||'').substring(0,40);
    };

    nav.setText = function(text) {
        var el = document.activeElement;
        if (!el) return 'no-active';
        var nativeSetter = Object.getOwnPropertyDescriptor(
            window.HTMLInputElement.prototype, 'value'
        );
        if (!nativeSetter) nativeSetter = Object.getOwnPropertyDescriptor(
            window.HTMLTextAreaElement.prototype, 'value'
        );
        if (nativeSetter && nativeSetter.set) {
            nativeSetter.set.call(el, text);
        } else {
            el.value = text;
        }
        el.dispatchEvent(new Event('input', { bubbles: true }));
        el.dispatchEvent(new Event('change', { bubbles: true }));
        return 'set:' + text.length + ' chars';
    };

    nav.scrollPage = function(direction) {
        window.scrollBy(0, direction === 'up' ? -400 : 400);
        return 'scrolled:' + direction;
    };

    var observer = new MutationObserver(function() {
        var oldLen = elements.length;
        scanElements();
        if (elements.length !== oldLen) updateHighlight();
    });
    observer.observe(document.body, { childList: true, subtree: true });

    scanElements();
    if (elements.length > 0) updateHighlight();
    window.__lunaNav = nav;
    console.log('__luna:nav-ready count:' + elements.length);
    return 'ready:' + elements.length;
})();
"

    // ─── Controller → Embedded Epic Browser navigation ───
    Connections {
        target: ControllerManager
        enabled: epicWizard.epicBrowserOpen && epicWizard.currentStep === 2 && !epicBrowserVK.visible
        function onActionTriggered(action) {
            function logResult(result) {
                console.log("[epic-browser] nav result:", result)
            }

            // When the header Retry button is focused, handle it here
            if (epicWizard.browserHeaderFocused) {
                switch (action) {
                case "confirm":
                    console.log("[epic-browser] Controller: Retry Login (header focused)")
                    epicWizard.browserHeaderFocused = false
                    epicWizard.awaitingPolicyAcceptance = false
                    epicLoginWebView.url = GameManager.getEpicLoginUrl()
                    return
                case "navigate_down":
                    epicWizard.browserHeaderFocused = false
                    return
                case "back":
                    epicWizard.browserHeaderFocused = false
                    epicLoginWebView.url = "about:blank"
                    epicPopupWebView.url = "about:blank"
                    epicPopupWebView.visible = false
                    epicWizard.epicBrowserOpen = false
                    return
                }
                return
            }

            // Route navigation to the popup when it's visible, otherwise main view
            var view = epicPopupWebView.visible ? epicPopupWebView : epicLoginWebView

            switch (action) {
            case "navigate_up":
                // When awaiting policy (main view only), check if we hit the top boundary
                // so we can shift focus to the Retry button in the header.
                if (epicWizard.awaitingPolicyAcceptance && !epicPopupWebView.visible) {
                    view.runJavaScript(
                        "window.__lunaNav && window.__lunaNav.move('up')",
                        function(result) {
                            logResult(result)
                            if (result && result.toString().indexOf("boundary:") === 0) {
                                epicWizard.browserHeaderFocused = true
                            }
                        })
                } else {
                    view.runJavaScript("window.__lunaNav && window.__lunaNav.move('up')", logResult)
                }
                break
            case "navigate_down":
                view.runJavaScript("window.__lunaNav && window.__lunaNav.move('down')", logResult)
                break
            case "navigate_left":
                view.runJavaScript("window.__lunaNav && window.__lunaNav.move('left')", logResult)
                break
            case "navigate_right":
                view.runJavaScript("window.__lunaNav && window.__lunaNav.move('right')", logResult)
                break
            case "confirm":
                view.runJavaScript(
                    "window.__lunaNav && window.__lunaNav.activate()",
                    function(result) {
                        console.log("[epic-browser] activate result:", result)
                        if (result && result.toString().indexOf("input:") === 0) {
                            var parts = result.toString().split(":")
                            var inputType = parts[1] || "text"
                            var currentVal = parts.slice(2).join(":")
                            var isPassword = (inputType === "password")
                            epicWizard.browserInputActive = true
                            epicBrowserVK.placeholderText = isPassword ? "Enter password..." : "Type here..."
                            epicBrowserVK.open(currentVal, isPassword)
                        }
                    })
                break
            case "scroll_up":
                view.runJavaScript("window.__lunaNav && window.__lunaNav.scrollPage('up')", logResult)
                break
            case "scroll_down":
                view.runJavaScript("window.__lunaNav && window.__lunaNav.scrollPage('down')", logResult)
                break
            case "back":
                // If a popup overlay is open, close that first
                if (epicPopupWebView.visible) {
                    console.log("[epic-browser] closing popup overlay")
                    epicPopupWebView.url = "about:blank"
                    epicPopupWebView.visible = false
                } else if (epicLoginWebView.canGoBack) {
                    console.log("[epic-browser] navigating back")
                    epicLoginWebView.goBack()
                } else {
                    console.log("[epic-browser] closing browser")
                    epicLoginWebView.url = "about:blank"
                    epicWizard.epicBrowserOpen = false
                }
                break
            default:
                break
            }
        }
    }

    // ── Embedded browser for Epic Games login ──
    Rectangle {
        id: epicLoginBrowser
        visible: epicWizard.epicBrowserOpen && epicWizard.currentStep === 2
        anchors.fill: parent
        z: 250
        color: ThemeManager.getColor("background")

        // Header bar
        Rectangle {
            id: epicBrowserHeader
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: 50
            color: ThemeManager.getColor("surface")
            z: 1

            Text {
                anchors.centerIn: parent
                text: epicWizard.awaitingPolicyAcceptance
                      ? "Accept the policy below, then navigate up to Retry Login"
                      : "Epic Games Login"
                font.pixelSize: ThemeManager.getFontSize("medium")
                font.bold: true
                font.family: ThemeManager.getFont("heading")
                color: epicWizard.awaitingPolicyAcceptance
                       ? "#f59e0b" : ThemeManager.getColor("textPrimary")
            }

            // Close button
            Rectangle {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: 14
                width: closeBrowserLabel.width + 28
                height: 34
                radius: 8
                color: "transparent"
                border.color: Qt.rgba(1, 1, 1, 0.15)
                border.width: 1

                Text {
                    id: closeBrowserLabel
                    anchors.centerIn: parent
                    text: "B  Close"
                    font.pixelSize: ThemeManager.getFontSize("small")
                    font.family: ThemeManager.getFont("body")
                    color: ThemeManager.getColor("textSecondary")
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        epicLoginWebView.url = "about:blank"
                        epicPopupWebView.url = "about:blank"
                        epicPopupWebView.visible = false
                        epicWizard.epicBrowserOpen = false
                    }
                }
            }

            // "Retry Login" button — shown after the user accepts Epic's
            // privacy policy so they can restart the OAuth flow.
            // Navigable: D-pad up from the top of the page focuses this button.
            Rectangle {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.rightMargin: 14
                width: retryLoginLabel.width + 28
                height: 34
                radius: 8
                visible: epicWizard.awaitingPolicyAcceptance
                color: epicWizard.browserHeaderFocused ? "#9b59b6" : "#7c3aed"
                border.color: epicWizard.browserHeaderFocused ? "#c084fc" : "transparent"
                border.width: epicWizard.browserHeaderFocused ? 2 : 0
                scale: epicWizard.browserHeaderFocused ? 1.05 : 1.0
                Behavior on scale { NumberAnimation { duration: 150 } }
                Behavior on color { ColorAnimation { duration: 150 } }

                Text {
                    id: retryLoginLabel
                    anchors.centerIn: parent
                    text: "Retry Login"
                    font.pixelSize: ThemeManager.getFontSize("small")
                    font.family: ThemeManager.getFont("body")
                    font.bold: true
                    color: "white"
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        console.log("[epic-browser] User clicked Retry Login after privacy policy")
                        epicWizard.browserHeaderFocused = false
                        epicWizard.awaitingPolicyAcceptance = false
                        epicLoginWebView.url = GameManager.getEpicLoginUrl()
                    }
                }
            }
        }

        WebEngineView {
            id: epicLoginWebView
            anchors.top: epicBrowserHeader.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            url: "about:blank"
            profile: SharedBrowserProfile
            settings.focusOnNavigationEnabled: false

            // Open popups (e.g. social-login, CAPTCHA, verification) in a
            // separate overlay view so the original Epic page stays alive and
            // can receive the callback when the popup finishes.
            onNewWindowRequested: function(request) {
                console.log("[epic-browser] Popup requested — opening in overlay view")
                epicPopupWebView.visible = true
                request.openIn(epicPopupWebView)
            }

            onLoadingChanged: function(loadRequest) {
                console.log("[epic-browser] loadingChanged:",
                            loadRequest.status === WebEngineView.LoadSucceededStatus ? "SUCCESS" :
                            loadRequest.status === WebEngineView.LoadFailedStatus ? "FAILED" :
                            "status=" + loadRequest.status,
                            "url:", loadRequest.url)
                if (loadRequest.status === WebEngineView.LoadSucceededStatus) {
                    // Check if we landed on the redirect page with the auth code
                    epicAuthCodePollTimer.restart()
                    // Inject the controller navigation overlay
                    epicNavInjectTimer.restart()
                }
            }

            onUrlChanged: {
                var urlStr = url.toString()
                console.log("[epic-browser] URL changed:", urlStr)
                // The redirect URL after login contains the authorization code.
                // Check the URL query parameters first for an immediate match.
                if (urlStr.indexOf("/id/api/redirect") !== -1) {
                    console.log("[epic-browser] Detected redirect URL, checking for auth code...")
                    var m = urlStr.match(/[?&]code=([a-f0-9]{32})/i)
                    if (!m) m = urlStr.match(/[?&]authorizationCode=([a-f0-9]{32})/i)
                    if (m) {
                        console.log("[epic-browser] Got auth code from redirect URL")
                        epicAuthCodePollTimer.stop()
                        epicLoginWebView.url = "about:blank"
                        epicPopupWebView.url = "about:blank"
                        epicPopupWebView.visible = false
                        epicWizard.epicBrowserOpen = false
                        epicWizard.loginInProgress = true
                        GameManager.epicLoginWithCode(m[1])
                    } else {
                        // Code not in URL — poll the page body
                        epicAuthCodePollTimer.restart()
                    }
                }
                // While awaiting privacy policy acceptance, do NOT auto-restart
                // OAuth on URL changes.  The user needs to stay on Epic's site
                // to read and accept the policy.  A "Retry Login" button in the
                // browser header lets them restart OAuth once they are done.
            }

            onJavaScriptConsoleMessage: function(level, message, lineNumber, sourceID) {
                console.log("[epic-browser-js]", message)
            }
        }

        // Overlay for popup windows opened by Epic's login page (social
        // login, CAPTCHA, verification dialogs, etc.).  Keeping these in
        // a separate WebEngineView means the original page stays loaded
        // and can receive the post-login callback from the popup.
        WebEngineView {
            id: epicPopupWebView
            anchors.fill: epicLoginWebView
            z: 1
            visible: false
            profile: SharedBrowserProfile
            settings.focusOnNavigationEnabled: false

            // When the popup calls window.close(), hide the overlay so the
            // original Epic page is visible again and can process the result.
            onWindowCloseRequested: {
                console.log("[epic-browser] Popup closed by page")
                epicPopupWebView.url = "about:blank"
                epicPopupWebView.visible = false
            }

            // Also watch for the auth redirect landing in the popup itself
            onUrlChanged: {
                var urlStr = url.toString()
                console.log("[epic-browser-popup] URL changed:", urlStr)
                if (urlStr.indexOf("/id/api/redirect") !== -1) {
                    console.log("[epic-browser-popup] Auth redirect detected in popup")
                    var m = urlStr.match(/[?&]code=([a-f0-9]{32})/i)
                    if (!m) m = urlStr.match(/[?&]authorizationCode=([a-f0-9]{32})/i)
                    if (m) {
                        console.log("[epic-browser-popup] Got auth code from redirect URL")
                        epicAuthCodePollTimer.stop()
                        epicLoginWebView.url = "about:blank"
                        epicPopupWebView.url = "about:blank"
                        epicPopupWebView.visible = false
                        epicWizard.epicBrowserOpen = false
                        epicWizard.loginInProgress = true
                        GameManager.epicLoginWithCode(m[1])
                    } else {
                        epicAuthCodePollTimer.restart()
                    }
                }
            }

            onLoadingChanged: function(loadRequest) {
                console.log("[epic-browser-popup] loadingChanged:",
                            loadRequest.status === WebEngineView.LoadSucceededStatus ? "SUCCESS" :
                            loadRequest.status === WebEngineView.LoadFailedStatus ? "FAILED" :
                            "status=" + loadRequest.status,
                            "url:", loadRequest.url)
                if (loadRequest.status === WebEngineView.LoadSucceededStatus) {
                    // Inject controller navigation overlay into the popup
                    epicPopupNavInjectTimer.restart()
                }
            }

            // Nested popups: open in the same overlay
            onNewWindowRequested: function(request) {
                console.log("[epic-browser-popup] Nested popup, reusing overlay")
                request.openIn(epicPopupWebView)
            }

            onJavaScriptConsoleMessage: function(level, message, lineNumber, sourceID) {
                console.log("[epic-browser-popup-js]", message)
            }
        }

        // Poll the redirect page for the authorization code.
        // Epic's redirect page has changed formats over time:
        //   - Old: raw JSON body  {"authorizationCode": "abc..."}
        //   - New: HTML page with the code in a script block, data
        //     attribute, hidden input, or URL query parameter.
        // We try all of these to be resilient.
        Timer {
            id: epicAuthCodePollTimer
            interval: 1000
            repeat: true
            onTriggered: {
                var urlStr = epicLoginWebView.url.toString()

                // ── Check the URL itself first (no JS needed) ──
                // Epic may redirect to .../redirect?code=... or
                // include authorizationCode as a query parameter.
                if (urlStr.indexOf("/id/api/redirect") !== -1) {
                    var urlCodeMatch = urlStr.match(/[?&]code=([a-f0-9]{32})/i)
                    if (!urlCodeMatch) urlCodeMatch = urlStr.match(/[?&]authorizationCode=([a-f0-9]{32})/i)
                    if (urlCodeMatch) {
                        console.log("[epic-browser] Got auth code from URL, length:", urlCodeMatch[1].length)
                        epicAuthCodePollTimer.stop()
                        epicLoginWebView.url = "about:blank"
                        epicPopupWebView.url = "about:blank"
                        epicPopupWebView.visible = false
                        epicWizard.epicBrowserOpen = false
                        epicWizard.loginInProgress = true
                        GameManager.epicLoginWithCode(urlCodeMatch[1])
                        return
                    }
                }

                if (urlStr.indexOf("/id/api/redirect") === -1) return

                // ── Scrape page content for the auth code ──
                epicLoginWebView.runJavaScript(
                    "(function() {" +
                    "  var text = document.body.innerText || document.body.textContent || '';" +
                    "  var html = document.documentElement.innerHTML || '';" +
                    "" +
                    "  // Detect corrective action (privacy policy)" +
                    "  if (text.indexOf('PRIVACY_POLICY_ACCEPTANCE') !== -1 ||" +
                    "      html.indexOf('corrective_action') !== -1 ||" +
                    "      html.indexOf('correctiveAction') !== -1) {" +
                    "    return '__CORRECTIVE_ACTION__';" +
                    "  }" +
                    "" +
                    "  // 1) Try parsing body as raw JSON (old format)" +
                    "  try {" +
                    "    var json = JSON.parse(text);" +
                    "    if (json.authorizationCode) return json.authorizationCode;" +
                    "    if (json.code) return json.code;" +
                    "    if (json.redirectUrl) {" +
                    "      var m = json.redirectUrl.match(/[?&]code=([a-f0-9]{32})/i);" +
                    "      if (m) return m[1];" +
                    "    }" +
                    "  } catch(e) {}" +
                    "" +
                    "  // 2) Search for code in page text via regex" +
                    "  var patterns = [" +
                    "    /authorizationCode[\"'\\s:]+([a-f0-9]{32})/i," +
                    "    /\\\"code\\\"\\s*:\\s*\\\"([a-f0-9]{32})\\\"/i," +
                    "    /['\"]authorizationCode['\"]\\s*[:,]\\s*['\"]([a-f0-9]{32})['\"]/" +
                    "  ];" +
                    "  for (var i = 0; i < patterns.length; i++) {" +
                    "    var m = text.match(patterns[i]) || html.match(patterns[i]);" +
                    "    if (m) return m[1];" +
                    "  }" +
                    "" +
                    "  // 3) Check embedded JSON in <script> tags" +
                    "  var scripts = document.querySelectorAll('script');" +
                    "  for (var j = 0; j < scripts.length; j++) {" +
                    "    var src = scripts[j].textContent || '';" +
                    "    for (var k = 0; k < patterns.length; k++) {" +
                    "      var sm = src.match(patterns[k]);" +
                    "      if (sm) return sm[1];" +
                    "    }" +
                    "  }" +
                    "" +
                    "  // 4) Check hidden inputs or data attributes" +
                    "  var codeEl = document.querySelector('[name=code],[name=authorizationCode],[data-code],[data-authorization-code]');" +
                    "  if (codeEl) {" +
                    "    var val = codeEl.value || codeEl.getAttribute('data-code') || codeEl.getAttribute('data-authorization-code');" +
                    "    if (val && val.length >= 30) return val;" +
                    "  }" +
                    "" +
                    "  return null;" +
                    "})()",
                    function(code) {
                        if (code === "__CORRECTIVE_ACTION__") {
                            console.log("[epic-browser] Corrective action required (privacy policy) — redirecting to Epic")
                            epicAuthCodePollTimer.stop()
                            epicWizard.awaitingPolicyAcceptance = true
                            epicLoginWebView.url = "https://www.epicgames.com"
                        } else if (code && code.length > 10) {
                            console.log("[epic-browser] Got authorization code from page, length:", code.length)
                            epicAuthCodePollTimer.stop()
                            epicLoginWebView.url = "about:blank"
                            epicPopupWebView.url = "about:blank"
                            epicPopupWebView.visible = false
                            epicWizard.epicBrowserOpen = false
                            epicWizard.loginInProgress = true
                            GameManager.epicLoginWithCode(code)
                        }
                    }
                )
            }
        }

        // Inject the controller navigation overlay after page load
        Timer {
            id: epicNavInjectTimer
            interval: 800
            repeat: false
            onTriggered: {
                console.log("[epic-browser] injecting navigation overlay")
                epicLoginWebView.runJavaScript(epicWizard.navOverlayScript,
                    function(result) {
                        console.log("[epic-browser] nav inject result:", result)
                    })
            }
        }

        // Inject navigation overlay into popup windows (social login, etc.)
        Timer {
            id: epicPopupNavInjectTimer
            interval: 800
            repeat: false
            onTriggered: {
                console.log("[epic-browser-popup] injecting navigation overlay into popup")
                epicPopupWebView.runJavaScript(epicWizard.navOverlayScript,
                    function(result) {
                        console.log("[epic-browser-popup] nav inject result:", result)
                    })
            }
        }
    }

    // ─── Virtual Keyboard for Epic Browser ───
    VirtualKeyboard {
        id: epicBrowserVK
        anchors.fill: parent

        onAccepted: function(typedText) {
            if (epicWizard.browserInputActive) {
                epicWizard.browserInputActive = false
                var escaped = typedText.replace(/\\/g, '\\\\').replace(/'/g, "\\'")
                var view = epicPopupWebView.visible ? epicPopupWebView : epicLoginWebView
                view.runJavaScript(
                    "window.__lunaNav && window.__lunaNav.setText('" + escaped + "')",
                    function(result) {
                        console.log("[epic-browser] setText result:", result)
                    })
            }
            epicWizard.forceActiveFocus()
        }

        onCancelled: {
            epicWizard.browserInputActive = false
            epicWizard.forceActiveFocus()
        }
    }
}
