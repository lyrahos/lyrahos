#include "browserbridge.h"
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QNetworkReply>
#include <QDebug>
#include <QDateTime>
#include <QTextStream>

// ── Constructor / Destructor ─────────────────────────────────────────

BrowserBridge::BrowserBridge(QObject *parent) : QObject(parent) {
    connect(&m_ws, &QWebSocket::connected,    this, &BrowserBridge::onWsConnected);
    connect(&m_ws, &QWebSocket::disconnected, this, &BrowserBridge::onWsDisconnected);
    connect(&m_ws, &QWebSocket::textMessageReceived,
            this, &BrowserBridge::onWsTextMessage);
    connect(&m_ws, &QWebSocket::errorOccurred, this, &BrowserBridge::onWsError);

    m_connectTimer.setSingleShot(true);
    connect(&m_connectTimer, &QTimer::timeout, this, &BrowserBridge::attemptConnection);
}

BrowserBridge::~BrowserBridge() {
    disconnect();
}

void BrowserBridge::diag(const QString &msg) {
    qDebug() << "BrowserBridge:" << msg;
    m_diagnostics = msg;
    emit diagnosticsChanged();

    // Append to log file so diagnostics survive even if the overlay isn't visible
    if (m_diagLog.isOpen()) {
        QTextStream out(&m_diagLog);
        out << QDateTime::currentDateTime().toString("hh:mm:ss.zzz") << "  " << msg << "\n";
        out.flush();
    }
}

void BrowserBridge::updateBrowserDiagOverlay() {
    if (!m_connected) return;
    // Inject/update a small diagnostic panel inside the browser page itself
    QString js = QStringLiteral(R"JS(
(function() {
    var d = document.getElementById('__luna-diag');
    if (!d) {
        d = document.createElement('div');
        d.id = '__luna-diag';
        d.style.cssText =
            'position:fixed; bottom:12px; left:12px; z-index:999998; '
            + 'background:rgba(0,0,0,0.88); color:#e67e22; font:13px/1.5 monospace; '
            + 'padding:10px 14px; border-radius:10px; pointer-events:none; '
            + 'border:1px solid #e67e22; max-width:500px; white-space:pre-wrap;';
        document.documentElement.appendChild(d);
    }
    d.textContent = %1;
})();
)JS");

    QString status = QString(
        "Luna BrowserBridge Diag\\n"
        "active: %1  connected: %2\\n"
        "actions in: %3  dispatched: %4\\n"
        "cdp sent: %5  errors: %6\\n"
        "last: %7")
        .arg(m_active ? "true" : "false")
        .arg(m_connected ? "true" : "false")
        .arg(m_actionsReceived)
        .arg(m_actionsDispatched)
        .arg(m_cdpCommandsSent)
        .arg(m_cdpErrors)
        .arg(QString(m_diagnostics).replace("'", "\\'").replace("\n", "\\n"));

    sendCdpCommand("Runtime.evaluate", {
        {"expression", js.arg(QString("'%1'").arg(status))}
    });
}

// ── Public API ───────────────────────────────────────────────────────

void BrowserBridge::connectToBrowser() {
    m_connectAttempts = 0;
    m_injected = false;
    m_actionsReceived = 0;
    m_actionsDispatched = 0;
    m_cdpCommandsSent = 0;
    m_cdpErrors = 0;

    // Open (or reopen) the diagnostic log file
    if (m_diagLog.isOpen()) m_diagLog.close();
    m_diagLog.setFileName("/tmp/luna-browserbridge-diag.log");
    m_diagLog.open(QIODevice::WriteOnly | QIODevice::Truncate | QIODevice::Text);

    diag("connectToBrowser() called — starting CDP discovery");
    attemptConnection();
}

void BrowserBridge::disconnect() {
    diag("disconnect() called");
    m_connectTimer.stop();
    if (m_ws.state() != QAbstractSocket::UnconnectedState) {
        m_ws.close();
    }
    if (m_connected) {
        m_connected = false;
        emit connectedChanged();
    }
    if (m_textFieldFocused) {
        m_textFieldFocused = false;
        emit textFieldFocusedChanged();
    }
    m_injected = false;
    if (m_diagLog.isOpen()) m_diagLog.close();
}

void BrowserBridge::setActive(bool active) {
    if (m_active == active) return;
    m_active = active;
    diag(QString("setActive(%1)").arg(active ? "true" : "false"));
    emit activeChanged();
}

void BrowserBridge::navigate(const QString &direction) {
    if (!m_connected) return;
    QString js = QString("window.__lunaNav && window.__lunaNav.move('%1')").arg(direction);
    sendCdpCommand("Runtime.evaluate", {{"expression", js}});
}

void BrowserBridge::confirmElement() {
    if (!m_connected) return;
    sendCdpCommand("Runtime.evaluate",
        {{"expression", "window.__lunaNav && window.__lunaNav.activate()"}});
}

void BrowserBridge::goBack() {
    if (!m_connected) return;
    sendCdpCommand("Runtime.evaluate",
        {{"expression", "window.history.back()"}});
}

void BrowserBridge::scrollPage(const QString &direction) {
    if (!m_connected) return;
    int amount = (direction == "up") ? -400 : 400;
    QString js = QString("window.scrollBy(0, %1)").arg(amount);
    sendCdpCommand("Runtime.evaluate", {{"expression", js}});
}

void BrowserBridge::sendText(const QString &text) {
    if (!m_connected) return;
    // Escape the text for JS string embedding
    QString escaped = text;
    escaped.replace("\\", "\\\\");
    escaped.replace("'", "\\'");
    escaped.replace("\n", "\\n");
    QString js = QString("window.__lunaNav && window.__lunaNav.setText('%1')").arg(escaped);
    sendCdpCommand("Runtime.evaluate", {{"expression", js}});
}

void BrowserBridge::clearTextField() {
    if (!m_connected) return;
    sendCdpCommand("Runtime.evaluate",
        {{"expression", "window.__lunaNav && window.__lunaNav.setText('')"}});
}

// ── Direct Action Handling ────────────────────────────────────────────
// When the browser has window focus, Luna-UI's QML focus system can't
// receive synthetic key events (focusObject() is null).  This slot
// receives actions directly from ControllerManager::actionTriggered,
// which fires regardless of window focus.

void BrowserBridge::handleAction(const QString &action) {
    m_actionsReceived++;

    if (!m_active) {
        // Only log the first few to avoid flooding
        if (m_actionsReceived <= 5)
            diag(QString("DROPPED action '%1': bridge not active").arg(action));
        emit diagnosticsChanged();
        return;
    }
    if (!m_connected) {
        if (m_actionsReceived <= 20)
            diag(QString("DROPPED action '%1': CDP not connected (attempt %2)")
                .arg(action).arg(m_connectAttempts));
        emit diagnosticsChanged();
        return;
    }

    // When VirtualKeyboard is showing (text field focused + Luna-UI raised),
    // let the normal QML key handlers drive the VK.  Only intercept
    // system_menu to allow closing the browser from VK mode.
    if (m_textFieldFocused) {
        if (action == "system_menu") emit browserClosed();
        return;
    }

    m_actionsDispatched++;
    emit diagnosticsChanged();

    // Update the in-browser diagnostic overlay periodically
    if (m_actionsDispatched % 10 == 1) updateBrowserDiagOverlay();

    if (action == "navigate_up")         navigate("up");
    else if (action == "navigate_down")  navigate("down");
    else if (action == "navigate_left")  navigate("left");
    else if (action == "navigate_right") navigate("right");
    else if (action == "confirm")        confirmElement();
    else if (action == "back")           goBack();
    else if (action == "scroll_up")      scrollPage("up");
    else if (action == "scroll_down")    scrollPage("down");
    else if (action == "system_menu") {
        emit browserClosed();
    }
}

// ── Connection Logic ─────────────────────────────────────────────────

void BrowserBridge::attemptConnection() {
    if (m_connected) return;
    if (!m_active) return;
    if (m_connectAttempts >= 30) {
        diag("GAVE UP connecting after 30 attempts");
        return;
    }
    m_connectAttempts++;
    diag(QString("CDP connection attempt %1/30").arg(m_connectAttempts));
    discoverTarget();
}

void BrowserBridge::discoverTarget() {
    // GET http://127.0.0.1:9222/json to discover debuggable tabs
    QNetworkReply *reply = m_nam.get(
        QNetworkRequest(QUrl("http://127.0.0.1:9222/json")));

    connect(reply, &QNetworkReply::finished, this, [this, reply]() {
        reply->deleteLater();
        if (reply->error() != QNetworkReply::NoError) {
            diag(QString("CDP endpoint not ready: %1").arg(reply->errorString()));
            m_connectTimer.start(2000);
            return;
        }

        QJsonArray tabs = QJsonDocument::fromJson(reply->readAll()).array();
        if (tabs.isEmpty()) {
            m_connectTimer.start(2000);
            return;
        }

        // Find the first "page" type tab
        QString wsUrl;
        for (const QJsonValue &v : tabs) {
            QJsonObject tab = v.toObject();
            if (tab["type"].toString() == "page") {
                wsUrl = tab["webSocketDebuggerUrl"].toString();
                break;
            }
        }
        if (wsUrl.isEmpty() && !tabs.isEmpty()) {
            wsUrl = tabs[0].toObject()["webSocketDebuggerUrl"].toString();
        }

        if (wsUrl.isEmpty()) {
            diag("No WebSocket URL in CDP response, retrying...");
            m_connectTimer.start(2000);
            return;
        }

        diag(QString("Found CDP target, connecting WS: %1").arg(wsUrl));
        m_wsUrl = wsUrl;
        m_ws.open(QUrl(wsUrl));
    });
}

// ── WebSocket Callbacks ──────────────────────────────────────────────

void BrowserBridge::onWsConnected() {
    m_connected = true;
    m_connectAttempts = 0;
    diag("WebSocket connected — enabling Runtime + injecting script");
    emit connectedChanged();

    // Enable Runtime domain to receive console messages from injected JS
    sendCdpCommand("Runtime.enable");

    // Inject the navigation overlay script
    injectNavigationScript();

    // Show diagnostic overlay inside the browser page after a short delay
    // (gives the nav script time to execute first)
    QTimer::singleShot(1000, this, [this]() {
        if (m_connected) updateBrowserDiagOverlay();
    });
}

void BrowserBridge::onWsDisconnected() {
    bool wasConnected = m_connected;
    diag(QString("WebSocket disconnected (wasConnected=%1)").arg(wasConnected));
    m_connected = false;
    m_injected = false;
    if (m_textFieldFocused) {
        m_textFieldFocused = false;
        emit textFieldFocusedChanged();
    }
    if (wasConnected) {
        emit connectedChanged();
        // Only signal browser closed if we actually had a working session.
        // A disconnect during the handshake phase is just a retry, not a
        // reason to tear down the browser.
        emit browserClosed();
    } else if (m_active) {
        // Handshake failed (e.g. Chromium rejected the WS upgrade).
        // Retry from target discovery.
        diag("WS handshake failed, retrying discovery...");
        m_connectTimer.start(2000);
    }
}

void BrowserBridge::onWsError(QAbstractSocket::SocketError error) {
    diag(QString("WebSocket error: %1 — %2").arg(error).arg(m_ws.errorString()));
    if (!m_connected && m_active) {
        // Retry from target discovery — the WS URL itself may have changed
        // if the browser reloaded or Chromium rejected the handshake (403).
        m_connectTimer.start(2000);
    }
}

void BrowserBridge::onWsTextMessage(const QString &message) {
    QJsonObject msg = QJsonDocument::fromJson(message.toUtf8()).object();

    if (msg.contains("id")) {
        // CDP response to a command we sent
        handleCdpResult(msg["id"].toInt(), msg["result"].toObject());
    } else if (msg.contains("method")) {
        // CDP event
        handleCdpEvent(msg);
    }
}

// ── CDP Communication ────────────────────────────────────────────────

int BrowserBridge::sendCdpCommand(const QString &method, const QJsonObject &params) {
    int id = m_cdpId++;
    QJsonObject msg;
    msg["id"] = id;
    msg["method"] = method;
    if (!params.isEmpty()) {
        msg["params"] = params;
    }
    m_cdpCommandsSent++;
    m_ws.sendTextMessage(QJsonDocument(msg).toJson(QJsonDocument::Compact));
    return id;
}

void BrowserBridge::handleCdpResult(int id, const QJsonObject &result) {
    // Check for CDP-level exceptions (script errors, etc.)
    if (result.contains("exceptionDetails")) {
        QJsonObject ex = result["exceptionDetails"].toObject();
        QString text = ex["text"].toString();
        if (text.isEmpty()) {
            QJsonObject exObj = ex["exception"].toObject();
            text = exObj["description"].toString();
        }
        m_cdpErrors++;
        diag(QString("CDP error (id %1): %2").arg(id).arg(text));
    }
}

void BrowserBridge::handleCdpEvent(const QJsonObject &msg) {
    QString method = msg["method"].toString();
    QJsonObject params = msg["params"].toObject();

    // Listen for console messages from our injected script
    if (method == "Runtime.consoleAPICalled") {
        QJsonArray args = params["args"].toArray();
        if (args.isEmpty()) return;

        QString text = args[0].toObject()["value"].toString();
        if (text.startsWith("__luna:")) {
            QString payload = text.mid(7); // skip "__luna:"
            QJsonObject data = QJsonDocument::fromJson(payload.toUtf8()).object();
            QString event = data["event"].toString();

            if (event == "ready") {
                int count = data["count"].toInt();
                diag(QString("Script injected OK — %1 interactive elements found").arg(count));
                updateBrowserDiagOverlay();
            } else if (event == "textFocus") {
                bool wasFocused = m_textFieldFocused;
                m_textFieldFocused = true;
                if (!wasFocused) emit textFieldFocusedChanged();
                // Raise Luna-UI's window so the VirtualKeyboard is visible
                emit raiseRequested();
                emit textInputRequested(
                    data["value"].toString(),
                    data["isPassword"].toBool());
            } else if (event == "textBlur") {
                if (m_textFieldFocused) {
                    m_textFieldFocused = false;
                    emit textFieldFocusedChanged();
                }
            }
        }
    }

    // Re-inject script on navigation (new page load)
    if (method == "Runtime.executionContextCreated" ||
        method == "Runtime.executionContextsCleared") {
        m_injected = false;
        // Small delay so the DOM is ready
        QTimer::singleShot(500, this, [this]() {
            if (m_connected && !m_injected) {
                injectNavigationScript();
            }
        });
    }
}

// ── Script Injection ─────────────────────────────────────────────────

void BrowserBridge::injectNavigationScript() {
    if (m_injected) return;
    m_injected = true;
    diag("Injecting navigation script...");
    sendCdpCommand("Runtime.evaluate", {
        {"expression", navigationScript()},
        {"allowUnsafeEvalBlockedByCSP", true}
    });
}

// ── Navigation JavaScript ────────────────────────────────────────────
// This script is injected into the browser page.  It builds a list of
// all interactive elements, draws a visible highlight ring around the
// currently focused one, and exposes window.__lunaNav for the C++
// bridge to call move() / activate() / setText().

QString BrowserBridge::navigationScript() {
    return QStringLiteral(R"JS(
(function() {
    if (window.__lunaNav) return;

    var nav = {};
    var currentIndex = 0;
    var elements = [];
    var highlightEl = null;

    // Selectors for interactive elements
    var SELECTORS = 'a[href], button, input, select, textarea, '
        + '[role="button"], [role="link"], [role="menuitem"], '
        + '[tabindex]:not([tabindex="-1"]), [onclick]';

    function isVisible(el) {
        if (!el || !el.getBoundingClientRect) return false;
        var r = el.getBoundingClientRect();
        if (r.width === 0 || r.height === 0) return false;
        var style = window.getComputedStyle(el);
        return style.display !== 'none'
            && style.visibility !== 'hidden'
            && style.opacity !== '0';
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
        if (elements.length === 0) {
            highlightEl.style.display = 'none';
            return;
        }
        var el = elements[currentIndex];
        if (!el) return;
        var r = el.getBoundingClientRect();
        highlightEl.style.left   = (r.left - 4) + 'px';
        highlightEl.style.top    = (r.top - 4)  + 'px';
        highlightEl.style.width  = (r.width + 8) + 'px';
        highlightEl.style.height = (r.height + 8) + 'px';
        highlightEl.style.display = 'block';

        // Scroll element into view if needed
        el.scrollIntoView({ block: 'nearest', behavior: 'smooth' });
    }

    // Spatial navigation: find the nearest element in the given direction
    function findNearest(direction) {
        if (elements.length < 2) return currentIndex;
        var cur = elements[currentIndex];
        if (!cur) return currentIndex;
        var cr = cur.getBoundingClientRect();
        var cx = cr.left + cr.width / 2;
        var cy = cr.top + cr.height / 2;

        var bestIdx = -1;
        var bestDist = Infinity;

        for (var i = 0; i < elements.length; i++) {
            if (i === currentIndex) continue;
            var er = elements[i].getBoundingClientRect();
            var ex = er.left + er.width / 2;
            var ey = er.top + er.height / 2;

            var dx = ex - cx;
            var dy = ey - cy;

            var inDirection = false;
            switch (direction) {
                case 'up':    inDirection = dy < -10; break;
                case 'down':  inDirection = dy > 10;  break;
                case 'left':  inDirection = dx < -10; break;
                case 'right': inDirection = dx > 10;  break;
            }
            if (!inDirection) continue;

            // Weighted distance: primary axis matters more
            var dist;
            if (direction === 'up' || direction === 'down') {
                dist = Math.abs(dy) + Math.abs(dx) * 2;
            } else {
                dist = Math.abs(dx) + Math.abs(dy) * 2;
            }

            if (dist < bestDist) {
                bestDist = dist;
                bestIdx = i;
            }
        }

        return bestIdx >= 0 ? bestIdx : currentIndex;
    }

    nav.move = function(direction) {
        scanElements();
        if (elements.length === 0) return;
        currentIndex = findNearest(direction);
        updateHighlight();
    };

    nav.activate = function() {
        scanElements();
        if (elements.length === 0) return;
        var el = elements[currentIndex];
        if (!el) return;

        var tag = el.tagName.toLowerCase();
        var type = (el.getAttribute('type') || '').toLowerCase();

        // Text inputs: signal Luna-UI to open VirtualKeyboard
        if (tag === 'input' && ['text','password','email','search','url','tel','number',''].indexOf(type) >= 0
            || tag === 'textarea') {
            el.focus();
            var isPassword = (type === 'password');
            console.log('__luna:' + JSON.stringify({
                event: 'textFocus',
                value: el.value || '',
                isPassword: isPassword
            }));
            return;
        }

        // Everything else: click it
        el.click();
        el.focus();
    };

    nav.setText = function(text) {
        var el = document.activeElement;
        if (!el) return;
        var tag = el.tagName.toLowerCase();
        if (tag === 'input' || tag === 'textarea') {
            // Use native setter to trigger React/Vue/Angular change detection
            var nativeSetter = Object.getOwnPropertyDescriptor(
                window.HTMLInputElement.prototype, 'value'
            ) || Object.getOwnPropertyDescriptor(
                window.HTMLTextAreaElement.prototype, 'value'
            );
            if (nativeSetter && nativeSetter.set) {
                nativeSetter.set.call(el, text);
            } else {
                el.value = text;
            }
            el.dispatchEvent(new Event('input', { bubbles: true }));
            el.dispatchEvent(new Event('change', { bubbles: true }));
        }
    };

    // Watch for focus/blur on text fields (mouse clicks, autofocus, etc.)
    document.addEventListener('focusin', function(e) {
        var tag = e.target.tagName.toLowerCase();
        var type = (e.target.getAttribute('type') || '').toLowerCase();
        if (tag === 'input' && ['text','password','email','search','url','tel','number',''].indexOf(type) >= 0
            || tag === 'textarea') {
            console.log('__luna:' + JSON.stringify({
                event: 'textFocus',
                value: e.target.value || '',
                isPassword: type === 'password'
            }));
        }
    }, true);

    document.addEventListener('focusout', function(e) {
        var tag = e.target.tagName.toLowerCase();
        if (tag === 'input' || tag === 'textarea') {
            console.log('__luna:' + JSON.stringify({ event: 'textBlur' }));
        }
    }, true);

    // Initial scan
    scanElements();
    if (elements.length > 0) updateHighlight();

    window.__lunaNav = nav;
    console.log('__luna:' + JSON.stringify({ event: 'ready', count: elements.length }));
})();
)JS");
}
