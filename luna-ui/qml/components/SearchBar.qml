import QtQuick
import QtQuick.Controls

Rectangle {
    id: searchBar
    height: 48
    radius: 8
    color: ThemeManager.getColor("surface")

    signal searchSubmitted(string query)

    TextField {
        id: searchField
        anchors.fill: parent
        anchors.margins: 4
        placeholderText: "Search games..."
        color: ThemeManager.getColor("textPrimary")
        font.pixelSize: ThemeManager.getFontSize("medium")
        font.family: ThemeManager.getFont("body")
        background: Rectangle { color: "transparent" }
        onAccepted: searchSubmitted(text)
    }
}
