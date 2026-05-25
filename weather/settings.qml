import QtQuick 2.15

Rectangle {
    id: settingsRoot
    color: "#FFFFFF"
    anchors.fill: parent
    z: 101

    property var mainApp: null

    signal back()

    Text {
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 6
        text: mainApp ? mainApp.currentDateTime : ""
        color: "#2C3E50"
        font.family: "Microsoft YaHei"
        font.pixelSize: 14
        opacity: 0.8
        z: 2
    }

    Item {
        id: titleBar
        x: 8; y: 1
        width: parent.width - 16
        height: 30

        Text {
            text: "设置"
            font.bold: true; font.pixelSize: 16; font.family: "Microsoft YaHei"; color: "#2C3E50"
            anchors.verticalCenter: parent.verticalCenter
        }
    }

    Flickable {
        id: flickableArea
        anchors.top: titleBar.bottom
        anchors.topMargin: 4
        anchors.bottom: bottomBar.top
        anchors.bottomMargin: 4
        anchors.left: parent.left
        anchors.right: parent.right
        contentWidth: parent.width
        contentHeight: switchesColumn.height
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: switchesColumn
            width: parent.width
            spacing: 4

            SwitchItem {
                label: "显示经纬度"
                isOn: mainApp ? mainApp.showGeo : true
                onToggled: function(on) {
                    if (mainApp) mainApp.showGeo = on;
                }
            }

            SwitchItem {
                label: "记录日志"
                isOn: mainApp ? mainApp.enableLog : false
                onToggled: function(on) {
                    if (mainApp) mainApp.enableLog = on;
                }
            }

            SwitchItem {
                label: "温度保留小数"
                isOn: mainApp ? mainApp.keepDecimal : true
                onToggled: function(on) {
                    if (mainApp) mainApp.keepDecimal = on;
                }
            }

            SwitchItem {
                label: "延长超时"
                isOn: mainApp ? mainApp.extendTimeout : false
                onToggled: function(on) {
                    if (mainApp) mainApp.extendTimeout = on;
                }
            }
        }
    }

    Row {
        id: bottomBar
        x: 8
        y: parent.height - 8 - 32
        width: parent.width - 16
        height: 32
        spacing: 6

        Rectangle {
            width: (parent.width - 6) / 2; height: 32; radius: 4
            color: __btnBack.pressed ? "#357ABD" : "#4A90E2"
            Text { text: "返回"; color: "white"; font.family: "Microsoft YaHei"; font.pixelSize: 16; anchors.centerIn: parent }
            MouseArea {
                id: __btnBack
                anchors.fill: parent
                onClicked: back()
            }
        }

        Rectangle {
            width: (parent.width - 6) / 2; height: 32; radius: 4
            color: __btnReset.pressed ? "#C0392B" : "#E74C3C"
            Text { text: "重置"; color: "white"; font.family: "Microsoft YaHei"; font.pixelSize: 16; anchors.centerIn: parent }
            MouseArea {
                id: __btnReset
                anchors.fill: parent
                onClicked: {
                    if (mainApp) {
                        mainApp.showGeo = true;
                        mainApp.enableLog = false;
                        mainApp.keepDecimal = true;
                        mainApp.extendTimeout = false;
                    }
                }
            }
        }
    }

    component SwitchItem: Rectangle {
        property string label: ""
        property bool isOn: false
        signal toggled(bool on)

        width: parent.width; height: 30
        color: switchArea.pressed ? "#E0E0E0" : "transparent"

        Row {
            anchors.fill: parent
            anchors.leftMargin: 8; anchors.rightMargin: 8
            spacing: 8

            Text {
                text: label
                font.family: "Microsoft YaHei"
                font.pixelSize: 14
                color: "#2C3E50"
                anchors.verticalCenter: parent.verticalCenter
            }

            Text {
                text: isOn ? "开" : "关"
                font.family: "Microsoft YaHei"
                font.pixelSize: 14
                color: isOn ? "#4CAF50" : "#E74C3C"
                anchors.verticalCenter: parent.verticalCenter
                anchors.right: parent.right
            }
        }

        MouseArea {
            id: switchArea
            anchors.fill: parent
            onClicked: parent.toggled(!parent.isOn)
        }
    }
}