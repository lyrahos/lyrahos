import QtQuick 2.15
import QtQuick.Controls 2.15

Rectangle {
    id: slideshow
    width: 800
    height: 400
    color: "#0f1419"

    property int currentSlide: 0
    readonly property var slides: [
        { title: "Welcome to Lyrah OS", text: "A gaming-focused Linux distribution built on Fedora 42." },
        { title: "Luna Mode", text: "A console-like gaming experience powered by gamescope. Launch games from a beautiful, controller-friendly interface." },
        { title: "Desktop Mode", text: "Full KDE Plasma 6 desktop for productivity, browsing, and everything else." },
        { title: "Game Compatibility", text: "Play Windows games via Proton/Wine. Supports Steam, Epic, GOG, and more." },
        { title: "Ready to Play", text: "Installation is almost complete. Enjoy Lyrah OS!" }
    ]

    // Starfield background
    Repeater {
        model: 40
        delegate: Rectangle {
            property real starX: Math.random()
            property real starY: Math.random()
            property real starSize: 1 + Math.random() * 1.5
            property real baseOpacity: 0.2 + Math.random() * 0.5

            x: starX * slideshow.width
            y: starY * slideshow.height
            width: starSize
            height: starSize
            radius: starSize / 2
            color: "#ffffff"
            opacity: baseOpacity

            SequentialAnimation on opacity {
                loops: Animation.Infinite
                NumberAnimation { to: baseOpacity * 0.2; duration: 3000 + Math.random() * 3000; easing.type: Easing.InOutSine }
                NumberAnimation { to: baseOpacity; duration: 3000 + Math.random() * 3000; easing.type: Easing.InOutSine }
            }
        }
    }

    // Nebula accent glow
    Rectangle {
        x: slideshow.width * 0.65
        y: -slideshow.height * 0.2
        width: slideshow.width * 0.4
        height: slideshow.height * 0.5
        radius: width / 2
        opacity: 0.06
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#8b5cf6" }
            GradientStop { position: 1.0; color: "transparent" }
        }
    }

    // Procedural logo mark
    Item {
        width: 48
        height: 48
        anchors.horizontalCenter: parent.horizontalCenter
        y: 40

        Rectangle {
            anchors.centerIn: parent
            width: 44; height: 44; radius: 22
            color: "transparent"
            border.color: "#8b5cf6"; border.width: 2
        }
        Rectangle {
            anchors.centerIn: parent
            width: 36; height: 36; radius: 18
            color: "transparent"
            border.color: Qt.rgba(0.231, 0.510, 0.965, 0.4); border.width: 1
        }
        Rectangle { x: 17; y: 12; width: 4; height: 24; color: "#ffffff" }
        Rectangle { x: 17; y: 32; width: 16; height: 4; color: "#ffffff" }
        Rectangle { x: 30; y: 13; width: 5; height: 5; radius: 2.5; color: "#06b6d4" }
    }

    Column {
        anchors.centerIn: parent
        anchors.verticalCenterOffset: 20
        spacing: 20

        Text {
            text: slides[currentSlide].title
            font.pixelSize: 28
            font.bold: true
            color: "#8b5cf6"
            anchors.horizontalCenter: parent.horizontalCenter
        }

        Text {
            text: slides[currentSlide].text
            font.pixelSize: 16
            color: "#ffffff"
            wrapMode: Text.WordWrap
            width: slideshow.width - 100
            horizontalAlignment: Text.AlignHCenter
            anchors.horizontalCenter: parent.horizontalCenter
        }

        // Slide indicator dots
        Row {
            spacing: 8
            anchors.horizontalCenter: parent.horizontalCenter

            Repeater {
                model: slides.length
                delegate: Rectangle {
                    width: currentSlide === index ? 20 : 8
                    height: 8
                    radius: 4
                    color: currentSlide === index ? "#3b82f6" : "#334155"
                    Behavior on width { NumberAnimation { duration: 200 } }
                    Behavior on color { ColorAnimation { duration: 200 } }
                }
            }
        }
    }

    Timer {
        interval: 5000
        running: true
        repeat: true
        onTriggered: currentSlide = (currentSlide + 1) % slides.length
    }
}
