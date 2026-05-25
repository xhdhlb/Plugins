import QtQuick 2.15

Rectangle {
    id: settingsRoot
    width: 320; height: 170; color: "#F5F5F5"

    signal backRequested()
    signal resetZoomRequested()
    signal wrapTextToggled(bool enabled)
    signal horizontalScrollToggled(bool enabled)
    signal showRawContentToggled(bool enabled)
    signal editSearchTemplate()
    signal resetSettingsRequested()

    property int zoomPercent: 100
    property bool wrapTextEnabled: true
    property bool horizontalScrollEnabled: false
    property bool showRawContentEnabled: false
    property string searchTemplate: ""
    property bool showTemplateWarning: false

    // 预防穿透
    MouseArea { anchors.fill: parent }

    TitleBar {
        id: titleBar
        width: parent.width
        height: 20
        title: "设置"
    }

    // 可滚动的设置内容区域
    Flickable {
        x: 0; y: 20; width: parent.width; height: parent.height - 50
        contentWidth: width
        contentHeight: columnContent.height
        boundsBehavior: Flickable.StopAtBounds
        clip: true

        Column {
            id: columnContent
            width: parent.width
            spacing: 0

            Rectangle {
                width: parent.width; height: 30; color: resetZoomArea.pressed ? "#E0E0E0" : "transparent"
                Row {
                    anchors.fill: parent; anchors.leftMargin: 8; anchors.rightMargin: 8
                    Text { anchors.verticalCenter: parent.verticalCenter; text: "重置网页缩放"; font.family: "Microsoft YaHei"; font.pixelSize: 13; color: "#000000" }
                    Text { anchors.verticalCenter: parent.verticalCenter; anchors.right: parent.right; text: "当前: " + zoomPercent + "%"; font.family: "Microsoft YaHei"; font.pixelSize: 13; color: "#000000" }
                }
                MouseArea { id: resetZoomArea; anchors.fill: parent; onClicked: settingsRoot.resetZoomRequested() }
            }

            Rectangle {
                width: parent.width; height: 30; color: searchArea.pressed ? "#E0E0E0" : "transparent"
                Row {
                    anchors.fill: parent; anchors.leftMargin: 8; anchors.rightMargin: 8
                    Text { anchors.verticalCenter: parent.verticalCenter; text: "搜索引擎"; font.family: "Microsoft YaHei"; font.pixelSize: 13; color: "#000000" }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter; anchors.right: parent.right; width: 220
                        text: searchTemplate; font.family: "Microsoft YaHei"; font.pixelSize: 13; color: "#000000"
                        elide: Text.ElideRight; horizontalAlignment: Text.AlignRight
                    }
                }
                MouseArea { id: searchArea; anchors.fill: parent; onClicked: settingsRoot.editSearchTemplate() }
            }

            SwitchItem {
                label: "自动换行"; isOn: wrapTextEnabled
                onToggled: settingsRoot.wrapTextToggled(on)
            }
            SwitchItem {
                label: "允许左右滑动"; isOn: horizontalScrollEnabled
                onToggled: settingsRoot.horizontalScrollToggled(on)
            }
            SwitchItem {
                label: "查看原始网页内容"; isOn: showRawContentEnabled
                onToggled: settingsRoot.showRawContentToggled(on)
            }
        }
    }

    // 底部栏
    Rectangle {
        x: 0; y: parent.height - 30; width: parent.width; height: 30; color: "#EEEEEE"; border.color: "#CCCCCC"; border.width: 0.5
        Row {
            anchors.fill: parent; anchors.leftMargin: 4; anchors.rightMargin: 4; spacing: 4
            Rectangle {
                width: 154; height: 26; anchors.verticalCenter: parent.verticalCenter; radius: 3
                color: backArea.pressed ? "#D0D0D0" : "#E0E0E0"; border.color: "#B0B0B0"; border.width: 0.5
                Text { anchors.centerIn: parent; text: "返回"; font.family: "Microsoft YaHei"; font.pixelSize: 14; color: "#000000" }
                MouseArea { id: backArea; anchors.fill: parent; onClicked: settingsRoot.backRequested() }
            }
            Rectangle {
                width: 154; height: 26; anchors.verticalCenter: parent.verticalCenter; radius: 3
                color: resetArea.pressed ? "#D0D0D0" : "#E0E0E0"; border.color: "#B0B0B0"; border.width: 0.5
                Text { anchors.centerIn: parent; text: "重置"; font.family: "Microsoft YaHei"; font.pixelSize: 14; color: "#FF0000" }
                MouseArea { id: resetArea; anchors.fill: parent; onClicked: settingsRoot.resetSettingsRequested() }
            }
        }
    }

    // 占位符警告遮罩与弹窗
    MouseArea {
        visible: showTemplateWarning; anchors.fill: parent; z: 109; onClicked: {}
    }
    Rectangle {
        visible: showTemplateWarning
        x: (parent.width - 240) / 2; y: (parent.height - 100) / 2; z: 110; width: 240; height: 100
        color: "#FFFFFF"; border.color: "#AAAAAA"; border.width: 1; radius: 6
        Column {
            anchors.centerIn: parent; spacing: 8
            Text {
                text: "需包含至少一个关键词占位符%1"; font.family: "Microsoft YaHei"; font.pixelSize: 13; color: "#000000"
                horizontalAlignment: Text.AlignHCenter; width: 220; wrapMode: Text.Wrap
            }
            Text {
                text: "（点击关闭）"; font.family: "Microsoft YaHei"; font.pixelSize: 12; color: "#888888"
                anchors.horizontalCenter: parent.horizontalCenter
            }
        }
        MouseArea { anchors.fill: parent; onClicked: showTemplateWarning = false }
    }

    component SwitchItem: Rectangle {
        property string label: ""
        property bool isOn: false
        signal toggled(bool on)
        width: parent.width; height: 30; color: switchArea.pressed ? "#E0E0E0" : "transparent"
        Row {
            anchors.fill: parent; anchors.leftMargin: 8; anchors.rightMargin: 8
            Text { anchors.verticalCenter: parent.verticalCenter; text: label; font.family: "Microsoft YaHei"; font.pixelSize: 13; color: "#000000" }
            Text {
                anchors.verticalCenter: parent.verticalCenter; anchors.right: parent.right
                text: isOn ? "开" : "关"; font.family: "Microsoft YaHei"; font.pixelSize: 13
                color: isOn ? "#4CAF50" : "#FF0000"
            }
        }
        MouseArea { id: switchArea; anchors.fill: parent; onClicked: parent.toggled(!parent.isOn) }
    }
}