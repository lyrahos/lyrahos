#ifndef BROWSERBRIDGE_H
#define BROWSERBRIDGE_H

#include <QObject>
#include <QWebSocket>
#include <QNetworkAccessManager>
#include <QTimer>

// BrowserBridge — connects to a Chromium-based browser via the Chrome
// DevTools Protocol (CDP) on localhost:9222.  It injects a JavaScript
// navigation overlay that lets a game controller highlight & click
// interactive elements, and detects text-field focus so Luna-UI can
// show its VirtualKeyboard.

class BrowserBridge : public QObject {
    Q_OBJECT
    Q_PROPERTY(bool connected READ isConnected NOTIFY connectedChanged)
    Q_PROPERTY(bool textFieldFocused READ isTextFieldFocused NOTIFY textFieldFocusedChanged)
    Q_PROPERTY(bool active READ isActive NOTIFY activeChanged)

public:
    explicit BrowserBridge(QObject *parent = nullptr);
    ~BrowserBridge();

    bool isConnected() const { return m_connected; }
    bool isTextFieldFocused() const { return m_textFieldFocused; }
    bool isActive() const { return m_active; }

    // Start trying to connect to the browser's CDP endpoint
    Q_INVOKABLE void connectToBrowser();
    // Disconnect and clean up
    Q_INVOKABLE void disconnect();

    // Navigation commands — called from QML when controller input arrives
    Q_INVOKABLE void navigate(const QString &direction); // "up","down","left","right"
    Q_INVOKABLE void confirmElement();   // "click" the focused element
    Q_INVOKABLE void goBack();           // browser back
    Q_INVOKABLE void scrollPage(const QString &direction); // "up" or "down"

    // Send text from VirtualKeyboard into the focused text field
    Q_INVOKABLE void sendText(const QString &text);
    // Clear the text field contents
    Q_INVOKABLE void clearTextField();

    // Mark the bridge as active/inactive (browser is in foreground)
    Q_INVOKABLE void setActive(bool active);

signals:
    void connectedChanged();
    void textFieldFocusedChanged();
    void activeChanged();
    // Emitted when the injected JS reports a text field was focused
    void textInputRequested(const QString &currentValue, bool isPassword);
    // Emitted when the browser page navigated away or closed
    void browserClosed();

private slots:
    void onWsConnected();
    void onWsDisconnected();
    void onWsTextMessage(const QString &message);
    void onWsError(QAbstractSocket::SocketError error);
    void attemptConnection();

private:
    QWebSocket m_ws;
    QNetworkAccessManager m_nam;
    QTimer m_connectTimer;
    int m_connectAttempts = 0;
    int m_cdpId = 1;         // incrementing CDP message id
    bool m_connected = false;
    bool m_textFieldFocused = false;
    bool m_active = false;
    bool m_injected = false;
    QString m_wsUrl;          // ws://127.0.0.1:9222/devtools/page/<id>

    void discoverTarget();
    void injectNavigationScript();
    int sendCdpCommand(const QString &method, const QJsonObject &params = {});
    void handleCdpEvent(const QJsonObject &msg);
    void handleCdpResult(int id, const QJsonObject &result);

    // The JavaScript code injected into the browser page
    static QString navigationScript();
};

#endif // BROWSERBRIDGE_H
