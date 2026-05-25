import QtQuick 2.15
import QtQuick.LocalStorage 2.15
import "qrc:/qml/commons"

Rectangle {
    id: locationRoot
    color: "#FFFFFF"
    anchors.fill: parent
    z: 101

    property var mainApp: null
    property var cityListModel: []
    property string currentCity: ""

    signal back()

    property bool isKeyboardActive: false
    property string statusMessage: ""
    property bool statusIsError: true   // 错误为红色，定位中为黑色

    Timer {
        id: clearStatusTimer
        interval: 3000
        onTriggered: {
            statusMessage = "";
            statusIsError = true;
        }
    }

    function showError(msg) {
        statusMessage = msg;
        statusIsError = true;
        clearStatusTimer.restart();
    }

    function showLocating() {
        statusMessage = "定位中…";
        statusIsError = false;        // 黑色
        clearStatusTimer.stop();
    }

    YPagePopHelper {
        id: pagePopHelper
        z: 102
        isShowing: qmlGlobal.inputPageShowing
        objectName: "from_Locations"

        function requestKeyboard() {
            if (isKeyboardActive) return;
            isKeyboardActive = true;

            var comp = qmlCreateComponent("YInputPage");
            if (comp.status === Component.Error) {
                isKeyboardActive = false;
                showError("无法打开键盘");
                return;
            }
            if (comp.status === Component.Ready) {
                var incubator = comp.incubateObject(pagePopHelper.containerItem);
                if (incubator.status !== Component.Ready) {
                    incubator.onStatusChanged = function(status) {
                        if (status === Component.Ready) {
                            pagePopHelper.inputPageCreated(incubator.object);
                        }
                    };
                } else {
                    pagePopHelper.inputPageCreated(incubator.object);
                }
            }
        }

        function inputPageCreated(keyboardPage) {
            keyboardPage.backButtonClicked.connect(function() {
                qmlGlobal.inputPageShowing = false;
                keyboardPage.todoDestroy();
                isKeyboardActive = false;
            });
            keyboardPage.inputFinished.connect(function(content) {
                qmlGlobal.inputPageShowing = false;
                keyboardPage.todoDestroy();
                isKeyboardActive = false;
                var raw = content.trim();
                var normalized = raw.replace(/\s+/g, ' ');
                if (normalized === "") {
                    showError("输入为空");
                    return;
                }
                if (mainApp) {
                    var added = mainApp.addCity(normalized);
                    if (!added) {
                        showError("地点已存在");
                    }
                }
            });
            keyboardPage.enterText("");
            keyboardPage.show();
            qmlGlobal.inputPageShowing = true;
        }
    }

    function locateAndAddCity() {
        if (isKeyboardActive) return;
        showLocating();

        var xhr = new XMLHttpRequest();
        xhr.open("GET", "https://api.live.bilibili.com/client/v1/Ip/getInfoNew", true);

        var finished = false;
        var timer = Qt.createQmlObject("import QtQuick 2.15; Timer { interval: 10000; running: true; repeat: false }", locationRoot);
        timer.triggered.connect(function() {
            if (finished) return;
            finished = true;
            if (xhr.readyState === XMLHttpRequest.LOADING) xhr.abort();
            timer.destroy();
            showError("请求超时");
        });

        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE) {
                if (finished) return;
                finished = true;
                timer.destroy();
                if (xhr.status === 200) {
                    try {
                        var obj = JSON.parse(xhr.responseText);
                        var city = (obj.data && obj.data.city) ? obj.data.city : "";
                        if (city !== "" && mainApp) {
                            var added = mainApp.addCity(city);
                            if (!added) {
                                showError("地点已存在");
                            } else {
                                // 成功：清除提示
                                clearStatusTimer.stop();
                                statusMessage = "";
                                statusIsError = true;
                            }
                        } else {
                            showError("地点数据为空");
                        }
                    } catch (e) {
                        showError("数据解析错误");
                    }
                } else if (xhr.status === 0) {
                    showError("网络连接异常");
                } else {
                    showError("网络错误 HTTP" + xhr.status);
                }
            }
        };
        xhr.send();
    }

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
            id: titleText
            text: "地点管理"
            font.bold: true; font.pixelSize: 16; font.family: "Microsoft YaHei"; color: "#2C3E50"
            anchors.verticalCenter: parent.verticalCenter
        }

        Text {
            anchors.left: titleText.right
            anchors.leftMargin: 8
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: statusMessage
            color: statusIsError ? "#E74C3C" : "#000000"
            font.family: "Microsoft YaHei"
            font.pixelSize: 16   // 与标题相同
            elide: Text.ElideRight
            visible: statusMessage !== ""
        }
    }

    ListView {
        id: cityListView
        x: 8
        y: titleBar.y + titleBar.height + 4
        width: parent.width - 16
        height: bottomBar.y - y - 6
        clip: true
        model: cityListModel
        delegate: Rectangle {
            width: cityListView.width; height: 35
            color: index % 2 ? "#F5F9FF" : "#FFFFFF"
            Row {
                anchors.fill: parent
                anchors.leftMargin: 6; anchors.rightMargin: 6; spacing: 6
                Text {
                    text: modelData
                    width: parent.width - 100
                    font.family: "Microsoft YaHei"; font.pixelSize: 15; color: "#2C3E50"
                    verticalAlignment: Text.AlignVCenter
                    elide: Text.ElideRight
                }
                Rectangle {
                    width: 40; height: 24; radius: 3
                    color: (mainApp && mainApp.currentCity === modelData) ? "#BDC3C7" : "#4A90E2"
                    Text { text: "选择"; color: "white"; font.family: "Microsoft YaHei"; font.pixelSize: 13; anchors.centerIn: parent }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            if (mainApp && mainApp.currentCity === modelData) return;
                            if (mainApp && mainApp.currentCity !== modelData) {
                                mainApp.abortWeather();
                                mainApp.currentCity = modelData;
                                mainApp.saveCurrentCity();
                                mainApp.fetchWeather(modelData);
                            }
                            back();
                        }
                    }
                }
                Rectangle {
                    width: 40; height: 24; radius: 3; color: "#E74C3C"
                    Text { text: "删除"; color: "white"; font.family: "Microsoft YaHei"; font.pixelSize: 13; anchors.centerIn: parent }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: { if (mainApp) mainApp.removeCity(modelData); }
                    }
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
            width: parent.width - 42 - 42 - 12; height: 32; radius: 4
            color: __btnInput.pressed ? "#219A52" : "#27AE60"
            Text { text: "输入地点"; color: "white"; font.family: "Microsoft YaHei"; font.pixelSize: 16; anchors.centerIn: parent }
            MouseArea { id: __btnInput; anchors.fill: parent; onClicked: pagePopHelper.requestKeyboard() }
        }
        Rectangle {
            width: 42; height: 32; radius: 4
            color: __btnLocate.pressed ? "#2E86C1" : "#3498DB"
            Text { text: "定位"; color: "white"; font.family: "Microsoft YaHei"; font.pixelSize: 16; anchors.centerIn: parent }
            MouseArea { id: __btnLocate; anchors.fill: parent; onClicked: locateAndAddCity() }
        }
        Rectangle {
            width: 42; height: 32; radius: 4
            color: __btnReturn.pressed ? "#357ABD" : "#4A90E2"
            Text { text: "返回"; color: "white"; font.family: "Microsoft YaHei"; font.pixelSize: 16; anchors.centerIn: parent }
            MouseArea { id: __btnReturn; anchors.fill: parent; onClicked: back() }
        }
    }
}