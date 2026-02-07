import QtQuick 2.15
import QtQuick.Controls 2.15
import SddmComponents 2.0

Rectangle {
    id: root
    width: Screen.width
    height: Screen.height

    // Deep space gradient background - no external image needed
    gradient: Gradient {
        GradientStop { position: 0.0; color: "#0a0d14" }
        GradientStop { position: 0.4; color: "#0f1419" }
        GradientStop { position: 0.7; color: "#12152a" }
        GradientStop { position: 1.0; color: "#0e0b1e" }
    }

    // Starfield: scattered dots to simulate distant stars
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

    // Subtle nebula glow - top right
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

    // Subtle nebula glow - bottom left
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

    // Login panel
    Rectangle {
        anchors.centerIn: parent
        width: 400
        height: 380
        radius: 16
        color: Qt.rgba(0.04, 0.05, 0.15, 0.85)
        border.color: Qt.rgba(0.55, 0.36, 0.96, 0.4)
        border.width: 1

        Column {
            anchors.centerIn: parent
            spacing: 16
            width: parent.width - 60

            // Procedural logo mark: ring + L
            Item {
                width: 64
                height: 64
                anchors.horizontalCenter: parent.horizontalCenter

                // Outer ring
                Rectangle {
                    anchors.centerIn: parent
                    width: 60; height: 60; radius: 30
                    color: "transparent"
                    border.color: "#8b5cf6"
                    border.width: 3
                }

                // Inner glow ring
                Rectangle {
                    anchors.centerIn: parent
                    width: 50; height: 50; radius: 25
                    color: "transparent"
                    border.color: Qt.rgba(0.231, 0.510, 0.965, 0.4)
                    border.width: 1
                }

                // L letterform - vertical
                Rectangle {
                    x: 22; y: 16
                    width: 5; height: 32
                    color: "#ffffff"
                }

                // L letterform - horizontal
                Rectangle {
                    x: 22; y: 43
                    width: 22; height: 5
                    color: "#ffffff"
                }

                // Accent dot
                Rectangle {
                    x: 40; y: 18
                    width: 7; height: 7; radius: 3.5
                    color: "#06b6d4"
                }
            }

            Text {
                text: "Lyrah OS"
                font.pixelSize: 28
                font.bold: true
                color: "#8b5cf6"
                anchors.horizontalCenter: parent.horizontalCenter
            }

            TextField {
                id: userField
                width: parent.width
                placeholderText: "Username"
                text: userModel.lastUser
                color: "white"
                background: Rectangle { color: "#1a1f2e"; radius: 8 }
            }

            TextField {
                id: passwordField
                width: parent.width
                placeholderText: "Password"
                echoMode: TextInput.Password
                color: "white"
                background: Rectangle { color: "#1a1f2e"; radius: 8 }
                Keys.onReturnPressed: sddm.login(userField.text, passwordField.text, sessionSelect.currentIndex)
            }

            ComboBox {
                id: sessionSelect
                width: parent.width
                model: sessionModel
                textRole: "name"
                currentIndex: sessionModel.lastIndex
            }

            Button {
                text: "Login"
                width: parent.width
                onClicked: sddm.login(userField.text, passwordField.text, sessionSelect.currentIndex)
            }
        }
    }
}
