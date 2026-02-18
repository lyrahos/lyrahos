#ifndef CONTROLLERMANAGER_H
#define CONTROLLERMANAGER_H

#include <QObject>
#include <QElapsedTimer>
#include <QGuiApplication>
#include <QKeyEvent>
#include <SDL2/SDL.h>
#include "profileresolver.h"

class Database;

class ControllerManager : public QObject {
    Q_OBJECT
    Q_PROPERTY(QString controllerFamily READ controllerFamilyName NOTIFY controllerFamilyChanged)
    Q_PROPERTY(QString controllerName READ controllerName NOTIFY controllerChanged)
    Q_PROPERTY(bool controllerConnected READ isControllerConnected NOTIFY controllerChanged)
    Q_PROPERTY(bool listeningForInput READ isListeningForInput NOTIFY listeningChanged)

public:
    explicit ControllerManager(QObject *parent = nullptr);
    ~ControllerManager();

    void initialize();
    void pollEvents();

    // Set database for ProfileResolver
    void setDatabase(Database *db);

    // Profile resolver access (exposed to QML via context property)
    ProfileResolver* profileResolver() { return &m_profileResolver; }

    // Controller info
    QString controllerFamilyName() const;
    QString controllerName() const;
    bool isControllerConnected() const { return m_controller != nullptr; }

    // Context switching for game launch/exit
    Q_INVOKABLE void setGameContext(const QString &clientId, int gameId);
    Q_INVOKABLE void clearGameContext();

    // Remap listening mode — for Settings UI "press a button" interaction
    Q_INVOKABLE void startListening();
    Q_INVOKABLE void stopListening();
    bool isListeningForInput() const { return m_listening; }

    // Get display info for a physical input based on current controller family
    Q_INVOKABLE QString getButtonDisplayName(const QString &physicalInput) const;
    Q_INVOKABLE QString getButtonGlyphPath(const QString &physicalInput) const;

    // Get the physical input name for an action (reverse lookup for UI)
    Q_INVOKABLE QString getInputForAction(const QString &action) const;
    Q_INVOKABLE QString getDisplayNameForAction(const QString &action) const;

signals:
    // New unified signal — the primary way to handle controller input
    void actionTriggered(const QString &action);

    // Input captured during listening mode (for remapping UI)
    void inputCaptured(const QString &physicalInput);

    // Controller state changes
    void controllerChanged();
    void controllerFamilyChanged();
    void listeningChanged();

    // Legacy signals — kept during transition, will be removed once QML is fully updated
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
    QElapsedTimer m_axisNavCooldown;
    QElapsedTimer m_triggerCooldown;

    ProfileResolver m_profileResolver;
    ControllerFamily m_detectedFamily = ControllerFamily::Generic;
    bool m_listening = false;

    void handleButtonPress(SDL_GameControllerButton button);
    void handleAxisMotion(SDL_GameControllerAxis axis, int value);
    void detectControllers();
    ControllerFamily detectFamily(SDL_GameController *controller);
    void dispatchAction(const QString &action);
    void emitLegacySignal(const QString &action);
    void sendSyntheticKeyEvent(const QString &action);
    void sendSyntheticKey(int qtKey);

    // Action-to-legacy-signal dispatch table
    static QHash<QString, void(ControllerManager::*)()> s_legacySignals;
    static QHash<QString, void(ControllerManager::*)()> initLegacySignals();
};

#endif
