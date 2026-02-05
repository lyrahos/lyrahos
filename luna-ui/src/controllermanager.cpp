#include "controllermanager.h"
#include <QDebug>

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

void ControllerManager::initialize() {
    SDL_Init(SDL_INIT_GAMECONTROLLER);
    SDL_GameControllerAddMappingsFromFile("/usr/share/luna-ui/gamecontrollerdb.txt");
    detectControllers();
}

void ControllerManager::detectControllers() {
    for (int i = 0; i < SDL_NumJoysticks(); ++i) {
        if (SDL_IsGameController(i)) {
            m_controller = SDL_GameControllerOpen(i);
            if (m_controller) {
                qDebug() << "Controller connected:" << SDL_GameControllerName(m_controller);
                break;
            }
        }
    }
}

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
        }
    }
}

void ControllerManager::handleButtonPress(SDL_GameControllerButton button) {
    switch (button) {
        case SDL_CONTROLLER_BUTTON_A:           emit confirmPressed(); break;
        case SDL_CONTROLLER_BUTTON_B:           emit backPressed(); break;
        case SDL_CONTROLLER_BUTTON_X:           emit quickActionPressed(); break;
        case SDL_CONTROLLER_BUTTON_Y:           emit searchPressed(); break;
        case SDL_CONTROLLER_BUTTON_DPAD_UP:     emit navigateUp(); break;
        case SDL_CONTROLLER_BUTTON_DPAD_DOWN:   emit navigateDown(); break;
        case SDL_CONTROLLER_BUTTON_DPAD_LEFT:   emit navigateLeft(); break;
        case SDL_CONTROLLER_BUTTON_DPAD_RIGHT:  emit navigateRight(); break;
        case SDL_CONTROLLER_BUTTON_LEFTSHOULDER:  emit previousTab(); break;
        case SDL_CONTROLLER_BUTTON_RIGHTSHOULDER: emit nextTab(); break;
        case SDL_CONTROLLER_BUTTON_START:       emit settingsPressed(); break;
        case SDL_CONTROLLER_BUTTON_BACK:        emit systemMenuPressed(); break;
        default: break;
    }
}

void ControllerManager::handleAxisMotion(SDL_GameControllerAxis axis, int value) {
    const int DEADZONE = 8000;
    const int NAV_COOLDOWN_MS = 200;   // FIX #20: 200ms cooldown prevents flooding

    // Left stick for navigation (with debounce)
    if (axis == SDL_CONTROLLER_AXIS_LEFTY || axis == SDL_CONTROLLER_AXIS_LEFTX) {
        if (m_axisNavCooldown.elapsed() < NAV_COOLDOWN_MS) return;

        if (axis == SDL_CONTROLLER_AXIS_LEFTY) {
            if (value < -DEADZONE) { emit navigateUp(); m_axisNavCooldown.restart(); }
            else if (value > DEADZONE) { emit navigateDown(); m_axisNavCooldown.restart(); }
        }
        if (axis == SDL_CONTROLLER_AXIS_LEFTX) {
            if (value < -DEADZONE) { emit navigateLeft(); m_axisNavCooldown.restart(); }
            else if (value > DEADZONE) { emit navigateRight(); m_axisNavCooldown.restart(); }
        }
    }

    // Right stick for quick scroll (with debounce)
    if (axis == SDL_CONTROLLER_AXIS_RIGHTY) {
        if (m_axisNavCooldown.elapsed() < NAV_COOLDOWN_MS) return;
        if (value < -DEADZONE) { emit scrollUp(); m_axisNavCooldown.restart(); }
        else if (value > DEADZONE) { emit scrollDown(); m_axisNavCooldown.restart(); }
    }

    // Triggers for filters/sort (with separate cooldown)
    if (axis == SDL_CONTROLLER_AXIS_TRIGGERLEFT && value > DEADZONE) {
        if (m_triggerCooldown.elapsed() > NAV_COOLDOWN_MS) {
            emit filtersPressed();
            m_triggerCooldown.restart();
        }
    }
    if (axis == SDL_CONTROLLER_AXIS_TRIGGERRIGHT && value > DEADZONE) {
        if (m_triggerCooldown.elapsed() > NAV_COOLDOWN_MS) {
            emit sortPressed();
            m_triggerCooldown.restart();
        }
    }
}
