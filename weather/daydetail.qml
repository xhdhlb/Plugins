import QtQuick 2.15

Rectangle {
    id: detailRoot
    width: 320
    height: 170
    color: "#FFFFFF"

    property var mainApp: null
    property var dayData: null

    signal back()

    // 右上角时间
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

    // 标题（向左偏移，内部文字居中）
    Text {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.rightMargin: 60   // 为返回按钮留出空间
        y: 10
        text: (mainApp ? mainApp.currentCity : "") + "  " + (dayData ? dayData.date : "")
        font.family: "Microsoft YaHei"
        font.pixelSize: 22
        font.bold: true
        color: "#2C3E50"
        horizontalAlignment: Text.AlignHCenter
    }

    // 可滚动详情（向左偏移）
    Flickable {
        anchors.top: parent.top
        anchors.topMargin: 40
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.rightMargin: 60   // 右侧留出按钮宽度
        contentWidth: parent.width - 60
        contentHeight: detailText.implicitHeight + 20
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Text {
            id: detailText
            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width - 32
            y: 3
            text: {
                if (!dayData) return "";
                var lines = [
                    dayData.desc,
                    (dayData.low && dayData.high) ? (dayData.low + "~" + dayData.high + "°C") : "",
                    dayData.meanTemp !== undefined ? ("平均温度 " + dayData.meanTemp + "°C") : "",
                    dayData.meanApparent !== undefined ? ("平均体感 " + dayData.meanApparent + "°C") : "",
                    dayData.precip !== undefined ? ("总降水 " + dayData.precip + "mm") : "",
                    dayData.precipHours !== undefined ? ("降水小时数 " + dayData.precipHours + "h") : "",
                    dayData.maxWind !== undefined ? ("最大风速 " + dayData.maxWind + "km/h") : "",
                    dayData.cloudcover !== undefined ? ("平均云量 " + dayData.cloudcover + "%") : "",
                    dayData.humidity !== undefined ? ("平均湿度 " + dayData.humidity + "%") : "",
                    dayData.sunrise ? dayData.sunrise : "",
                    dayData.sunset ? dayData.sunset : ""
                ];
                return lines.filter(function(s) { return s !== "" }).join("\n");
            }
            font.family: "Microsoft YaHei"
            font.pixelSize: 20
            color: "#2C3E50"
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
        }
    }

    // 返回按钮（右下角）
    Rectangle {
        width: 48
        height: 28
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 6
        color: mouseBack.pressed ? "#357ABD" : "#4A90E2"
        radius: 4
        border.color: "#2C6B9E"
        z: 3

        Text {
            text: "返回"
            color: "white"
            font.family: "Microsoft YaHei"
            font.pixelSize: 14
            anchors.centerIn: parent
        }
        MouseArea {
            id: mouseBack
            anchors.fill: parent
            onClicked: back()
        }
    }
}