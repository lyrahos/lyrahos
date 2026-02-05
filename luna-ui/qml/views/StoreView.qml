import QtQuick
import QtQuick.Controls

Rectangle {
    color: "transparent"
    Text {
        anchors.centerIn: parent
        text: "Store -- Coming Soon"
        font.pixelSize: 24
        color: ThemeManager.getColor("textSecondary")
    }
}
