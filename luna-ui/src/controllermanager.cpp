#include "controllermanager.h"
#include "database.h"
#include <QDebug>

// ── Legacy signal dispatch table ─────────────────────────────────────

QHash<QString, void(ControllerManager::*)()> ControllerManager::s_legacySignals = ControllerManager::initLegacySignals();

QHash<QString, void(ControllerManager::*)()> ControllerManager::initLegacySignals() {
    QHash<QString, void(ControllerManager::*)()> map;
    map["confirm"]        = &ControllerManager::confirmPressed;
    map["back"]           = &ControllerManager::backPressed;
    map["quick_action"]   = &ControllerManager::quickActionPressed;
    map["search"]         = &ControllerManager::searchPressed;
    map["settings"]       = &ControllerManager::settingsPressed;
    map["system_menu"]    = &ControllerManager::systemMenuPressed;
    map["navigate_up"]    = &ControllerManager::navigateUp;
    map["navigate_down"]  = &ControllerManager::navigateDown;
    map["navigate_left"]  = &ControllerManager::navigateLeft;
    map["navigate_right"] = &ControllerManager::navigateRight;
    map["previous_tab"]   = &ControllerManager::previousTab;
    map["next_tab"]       = &ControllerManager::nextTab;
    map["filters"]        = &ControllerManager::filtersPressed;
    map["sort"]           = &ControllerManager::sortPressed;
    map["scroll_up"]      = &ControllerManager::scrollUp;
    map["scroll_down"]    = &ControllerManager::scrollDown;
    return map;
}

// ── Constructor / Destructor ─────────────────────────────────────────

ControllerManager::ControllerManager(QObject *parent) : QObject(parent) {
    m_axisNavCooldown.start();
    m_triggerCooldown.start();
}

ControllerManager::~ControllerManager() {
    if (m_controller) {
        SDL_GameControllerClose(m_controller);
    }
    SDL_Quit();
}

// ── Initialization ───────────────────────────────────────────────────

void ControllerManager::initialize() {
    SDL_Init(SDL_INIT_GAMECONTROLLER);
    SDL_GameControllerAddMappingsFromFile("/usr/share/luna-ui/gamecontrollerdb.txt");
    detectControllers();
}

void ControllerManager::setDatabase(Database *db) {
    m_profileResolver.setDatabase(db->db());
    m_profileResolver.createTables();
    m_profileResolver.seedDefaults();
    // Load initial profiles with current family
    m_profileResolver.setContext(QString(), 0, m_detectedFamily);
}

// ── Controller Detection ─────────────────────────────────────────────

void ControllerManager::detectControllers() {
    for (int i = 0; i < SDL_NumJoysticks(); ++i) {
        if (SDL_IsGameController(i)) {
            m_controller = SDL_GameControllerOpen(i);
            if (m_controller) {
                qDebug() << "Controller connected:" << SDL_GameControllerName(m_controller);

                // Detect controller family
                ControllerFamily newFamily = detectFamily(m_controller);
                if (newFamily != m_detectedFamily) {
                    m_detectedFamily = newFamily;
                    m_profileResolver.setControllerFamily(m_detectedFamily);
                    emit controllerFamilyChanged();
                }

                emit controllerChanged();
                break;
            }
        }
    }
}

ControllerFamily ControllerManager::detectFamily(SDL_GameController *controller) {
    SDL_GameControllerType type = SDL_GameControllerGetType(controller);
    switch (type) {
    case SDL_CONTROLLER_TYPE_XBOX360:
    case SDL_CONTROLLER_TYPE_XBOXONE:
        return ControllerFamily::Xbox;

    case SDL_CONTROLLER_TYPE_PS3:
    case SDL_CONTROLLER_TYPE_PS4:
    case SDL_CONTROLLER_TYPE_PS5:
        return ControllerFamily::PlayStation;

    case SDL_CONTROLLER_TYPE_NINTENDO_SWITCH_PRO:
    case SDL_CONTROLLER_TYPE_NINTENDO_SWITCH_JOYCON_LEFT:
    case SDL_CONTROLLER_TYPE_NINTENDO_SWITCH_JOYCON_PAIR:
    case SDL_CONTROLLER_TYPE_NINTENDO_SWITCH_JOYCON_RIGHT:
        return ControllerFamily::Switch;

    case SDL_CONTROLLER_TYPE_AMAZON_LUNA:
        return ControllerFamily::Luna;

    default:
        // Check name for additional hints
        const char *name = SDL_GameControllerName(controller);
        if (name) {
            QString nameStr = QString::fromUtf8(name).toLower();
            if (nameStr.contains("xbox") || nameStr.contains("xinput"))
                return ControllerFamily::Xbox;
            if (nameStr.contains("playstation") || nameStr.contains("dualshock") || nameStr.contains("dualsense"))
                return ControllerFamily::PlayStation;
            if (nameStr.contains("nintendo") || nameStr.contains("switch") || nameStr.contains("pro controller"))
                return ControllerFamily::Switch;
            if (nameStr.contains("luna"))
                return ControllerFamily::Luna;
        }
        return ControllerFamily::Generic;
    }
}

// ── Event Polling ────────────────────────────────────────────────────

void ControllerManager::pollEvents() {
    SDL_Event event;
    while (SDL_PollEvent(&event)) {
        switch (event.type) {
        case SDL_CONTROLLERBUTTONDOWN:
            handleButtonPress((SDL_GameControllerButton)event.cbutton.button);
            break;
        case SDL_CONTROLLERAXISMOTION:
            handleAxisMotion((SDL_GameControllerAxis)event.caxis.axis, event.caxis.value);
            break;
        case SDL_CONTROLLERDEVICEADDED:
            detectControllers();
            break;
        case SDL_CONTROLLERDEVICEREMOVED:
            if (m_controller) {
                SDL_GameControllerClose(m_controller);
                m_controller = nullptr;
                emit controllerChanged();
            }
            break;
        }
    }
}

// ── Input Handling ───────────────────────────────────────────────────

void ControllerManager::handleButtonPress(SDL_GameControllerButton button) {
    QString physicalInput = ProfileResolver::sdlButtonToPositional(button);
    if (physicalInput.isEmpty()) return;

    // Listening mode — capture the input for remapping UI
    if (m_listening) {
        emit inputCaptured(physicalInput);
        return;
    }

    // Normal mode — resolve through profile cascade
    QString action = m_profileResolver.resolveAction(physicalInput);
    if (!action.isEmpty()) {
        dispatchAction(action);
    } else if (physicalInput == "stick_left_click") {
        // L3 with no profile mapping → send CapsLock for virtual keyboard
        sendSyntheticKey(Qt::Key_CapsLock);
    }
}

void ControllerManager::handleAxisMotion(SDL_GameControllerAxis axis, int value) {
    const int NAV_COOLDOWN_MS = 200;

    // Get configurable deadzone from profile parameters
    QString axisName = ProfileResolver::sdlAxisToPositional(axis);
    QJsonObject params = m_profileResolver.resolveParameters(axisName);
    int deadzone = params.value("deadzone").toInt(8000);
    int threshold = params.value("threshold").toInt(8000);

    // Left stick → directional inputs
    if (axis == SDL_CONTROLLER_AXIS_LEFTY || axis == SDL_CONTROLLER_AXIS_LEFTX) {
        if (m_axisNavCooldown.elapsed() < NAV_COOLDOWN_MS) return;

        QString physicalInput;
        if (axis == SDL_CONTROLLER_AXIS_LEFTY) {
            if (value < -deadzone) physicalInput = "stick_left_up";
            else if (value > deadzone) physicalInput = "stick_left_down";
        } else {
            if (value < -deadzone) physicalInput = "stick_left_left";
            else if (value > deadzone) physicalInput = "stick_left_right";
        }

        if (!physicalInput.isEmpty()) {
            if (m_listening) {
                emit inputCaptured(physicalInput);
                return;
            }
            QString action = m_profileResolver.resolveAction(physicalInput);
            if (!action.isEmpty()) {
                dispatchAction(action);
                m_axisNavCooldown.restart();
            }
        }
    }

    // Right stick → scroll inputs
    if (axis == SDL_CONTROLLER_AXIS_RIGHTY) {
        if (m_axisNavCooldown.elapsed() < NAV_COOLDOWN_MS) return;

        QString physicalInput;
        if (value < -deadzone) physicalInput = "stick_right_up";
        else if (value > deadzone) physicalInput = "stick_right_down";

        if (!physicalInput.isEmpty()) {
            if (m_listening) {
                emit inputCaptured(physicalInput);
                return;
            }
            QString action = m_profileResolver.resolveAction(physicalInput);
            if (!action.isEmpty()) {
                dispatchAction(action);
                m_axisNavCooldown.restart();
            }
        }
    }

    // Triggers
    if (axis == SDL_CONTROLLER_AXIS_TRIGGERLEFT && value > threshold) {
        if (m_triggerCooldown.elapsed() > NAV_COOLDOWN_MS) {
            QString physicalInput = "trigger_left";
            if (m_listening) {
                emit inputCaptured(physicalInput);
                return;
            }
            QString action = m_profileResolver.resolveAction(physicalInput);
            if (!action.isEmpty()) {
                dispatchAction(action);
                m_triggerCooldown.restart();
            }
        }
    }
    if (axis == SDL_CONTROLLER_AXIS_TRIGGERRIGHT && value > threshold) {
        if (m_triggerCooldown.elapsed() > NAV_COOLDOWN_MS) {
            QString physicalInput = "trigger_right";
            if (m_listening) {
                emit inputCaptured(physicalInput);
                return;
            }
            QString action = m_profileResolver.resolveAction(physicalInput);
            if (!action.isEmpty()) {
                dispatchAction(action);
                m_triggerCooldown.restart();
            }
        }
    }
}

// ── Action Dispatch ──────────────────────────────────────────────────

void ControllerManager::dispatchAction(const QString &action) {
    emit actionTriggered(action);
    emitLegacySignal(action);
    sendSyntheticKeyEvent(action);
}

void ControllerManager::emitLegacySignal(const QString &action) {
    auto it = s_legacySignals.find(action);
    if (it != s_legacySignals.end()) {
        (this->*(it.value()))();
    }
}

void ControllerManager::sendSyntheticKeyEvent(const QString &action) {
    // Map actions to Qt key events so existing QML Keys.onPressed handlers work
    static const QHash<QString, int> actionToKey = {
        {"confirm",        Qt::Key_Return},
        {"back",           Qt::Key_Escape},
        {"navigate_up",    Qt::Key_Up},
        {"navigate_down",  Qt::Key_Down},
        {"navigate_left",  Qt::Key_Left},
        {"navigate_right", Qt::Key_Right},
        {"previous_tab",   Qt::Key_BracketLeft},
        {"next_tab",       Qt::Key_BracketRight},
        {"search",         Qt::Key_F3},
        {"settings",       Qt::Key_F10},
        {"system_menu",    Qt::Key_F12},
        {"quick_action",   Qt::Key_F2},
        {"filters",        Qt::Key_F5},
        {"sort",           Qt::Key_F6},
        {"scroll_up",      Qt::Key_PageUp},
        {"scroll_down",    Qt::Key_PageDown},
    };

    auto it = actionToKey.find(action);
    if (it == actionToKey.end()) return;

    QObject *focusObj = QGuiApplication::focusObject();
    if (!focusObj) return;

    QKeyEvent pressEvent(QEvent::KeyPress, it.value(), Qt::NoModifier);
    QKeyEvent releaseEvent(QEvent::KeyRelease, it.value(), Qt::NoModifier);
    QGuiApplication::sendEvent(focusObj, &pressEvent);
    QGuiApplication::sendEvent(focusObj, &releaseEvent);
}

void ControllerManager::sendSyntheticKey(int qtKey) {
    QObject *focusObj = QGuiApplication::focusObject();
    if (!focusObj) return;
    QKeyEvent pressEvent(QEvent::KeyPress, qtKey, Qt::NoModifier);
    QKeyEvent releaseEvent(QEvent::KeyRelease, qtKey, Qt::NoModifier);
    QGuiApplication::sendEvent(focusObj, &pressEvent);
    QGuiApplication::sendEvent(focusObj, &releaseEvent);
}

// ── Context Switching ────────────────────────────────────────────────

void ControllerManager::setGameContext(const QString &clientId, int gameId) {
    m_profileResolver.setContext(clientId, gameId, m_detectedFamily);
}

void ControllerManager::clearGameContext() {
    m_profileResolver.setContext(QString(), 0, m_detectedFamily);
}

// ── Listening Mode ───────────────────────────────────────────────────

void ControllerManager::startListening() {
    m_listening = true;
    emit listeningChanged();
}

void ControllerManager::stopListening() {
    m_listening = false;
    emit listeningChanged();
}

// ── Display Helpers ──────────────────────────────────────────────────

QString ControllerManager::controllerFamilyName() const {
    return ProfileResolver::familyToString(m_detectedFamily);
}

QString ControllerManager::controllerName() const {
    if (m_controller) {
        return QString::fromUtf8(SDL_GameControllerName(m_controller));
    }
    return QString();
}

QString ControllerManager::getButtonDisplayName(const QString &physicalInput) const {
    // Display names vary by controller family
    static const QHash<QString, QHash<QString, QString>> familyNames = {
        {"xbox", {
            {"button_south", "A"}, {"button_east", "B"},
            {"button_west", "X"}, {"button_north", "Y"},
            {"shoulder_left", "LB"}, {"shoulder_right", "RB"},
            {"trigger_left", "LT"}, {"trigger_right", "RT"},
            {"button_start", "Menu"}, {"button_back", "View"},
            {"dpad_up", "D-Pad Up"}, {"dpad_down", "D-Pad Down"},
            {"dpad_left", "D-Pad Left"}, {"dpad_right", "D-Pad Right"},
            {"stick_left_up", "Left Stick Up"}, {"stick_left_down", "Left Stick Down"},
            {"stick_left_left", "Left Stick Left"}, {"stick_left_right", "Left Stick Right"},
            {"stick_right_up", "Right Stick Up"}, {"stick_right_down", "Right Stick Down"},
        }},
        {"playstation", {
            {"button_south", "\u2715"}, {"button_east", "\u25CB"},
            {"button_west", "\u25A1"}, {"button_north", "\u25B3"},
            {"shoulder_left", "L1"}, {"shoulder_right", "R1"},
            {"trigger_left", "L2"}, {"trigger_right", "R2"},
            {"button_start", "Options"}, {"button_back", "Share"},
            {"dpad_up", "D-Pad Up"}, {"dpad_down", "D-Pad Down"},
            {"dpad_left", "D-Pad Left"}, {"dpad_right", "D-Pad Right"},
            {"stick_left_up", "Left Stick Up"}, {"stick_left_down", "Left Stick Down"},
            {"stick_left_left", "Left Stick Left"}, {"stick_left_right", "Left Stick Right"},
            {"stick_right_up", "Right Stick Up"}, {"stick_right_down", "Right Stick Down"},
        }},
        {"switch", {
            {"button_south", "B"}, {"button_east", "A"},
            {"button_west", "Y"}, {"button_north", "X"},
            {"shoulder_left", "L"}, {"shoulder_right", "R"},
            {"trigger_left", "ZL"}, {"trigger_right", "ZR"},
            {"button_start", "+"}, {"button_back", "-"},
            {"dpad_up", "D-Pad Up"}, {"dpad_down", "D-Pad Down"},
            {"dpad_left", "D-Pad Left"}, {"dpad_right", "D-Pad Right"},
            {"stick_left_up", "Left Stick Up"}, {"stick_left_down", "Left Stick Down"},
            {"stick_left_left", "Left Stick Left"}, {"stick_left_right", "Left Stick Right"},
            {"stick_right_up", "Right Stick Up"}, {"stick_right_down", "Right Stick Down"},
        }},
    };

    QString family = controllerFamilyName();
    // Luna and generic use Xbox names
    if (family == "luna" || family == "generic") family = "xbox";

    auto familyIt = familyNames.find(family);
    if (familyIt != familyNames.end()) {
        auto nameIt = familyIt.value().find(physicalInput);
        if (nameIt != familyIt.value().end()) {
            return nameIt.value();
        }
    }

    // Fallback: clean up the physical input name
    return physicalInput;
}

QString ControllerManager::getButtonGlyphPath(const QString &physicalInput) const {
    QString family = controllerFamilyName();
    if (family == "luna" || family == "generic") family = "xbox";
    return QString("qrc:/LunaUI/resources/icons/controllers/%1/%2.svg")
        .arg(family, physicalInput);
}

QString ControllerManager::getInputForAction(const QString &action) const {
    return m_profileResolver.resolveInput(action);
}

QString ControllerManager::getDisplayNameForAction(const QString &action) const {
    QString input = m_profileResolver.resolveInput(action);
    if (input.isEmpty()) return QString();
    return getButtonDisplayName(input);
}
