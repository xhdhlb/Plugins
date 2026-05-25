import QtQuick 2.15

Rectangle {
    id: titleBar
    width: parent.width
    height: 20
    color: "#E8E8E8"
    border.color: "#CCCCCC"
    border.width: 0.5

    property string title: ""

    property string currentTime: ""
    Timer {
        interval: 1000; running: true; repeat: true
        onTriggered: currentTime = Qt.formatDateTime(new Date(), "hh:mm:ss")
    }

    Row {
        anchors.fill: parent
        anchors.leftMargin: 6
        anchors.rightMargin: 6
        spacing: 8
        Text {
            width: parent.width - timeText.width - 16
            text: title
            font.family: "Microsoft YaHei"
            font.pixelSize: 12
            color: "#000000"
            elide: Text.ElideRight
            verticalAlignment: Text.AlignVCenter
            height: parent.height
        }
        Text {
            id: timeText
            text: currentTime
            font.family: "Microsoft YaHei"
            font.pixelSize: 11
            color: "#666666"
            verticalAlignment: Text.AlignVCenter
            height: parent.height
        }
    }

    Component.onCompleted: {
        currentTime = Qt.formatDateTime(new Date(), "hh:mm:ss")
    }
}