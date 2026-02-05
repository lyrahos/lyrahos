#ifndef CONTROLLERMANAGER_H
#define CONTROLLERMANAGER_H

#include <QObject>
#include <QElapsedTimer>      // FIX #20: For axis debounce
#include <SDL2/SDL.h>

class ControllerManager : public QObject {
    Q_OBJECT
public:
    explicit ControllerManager(QObject *parent = nullptr);
    ~ControllerManager();

    void initialize();
    void pollEvents();

signals:
    void confirmPressed();
    void backPressed();
    void quickActionPressed();
    void searchPressed();
    void settingsPressed();
    void systemMenuPressed();
    void navigateUp();
    void navigateDown();
    void navigateLeft();
    void navigateRight();
    void previousTab();
    void nextTab();
    void filtersPressed();
    void sortPressed();
    void scrollUp();
    void scrollDown();

private:
    SDL_GameController *m_controller = nullptr;
    QElapsedTimer m_axisNavCooldown;    // FIX #20: Debounce timer
    QElapsedTimer m_triggerCooldown;

    void handleButtonPress(SDL_GameControllerButton button);
    void handleAxisMotion(SDL_GameControllerAxis axis, int value);
    void detectControllers();
};

#endif
