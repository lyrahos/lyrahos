#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QTimer>
#include <QtWebEngineQuick>
#include "thememanager.h"
#include "gamemanager.h"
#include "database.h"
#include "controllermanager.h"
#include "artworkmanager.h"
#include "storeapimanager.h"
#include "browserbridge.h"

int main(int argc, char *argv[]) {
    // Must be called before QGuiApplication for WebEngineView to work
    QtWebEngineQuick::initialize();

    QGuiApplication app(argc, argv);
    app.setApplicationName("Luna UI");
    app.setOrganizationName("Lyrah OS");

    Database db;
    if (!db.initialize()) {
        qCritical() << "Failed to initialize database!";
        return 1;
    }

    ThemeManager themeManager;
    GameManager gameManager(&db);
    ControllerManager controllerManager;
    controllerManager.initialize();
    controllerManager.setDatabase(&db);
    ArtworkManager artworkManager;
    StoreApiManager storeApiManager;
    BrowserBridge browserBridge;

    // Connect GameManager browser signals to BrowserBridge
    QObject::connect(&gameManager, &GameManager::browserOpened, [&]() {
        browserBridge.setActive(true);
        browserBridge.connectToBrowser();
    });
    QObject::connect(&gameManager, &GameManager::browserClosed, [&]() {
        browserBridge.setActive(false);
        browserBridge.disconnect();
    });

    // Route controller actions directly to BrowserBridge.
    // When the browser is in the foreground, Luna-UI loses window focus
    // and QGuiApplication::focusObject() returns null, so synthetic key
    // events are dropped.  actionTriggered fires regardless of window
    // focus, so BrowserBridge can handle navigation via CDP.
    QObject::connect(&controllerManager, &ControllerManager::actionTriggered,
                     &browserBridge, &BrowserBridge::handleAction);

    // When BrowserBridge needs the VirtualKeyboard, raise Luna-UI's window
    QObject::connect(&browserBridge, &BrowserBridge::raiseRequested,
                     &gameManager, &GameManager::raiseLunaWindow);

    // When BrowserBridge detects the browser closed (e.g. system_menu),
    // close the browser process and raise Luna-UI
    QObject::connect(&browserBridge, &BrowserBridge::browserClosed, [&]() {
        browserBridge.setActive(false);
        browserBridge.disconnect();
        gameManager.raiseLunaWindow();
        gameManager.closeApiKeyBrowser();
    });

    QQmlApplicationEngine engine;
    engine.rootContext()->setContextProperty("ThemeManager", &themeManager);
    engine.rootContext()->setContextProperty("GameManager", &gameManager);
    engine.rootContext()->setContextProperty("ControllerManager", &controllerManager);
    engine.rootContext()->setContextProperty("ProfileResolver", controllerManager.profileResolver());
    engine.rootContext()->setContextProperty("ArtworkManager", &artworkManager);
    engine.rootContext()->setContextProperty("StoreApi", &storeApiManager);
    engine.rootContext()->setContextProperty("BrowserBridge", &browserBridge);

    // RESOURCE_PREFIX / in CMakeLists.txt places QML files at :/LunaUI/...
    engine.load(QUrl(QStringLiteral("qrc:/LunaUI/qml/Main.qml")));

    if (engine.rootObjects().isEmpty())
        return -1;

    // Poll controller input at 60Hz
    QTimer controllerTimer;
    QObject::connect(&controllerTimer, &QTimer::timeout, [&]() {
        controllerManager.pollEvents();
    });
    controllerTimer.start(16); // ~60fps

    // Initial game library scan (background)
    QTimer::singleShot(500, [&]() {
        gameManager.scanAllStores();
    });

    return app.exec();
}
