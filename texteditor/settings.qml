import QtQuick 2.15

Rectangle {
    id: settingsRoot
    width: 320; height: 170; color: "#F5F5F5"

    signal backRequested()
    signal showLineNumbersToggled(bool enabled)
    signal resetSettingsRequested()

    property bool showLineNumbersEnabled: true

    // 使用公共标题栏
    TitleBar {
        width: parent.width
        title: "设置"
    }

    Flickable {
        x: 0; y: 20; width: parent.width; height: parent.height - 50
        contentWidth: width; contentHeight: columnContent.height
        boundsBehavior: Flickable.StopAtBounds; clip: true
        Column {
            id: columnContent
            width: parent.width; spacing: 0
            SwitchItem {
                label: "显示行号"
                isOn: showLineNumbersEnabled
                onToggled: settingsRoot.showLineNumbersToggled(on)
            }
        }
    }

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