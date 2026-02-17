import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// ─── Luna-UI Virtual Keyboard ───
// Controller-navigable on-screen keyboard for text input.
// Uses D-pad to move between keys, Confirm to press, Back to cancel.

Item {
    id: vk
    anchors.fill: parent
    visible: false
    z: 9999

    property string text: ""
    property string placeholderText: "Type here..."
    property bool passwordMode: false
    property bool isShifted: false
    property bool showNumbers: false
    property int focusRow: 0
    property int focusCol: 0

    signal accepted(string text)
    signal cancelled()

    // ─── Key Layouts ───
    readonly property var letterRows: [
        ["q","w","e","r","t","y","u","i","o","p"],
        ["a","s","d","f","g","h","j","k","l"],
        ["z","x","c","v","b","n","m"]
    ]

    readonly property var numberRows: [
        ["1","2","3","4","5","6","7","8","9","0"],
        ["@","#","$","_","&","-","+","(",")"],
        ["!","\"","'",":",";","/","?"]
    ]

    // Action row: Shift | Space | Backspace | Search
    readonly property var actionKeys: ["Shift", "Space", "Backspace", "Search"]

    readonly property var currentRows: showNumbers ? numberRows : letterRows

    function open(initialText, isPassword) {
        text = initialText || ""
        passwordMode = isPassword || false
        isShifted = false
        showNumbers = false
        focusRow = 0
        focusCol = 0
        visible = true
        vk.forceActiveFocus()
    }

    function close() {
        visible = false
    }

    function currentRowLength(row) {
        if (row < currentRows.length)
            return currentRows[row].length
        return actionKeys.length
    }

    function isActionRow() {
        return focusRow >= currentRows.length
    }

    function pressCurrentKey() {
        if (isActionRow()) {
            var action = actionKeys[focusCol]
            switch (action) {
            case "Shift":
                isShifted = !isShifted
                break
            case "Space":
                text += " "
                break
            case "Backspace":
                if (text.length > 0)
                    text = text.substring(0, text.length - 1)
                break
            case "Search":
                accepted(text)
                close()
                break
            }
        } else {
            var ch = currentRows[focusRow][focusCol]
            if (isShifted) ch = ch.toUpperCase()
            text += ch
            if (isShifted) isShifted = false
        }
    }

    // ─── Key Handler ───
    Keys.onPressed: function(event) {
        switch (event.key) {
        case Qt.Key_Left:
            if (focusCol > 0) focusCol--
            event.accepted = true
            break
        case Qt.Key_Right:
            if (focusCol < currentRowLength(focusRow) - 1) focusCol++
            event.accepted = true
            break
        case Qt.Key_Up:
            if (focusRow > 0) {
                focusRow--
                if (focusCol >= currentRowLength(focusRow))
                    focusCol = currentRowLength(focusRow) - 1
            }
            event.accepted = true
            break
        case Qt.Key_Down:
            var totalRows = currentRows.length + 1
            if (focusRow < totalRows - 1) {
                focusRow++
                if (focusCol >= currentRowLength(focusRow))
                    focusCol = currentRowLength(focusRow) - 1
            }
            event.accepted = true
            break
        case Qt.Key_Return:
        case Qt.Key_Enter:
            pressCurrentKey()
            event.accepted = true
            break
        case Qt.Key_Escape:
            cancelled()
            close()
            event.accepted = true
            break
        // Shoulder buttons: toggle number/symbol mode
        case Qt.Key_BracketLeft:   // L1 often maps here
        case Qt.Key_BracketRight:  // R1 often maps here
            showNumbers = !showNumbers
            if (focusCol >= currentRowLength(focusRow))
                focusCol = currentRowLength(focusRow) - 1
            event.accepted = true
            break
        }
    }

    // ─── Dimmed Background ───
    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.75)
        opacity: vk.visible ? 1.0 : 0.0
        Behavior on opacity { NumberAnimation { duration: 200 } }

        MouseArea {
            anchors.fill: parent
            onClicked: { vk.cancelled(); vk.close() }
        }
    }

    // ─── Keyboard Panel ───
    Rectangle {
        id: keyboardPanel
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 40
        width: Math.min(parent.width - 80, 1100)
        height: panelContent.height + 48
        radius: 24
        color: ThemeManager.getColor("surface")
        border.color: Qt.rgba(ThemeManager.getColor("primary").r,
                               ThemeManager.getColor("primary").g,
                               ThemeManager.getColor("primary").b, 0.3)
        border.width: 2

        // Top glow accent bar
        Rectangle {
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: 24
            anchors.rightMargin: 24
            height: 3
            radius: 2
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: ThemeManager.getColor("primary") }
                GradientStop { position: 0.5; color: ThemeManager.getColor("accent") }
                GradientStop { position: 1.0; color: ThemeManager.getColor("secondary") }
            }
        }

        ColumnLayout {
            id: panelContent
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: 24
            spacing: 16

            // ─── Text Preview ───
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 64
                radius: 14
                color: ThemeManager.getColor("background")
                border.color: ThemeManager.getColor("focus")
                border.width: 2

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 20
                    anchors.rightMargin: 20
                    spacing: 10

                    Text {
                        text: "\u2315"
                        font.pixelSize: 28
                        color: ThemeManager.getColor("textSecondary")
                    }

                    Text {
                        Layout.fillWidth: true
                        text: {
                            if (vk.text.length === 0) return vk.placeholderText
                            if (vk.passwordMode) return "\u2022".repeat(vk.text.length)
                            return vk.text
                        }
                        font.pixelSize: 28
                        font.family: ThemeManager.getFont("body")
                        color: vk.text.length > 0
                               ? ThemeManager.getColor("textPrimary")
                               : ThemeManager.getColor("textSecondary")
                        elide: Text.ElideRight
                        verticalAlignment: Text.AlignVCenter
                    }

                    // Blinking cursor
                    Rectangle {
                        visible: vk.text.length > 0
                        Layout.preferredWidth: 2
                        Layout.preferredHeight: 28
                        color: ThemeManager.getColor("focus")
                        opacity: cursorBlink.running ? (cursorBlink.blinkOn ? 1.0 : 0.0) : 1.0

                        Timer {
                            id: cursorBlink
                            property bool blinkOn: true
                            interval: 530
                            running: vk.visible
                            repeat: true
                            onTriggered: blinkOn = !blinkOn
                        }
                    }
                }
            }

            // ─── Mode Toggle Hint ───
            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                Rectangle {
                    Layout.preferredWidth: modeLabel.width + 28
                    Layout.preferredHeight: 36
                    radius: 8
                    color: showNumbers
                           ? ThemeManager.getColor("accent")
                           : ThemeManager.getColor("primary")

                    Text {
                        id: modeLabel
                        anchors.centerIn: parent
                        text: showNumbers ? "123" : "ABC"
                        font.pixelSize: 20
                        font.family: ThemeManager.getFont("ui")
                        font.bold: true
                        color: "#ffffff"
                    }
                }

                Text {
                    text: "LB / RB to switch"
                    font.pixelSize: 20
                    font.family: ThemeManager.getFont("ui")
                    color: ThemeManager.getColor("textSecondary")
                }

                Item { Layout.fillWidth: true }

                Text {
                    text: "B  Cancel"
                    font.pixelSize: 20
                    font.family: ThemeManager.getFont("ui")
                    color: ThemeManager.getColor("textSecondary")
                }
            }

            // ─── Key Rows ───
            Repeater {
                model: currentRows.length

                Row {
                    id: keyRow
                    property int rowIndex: index
                    Layout.alignment: Qt.AlignHCenter
                    spacing: 8

                    Repeater {
                        model: currentRows[keyRow.rowIndex]

                        Rectangle {
                            id: keyRect
                            property bool isFocused: vk.focusRow === keyRow.rowIndex && vk.focusCol === index
                            width: 72
                            height: 64
                            radius: 12
                            color: isFocused
                                   ? ThemeManager.getColor("primary")
                                   : ThemeManager.getColor("hover")
                            border.color: isFocused
                                          ? ThemeManager.getColor("focus")
                                          : "transparent"
                            border.width: isFocused ? 2 : 0

                            Behavior on color { ColorAnimation { duration: 120 } }
                            Behavior on scale { NumberAnimation { duration: 100 } }
                            scale: isFocused ? 1.08 : 1.0

                            Text {
                                anchors.centerIn: parent
                                text: {
                                    var ch = modelData
                                    if (!vk.showNumbers && vk.isShifted)
                                        ch = ch.toUpperCase()
                                    return ch
                                }
                                font.pixelSize: 28
                                font.family: ThemeManager.getFont("ui")
                                font.bold: isFocused
                                color: isFocused ? "#ffffff" : ThemeManager.getColor("textPrimary")
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    vk.focusRow = keyRow.rowIndex
                                    vk.focusCol = index
                                    vk.pressCurrentKey()
                                }
                            }
                        }
                    }
                }
            }

            // ─── Action Row ───
            Row {
                Layout.alignment: Qt.AlignHCenter
                spacing: 12

                Repeater {
                    model: actionKeys

                    Rectangle {
                        property bool isFocused: vk.isActionRow() && vk.focusCol === index
                        property bool isActive: {
                            if (modelData === "Shift") return vk.isShifted
                            return false
                        }
                        width: {
                            switch (modelData) {
                            case "Space": return 320
                            case "Backspace": return 140
                            case "Search": return 140
                            default: return 100
                            }
                        }
                        height: 64
                        radius: 12
                        color: {
                            if (isFocused) return ThemeManager.getColor("primary")
                            if (isActive) return Qt.darker(ThemeManager.getColor("primary"), 1.4)
                            if (modelData === "Search") return Qt.rgba(
                                ThemeManager.getColor("accent").r,
                                ThemeManager.getColor("accent").g,
                                ThemeManager.getColor("accent").b, 0.3)
                            return ThemeManager.getColor("hover")
                        }
                        border.color: isFocused
                                      ? ThemeManager.getColor("focus")
                                      : isActive ? ThemeManager.getColor("primary") : "transparent"
                        border.width: (isFocused || isActive) ? 2 : 0

                        Behavior on color { ColorAnimation { duration: 120 } }
                        Behavior on scale { NumberAnimation { duration: 100 } }
                        scale: isFocused ? 1.06 : 1.0

                        Text {
                            anchors.centerIn: parent
                            text: {
                                switch (modelData) {
                                case "Shift": return vk.isShifted ? "\u21E7 ON" : "\u21E7"
                                case "Space": return "\u2423  Space"
                                case "Backspace": return "\u232B"
                                case "Search": return "\u2315 Search"
                                default: return modelData
                                }
                            }
                            font.pixelSize: modelData === "Backspace" ? 32 : 24
                            font.family: ThemeManager.getFont("ui")
                            font.bold: isFocused || modelData === "Search"
                            color: isFocused ? "#ffffff"
                                   : modelData === "Search" ? ThemeManager.getColor("accent")
                                   : ThemeManager.getColor("textPrimary")
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                vk.focusRow = vk.currentRows.length
                                vk.focusCol = index
                                vk.pressCurrentKey()
                            }
                        }
                    }
                }
            }
        }
    }
}
