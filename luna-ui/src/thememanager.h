#ifndef THEMEMANAGER_H
#define THEMEMANAGER_H

#include <QObject>
#include <QColor>
#include <QFont>
#include <QJsonObject>

// NOTE (FIX #23): Returning QColor from Q_INVOKABLE works correctly in QML.
// QML can access .r, .g, .b properties on the returned QColor object.
// For a more idiomatic approach in future, consider Q_PROPERTY with NOTIFY
// signals for commonly used theme colors to avoid repeated method calls.

class ThemeManager : public QObject {
    Q_OBJECT
    Q_PROPERTY(QString currentTheme READ currentTheme NOTIFY themeChanged)

public:
    explicit ThemeManager(QObject *parent = nullptr);

    QString currentTheme() const { return m_currentTheme; }

    Q_INVOKABLE void loadTheme(const QString &themeName);
    Q_INVOKABLE QColor getColor(const QString &key);
    Q_INVOKABLE QString getFont(const QString &key);
    Q_INVOKABLE int getFontSize(const QString &key);
    Q_INVOKABLE bool effectEnabled(const QString &effect);
    Q_INVOKABLE int getLayoutValue(const QString &key);
    Q_INVOKABLE QStringList availableThemes();
    Q_INVOKABLE void saveUserTheme(const QString &name, const QJsonObject &themeData);

signals:
    void themeChanged();

private:
    QString m_currentTheme;
    QJsonObject m_themeData;
    void loadDefaultTheme();
};

#endif
