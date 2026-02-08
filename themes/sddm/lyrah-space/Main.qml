import QtQuick 2.15
import SddmComponents 2.0

Rectangle {
    id: root
    width: Screen.width
    height: Screen.height

    property int selectedUser: 0

    // Deep space gradient background
    gradient: Gradient {
        GradientStop { position: 0.0; color: "#0a0d14" }
        GradientStop { position: 0.4; color: "#0f1419" }
        GradientStop { position: 0.7; color: "#12152a" }
        GradientStop { position: 1.0; color: "#0e0b1e" }
    }

    // Starfield
    Repeater {
        model: 80
        delegate: Rectangle {
            property real starX: Math.random()
            property real starY: Math.random()
            property real starSize: 1 + Math.random() * 2
            property real starOpacity: 0.3 + Math.random() * 0.7

            x: starX * root.width
            y: starY * root.height
            width: starSize
            height: starSize
            radius: starSize / 2
            color: "#ffffff"
            opacity: starOpacity

            SequentialAnimation on opacity {
                loops: Animation.Infinite
                NumberAnimation {
                    to: starOpacity * 0.3
                    duration: 2000 + Math.random() * 4000
                    easing.type: Easing.InOutSine
                }
                NumberAnimation {
                    to: starOpacity
                    duration: 2000 + Math.random() * 4000
                    easing.type: Easing.InOutSine
                }
            }
        }
    }

    // Nebula glow - top right
    Rectangle {
        x: root.width * 0.6
        y: -root.height * 0.1
        width: root.width * 0.5
        height: root.height * 0.5
        radius: width / 2
        opacity: 0.08
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#8b5cf6" }
            GradientStop { position: 1.0; color: "transparent" }
        }
    }

    // Nebula glow - bottom left
    Rectangle {
        x: -root.width * 0.15
        y: root.height * 0.55
        width: root.width * 0.45
        height: root.height * 0.45
        radius: width / 2
        opacity: 0.06
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#06b6d4" }
            GradientStop { position: 1.0; color: "transparent" }
        }
    }

    // Main content
    Column {
        anchors.centerIn: parent
        spacing: 32
        width: Math.min(root.width - 80, 700)

        // Logo + title
        Column {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 12

            // Procedural logo mark
            Item {
                width: 72
                height: 72
                anchors.horizontalCenter: parent.horizontalCenter

                Rectangle {
                    anchors.centerIn: parent
                    width: 68; height: 68; radius: 34
                    color: "transparent"
                    border.color: "#8b5cf6"; border.width: 3
                }
                Rectangle {
                    anchors.centerIn: parent
                    width: 56; height: 56; radius: 28
                    color: "transparent"
                    border.color: Qt.rgba(0.231, 0.510, 0.965, 0.4)
                    border.width: 1
                }
                Rectangle { x: 25; y: 18; width: 6; height: 36; color: "#ffffff" }
                Rectangle { x: 25; y: 49; width: 24; height: 6; color: "#ffffff" }
                Rectangle { x: 46; y: 20; width: 8; height: 8; radius: 4; color: "#06b6d4" }
            }

            Text {
                text: "Lyrah OS"
                font.pixelSize: 32
                font.bold: true
                color: "#ffffff"
                anchors.horizontalCenter: parent.horizontalCenter
            }

            Text {
                text: "Who's playing?"
                font.pixelSize: 16
                color: "#9ca3af"
                anchors.horizontalCenter: parent.horizontalCenter
            }
        }

        // ── User account cards ──
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 20

            Repeater {
                model: userModel

                Rectangle {
                    width: 120
                    height: 140
                    radius: 12
                    color: selectedUser === index
                           ? Qt.rgba(0.55, 0.36, 0.96, 0.25)
                           : Qt.rgba(0.04, 0.05, 0.15, 0.6)
                    border.color: selectedUser === index
                                  ? "#8b5cf6"
                                  : cardMouse.containsMouse
                                    ? Qt.rgba(0.55, 0.36, 0.96, 0.4)
                                    : Qt.rgba(1, 1, 1, 0.08)
                    border.width: selectedUser === index ? 2 : 1

                    Behavior on border.color { ColorAnimation { duration: 150 } }
                    Behavior on color { ColorAnimation { duration: 150 } }

                    scale: cardMouse.containsMouse ? 1.05 : 1.0
                    Behavior on scale { NumberAnimation { duration: 150 } }

                    Column {
                        anchors.centerIn: parent
                        spacing: 10

                        // Avatar circle
                        Rectangle {
                            width: 56
                            height: 56
                            radius: 28
                            anchors.horizontalCenter: parent.horizontalCenter
                            color: selectedUser === index ? "#7c3aed" : "#1f2937"
                            border.color: selectedUser === index
                                          ? "#a78bfa" : "#374151"
                            border.width: 2

                            Behavior on color { ColorAnimation { duration: 150 } }
                            Behavior on border.color { ColorAnimation { duration: 150 } }

                            // User icon image if available
                            Image {
                                anchors.fill: parent
                                anchors.margins: 2
                                source: icon || ""
                                fillMode: Image.PreserveAspectCrop
                                visible: status === Image.Ready

                                // Clip to circle
                                layer.enabled: true
                                layer.effect: Item {}
                            }

                            // Fallback: first letter of name
                            Text {
                                anchors.centerIn: parent
                                text: (realName || name).charAt(0).toUpperCase()
                                font.pixelSize: 24
                                font.bold: true
                                color: "#ffffff"
                                visible: !icon || icon === ""
                            }
                        }

                        // Display name
                        Text {
                            text: realName || name
                            font.pixelSize: 13
                            font.bold: selectedUser === index
                            color: selectedUser === index
                                   ? "#ffffff" : "#9ca3af"
                            anchors.horizontalCenter: parent.horizontalCenter
                            elide: Text.ElideRight
                            width: 100
                            horizontalAlignment: Text.AlignHCenter

                            Behavior on color { ColorAnimation { duration: 150 } }
                        }
                    }

                    MouseArea {
                        id: cardMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: {
                            selectedUser = index
                            passwordField.text = ""
                            passwordField.focus = true
                        }
                    }
                }
            }
        }

        // ── Password + session panel ──
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 360
            height: passwordCol.height + 40
            radius: 12
            color: Qt.rgba(0.04, 0.05, 0.15, 0.7)
            border.color: Qt.rgba(1, 1, 1, 0.06)
            border.width: 1

            Column {
                id: passwordCol
                anchors.centerIn: parent
                width: parent.width - 40
                spacing: 12

                PasswordBox {
                    id: passwordField
                    width: parent.width
                    height: 44
                    font.pixelSize: 14
                    color: "#1a1f2e"
                    borderColor: "#2a2f3e"
                    focusColor: "#8b5cf6"
                    textColor: "white"
                    focus: true
                    Keys.onReturnPressed: sddm.login(userModel.data(userModel.index(selectedUser, 0), Qt.UserRole + 1), passwordField.text, sessionSelect.index)
                }

                Row {
                    width: parent.width
                    spacing: 10

                    ComboBox {
                        id: sessionSelect
                        width: parent.width - loginBtn.width - 10
                        height: 44
                        model: sessionModel
                        index: sessionModel.lastIndex
                        font.pixelSize: 13
                        color: "#1a1f2e"
                        borderColor: "#2a2f3e"
                        focusColor: "#8b5cf6"
                        textColor: "white"
                    }

                    Button {
                        id: loginBtn
                        width: 100
                        height: 44
                        text: "Login"
                        color: "#7c3aed"
                        textColor: "white"
                        font.pixelSize: 15
                        onClicked: sddm.login(userModel.data(userModel.index(selectedUser, 0), Qt.UserRole + 1), passwordField.text, sessionSelect.index)
                    }
                }
            }
        }
    }

    // Initialize selected user to last logged in
    Component.onCompleted: {
        for (var i = 0; i < userModel.count; i++) {
            if (userModel.data(userModel.index(i, 0), Qt.UserRole + 1) === userModel.lastUser) {
                selectedUser = i
                break
            }
        }
    }
}
