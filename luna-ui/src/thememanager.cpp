#include "thememanager.h"
#include <QFile>
#include <QJsonDocument>
#include <QDir>
#include <QDebug>

ThemeManager::ThemeManager(QObject *parent) : QObject(parent) {
    loadDefaultTheme();
}

void ThemeManager::loadTheme(const QString &themeName) {
    QString userTheme = QDir::homePath() + "/.config/luna-ui/themes/" + themeName + ".json";
    QString systemTheme = "/usr/share/luna-ui/themes/" + themeName + ".json";
    QString themePath = QFile::exists(userTheme) ? userTheme : systemTheme;

    QFile file(themePath);
    if (file.open(QIODevice::ReadOnly)) {
        QJsonDocument doc = QJsonDocument::fromJson(file.readAll());
        m_themeData = doc.object();
        m_currentTheme = themeName;

        QDir().mkpath(QDir::homePath() + "/.config/luna-ui");
        QFile activeTheme(QDir::homePath() + "/.config/luna-ui/active-theme");
        if (activeTheme.open(QIODevice::WriteOnly)) {
            activeTheme.write(themeName.toUtf8());
        }
        emit themeChanged();
    } else {
        qWarning() << "Could not load theme:" << themePath;
    }
}

QColor ThemeManager::getColor(const QString &key) {
    QJsonObject colors = m_themeData["colors"].toObject();
    return QColor(colors.value(key).toString("#ffffff"));
}

QString ThemeManager::getFont(const QString &key) {
    QJsonObject fonts = m_themeData["fonts"].toObject();
    return fonts.value(key).toString("Inter");
}

int ThemeManager::getFontSize(const QString &key) {
    QJsonObject layout = m_themeData["layout"].toObject();
    QJsonObject fontSize = layout["fontSize"].toObject();
    return fontSize.value(key).toInt(16);
}

bool ThemeManager::effectEnabled(const QString &effect) {
    QJsonObject effects = m_themeData["effects"].toObject();
    return effects.value(effect).toBool(false);
}

int ThemeManager::getLayoutValue(const QString &key) {
    QJsonObject layout = m_themeData["layout"].toObject();
    return layout.value(key).toInt(0);
}

QStringList ThemeManager::availableThemes() {
    QStringList themes;
    QDir systemDir("/usr/share/luna-ui/themes");
    for (const QString &file : systemDir.entryList(QStringList() << "*.json", QDir::Files)) {
        themes << file.chopped(5);
    }
    QDir userDir(QDir::homePath() + "/.config/luna-ui/themes");
    for (const QString &file : userDir.entryList(QStringList() << "*.json", QDir::Files)) {
        QString name = file.chopped(5);
        if (!themes.contains(name)) themes << name;
    }
    return themes;
}

void ThemeManager::saveUserTheme(const QString &name, const QJsonObject &themeData) {
    QString dir = QDir::homePath() + "/.config/luna-ui/themes";
    QDir().mkpath(dir);
    QFile file(dir + "/" + name + ".json");
    if (file.open(QIODevice::WriteOnly)) {
        file.write(QJsonDocument(themeData).toJson());
    }
}

void ThemeManager::loadDefaultTheme() {
    QFile activeTheme(QDir::homePath() + "/.config/luna-ui/active-theme");
    if (activeTheme.open(QIODevice::ReadOnly)) {
        QString savedTheme = QString::fromUtf8(activeTheme.readAll()).trimmed();
        if (!savedTheme.isEmpty()) {
            loadTheme(savedTheme);
            return;
        }
    }
    loadTheme("nebula-dark");
}
