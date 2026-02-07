import QtQuick 2.15
import QtQuick.Controls 2.15

Rectangle {
    id: root
    width: 800
    height: 400
    color: "#090d14"

    property int currentSlide: 0
    readonly property var slides: [
        {
            kicker: "LYRAH OS",
            title: "Deployment, tuned for daily speed",
            text: "Fedora-based core with KDE Plasma, ready for gaming and productivity from first boot.",
            stat: "KDE Plasma 6 default"
        },
        {
            kicker: "PERFORMANCE",
            title: "Modern graphics stack",
            text: "Designed for low-latency sessions, current drivers, and broad game compatibility.",
            stat: "Proton + Wine ready"
        },
        {
            kicker: "WORKFLOW",
            title: "Desktop-first installation",
            text: "Installer applies a polished Plasma session automatically so setup is predictable.",
            stat: "No mode selection required"
        },
        {
            kicker: "READY",
            title: "Finish setup and launch",
            text: "After reboot, sign in to a clean space-themed environment and start immediately.",
            stat: "Install in minutes"
        }
    ]

    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#090d14" }
            GradientStop { position: 0.55; color: "#0d1523" }
            GradientStop { position: 1.0; color: "#101a2b" }
        }
    }

    Rectangle {
        width: parent.width * 0.7
        height: parent.height * 0.9
        x: parent.width * 0.45
        y: -parent.height * 0.25
        radius: width / 2
        color: "#5f8fda"
        opacity: 0.08
    }

    Rectangle {
        anchors.fill: parent
        color: "transparent"
        border.width: 1
        border.color: "#1e2b42"
    }

    Column {
        anchors.left: parent.left
        anchors.leftMargin: 48
        anchors.right: parent.right
        anchors.rightMargin: 48
        anchors.verticalCenter: parent.verticalCenter
        spacing: 20

        Text {
            text: slides[currentSlide].kicker
            color: "#7aa3ec"
            font.pixelSize: 12
            font.letterSpacing: 2
            font.bold: true
        }

        Text {
            text: slides[currentSlide].title
            color: "#e9f0ff"
            font.pixelSize: 34
            font.weight: Font.DemiBold
            wrapMode: Text.WordWrap
            width: parent.width * 0.75
        }

        Text {
            text: slides[currentSlide].text
            color: "#b8c8e6"
            font.pixelSize: 17
            lineHeight: 1.35
            wrapMode: Text.WordWrap
            width: parent.width * 0.72
        }

        Rectangle {
            width: 290
            height: 42
            radius: 8
            color: "#121e31"
            border.color: "#2e4366"
            border.width: 1

            Text {
                anchors.centerIn: parent
                text: slides[currentSlide].stat
                color: "#d8e6ff"
                font.pixelSize: 14
                font.bold: true
            }
        }

        Row {
            spacing: 10
            Repeater {
                model: slides.length
                delegate: Rectangle {
                    width: currentSlide === index ? 30 : 12
                    height: 5
                    radius: 3
                    color: currentSlide === index ? "#77a4f6" : "#334866"
                    Behavior on width { NumberAnimation { duration: 180 } }
                    Behavior on color { ColorAnimation { duration: 180 } }
                }
            }
        }
    }

    Timer {
        interval: 5500
        running: true
        repeat: true
        onTriggered: currentSlide = (currentSlide + 1) % slides.length
    }
}
