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

    // Static starfield — no animations, just random dots to avoid
    // continuous per-frame updates that cause input lag on SDDM.
    Repeater {
        model: 40
        delegate: Rectangle {
            x: Math.random() * root.width
            y: Math.random() * root.height
            width: 1 + Math.random() * 2
            height: width
            radius: width / 2
            color: "#ffffff"
            opacity: 0.2 + Math.random() * 0.6
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
                                  : Qt.rgba(1, 1, 1, 0.08)
                    border.width: selectedUser === index ? 2 : 1

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

                            // User icon image if available
                            Image {
                                anchors.fill: parent
                                anchors.margins: 2
                                source: icon || ""
                                fillMode: Image.PreserveAspectCrop
                                visible: status === Image.Ready
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
                        }
                    }

                    MouseArea {
                        id: cardMouse
                        anchors.fill: parent
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
