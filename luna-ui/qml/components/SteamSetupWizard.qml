import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtWebEngine

// Full-screen modal wizard for first-time Steam setup.
// Step 0: Intro explaining the multi-login process
// Step 1: Steam client login
// Step 2: API key retrieval via browser
// Step 3: SteamCMD login with password + authenticator approval
// Step 4: Done
//
// Fully controller-navigable: D-pad moves between items,
// A/Enter activates, B/Escape goes back or closes.
Rectangle {
    id: wizard
    anchors.fill: parent
    color: Qt.rgba(0, 0, 0, 0.8)
    z: 200
    visible: false

    signal closed()

    property int currentStep: 0  // 0=intro, 1=steam-login, 2=api-key, 3=steamcmd-login, 4=done

    // Sub-states for step 2 (API key)
    property bool apiKeyScraping: false
    property string apiKeyScrapeErrorMsg: ""
    property bool apiKeyBrowserOpen: false
    property string detectedApiKey: ""
    property bool showManualInput: false
    property bool browserInputActive: false   // true when virtual keyboard targets a browser input

    // Sub-states for step 3 (SteamCMD)
    property string steamCmdPromptType: ""  // "password" or "steamguard"
    property bool steamCmdWaiting: false
    property bool steamCmdAwaitingGuard: false  // true after password submitted, before guard prompt
    property bool steamCmdVerifyingGuard: false // true after guard code submitted, waiting for result
    property string steamCmdError: ""

    // ─── Controller Navigation ───
    property int wizFocusIndex: 0
    property int overlayFocusIdx: 0

    onCurrentStepChanged: {
        wizFocusIndex = 0
        // Only grab focus if already visible; open() handles the initial case
        if (wizard.visible) wizard.forceActiveFocus()
    }
    onVisibleChanged: {
        if (visible) {
            wizFocusIndex = 0
            wizard.forceActiveFocus()
        }
    }
    onShowManualInputChanged: wizFocusIndex = 0
    onSteamCmdPromptTypeChanged: wizFocusIndex = 0
    onSteamCmdWaitingChanged: wizFocusIndex = 0
    onApiKeyBrowserOpenChanged: wizFocusIndex = 0

    function wizFocusCount() {
        if (apiKeyConfirmOverlay.visible) return 2
        if (apiKeyBrowserOpen && currentStep === 2) return 1
        switch (currentStep) {
        case 0: return 2  // Cancel, Next
        case 1: return 2  // Back, Open Steam
        case 2:
            if (detectedApiKey !== "" && !showManualInput) return 2  // Yes, No
            if (showManualInput && detectedApiKey === "") return 4  // Input, Retry, Back, Skip
            return 3  // Get API Key, Back, Skip
        case 3:
            if (steamCmdPromptType === "password") return 4  // Input, Submit, Back, Skip
            if (steamCmdPromptType === "steamguard") return 4  // Input, Submit, Back, Skip
            if (steamCmdPromptType === "" && !steamCmdWaiting && !steamCmdAwaitingGuard && !steamCmdVerifyingGuard)
                return 3  // Start Login, Back, Skip
            return 2  // Waiting states: Back, Skip
        case 4: return 1  // Start Playing
        }
        return 0
    }

    function isWizFocused(idx) {
        return wizard.visible && !wizardVirtualKeyboard.visible
               && !apiKeyConfirmOverlay.visible && !(apiKeyBrowserOpen && currentStep === 2)
               && wizFocusIndex === idx
    }

    function isOverlayFocused(idx) {
        return apiKeyConfirmOverlay.visible && overlayFocusIdx === idx
    }

    function isBrowserBtnFocused() {
        return apiKeyBrowserOpen && currentStep === 2 && !apiKeyConfirmOverlay.visible
    }

    function wizActivate(idx) {
        switch (currentStep) {
        case 0:
            if (idx === 0) wizard.close()
            else if (idx === 1) wizard.currentStep = 1
            break
        case 1:
            if (idx === 0) wizard.currentStep = 0
            else if (idx === 1) {
                if (!GameManager.hasSteamApiKey())
                    GameManager.setSteamApiKey("__setup_pending__")
                GameManager.launchSteamLogin()
            }
            break
        case 2:
            if (detectedApiKey !== "" && !showManualInput) {
                if (idx === 0) {
                    apiKeyWebView.url = "about:blank"
                    wizard.apiKeyBrowserOpen = false
                    GameManager.setSteamApiKey(wizard.detectedApiKey)
                    wizard.currentStep = 3
                } else if (idx === 1) {
                    wizard.detectedApiKey = ""
                    wizard.showManualInput = true
                }
            } else if (showManualInput && detectedApiKey === "") {
                if (idx === 0) {
                    wizardVirtualKeyboard.placeholderText = "Steam API key..."
                    wizardVirtualKeyboard.open(manualKeyInput.text)
                } else if (idx === 1) {
                    wizard.showManualInput = false
                    wizard.apiKeyScrapeErrorMsg = ""
                    wizard.apiKeyBrowserOpen = true
                    apiKeyWebView.url = "https://steamcommunity.com/dev/apikey"
                } else if (idx === 2) {
                    wizard.currentStep = 0
                } else if (idx === 3) {
                    if (GameManager.getSteamApiKey() === "__setup_pending__")
                        GameManager.setSteamApiKey("")
                    wizard.currentStep = 3
                }
            } else {
                if (idx === 0) {
                    wizard.apiKeyBrowserOpen = true
                    apiKeyWebView.url = "https://steamcommunity.com/dev/apikey"
                } else if (idx === 1) {
                    wizard.currentStep = 0
                } else if (idx === 2) {
                    if (GameManager.getSteamApiKey() === "__setup_pending__")
                        GameManager.setSteamApiKey("")
                    wizard.currentStep = 3
                }
            }
            break
        case 3:
            if (steamCmdPromptType === "password") {
                if (idx === 0) {
                    wizardVirtualKeyboard.placeholderText = "Enter password..."
                    wizardVirtualKeyboard.open("", true)
                } else if (idx === 1) {
                    if (setupCredInput.text.length > 0) {
                        GameManager.provideSteamCmdSetupCredential(setupCredInput.text)
                        setupCredInput.text = ""
                        wizard.steamCmdPromptType = ""
                        wizard.steamCmdAwaitingGuard = true
                        wizard.steamCmdWaiting = false
                    }
                } else if (idx === 2) {
                    GameManager.cancelSteamCmdSetup()
                    wizard.steamCmdPromptType = ""
                    wizard.steamCmdWaiting = false
                    wizard.currentStep = 2
                } else if (idx === 3) {
                    GameManager.cancelSteamCmdSetup()
                    wizard.close()
                }
            } else if (steamCmdPromptType === "steamguard") {
                if (idx === 0) {
                    wizardVirtualKeyboard.placeholderText = "Enter code..."
                    wizardVirtualKeyboard.open("")
                } else if (idx === 1) {
                    if (guardCodeInput.text.length > 0) {
                        GameManager.provideSteamCmdSetupCredential(guardCodeInput.text)
                        guardCodeInput.text = ""
                        wizard.steamCmdPromptType = ""
                        wizard.steamCmdWaiting = true
                        wizard.steamCmdVerifyingGuard = true
                    }
                } else if (idx === 2) {
                    GameManager.cancelSteamCmdSetup()
                    wizard.steamCmdPromptType = ""
                    wizard.steamCmdWaiting = false
                    wizard.currentStep = 2
                } else if (idx === 3) {
                    GameManager.cancelSteamCmdSetup()
                    wizard.close()
                }
            } else if (steamCmdPromptType === "" && !steamCmdWaiting && !steamCmdAwaitingGuard && !steamCmdVerifyingGuard) {
                if (idx === 0) {
                    wizard.steamCmdWaiting = true
                    wizard.steamCmdError = ""
                    GameManager.loginSteamCmd()
                } else if (idx === 1) {
                    GameManager.cancelSteamCmdSetup()
                    wizard.steamCmdPromptType = ""
                    wizard.steamCmdWaiting = false
                    wizard.currentStep = 2
                } else if (idx === 2) {
                    GameManager.cancelSteamCmdSetup()
                    wizard.close()
                }
            } else {
                // Waiting states: Back=0, Skip=1
                if (idx === 0) {
                    GameManager.cancelSteamCmdSetup()
                    wizard.steamCmdPromptType = ""
                    wizard.steamCmdWaiting = false
                    wizard.currentStep = 2
                } else if (idx === 1) {
                    GameManager.cancelSteamCmdSetup()
                    wizard.close()
                }
            }
            break
        case 4:
            if (idx === 0) {
                GameManager.restartSteam()
                GameManager.scanAllStores()
                GameManager.fetchSteamOwnedGames()
                wizard.close()
            }
            break
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

    /* Return the best visual bounding rect for an element.
       Handles inline elements that wrap across lines (use the largest
       individual client rect instead of the union), and tiny interactive
       elements wrapped inside a styled parent container. */
    function getVisualRect(el) {
        var rects = el.getClientRects();
        var r = el.getBoundingClientRect();

        // Inline elements wrapping across lines produce multiple rects;
        // the union (getBoundingClientRect) can be absurdly wide.
        // Pick the largest individual rect instead.
        if (rects.length > 1) {
            var best = rects[0];
            var bestArea = best.width * best.height;
            for (var i = 1; i < rects.length; i++) {
                var a = rects[i].width * rects[i].height;
                if (a > bestArea) { best = rects[i]; bestArea = a; }
            }
            r = best;
        }

        // If the element itself is very small (icon-only button, hidden
        // checkbox, etc.) but lives inside a reasonably-sized parent that
        // looks like the actual visual target, snap to the parent.
        if ((r.width < 16 || r.height < 16) && el.parentElement) {
            var pr = el.parentElement.getBoundingClientRect();
            if (pr.width >= r.width && pr.height >= r.height
                && pr.width < 500 && pr.height < 120) {
                r = pr;
            }
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
        currentIndex = findNearest(direction);
        updateHighlight();
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

    // Re-scan when the DOM changes so newly-added elements (Steam
    // loads content dynamically) are picked up automatically.
    var observer = new MutationObserver(function() {
        var oldLen = elements.length;
        scanElements();
        if (elements.length !== oldLen) {
            updateHighlight();
        }
    });
    observer.observe(document.body, { childList: true, subtree: true });

    scanElements();
    if (elements.length > 0) updateHighlight();
    window.__lunaNav = nav;
    console.log('__luna:nav-ready count:' + elements.length);
    return 'ready:' + elements.length;
})();
"

    // ─── Controller → Embedded Browser navigation ───
    // When the WebEngineView is active it steals focus, so synthetic key
    // events from ControllerManager never reach Keys.onPressed.  Listen to
    // actionTriggered directly — it fires regardless of focus state.
    Connections {
        target: ControllerManager
        enabled: wizard.apiKeyBrowserOpen && wizard.currentStep === 2
        function onActionTriggered(action) {
            function logResult(result) {
                console.log("[wizard-browser] nav result:", result)
            }
            switch (action) {
            case "navigate_up":
                apiKeyWebView.runJavaScript("window.__lunaNav && window.__lunaNav.move('up')", logResult)
                break
            case "navigate_down":
                apiKeyWebView.runJavaScript("window.__lunaNav && window.__lunaNav.move('down')", logResult)
                break
            case "navigate_left":
                apiKeyWebView.runJavaScript("window.__lunaNav && window.__lunaNav.move('left')", logResult)
                break
            case "navigate_right":
                apiKeyWebView.runJavaScript("window.__lunaNav && window.__lunaNav.move('right')", logResult)
                break
            case "confirm":
                apiKeyWebView.runJavaScript(
                    "window.__lunaNav && window.__lunaNav.activate()",
                    function(result) {
                        console.log("[wizard-browser] activate result:", result)
                        if (result && result.toString().indexOf("input:") === 0) {
                            // result is "input:<type>:<currentValue>"
                            var parts = result.toString().split(":")
                            var inputType = parts[1] || "text"
                            var currentVal = parts.slice(2).join(":") // value may contain colons
                            var isPassword = (inputType === "password")
                            wizard.browserInputActive = true
                            wizardVirtualKeyboard.placeholderText = isPassword ? "Enter password..." : "Type here..."
                            wizardVirtualKeyboard.open(currentVal, isPassword)
                        }
                    })
                break
            case "scroll_up":
                apiKeyWebView.runJavaScript("window.__lunaNav && window.__lunaNav.scrollPage('up')", logResult)
                break
            case "scroll_down":
                apiKeyWebView.runJavaScript("window.__lunaNav && window.__lunaNav.scrollPage('down')", logResult)
                break
            case "back":
                console.log("[wizard-browser] closing browser")
                wizard.apiKeyBrowserOpen = false
                apiKeyPollTimer.stop()
                apiKeyWebView.url = "about:blank"
                break
            default:
                break
            }
        }
    }

    // ─── Key Handler ───
    Keys.onPressed: function(event) {
        if (wizardVirtualKeyboard.visible) return

        // Overlay navigation
        if (apiKeyConfirmOverlay.visible) {
            switch (event.key) {
            case Qt.Key_Left:
                if (overlayFocusIdx > 0) overlayFocusIdx--
                event.accepted = true; break
            case Qt.Key_Right:
                if (overlayFocusIdx < 1) overlayFocusIdx++
                event.accepted = true; break
            case Qt.Key_Return:
            case Qt.Key_Enter:
                if (overlayFocusIdx === 0) {
                    apiKeyConfirmOverlay.visible = false
                    apiKeyWebView.url = "about:blank"
                    GameManager.setSteamApiKey(apiKeyConfirmOverlay.overlayKey)
                    wizard.detectedApiKey = apiKeyConfirmOverlay.overlayKey
                    wizard.apiKeyBrowserOpen = false
                    wizard.currentStep = 3
                } else {
                    apiKeyConfirmOverlay.visible = false
                    apiKeyWebView.url = "about:blank"
                    wizard.detectedApiKey = ""
                    wizard.apiKeyBrowserOpen = false
                    wizard.showManualInput = true
                }
                event.accepted = true; break
            case Qt.Key_Escape:
                apiKeyConfirmOverlay.visible = false
                event.accepted = true; break
            }
            return
        }

        // Browser navigation is handled by the Connections block above
        // (listening to ControllerManager.actionTriggered directly),
        // because the WebEngineView steals focus and key events never
        // reach this handler while the browser is open.
        if (apiKeyBrowserOpen && currentStep === 2) return

        // Main wizard navigation
        var count = wizFocusCount()
        switch (event.key) {
        case Qt.Key_Up:
        case Qt.Key_Left:
            if (wizFocusIndex > 0) wizFocusIndex--
            event.accepted = true
            break
        case Qt.Key_Down:
        case Qt.Key_Right:
            if (wizFocusIndex < count - 1) wizFocusIndex++
            event.accepted = true
            break
        case Qt.Key_Return:
        case Qt.Key_Enter:
            wizActivate(wizFocusIndex)
            event.accepted = true
            break
        case Qt.Key_Escape:
            if (currentStep === 0) wizard.close()
            else if (currentStep === 1) wizard.currentStep = 0
            else if (currentStep === 2) wizard.currentStep = 0
            else if (currentStep === 3) {
                GameManager.cancelSteamCmdSetup()
                wizard.steamCmdPromptType = ""
                wizard.steamCmdWaiting = false
                wizard.currentStep = 2
            }
            else if (currentStep === 4) wizard.close()
            event.accepted = true
            break
        }
    }

    // Click blocker
    MouseArea { anchors.fill: parent; onClicked: {} }

    // Signal connections
    Connections {
        target: GameManager

        function onApiKeyScraped(key) {
            wizard.apiKeyScraping = false
            wizard.detectedApiKey = key
            apiKeyConfirmOverlay.overlayKey = key
            apiKeyConfirmOverlay.visible = true
            wizard.overlayFocusIdx = 0
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
            wizard.wizFocusIndex = 0
            wizard.forceActiveFocus()
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
        wizFocusIndex = 0
        overlayFocusIdx = 0
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
        if (GameManager.isSteamAvailable()) {
            if (!GameManager.isSteamCmdAvailable()) {
                GameManager.downloadSteamCmd()
            }
            if (GameManager.hasSteamApiKey() && GameManager.isSteamCmdAvailable()) {
                currentStep = 4
            } else if (GameManager.hasSteamApiKey()) {
                currentStep = 3
            } else {
                currentStep = 2
            }
        }
        visible = true
        wizard.forceActiveFocus()
    }

    function close() {
        GameManager.closeApiKeyBrowser()
        GameManager.cancelSteamCmdSetup()
        visible = false
        closed()
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
                        border.color: isWizFocused(0) ? ThemeManager.getColor("focus") : Qt.rgba(1, 1, 1, 0.15)
                        border.width: isWizFocused(0) ? 3 : 1
                        Behavior on border.color { ColorAnimation { duration: 150 } }

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
                        border.color: isWizFocused(1) ? ThemeManager.getColor("focus") : "transparent"
                        border.width: isWizFocused(1) ? 3 : 0
                        Behavior on border.color { ColorAnimation { duration: 150 } }

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
                            onClicked: wizard.currentStep = 1
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
                        border.color: isWizFocused(0) ? ThemeManager.getColor("focus") : Qt.rgba(1, 1, 1, 0.15)
                        border.width: isWizFocused(0) ? 3 : 1
                        Behavior on border.color { ColorAnimation { duration: 150 } }

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
                        border.color: isWizFocused(1) ? ThemeManager.getColor("focus") : "transparent"
                        border.width: isWizFocused(1) ? 3 : 0
                        Behavior on border.color { ColorAnimation { duration: 150 } }

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
                    border.color: isWizFocused(0) && !wizard.apiKeyBrowserOpen && wizard.detectedApiKey === "" && !wizard.showManualInput
                                  ? ThemeManager.getColor("focus") : "transparent"
                    border.width: isWizFocused(0) && !wizard.apiKeyBrowserOpen && wizard.detectedApiKey === "" && !wizard.showManualInput ? 3 : 0
                    Behavior on border.color { ColorAnimation { duration: 150 } }

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
                                border.color: isWizFocused(0) && wizard.detectedApiKey !== "" && !wizard.showManualInput
                                              ? ThemeManager.getColor("focus") : "transparent"
                                border.width: isWizFocused(0) && wizard.detectedApiKey !== "" && !wizard.showManualInput ? 3 : 0
                                Behavior on border.color { ColorAnimation { duration: 150 } }

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
                                border.color: isWizFocused(1) && wizard.detectedApiKey !== "" && !wizard.showManualInput
                                              ? ThemeManager.getColor("focus") : Qt.rgba(1, 1, 1, 0.15)
                                border.width: isWizFocused(1) && wizard.detectedApiKey !== "" && !wizard.showManualInput ? 3 : 1
                                Behavior on border.color { ColorAnimation { duration: 150 } }

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
                        border.color: (manualKeyInput.activeFocus || (isWizFocused(0) && wizard.showManualInput))
                                      ? ThemeManager.getColor("focus") : "transparent"
                        border.width: (manualKeyInput.activeFocus || (isWizFocused(0) && wizard.showManualInput)) ? 3 : 0
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
                        border.color: (isWizFocused(1) && wizard.showManualInput)
                                      ? ThemeManager.getColor("focus") : Qt.rgba(1, 1, 1, 0.12)
                        border.width: (isWizFocused(1) && wizard.showManualInput) ? 3 : 1
                        Behavior on border.color { ColorAnimation { duration: 150 } }

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
                        property int myIdx: wizard.showManualInput ? 2 : 1
                        Layout.preferredWidth: backStep2Label.width + 32
                        Layout.preferredHeight: 44
                        radius: 8
                        color: "transparent"
                        border.color: isWizFocused(myIdx) ? ThemeManager.getColor("focus") : Qt.rgba(1, 1, 1, 0.15)
                        border.width: isWizFocused(myIdx) ? 3 : 1
                        Behavior on border.color { ColorAnimation { duration: 150 } }

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
                        property int myIdx: wizard.showManualInput ? 3 : 2
                        visible: !GameManager.hasSteamApiKey() || GameManager.getSteamApiKey() === "__setup_pending__"
                        Layout.preferredWidth: skipApiLabel.width + 32
                        Layout.preferredHeight: 44
                        radius: 8
                        color: "transparent"
                        border.color: isWizFocused(myIdx) ? ThemeManager.getColor("focus") : Qt.rgba(1, 1, 1, 0.08)
                        border.width: isWizFocused(myIdx) ? 3 : 1
                        Behavior on border.color { ColorAnimation { duration: 150 } }

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
                    border.color: isWizFocused(0) && wizard.steamCmdPromptType === "" && !wizard.steamCmdWaiting
                                  ? ThemeManager.getColor("focus") : "transparent"
                    border.width: isWizFocused(0) && wizard.steamCmdPromptType === "" && !wizard.steamCmdWaiting ? 3 : 0
                    Behavior on border.color { ColorAnimation { duration: 150 } }

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
                        border.color: (setupCredInput.activeFocus || (isWizFocused(0) && wizard.steamCmdPromptType === "password"))
                                      ? ThemeManager.getColor("focus") : "transparent"
                        border.width: (setupCredInput.activeFocus || (isWizFocused(0) && wizard.steamCmdPromptType === "password")) ? 3 : 0
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
                        border.color: (isWizFocused(1) && wizard.steamCmdPromptType === "password")
                                      ? ThemeManager.getColor("focus") : "transparent"
                        border.width: (isWizFocused(1) && wizard.steamCmdPromptType === "password") ? 3 : 0
                        Behavior on border.color { ColorAnimation { duration: 150 } }

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
                            border.color: (guardCodeInput.activeFocus || (isWizFocused(0) && wizard.steamCmdPromptType === "steamguard"))
                                          ? ThemeManager.getColor("focus") : "transparent"
                            border.width: (guardCodeInput.activeFocus || (isWizFocused(0) && wizard.steamCmdPromptType === "steamguard")) ? 3 : 0
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
                            border.color: (isWizFocused(1) && wizard.steamCmdPromptType === "steamguard")
                                          ? ThemeManager.getColor("focus") : "transparent"
                            border.width: (isWizFocused(1) && wizard.steamCmdPromptType === "steamguard") ? 3 : 0
                            Behavior on border.color { ColorAnimation { duration: 150 } }

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
                        // Back index depends on the current sub-state
                        property int myIdx: {
                            if (wizard.steamCmdPromptType === "password" || wizard.steamCmdPromptType === "steamguard")
                                return 2
                            if (wizard.steamCmdPromptType === "" && !wizard.steamCmdWaiting && !wizard.steamCmdAwaitingGuard && !wizard.steamCmdVerifyingGuard)
                                return 1
                            return 0  // Waiting states
                        }
                        Layout.preferredWidth: backStep3Label.width + 32
                        Layout.preferredHeight: 44
                        radius: 8
                        color: "transparent"
                        border.color: isWizFocused(myIdx) ? ThemeManager.getColor("focus") : Qt.rgba(1, 1, 1, 0.15)
                        border.width: isWizFocused(myIdx) ? 3 : 1
                        Behavior on border.color { ColorAnimation { duration: 150 } }

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
                        property int myIdx: {
                            if (wizard.steamCmdPromptType === "password" || wizard.steamCmdPromptType === "steamguard")
                                return 3
                            if (wizard.steamCmdPromptType === "" && !wizard.steamCmdWaiting && !wizard.steamCmdAwaitingGuard && !wizard.steamCmdVerifyingGuard)
                                return 2
                            return 1  // Waiting states
                        }
                        Layout.preferredWidth: skipCmdLabel.width + 32
                        Layout.preferredHeight: 44
                        radius: 8
                        color: "transparent"
                        border.color: isWizFocused(myIdx) ? ThemeManager.getColor("focus") : Qt.rgba(1, 1, 1, 0.08)
                        border.width: isWizFocused(myIdx) ? 3 : 1
                        Behavior on border.color { ColorAnimation { duration: 150 } }

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
                        border.color: isWizFocused(0) ? ThemeManager.getColor("focus") : "transparent"
                        border.width: isWizFocused(0) ? 3 : 0
                        Behavior on border.color { ColorAnimation { duration: 150 } }

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
                border.color: isBrowserBtnFocused() ? ThemeManager.getColor("focus") : Qt.rgba(1, 1, 1, 0.15)
                border.width: isBrowserBtnFocused() ? 3 : 1
                Behavior on border.color { ColorAnimation { duration: 150 } }

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
            // Prevent WebEngineView from stealing focus so the wizard's
            // key handler keeps working for non-browser steps.
            settings.focusOnNavigationEnabled: false

            onLoadingChanged: function(loadRequest) {
                console.log("[wizard-browser] loadingChanged:",
                            loadRequest.status === WebEngineView.LoadSucceededStatus ? "SUCCESS" :
                            loadRequest.status === WebEngineView.LoadFailedStatus ? "FAILED" :
                            "status=" + loadRequest.status,
                            "url:", loadRequest.url)
                if (loadRequest.status === WebEngineView.LoadSucceededStatus) {
                    apiKeyPollTimer.start()
                    // Inject the controller navigation overlay after a short
                    // delay so the DOM is fully ready (Steam pages load JS
                    // that creates elements after DOMContentLoaded).
                    navInjectTimer.restart()
                }
            }
            onJavaScriptConsoleMessage: function(level, message, lineNumber, sourceID) {
                console.log("[wizard-browser-js]", message)
            }
        }

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
                            wizard.overlayFocusIdx = 0
                        }
                    }
                )
            }
        }

        // Inject the controller navigation overlay after page load.
        // A short delay ensures Steam's JS has finished creating DOM
        // elements (login forms, buttons, etc.) before we scan.
        Timer {
            id: navInjectTimer
            interval: 800
            repeat: false
            onTriggered: {
                console.log("[wizard-browser] injecting navigation overlay")
                apiKeyWebView.runJavaScript(wizard.navOverlayScript,
                    function(result) {
                        console.log("[wizard-browser] nav inject result:", result)
                    })
            }
        }
    }

    // ── API Key confirmation overlay ──
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
                        border.color: isOverlayFocused(0) ? ThemeManager.getColor("focus") : "transparent"
                        border.width: isOverlayFocused(0) ? 3 : 0
                        Behavior on border.color { ColorAnimation { duration: 150 } }

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
                        border.color: isOverlayFocused(1) ? ThemeManager.getColor("focus") : Qt.rgba(1, 1, 1, 0.15)
                        border.width: isOverlayFocused(1) ? 3 : 1
                        Behavior on border.color { ColorAnimation { duration: 150 } }

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

    // ─── Virtual Keyboard for Wizard Text Inputs ───
    VirtualKeyboard {
        id: wizardVirtualKeyboard
        anchors.fill: parent

        onAccepted: function(typedText) {
            // Route typed text to the correct input based on current state
            if (wizard.browserInputActive) {
                // Send text back into the embedded browser's focused input
                wizard.browserInputActive = false
                var escaped = typedText.replace(/\\/g, '\\\\').replace(/'/g, "\\'")
                apiKeyWebView.runJavaScript(
                    "window.__lunaNav && window.__lunaNav.setText('" + escaped + "')",
                    function(result) {
                        console.log("[wizard-browser] setText result:", result)
                    })
            } else if (wizard.currentStep === 2 && wizard.showManualInput) {
                manualKeyInput.text = typedText
                if (typedText.trim().length >= 20) {
                    GameManager.setSteamApiKey(typedText.trim())
                    wizard.currentStep = 3
                }
            } else if (wizard.currentStep === 3 && wizard.steamCmdPromptType === "password") {
                setupCredInput.text = typedText
                if (typedText.length > 0) {
                    GameManager.provideSteamCmdSetupCredential(typedText)
                    setupCredInput.text = ""
                    wizard.steamCmdPromptType = ""
                    wizard.steamCmdAwaitingGuard = true
                    wizard.steamCmdWaiting = false
                }
            } else if (wizard.currentStep === 3 && wizard.steamCmdPromptType === "steamguard") {
                guardCodeInput.text = typedText
                if (typedText.length > 0) {
                    GameManager.provideSteamCmdSetupCredential(typedText)
                    guardCodeInput.text = ""
                    wizard.steamCmdPromptType = ""
                    wizard.steamCmdWaiting = true
                    wizard.steamCmdVerifyingGuard = true
                }
            }
            wizard.forceActiveFocus()
        }

        onCancelled: {
            wizard.browserInputActive = false
            wizard.forceActiveFocus()
        }
    }
}
