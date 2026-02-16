import QtQuick
import QtQuick.Controls

Rectangle {
    color: "transparent"

    signal requestNavFocus()

    function gainFocus() { forceActiveFocus() }
    function loseFocus() {}

    Keys.onLeftPressed: requestNavFocus()

    Text {
        anchors.centerIn: parent
        text: "Media -- Coming Soon"
        font.pixelSize: 24
        color: ThemeManager.getColor("textSecondary")
    }
}
