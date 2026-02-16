#include "profileresolver.h"
#include <QSqlQuery>
#include <QSqlError>
#include <QJsonDocument>
#include <QJsonArray>
#include <QDir>
#include <QFile>
#include <QDebug>

ProfileResolver::ProfileResolver(QObject *parent) : QObject(parent) {}

// ── Core Resolution ──────────────────────────────────────────────────

QString ProfileResolver::resolveAction(const QString &physicalInput) const {
    return m_actionCache.value(physicalInput);
}

QString ProfileResolver::resolveInput(const QString &action) const {
    return m_inputCache.value(action);
}

QJsonObject ProfileResolver::resolveParameters(const QString &physicalInput) const {
    return m_paramsCache.value(physicalInput);
}

// ── Context Management ───────────────────────────────────────────────

void ProfileResolver::setContext(const QString &clientId, int gameId, ControllerFamily family) {
    m_clientId = clientId;
    m_gameId = gameId;
    m_family = family;
    loadProfiles();
    emit contextChanged();
}

void ProfileResolver::setControllerFamily(ControllerFamily family) {
    if (m_family == family) return;
    m_family = family;
    loadProfiles();
    emit contextChanged();
}

void ProfileResolver::reload() {
    loadProfiles();
    emit profilesChanged();
}

void ProfileResolver::setDatabase(QSqlDatabase db) {
    m_db = db;
}

// ── Database Schema ──────────────────────────────────────────────────

void ProfileResolver::createTables() {
    QSqlQuery query(m_db);

    query.exec("CREATE TABLE IF NOT EXISTS controller_profiles ("
               "id INTEGER PRIMARY KEY AUTOINCREMENT,"
               "name TEXT NOT NULL,"
               "scope TEXT NOT NULL,"
               "controller_family TEXT DEFAULT 'any',"
               "client_id TEXT,"
               "game_id INTEGER,"
               "is_default BOOLEAN DEFAULT 0,"
               "created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,"
               "updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP"
               ")");

    query.exec("CREATE UNIQUE INDEX IF NOT EXISTS idx_profile_scope "
               "ON controller_profiles(scope, controller_family, client_id, game_id)");

    query.exec("CREATE TABLE IF NOT EXISTS controller_mappings ("
               "id INTEGER PRIMARY KEY AUTOINCREMENT,"
               "profile_id INTEGER NOT NULL,"
               "physical_input TEXT NOT NULL,"
               "action TEXT NOT NULL,"
               "parameters TEXT,"
               "FOREIGN KEY (profile_id) REFERENCES controller_profiles(id) ON DELETE CASCADE"
               ")");

    query.exec("CREATE UNIQUE INDEX IF NOT EXISTS idx_mapping_input "
               "ON controller_mappings(profile_id, physical_input)");
}

void ProfileResolver::seedDefaults() {
    QSqlQuery check(m_db);
    check.exec("SELECT COUNT(*) FROM controller_profiles WHERE is_default = 1");
    if (check.next() && check.value(0).toInt() > 0) {
        return; // Already seeded
    }

    // Shared base mappings (position-based, controller-agnostic)
    auto insertMappings = [this](int profileId, const QHash<QString, QString> &overrides = {}) {
        // Standard mappings — south=confirm is the default for Xbox/Generic
        QHash<QString, QString> mappings = {
            {"button_south",     "confirm"},
            {"button_east",      "back"},
            {"button_west",      "quick_action"},
            {"button_north",     "search"},
            {"dpad_up",          "navigate_up"},
            {"dpad_down",        "navigate_down"},
            {"dpad_left",        "navigate_left"},
            {"dpad_right",       "navigate_right"},
            {"shoulder_left",    "previous_tab"},
            {"shoulder_right",   "next_tab"},
            {"trigger_left",     "filters"},
            {"trigger_right",    "sort"},
            {"stick_left_up",    "navigate_up"},
            {"stick_left_down",  "navigate_down"},
            {"stick_left_left",  "navigate_left"},
            {"stick_left_right", "navigate_right"},
            {"stick_right_up",   "scroll_up"},
            {"stick_right_down", "scroll_down"},
            {"button_start",     "settings"},
            {"button_back",      "system_menu"},
        };

        // Apply overrides
        for (auto it = overrides.begin(); it != overrides.end(); ++it) {
            mappings[it.key()] = it.value();
        }

        QSqlQuery q(m_db);
        q.prepare("INSERT INTO controller_mappings (profile_id, physical_input, action, parameters) "
                  "VALUES (?, ?, ?, ?)");
        for (auto it = mappings.begin(); it != mappings.end(); ++it) {
            q.addBindValue(profileId);
            q.addBindValue(it.key());
            q.addBindValue(it.value());
            // Add deadzone parameters for analog inputs
            QJsonObject params;
            if (it.key().startsWith("stick_") || it.key().startsWith("trigger_")) {
                params["deadzone"] = 8000;
                if (it.key().startsWith("trigger_")) {
                    params["threshold"] = 8000;
                }
            }
            q.addBindValue(params.isEmpty() ? QString() : QString(QJsonDocument(params).toJson(QJsonDocument::Compact)));
            q.exec();
        }
    };

    auto createProfile = [this](const QString &name, const QString &scope,
                                 const QString &family) -> int {
        QSqlQuery q(m_db);
        q.prepare("INSERT INTO controller_profiles (name, scope, controller_family, is_default) "
                  "VALUES (?, ?, ?, 1)");
        q.addBindValue(name);
        q.addBindValue(scope);
        q.addBindValue(family);
        if (q.exec()) return q.lastInsertId().toInt();
        qWarning() << "Failed to create default profile:" << q.lastError().text();
        return -1;
    };

    // 1. Global default
    int globalId = createProfile("Global Default", "global", "any");
    if (globalId > 0) insertMappings(globalId);

    // 2. Xbox family — same as global (A=south=confirm)
    int xboxId = createProfile("Xbox Default", "family", "xbox");
    if (xboxId > 0) insertMappings(xboxId);

    // 3. PlayStation family — western convention: X(south)=confirm, O(east)=back
    //    Same as global for western markets
    int psId = createProfile("PlayStation Default", "family", "playstation");
    if (psId > 0) insertMappings(psId);

    // 4. Switch family — B(south)=confirm, A(east)=back (Nintendo convention)
    //    Positionally identical: south=confirm, east=back
    int switchId = createProfile("Nintendo Switch Default", "family", "switch");
    if (switchId > 0) insertMappings(switchId);

    // 5. Luna controller — same as Xbox
    int lunaId = createProfile("Luna Default", "family", "luna");
    if (lunaId > 0) insertMappings(lunaId);

    // 6. Generic controller
    int genericId = createProfile("Generic Default", "family", "generic");
    if (genericId > 0) insertMappings(genericId);

    qDebug() << "Seeded default controller profiles";
}

// ── Profile Loading & Cache ──────────────────────────────────────────

void ProfileResolver::loadProfiles() {
    m_globalProfile = loadProfileFromDb("global", "any", QString(), 0);
    m_familyProfile = loadProfileFromDb("family", familyToString(m_family), QString(), 0);
    m_clientProfile = ControllerProfile{};
    m_gameProfile = ControllerProfile{};

    if (!m_clientId.isEmpty()) {
        m_clientProfile = loadProfileFromDb("client", familyToString(m_family), m_clientId, 0);
        // Also try "any" family for client profiles
        if (m_clientProfile.id == 0) {
            m_clientProfile = loadProfileFromDb("client", "any", m_clientId, 0);
        }
    }
    if (m_gameId > 0) {
        m_gameProfile = loadProfileFromDb("game", familyToString(m_family), m_clientId, m_gameId);
        if (m_gameProfile.id == 0) {
            m_gameProfile = loadProfileFromDb("game", "any", QString(), m_gameId);
        }
    }

    buildMergedCache();
}

ControllerProfile ProfileResolver::loadProfileFromDb(const QString &scope, const QString &family,
                                                       const QString &clientId, int gameId) {
    ControllerProfile profile;
    QSqlQuery q(m_db);

    if (scope == "global") {
        q.prepare("SELECT * FROM controller_profiles WHERE scope = 'global' LIMIT 1");
    } else if (scope == "family") {
        q.prepare("SELECT * FROM controller_profiles WHERE scope = 'family' AND controller_family = ? LIMIT 1");
        q.addBindValue(family);
    } else if (scope == "client") {
        q.prepare("SELECT * FROM controller_profiles WHERE scope = 'client' AND client_id = ? "
                  "AND (controller_family = ? OR controller_family = 'any') "
                  "ORDER BY CASE WHEN controller_family = ? THEN 0 ELSE 1 END LIMIT 1");
        q.addBindValue(clientId);
        q.addBindValue(family);
        q.addBindValue(family);
    } else if (scope == "game") {
        q.prepare("SELECT * FROM controller_profiles WHERE scope = 'game' AND game_id = ? "
                  "AND (controller_family = ? OR controller_family = 'any') "
                  "ORDER BY CASE WHEN controller_family = ? THEN 0 ELSE 1 END LIMIT 1");
        q.addBindValue(gameId);
        q.addBindValue(family);
        q.addBindValue(family);
    }

    if (!q.exec() || !q.next()) return profile;

    profile.id = q.value("id").toInt();
    profile.name = q.value("name").toString();
    profile.scope = q.value("scope").toString();
    profile.controllerFamily = q.value("controller_family").toString();
    profile.clientId = q.value("client_id").toString();
    profile.gameId = q.value("game_id").toInt();
    profile.isDefault = q.value("is_default").toBool();

    // Load mappings
    QSqlQuery mq(m_db);
    mq.prepare("SELECT * FROM controller_mappings WHERE profile_id = ?");
    mq.addBindValue(profile.id);
    if (mq.exec()) {
        while (mq.next()) {
            ControllerMapping mapping;
            mapping.physicalInput = mq.value("physical_input").toString();
            mapping.action = mq.value("action").toString();
            QString paramsStr = mq.value("parameters").toString();
            if (!paramsStr.isEmpty()) {
                mapping.parameters = QJsonDocument::fromJson(paramsStr.toUtf8()).object();
            }
            profile.mappings[mapping.physicalInput] = mapping;
        }
    }

    return profile;
}

void ProfileResolver::buildMergedCache() {
    m_actionCache.clear();
    m_inputCache.clear();
    m_paramsCache.clear();

    // Merge in specificity order: global → family → client → game
    // Later layers override earlier ones
    auto mergeProfile = [this](const ControllerProfile &profile) {
        for (auto it = profile.mappings.begin(); it != profile.mappings.end(); ++it) {
            m_actionCache[it.key()] = it.value().action;
            m_inputCache[it.value().action] = it.key();
            if (!it.value().parameters.isEmpty()) {
                m_paramsCache[it.key()] = it.value().parameters;
            }
        }
    };

    mergeProfile(m_globalProfile);
    if (m_familyProfile.id > 0) mergeProfile(m_familyProfile);
    if (m_clientProfile.id > 0) mergeProfile(m_clientProfile);
    if (m_gameProfile.id > 0) mergeProfile(m_gameProfile);
}

// ── Profile CRUD ─────────────────────────────────────────────────────

QVariantList ProfileResolver::getProfiles(const QString &scope, const QString &family) {
    QVariantList result;
    QSqlQuery q(m_db);

    QString sql = "SELECT * FROM controller_profiles WHERE 1=1";
    if (!scope.isEmpty()) sql += " AND scope = ?";
    if (!family.isEmpty()) sql += " AND controller_family = ?";
    sql += " ORDER BY scope, controller_family, name";

    q.prepare(sql);
    if (!scope.isEmpty()) q.addBindValue(scope);
    if (!family.isEmpty()) q.addBindValue(family);

    if (q.exec()) {
        while (q.next()) {
            QVariantMap p;
            p["id"] = q.value("id");
            p["name"] = q.value("name");
            p["scope"] = q.value("scope");
            p["controllerFamily"] = q.value("controller_family");
            p["clientId"] = q.value("client_id");
            p["gameId"] = q.value("game_id");
            p["isDefault"] = q.value("is_default");
            result.append(p);
        }
    }
    return result;
}

QVariantMap ProfileResolver::getProfileById(int profileId) {
    QVariantMap result;
    QSqlQuery q(m_db);
    q.prepare("SELECT * FROM controller_profiles WHERE id = ?");
    q.addBindValue(profileId);
    if (q.exec() && q.next()) {
        result["id"] = q.value("id");
        result["name"] = q.value("name");
        result["scope"] = q.value("scope");
        result["controllerFamily"] = q.value("controller_family");
        result["clientId"] = q.value("client_id");
        result["gameId"] = q.value("game_id");
        result["isDefault"] = q.value("is_default");
    }
    return result;
}

QVariantList ProfileResolver::getMappingsForProfile(int profileId) {
    QVariantList result;
    QSqlQuery q(m_db);
    q.prepare("SELECT * FROM controller_mappings WHERE profile_id = ? ORDER BY physical_input");
    q.addBindValue(profileId);
    if (q.exec()) {
        while (q.next()) {
            QVariantMap m;
            m["id"] = q.value("id");
            m["profileId"] = q.value("profile_id");
            m["physicalInput"] = q.value("physical_input");
            m["action"] = q.value("action");
            m["parameters"] = q.value("parameters");
            result.append(m);
        }
    }
    return result;
}

int ProfileResolver::createProfile(const QString &name, const QString &scope,
                                    const QString &controllerFamily,
                                    const QString &clientId, int gameId) {
    QSqlQuery q(m_db);
    q.prepare("INSERT INTO controller_profiles (name, scope, controller_family, client_id, game_id) "
              "VALUES (?, ?, ?, ?, ?)");
    q.addBindValue(name);
    q.addBindValue(scope);
    q.addBindValue(controllerFamily);
    q.addBindValue(clientId.isEmpty() ? QVariant() : clientId);
    q.addBindValue(gameId > 0 ? gameId : QVariant());

    if (q.exec()) {
        int id = q.lastInsertId().toInt();
        emit profilesChanged();
        return id;
    }
    qWarning() << "Failed to create profile:" << q.lastError().text();
    return -1;
}

bool ProfileResolver::deleteProfile(int profileId) {
    // Don't delete built-in defaults
    QSqlQuery check(m_db);
    check.prepare("SELECT is_default FROM controller_profiles WHERE id = ?");
    check.addBindValue(profileId);
    if (check.exec() && check.next() && check.value(0).toBool()) {
        qWarning() << "Cannot delete built-in default profile";
        return false;
    }

    QSqlQuery q(m_db);
    q.prepare("DELETE FROM controller_profiles WHERE id = ?");
    q.addBindValue(profileId);
    if (q.exec()) {
        reload();
        return true;
    }
    return false;
}

bool ProfileResolver::setMapping(int profileId, const QString &physicalInput,
                                  const QString &action, const QString &parameters) {
    QSqlQuery q(m_db);
    q.prepare("INSERT OR REPLACE INTO controller_mappings (profile_id, physical_input, action, parameters) "
              "VALUES (?, ?, ?, ?)");
    q.addBindValue(profileId);
    q.addBindValue(physicalInput);
    q.addBindValue(action);
    q.addBindValue(parameters.isEmpty() ? QVariant() : parameters);

    if (q.exec()) {
        // Update timestamp
        QSqlQuery ts(m_db);
        ts.prepare("UPDATE controller_profiles SET updated_at = CURRENT_TIMESTAMP WHERE id = ?");
        ts.addBindValue(profileId);
        ts.exec();

        reload();
        return true;
    }
    qWarning() << "Failed to set mapping:" << q.lastError().text();
    return false;
}

bool ProfileResolver::removeMapping(int profileId, const QString &physicalInput) {
    QSqlQuery q(m_db);
    q.prepare("DELETE FROM controller_mappings WHERE profile_id = ? AND physical_input = ?");
    q.addBindValue(profileId);
    q.addBindValue(physicalInput);
    if (q.exec()) {
        reload();
        return true;
    }
    return false;
}

// ── JSON Export ───────────────────────────────────────────────────────

bool ProfileResolver::exportProfile(int profileId, const QString &filePath) {
    QSqlQuery pq(m_db);
    pq.prepare("SELECT * FROM controller_profiles WHERE id = ?");
    pq.addBindValue(profileId);
    if (!pq.exec() || !pq.next()) return false;

    QJsonObject root;
    root["version"] = 1;
    root["name"] = pq.value("name").toString();
    root["scope"] = pq.value("scope").toString();
    root["controller_family"] = pq.value("controller_family").toString();
    if (!pq.value("client_id").isNull())
        root["client_id"] = pq.value("client_id").toString();
    if (!pq.value("game_id").isNull() && pq.value("game_id").toInt() > 0)
        root["game_id"] = pq.value("game_id").toInt();

    QJsonObject mappingsObj;
    QSqlQuery mq(m_db);
    mq.prepare("SELECT * FROM controller_mappings WHERE profile_id = ?");
    mq.addBindValue(profileId);
    if (mq.exec()) {
        while (mq.next()) {
            QJsonObject entry;
            entry["action"] = mq.value("action").toString();
            QString params = mq.value("parameters").toString();
            if (!params.isEmpty()) {
                entry["parameters"] = QJsonDocument::fromJson(params.toUtf8()).object();
            }
            mappingsObj[mq.value("physical_input").toString()] = entry;
        }
    }
    root["mappings"] = mappingsObj;

    QFile file(filePath);
    if (!file.open(QIODevice::WriteOnly)) return false;
    file.write(QJsonDocument(root).toJson(QJsonDocument::Indented));
    return true;
}

bool ProfileResolver::exportAllProfiles() {
    QString dir = QDir::homePath() + "/.config/luna-ui/profiles";
    QDir().mkpath(dir);

    QSqlQuery q(m_db);
    q.exec("SELECT id, scope, controller_family, client_id, game_id FROM controller_profiles");
    while (q.next()) {
        int id = q.value("id").toInt();
        QString scope = q.value("scope").toString();
        QString family = q.value("controller_family").toString();
        QString clientId = q.value("client_id").toString();
        int gameId = q.value("game_id").toInt();

        QString filename;
        if (scope == "global") {
            filename = "global.json";
        } else if (scope == "family") {
            filename = "family_" + family + ".json";
        } else if (scope == "client") {
            filename = "client_" + clientId + ".json";
        } else if (scope == "game") {
            filename = "game_" + clientId + "_" + QString::number(gameId) + ".json";
        }
        exportProfile(id, dir + "/" + filename);
    }
    return true;
}

// ── Static Helpers ───────────────────────────────────────────────────

QString ProfileResolver::familyToString(ControllerFamily family) {
    switch (family) {
    case ControllerFamily::Xbox:        return "xbox";
    case ControllerFamily::PlayStation: return "playstation";
    case ControllerFamily::Switch:      return "switch";
    case ControllerFamily::Luna:        return "luna";
    case ControllerFamily::Generic:     return "generic";
    }
    return "generic";
}

ControllerFamily ProfileResolver::stringToFamily(const QString &str) {
    if (str == "xbox")        return ControllerFamily::Xbox;
    if (str == "playstation") return ControllerFamily::PlayStation;
    if (str == "switch")      return ControllerFamily::Switch;
    if (str == "luna")        return ControllerFamily::Luna;
    return ControllerFamily::Generic;
}

QString ProfileResolver::controllerFamilyName() const {
    return familyToString(m_family);
}

QString ProfileResolver::sdlButtonToPositional(int sdlButton) {
    switch (sdlButton) {
    case SDL_CONTROLLER_BUTTON_A:             return "button_south";
    case SDL_CONTROLLER_BUTTON_B:             return "button_east";
    case SDL_CONTROLLER_BUTTON_X:             return "button_west";
    case SDL_CONTROLLER_BUTTON_Y:             return "button_north";
    case SDL_CONTROLLER_BUTTON_DPAD_UP:       return "dpad_up";
    case SDL_CONTROLLER_BUTTON_DPAD_DOWN:     return "dpad_down";
    case SDL_CONTROLLER_BUTTON_DPAD_LEFT:     return "dpad_left";
    case SDL_CONTROLLER_BUTTON_DPAD_RIGHT:    return "dpad_right";
    case SDL_CONTROLLER_BUTTON_LEFTSHOULDER:  return "shoulder_left";
    case SDL_CONTROLLER_BUTTON_RIGHTSHOULDER: return "shoulder_right";
    case SDL_CONTROLLER_BUTTON_START:         return "button_start";
    case SDL_CONTROLLER_BUTTON_BACK:          return "button_back";
    case SDL_CONTROLLER_BUTTON_GUIDE:         return "button_guide";
    case SDL_CONTROLLER_BUTTON_LEFTSTICK:     return "stick_left_click";
    case SDL_CONTROLLER_BUTTON_RIGHTSTICK:    return "stick_right_click";
    default: return QString();
    }
}

QString ProfileResolver::sdlAxisToPositional(int sdlAxis) {
    switch (sdlAxis) {
    case SDL_CONTROLLER_AXIS_LEFTX:       return "axis_leftx";
    case SDL_CONTROLLER_AXIS_LEFTY:       return "axis_lefty";
    case SDL_CONTROLLER_AXIS_RIGHTX:      return "axis_rightx";
    case SDL_CONTROLLER_AXIS_RIGHTY:      return "axis_righty";
    case SDL_CONTROLLER_AXIS_TRIGGERLEFT: return "trigger_left";
    case SDL_CONTROLLER_AXIS_TRIGGERRIGHT: return "trigger_right";
    default: return QString();
    }
}

QStringList ProfileResolver::allActions() {
    return {
        "confirm", "back", "quick_action", "search",
        "settings", "system_menu",
        "navigate_up", "navigate_down", "navigate_left", "navigate_right",
        "previous_tab", "next_tab",
        "filters", "sort",
        "scroll_up", "scroll_down"
    };
}

QString ProfileResolver::actionDisplayName(const QString &action) {
    static QHash<QString, QString> names = {
        {"confirm",        "Confirm / Select"},
        {"back",           "Back / Cancel"},
        {"quick_action",   "Quick Action"},
        {"search",         "Search"},
        {"settings",       "Settings"},
        {"system_menu",    "System Menu"},
        {"navigate_up",    "Navigate Up"},
        {"navigate_down",  "Navigate Down"},
        {"navigate_left",  "Navigate Left"},
        {"navigate_right", "Navigate Right"},
        {"previous_tab",   "Previous Tab"},
        {"next_tab",       "Next Tab"},
        {"filters",        "Filters"},
        {"sort",           "Sort"},
        {"scroll_up",      "Scroll Up"},
        {"scroll_down",    "Scroll Down"},
    };
    return names.value(action, action);
}
