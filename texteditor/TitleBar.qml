import QtQuick 2.15

Rectangle {
    id: titleBar
    width: parent.width
    height: 20
    color: "#E8E8E8"
    border.color: "#CCCCCC"
    border.width: 0.5

    property string title: ""
    property int currentChars: -1      // -1 时不显示
    property int totalChars: -1

    property string currentTime: ""
    Timer {
        interval: 1000; running: true; repeat: true
        onTriggered: currentTime = Qt.formatDateTime(new Date(), "hh:mm")
    }

    Row {
        anchors.fill: parent
        anchors.leftMargin: 5
        anchors.rightMargin: 0
        spacing: 0
        // 标题，占据左侧剩余空间
        Text {
            width: parent.width - rightText.width - 5  // 减去左右边距
            text: title
            font.family: "Microsoft YaHei"
            font.pixelSize: 12
            color: "#000000"
            elide: Text.ElideRight
            verticalAlignment: Text.AlignVCenter
            height: parent.height
        }

        // 右侧组合信息：字符统计（如果有）+ 两个空格 + 时间，始终右对齐
        Text {
            id: rightText
            text: {
                var info = ""
                if (currentChars >= 0 && totalChars >= 0) {
                    info = currentChars + "/" + totalChars + "  "   // 两个空格
                }
                return info + currentTime
            }
            font.family: "Microsoft YaHei"
            font.pixelSize: 12
            color: "#666666"
            verticalAlignment: Text.AlignVCenter
            height: parent.height
            horizontalAlignment: Text.AlignRight
        }
    }

    Component.onCompleted: {
        currentTime = Qt.formatDateTime(new Date(), "hh:mm")
    }
}