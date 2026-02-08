import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Rectangle {
    id: slideshow
    width: 800
    height: 440
    color: "#0d1117"

    property int currentSlide: 0
    readonly property var slides: [
        {
            title: "Welcome to Lyrah OS",
            text: "A gaming-focused Linux distribution built on Fedora.\nDesigned for gamers who want performance without complexity.",
            accent: "#a78bfa"
        },
        {
            title: "Luna Mode",
            text: "A console-like gaming experience powered by Gamescope.\nLaunch and manage your games from a sleek, controller-friendly interface.",
            accent: "#3b82f6"
        },
        {
            title: "Desktop Mode",
            text: "Full KDE Plasma 6 desktop for browsing, productivity, and everything else.\nSwitch between modes anytime from the login screen.",
            accent: "#06b6d4"
        },
        {
            title: "Play Anything",
            text: "Windows games run via Proton and Wine.\nSteam, Lutris, and your entire library — ready out of the box.",
            accent: "#10b981"
        },
        {
            title: "Almost There",
            text: "Installation is finishing up.\nYou'll be gaming in no time.",
            accent: "#a78bfa"
        }
    ]

    // Starfield background
    Repeater {
        model: 60
        delegate: Rectangle {
            property real starX: Math.random()
            property real starY: Math.random()
            property real starSize: 1 + Math.random() * 1.5
            property real baseOpacity: 0.15 + Math.random() * 0.4

            x: starX * slideshow.width
            y: starY * slideshow.height
            width: starSize
            height: starSize
            radius: starSize / 2
            color: "#ffffff"
            opacity: baseOpacity

            SequentialAnimation on opacity {
                loops: Animation.Infinite
                NumberAnimation { to: baseOpacity * 0.15; duration: 2500 + Math.random() * 4000; easing.type: Easing.InOutSine }
                NumberAnimation { to: baseOpacity; duration: 2500 + Math.random() * 4000; easing.type: Easing.InOutSine }
            }
        }
    }

    // Subtle accent glow (changes color per slide)
    Rectangle {
        x: slideshow.width * 0.6
        y: -slideshow.height * 0.3
        width: slideshow.width * 0.5
        height: slideshow.height * 0.6
        radius: width / 2
        opacity: 0.04
        color: slides[currentSlide].accent

        Behavior on color { ColorAnimation { duration: 800 } }
    }

    Rectangle {
        x: -slideshow.width * 0.1
        y: slideshow.height * 0.6
        width: slideshow.width * 0.4
        height: slideshow.height * 0.5
        radius: width / 2
        opacity: 0.03
        color: slides[currentSlide].accent

        Behavior on color { ColorAnimation { duration: 800 } }
    }

    // Content
    Item {
        anchors.fill: parent
        anchors.margins: 40

        // Slide content with fade transition
        Column {
            anchors.centerIn: parent
            spacing: 24
            width: parent.width

            // Accent line
            Rectangle {
                width: 48
                height: 3
                radius: 2
                color: slides[currentSlide].accent
                anchors.horizontalCenter: parent.horizontalCenter

                Behavior on color { ColorAnimation { duration: 500 } }
            }

            // Title
            Text {
                text: slides[currentSlide].title
                font.pixelSize: 32
                font.bold: true
                color: "#ffffff"
                anchors.horizontalCenter: parent.horizontalCenter
                horizontalAlignment: Text.AlignHCenter

                Behavior on text {
                    SequentialAnimation {
                        NumberAnimation { target: titleFade; property: "opacity"; to: 0; duration: 200 }
                        PropertyAction {}
                        NumberAnimation { target: titleFade; property: "opacity"; to: 1; duration: 300 }
                    }
                }
            }

            // Description
            Text {
                id: titleFade
                text: slides[currentSlide].text
                font.pixelSize: 16
                lineHeight: 1.6
                color: "#9ca3af"
                wrapMode: Text.WordWrap
                width: Math.min(parent.width, 560)
                horizontalAlignment: Text.AlignHCenter
                anchors.horizontalCenter: parent.horizontalCenter
            }
        }

        // Slide indicator dots at bottom
        Row {
            spacing: 10
            anchors.bottom: parent.bottom
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottomMargin: 8

            Repeater {
                model: slides.length
                delegate: Rectangle {
                    width: currentSlide === index ? 24 : 8
                    height: 8
                    radius: 4
                    color: currentSlide === index ? slides[currentSlide].accent : "#374151"

                    Behavior on width { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
                    Behavior on color { ColorAnimation { duration: 250 } }

                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -4
                        onClicked: currentSlide = index
                    }
                }
            }
        }
    }

    Timer {
        interval: 6000
        running: true
        repeat: true
        onTriggered: currentSlide = (currentSlide + 1) % slides.length
    }
}
