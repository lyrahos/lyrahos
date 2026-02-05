import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../components"

Rectangle {
    color: "transparent"

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 24

        Text {
            text: "Games Library"
            font.pixelSize: ThemeManager.getFontSize("xlarge")
            font.family: ThemeManager.getFont("heading")
            font.bold: true
            color: ThemeManager.getColor("textPrimary")
        }

        // TODO: Implement full game grid with GameCard components
        // - Recently Played row
        // - All Games grid
        // - Search bar
        // - Filter/sort controls
        Text {
            text: "Game library view -- implementation in progress"
            color: ThemeManager.getColor("textSecondary")
        }
    }
}
