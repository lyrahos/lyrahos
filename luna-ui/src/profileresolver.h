#ifndef PROFILERESOLVER_H
#define PROFILERESOLVER_H

#include <QObject>
#include <QHash>
#include <QSqlDatabase>
#include <QString>
#include <QJsonObject>

// Controller family classification
enum class ControllerFamily {
    Xbox,
    PlayStation,
    Switch,
    Luna,
    Generic
};

// A single mapping entry: physical input → action + optional parameters
struct ControllerMapping {
    QString physicalInput;  // e.g. "button_south", "axis_lefty", "trigger_left"
    QString action;         // e.g. "confirm", "back", "navigate_up"
    QJsonObject parameters; // e.g. {"deadzone": 8000, "threshold": 16000, "inverted": false}
};

// A complete profile with its scope metadata
struct ControllerProfile {
    int id = 0;
    QString name;
    QString scope;             // "global", "family", "client", "game"
    QString controllerFamily;  // "xbox", "playstation", "switch", "luna", "generic", "any"
    QString clientId;          // "steam", "epic", "gog", "lutris", "custom" or empty
    int gameId = 0;            // FK to games(id) or 0
    bool isDefault = false;
    QHash<QString, ControllerMapping> mappings; // physicalInput → mapping
};

class ProfileResolver : public QObject {
    Q_OBJECT
    Q_PROPERTY(QString controllerFamily READ controllerFamilyName NOTIFY contextChanged)
    Q_PROPERTY(QString currentClientId READ currentClientId NOTIFY contextChanged)
    Q_PROPERTY(int currentGameId READ currentGameId NOTIFY contextChanged)

public:
    explicit ProfileResolver(QObject *parent = nullptr);

    // Core resolution: physical input → action ID
    QString resolveAction(const QString &physicalInput) const;

    // Reverse resolution: action ID → physical input (for UI display)
    QString resolveInput(const QString &action) const;

    // Get parameters for a physical input (deadzone, threshold, etc.)
    QJsonObject resolveParameters(const QString &physicalInput) const;

    // Set the current context — loads appropriate profiles from DB
    void setContext(const QString &clientId, int gameId, ControllerFamily family);

    // Set just the controller family (on controller connect)
    void setControllerFamily(ControllerFamily family);

    // Reload profiles from database (after user edits a profile)
    void reload();

    // Database initialization
    void setDatabase(QSqlDatabase db);
    void createTables();
    void seedDefaults();

    // Profile CRUD (for Settings UI)
    Q_INVOKABLE QVariantList getProfiles(const QString &scope = QString(),
                                          const QString &family = QString());
    Q_INVOKABLE QVariantMap getProfileById(int profileId);
    Q_INVOKABLE QVariantList getMappingsForProfile(int profileId);
    Q_INVOKABLE int createProfile(const QString &name, const QString &scope,
                                   const QString &controllerFamily,
                                   const QString &clientId = QString(),
                                   int gameId = 0);
    Q_INVOKABLE bool deleteProfile(int profileId);
    Q_INVOKABLE bool setMapping(int profileId, const QString &physicalInput,
                                 const QString &action, const QString &parameters = QString());
    Q_INVOKABLE bool removeMapping(int profileId, const QString &physicalInput);

    // Export profile to JSON file
    Q_INVOKABLE bool exportProfile(int profileId, const QString &filePath);
    Q_INVOKABLE bool exportAllProfiles();

    // Getters
    ControllerFamily family() const { return m_family; }
    QString controllerFamilyName() const;
    QString currentClientId() const { return m_clientId; }
    int currentGameId() const { return m_gameId; }

    // Static helpers
    static QString familyToString(ControllerFamily family);
    static ControllerFamily stringToFamily(const QString &str);
    static QString sdlButtonToPositional(int sdlButton);
    static QString sdlAxisToPositional(int sdlAxis);

    // All defined action IDs
    static QStringList allActions();
    static QString actionDisplayName(const QString &action);

signals:
    void contextChanged();
    void profilesChanged();

private:
    void loadProfiles();
    void buildMergedCache();
    ControllerProfile loadProfileFromDb(const QString &scope, const QString &family,
                                         const QString &clientId, int gameId);

    QSqlDatabase m_db;
    ControllerFamily m_family = ControllerFamily::Generic;
    QString m_clientId;
    int m_gameId = 0;

    // Loaded profiles per layer
    ControllerProfile m_globalProfile;
    ControllerProfile m_familyProfile;
    ControllerProfile m_clientProfile;
    ControllerProfile m_gameProfile;

    // Merged cache: physicalInput → action (O(1) lookup)
    QHash<QString, QString> m_actionCache;
    // Reverse cache: action → physicalInput
    QHash<QString, QString> m_inputCache;
    // Parameters cache: physicalInput → parameters
    QHash<QString, QJsonObject> m_paramsCache;
};

#endif
