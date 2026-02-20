import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

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

    // Controller focus
    property int wizFocusIndex: 0

    function open() {
        currentStep = 0
        errorMessage = ""
        gamesFound = 0
        legendaryInstalling = false
        loginInProgress = false
        fetchingLibrary = false
        wizFocusIndex = 0
        visible = true
        epicWizard.forceActiveFocus()
    }

    function close() {
        visible = false
        closed()
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
        return epicWizard.visible && wizFocusIndex === idx
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
            if (loginInProgress) break
            if (GameManager.isEpicLoggedIn()) {
                if (wizFocusIndex === 0) currentStep = 1       // Back
                else if (wizFocusIndex === 1) {                // Next
                    currentStep = 3
                    fetchingLibrary = true
                    GameManager.fetchEpicLibrary()
                }
            } else {
                if (wizFocusIndex === 0) {                     // Login
                    loginInProgress = true
                    errorMessage = ""
                    GameManager.epicLogin()
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
                            ? "A browser window will open for Epic Games login.\n" +
                              "Complete the login in the browser, then return here."
                            : "Click the button below to open a browser window where\n" +
                              "you can log in to your Epic Games account."
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
                                loginInProgress = true
                                errorMessage = ""
                                GameManager.epicLogin()
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
}
