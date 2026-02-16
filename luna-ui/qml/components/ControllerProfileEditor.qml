import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// ControllerProfileEditor — Edits a single controller profile's mappings.
// Shows a list of actions with their current physical input assignments.
// Supports "press to remap" listening mode.

Rectangle {
    id: editor
    color: "transparent"

    property int profileId: -1
    property string profileName: ""
    property bool isDefault: false

    signal backRequested()

    // Focus tracking
    property int focusedActionIndex: 0
    property bool isListening: false
    property string listeningAction: ""

    // Action list — populated from ProfileResolver
    property var actionList: []
    property var mappingData: ({})

    function loadMappings() {
        // Get all defined actions and current mappings
        var actions = [
            "confirm", "back", "quick_action", "search",
            "settings", "system_menu",
            "navigate_up", "navigate_down", "navigate_left", "navigate_right",
            "previous_tab", "next_tab",
            "filters", "sort",
            "scroll_up", "scroll_down"
        ]

        var actionNames = {
            "confirm": "Confirm / Select",
            "back": "Back / Cancel",
            "quick_action": "Quick Action",
            "search": "Search",
            "settings": "Settings",
            "system_menu": "System Menu",
            "navigate_up": "Navigate Up",
            "navigate_down": "Navigate Down",
            "navigate_left": "Navigate Left",
            "navigate_right": "Navigate Right",
            "previous_tab": "Previous Tab",
            "next_tab": "Next Tab",
            "filters": "Filters",
            "sort": "Sort",
            "scroll_up": "Scroll Up",
            "scroll_down": "Scroll Down"
        }

        var mappings = ProfileResolver.getMappingsForProfile(profileId)
        var mappingMap = {}
        for (var i = 0; i < mappings.length; i++) {
            mappingMap[mappings[i].action] = mappings[i].physicalInput
        }

        actionListModel.clear()
        for (var j = 0; j < actions.length; j++) {
            var act = actions[j]
            var input = mappingMap[act] || ""
            var displayName = input !== "" ? ControllerManager.getButtonDisplayName(input) : "Not assigned"
            actionListModel.append({
                "actionId": act,
                "actionName": actionNames[act] || act,
                "physicalInput": input,
                "buttonDisplay": displayName
            })
        }
    }

    Component.onCompleted: {
        if (profileId > 0) loadMappings()
    }

    onProfileIdChanged: {
        if (profileId > 0) loadMappings()
    }

    // Handle keyboard navigation
    Keys.onPressed: function(event) {
        if (isListening) {
            // Escape cancels listening
            if (event.key === Qt.Key_Escape) {
                cancelListening()
                event.accepted = true
            }
            return
        }

        switch (event.key) {
        case Qt.Key_Up:
            if (focusedActionIndex > 0) focusedActionIndex--
            event.accepted = true
            break
        case Qt.Key_Down:
            if (focusedActionIndex < actionListModel.count - 1) focusedActionIndex++
            event.accepted = true
            break
        case Qt.Key_Return:
        case Qt.Key_Enter:
            startListening(focusedActionIndex)
            event.accepted = true
            break
        case Qt.Key_Escape:
        case Qt.Key_Left:
            backRequested()
            event.accepted = true
            break
        }
    }

    // Listen for controller input capture
    Connections {
        target: ControllerManager
        function onInputCaptured(physicalInput) {
            if (!isListening) return
            // Save the mapping
            ProfileResolver.setMapping(profileId, physicalInput, listeningAction)
            finishListening()
            loadMappings()
        }
    }

    function startListening(index) {
        if (isDefault) return  // Can't edit default profiles directly
        var item = actionListModel.get(index)
        if (!item) return
        isListening = true
        listeningAction = item.actionId
        ControllerManager.startListening()
    }

    function cancelListening() {
        isListening = false
        listeningAction = ""
        ControllerManager.stopListening()
    }

    function finishListening() {
        isListening = false
        listeningAction = ""
        ControllerManager.stopListening()
    }

    ListModel { id: actionListModel }

    ColumnLayout {
        anchors.fill: parent
        spacing: 16

        // Header
        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            Rectangle {
                Layout.preferredWidth: 40
                Layout.preferredHeight: 40
                radius: 20
                color: backArea.containsMouse ? ThemeManager.getColor("hover") : "transparent"

                Text {
                    anchors.centerIn: parent
                    text: "<"
                    font.pixelSize: 20
                    font.bold: true
                    color: ThemeManager.getColor("textPrimary")
                }

                MouseArea {
                    id: backArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: backRequested()
                }
            }

            Text {
                text: profileName
                font.pixelSize: ThemeManager.getFontSize("large")
                font.family: ThemeManager.getFont("heading")
                font.bold: true
                color: ThemeManager.getColor("textPrimary")
                Layout.fillWidth: true
            }

            // Controller family indicator
            Rectangle {
                visible: ControllerManager.controllerConnected
                Layout.preferredWidth: familyLabel.width + 24
                Layout.preferredHeight: 32
                radius: 16
                color: Qt.rgba(ThemeManager.getColor("primary").r,
                             ThemeManager.getColor("primary").g,
                             ThemeManager.getColor("primary").b, 0.2)

                Text {
                    id: familyLabel
                    anchors.centerIn: parent
                    text: ControllerManager.controllerFamily
                    font.pixelSize: ThemeManager.getFontSize("small")
                    font.family: ThemeManager.getFont("body")
                    color: ThemeManager.getColor("primary")
                    font.capitalization: Font.Capitalize
                }
            }
        }

        // Listening overlay
        Rectangle {
            visible: isListening
            Layout.fillWidth: true
            Layout.preferredHeight: 80
            radius: 12
            color: Qt.rgba(ThemeManager.getColor("primary").r,
                         ThemeManager.getColor("primary").g,
                         ThemeManager.getColor("primary").b, 0.15)
            border.color: ThemeManager.getColor("primary")
            border.width: 2

            ColumnLayout {
                anchors.centerIn: parent
                spacing: 8

                Text {
                    text: "Press the button you want for:"
                    font.pixelSize: ThemeManager.getFontSize("small")
                    font.family: ThemeManager.getFont("body")
                    color: ThemeManager.getColor("textSecondary")
                    Layout.alignment: Qt.AlignHCenter
                }

                Text {
                    text: {
                        var names = {
                            "confirm": "Confirm / Select",
                            "back": "Back / Cancel",
                            "quick_action": "Quick Action",
                            "search": "Search",
                            "settings": "Settings",
                            "system_menu": "System Menu",
                            "navigate_up": "Navigate Up",
                            "navigate_down": "Navigate Down",
                            "navigate_left": "Navigate Left",
                            "navigate_right": "Navigate Right",
                            "previous_tab": "Previous Tab",
                            "next_tab": "Next Tab",
                            "filters": "Filters",
                            "sort": "Sort",
                            "scroll_up": "Scroll Up",
                            "scroll_down": "Scroll Down"
                        }
                        return names[listeningAction] || listeningAction
                    }
                    font.pixelSize: ThemeManager.getFontSize("medium")
                    font.family: ThemeManager.getFont("heading")
                    font.bold: true
                    color: ThemeManager.getColor("primary")
                    Layout.alignment: Qt.AlignHCenter

                    SequentialAnimation on opacity {
                        running: isListening
                        loops: Animation.Infinite
                        NumberAnimation { to: 0.4; duration: 800 }
                        NumberAnimation { to: 1.0; duration: 800 }
                    }
                }
            }
        }

        // Default profile notice
        Rectangle {
            visible: isDefault
            Layout.fillWidth: true
            Layout.preferredHeight: 40
            radius: 8
            color: Qt.rgba(1, 0.75, 0, 0.1)

            Text {
                anchors.centerIn: parent
                text: "Built-in default — create a custom profile to modify"
                font.pixelSize: ThemeManager.getFontSize("small")
                font.family: ThemeManager.getFont("body")
                color: "#ffbe00"
            }
        }

        // Action list
        ListView {
            id: actionListView
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 4
            model: actionListModel
            currentIndex: focusedActionIndex

            delegate: Rectangle {
                required property int index
                required property string actionId
                required property string actionName
                required property string physicalInput
                required property string buttonDisplay

                width: actionListView.width
                height: 56
                radius: 10

                property bool isFocused: index === focusedActionIndex
                property bool isRemapping: isListening && listeningAction === actionId

                color: isRemapping
                       ? Qt.rgba(ThemeManager.getColor("primary").r,
                                 ThemeManager.getColor("primary").g,
                                 ThemeManager.getColor("primary").b, 0.2)
                       : (actionItemArea.containsMouse || isFocused)
                         ? Qt.rgba(ThemeManager.getColor("primary").r,
                                   ThemeManager.getColor("primary").g,
                                   ThemeManager.getColor("primary").b, 0.1)
                         : ThemeManager.getColor("hover")
                border.color: (actionItemArea.containsMouse || isFocused)
                              ? ThemeManager.getColor("focus") : "transparent"
                border.width: (actionItemArea.containsMouse || isFocused) ? 2 : 0

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 16
                    anchors.rightMargin: 16
                    spacing: 16

                    // Action name
                    Text {
                        text: actionName
                        font.pixelSize: ThemeManager.getFontSize("medium")
                        font.family: ThemeManager.getFont("body")
                        color: ThemeManager.getColor("textPrimary")
                        Layout.fillWidth: true
                    }

                    // Current button assignment
                    Rectangle {
                        Layout.preferredWidth: buttonLabel.width + 24
                        Layout.preferredHeight: 32
                        radius: 8
                        color: physicalInput !== ""
                               ? Qt.rgba(ThemeManager.getColor("secondary").r,
                                         ThemeManager.getColor("secondary").g,
                                         ThemeManager.getColor("secondary").b, 0.15)
                               : Qt.rgba(1, 1, 1, 0.05)

                        Text {
                            id: buttonLabel
                            anchors.centerIn: parent
                            text: buttonDisplay
                            font.pixelSize: ThemeManager.getFontSize("small")
                            font.family: ThemeManager.getFont("body")
                            font.bold: true
                            color: physicalInput !== ""
                                   ? ThemeManager.getColor("secondary")
                                   : ThemeManager.getColor("textSecondary")
                        }
                    }
                }

                MouseArea {
                    id: actionItemArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        focusedActionIndex = index
                        editor.forceActiveFocus()
                        startListening(index)
                    }
                }

                Behavior on color { ColorAnimation { duration: 120 } }
                Behavior on border.color { ColorAnimation { duration: 120 } }
            }
        }
    }
}
