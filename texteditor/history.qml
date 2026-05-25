import QtQuick 2.15

Rectangle {
    id: historyRoot
    width: 320; height: 170; color: "#F5F5F5"

    property var historyModel: []
    signal urlClicked(string url, int index)
    signal clearHistoryRequested()
    signal backRequested()

    // 预防点击穿透
    MouseArea { anchors.fill: parent }

    // 使用公共标题栏
    TitleBar {
        width: parent.width
        title: "历史记录"
    }

    // 列表区
    ListView {
        id: listView
        x: 0; y: 20; width: parent.width; height: parent.height - 50; clip: true
        model: historyModel.slice().reverse()
        delegate: Rectangle {
            width: listView.width; height: 30
            color: mouseArea.pressed ? "#E0E0E0" : "transparent"
            Text {
                anchors.fill: parent; anchors.leftMargin: 8; anchors.rightMargin: 8
                verticalAlignment: Text.AlignVCenter; text: modelData
                font.family: "Microsoft YaHei"; font.pixelSize: 12; color: "#000000"; elide: Text.ElideRight
            }
            MouseArea {
                id: mouseArea; anchors.fill: parent
                onClicked: { var ri = historyModel.length - 1 - index; historyRoot.urlClicked(modelData, ri) }
            }
        }
    }

    // 底部栏
    Rectangle {
        x: 0; y: parent.height - 30; width: parent.width; height: 30; color: "#EEEEEE"; border.color: "#CCCCCC"; border.width: 0.5
        Row {
            anchors.fill: parent; anchors.leftMargin: 4; anchors.rightMargin: 4; spacing: 4
            Rectangle {
                width: 156; height: 26; anchors.verticalCenter: parent.verticalCenter; radius: 3
                color: backArea.pressed ? "#D0D0D0" : "#E0E0E0"; border.color: "#B0B0B0"; border.width: 0.5
                Text { anchors.centerIn: parent; text: "返回"; font.family: "Microsoft YaHei"; font.pixelSize: 13; color: "#000000" }
                MouseArea { id: backArea; anchors.fill: parent; onClicked: historyRoot.backRequested() }
            }
            Rectangle {
                width: 156; height: 26; anchors.verticalCenter: parent.verticalCenter; radius: 3
                color: clearArea.pressed ? "#D0D0D0" : "#E0E0E0"; border.color: "#B0B0B0"; border.width: 0.5
                Text { anchors.centerIn: parent; text: "清空"; font.family: "Microsoft YaHei"; font.pixelSize: 13; color: "#FF0000" }
                MouseArea { id: clearArea; anchors.fill: parent; onClicked: historyRoot.clearHistoryRequested() }
            }
        }
    }
}