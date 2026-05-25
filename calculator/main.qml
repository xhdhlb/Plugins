import QtQuick 2.15
import QtQuick.Controls 1.4
import QtQuick.Controls.Styles 1.4
import QtQuick.LocalStorage 2.15

Rectangle {
    id: root
    width: 320
    height: 170
    color: "#f5f5f5"

    signal backButtonClicked()

    property bool secondMode: false
    property var db: null
    property string savedExpression: ""
    property bool isError: false

    // 左列主功能 / 上档功能文本
    property var leftPrimary: ["√", "log", "%", "x²", "sin", "cos", "π", "^"]
    property var leftSecond:  ["³√", "ln", "‰", "x³", "asin", "acos", "e", "!"]

    Component.onCompleted: {
        mainColumn.anchors.margins = root.height * 0.02;
        initDatabase();
        loadExpression();
    }

    // 数据库初始化
    function initDatabase() {
        db = LocalStorage.openDatabaseSync("Calculator", "1.0", "Calculator expression storage", 1000000);
        db.transaction(function(tx) {
            tx.executeSql('CREATE TABLE IF NOT EXISTS calc(id INTEGER PRIMARY KEY, expr TEXT)');
        });
    }

    function saveExpression() {
        if (!db) return;
        var expr = isError ? savedExpression : display.text;
        db.transaction(function(tx) {
            tx.executeSql('DELETE FROM calc');
            tx.executeSql('INSERT INTO calc(id, expr) VALUES(1, ?)', [expr]);
        });
    }

    function loadExpression() {
        if (!db) return;
        db.transaction(function(tx) {
            var rs = tx.executeSql('SELECT expr FROM calc WHERE id = 1');
            if (rs.rows.length > 0) {
                var expr = rs.rows.item(0).expr;
                display.text = expr;
                display.cursorPosition = expr.length;
            } else {
                display.text = "";
                display.cursorPosition = 0;
            }
        });
    }

    // 表达式预处理（替换符号、处理百分号/千分号/前导零）
    function preprocessExpression(expr) {
        var result = expr;
        result = result.replace(/×/g, "*").replace(/÷/g, "/");
        result = result.replace(/(^|[^\d.])0+(\d+)/g, "$1$2");
        var prev;
        do {
            prev = result;
            result = result.replace(/(\d+(?:\.\d+)?|\([^()]*\))%/g, "($1*0.01)");
        } while (result !== prev);
        do {
            prev = result;
            result = result.replace(/(\d+(?:\.\d+)?|\([^()]*\))‰/g, "($1*0.001)");
        } while (result !== prev);
        return result;
    }

    // 计算并显示结果，处理错误
    function calculate() {
        var expr = display.text;
        savedExpression = expr;
        var processed = preprocessExpression(expr);
        processed = processed.replace(/(\d+)!/g, "fact($1)");
        processed = processed.replace(/√\(/g, "Math.sqrt(");
        processed = processed.replace(/³√\(/g, "Math.cbrt(");
        processed = processed.replace(/log\(/g, "Math.log10(");
        processed = processed.replace(/ln\(/g, "Math.log(");
        processed = processed.replace(/π/g, "Math.PI");
        processed = processed.replace(/e/g, "Math.E");
        processed = processed.replace(/\^/g, "**");
        processed = processed.replace(/sin\(/g, "Math.sin(");
        processed = processed.replace(/asin\(/g, "Math.asin(");
        processed = processed.replace(/cos\(/g, "Math.cos(");
        processed = processed.replace(/acos\(/g, "Math.acos(");

        try {
            var fact = function(n) {
                n = Number(n);
                if (n < 0) return NaN;
                if (n === 0 || n === 1) return 1;
                var result = 1;
                for (var i = 2; i <= n; i++) result *= i;
                return result;
            };
            var result = eval(processed);
            var errorMsg = "";
            if (result === Infinity || result === -Infinity) {
                errorMsg = "不能除以0";
            } else if (isNaN(result)) {
                errorMsg = "结果未定义";
            } else {
                var rounded;
                if (Number.isInteger(result)) {
                    rounded = result.toString();
                } else {
                    rounded = result.toFixed(12).replace(/\.?0+$/, '');
                    if (rounded === "-0") rounded = "0";
                }
                display.text = rounded;
                display.cursorPosition = display.text.length;
                isError = false;
                return;
            }
            display.text = errorMsg;
            isError = true;
            display.cursorPosition = display.text.length;
        } catch (e) {
            display.text = "格式错误";
            isError = true;
            display.cursorPosition = display.text.length;
        }
    }

    // 在光标处插入文本，若当前为错误信息则先恢复原表达式
    function insertAtCursor(insertText) {
        if (isError) {
            display.text = savedExpression;
            display.cursorPosition = savedExpression.length;
            isError = false;
        }
        var text = display.text;
        var cursor = display.cursorPosition;
        var selStart = display.selectionStart;
        var selEnd = display.selectionEnd;
        if (selStart !== selEnd) {
            text = text.slice(0, selStart) + text.slice(selEnd);
            cursor = selStart;
        }
        if ((text === "" || text === "0") && cursor === 0 &&
            (insertText.match(/^[0-9.]$/) || insertText === ".")) {
            text = insertText;
            cursor = text.length;
        } else {
            text = text.slice(0, cursor) + insertText + text.slice(cursor);
            cursor += insertText.length;
        }
        display.text = text;
        display.cursorPosition = cursor;
    }

    function onButtonClick(btnText) {
        if (btnText === "C") {
            display.text = "";
            display.cursorPosition = 0;
            isError = false;
            savedExpression = "";
        } else if (btnText === "←") {
            if (isError) {
                display.text = savedExpression;
                display.cursorPosition = savedExpression.length;
                isError = false;
            }
            if (display.selectionStart !== display.selectionEnd) {
                var selStart = display.selectionStart;
                var selEnd = display.selectionEnd;
                display.text = display.text.slice(0, selStart) + display.text.slice(selEnd);
                display.cursorPosition = selStart;
            } else if (display.cursorPosition > 0) {
                var pos = display.cursorPosition;
                display.text = display.text.slice(0, pos-1) + display.text.slice(pos);
                display.cursorPosition = pos - 1;
            }
        } else if (btnText === "=") {
            if (display.text.trim() === "") return;     // 空输入不计算
            if (isError) {
                display.text = savedExpression;
                display.cursorPosition = savedExpression.length;
                isError = false;
            }
            calculate();
        } else if (btnText === "退出") {
            saveExpression();
            root.backButtonClicked();
        } else if (btnText === "◀") {
            if (isError) {
                display.text = savedExpression;
                display.cursorPosition = savedExpression.length;
                isError = false;
            }
            if (display.cursorPosition > 0)
                display.cursorPosition -= 1;
        } else if (btnText === "▶") {
            if (isError) {
                display.text = savedExpression;
                display.cursorPosition = savedExpression.length;
                isError = false;
            }
            if (display.cursorPosition < display.text.length)
                display.cursorPosition += 1;
        } else if (btnText === "2nd") {
            secondMode = !secondMode;
        } else {
            if (isError) {
                display.text = savedExpression;
                display.cursorPosition = savedExpression.length;
                isError = false;
            }
            var newText = btnText;
            if (!secondMode) {
                if (btnText === "√") newText = "√(";
                else if (btnText === "log") newText = "log(";
                else if (btnText === "%") newText = "%";
                else if (btnText === "x²") newText = "^2";
                else if (btnText === "sin") newText = "sin(";
                else if (btnText === "cos") newText = "cos(";
                else if (btnText === "π") newText = "π";
                else if (btnText === "^") newText = "^";
            } else {
                if (btnText === "³√") newText = "³√(";
                else if (btnText === "ln") newText = "ln(";
                else if (btnText === "‰") newText = "‰";
                else if (btnText === "x³") newText = "^3";
                else if (btnText === "asin") newText = "asin(";
                else if (btnText === "acos") newText = "acos(";
                else if (btnText === "e") newText = "e";
                else if (btnText === "!") newText = "!";
            }
            insertAtCursor(newText);
        }
    }

    function buttonColor(text, col) {
        if (col < 2) return "#e0f0ff";
        if (["C","←","退出","◀","▶","2nd"].indexOf(text) >= 0) return "#ffe0e0";
        if (text.match(/^[0-9]$/) || text === "." || text === "=") return "#f8f8f8";
        if (["×","÷","+","-"].indexOf(text) >= 0) return "#fff5e0";
        if (["(", ")"].indexOf(text) >= 0) return "#f0fff0";
        return "#f8f8f8";
    }

    function getButtonColor(text, col, pressed, secondModeActive) {
        var base = buttonColor(text, col);
        if (text === "2nd" && secondModeActive)
            return Qt.darker(base, 1.3);
        else if (pressed)
            return Qt.darker(base, 1.1);
        else
            return base;
    }

    function getButtonText(index) {
        var row = Math.floor(index / 8);
        var col = index % 8;
        var fixedRows = [
            ["7", "8", "9", "◀", "▶", "←"],
            ["4", "5", "6", "(", ")", "C"],
            ["1", "2", "3", "+", "-", "2nd"],
            ["0", ".", "=", "×", "÷", "退出"]
        ];
        if (col < 2) {
            var leftIndex = row * 2 + col;
            return secondMode ? leftSecond[leftIndex] : leftPrimary[leftIndex];
        } else {
            return fixedRows[row][col - 2];
        }
    }

    Column {
        id: mainColumn
        anchors.fill: parent
        spacing: parent.height * 0.02

        // 显示区域
        Rectangle {
            id: displayRect
            width: parent.width
            height: parent.height * 0.18
            color: "#ffffff"
            border.color: "#cccccc"
            border.width: 2
            radius: 8

            readonly property real leftMargin: height * 0.1
            readonly property real rightMargin: height * 0.15

            TextInput {
                id: display
                x: displayRect.leftMargin
                y: 0
                width: parent.width - displayRect.leftMargin - displayRect.rightMargin
                height: parent.height
                text: ""
                font.pixelSize: parent.height * 0.5
                font.family: "Microsoft YaHei"
                color: "#333333"
                horizontalAlignment: TextInput.AlignRight
                verticalAlignment: TextInput.AlignVCenter
                readOnly: false
                autoScroll: true
                clip: true
                selectByMouse: true
                cursorVisible: true
                activeFocusOnPress: true
                inputMethodHints: Qt.ImhNone
            }
        }

        // 按钮区域
        Item {
            id: buttonContainer
            width: parent.width
            height: parent.height * 0.8

            readonly property int cols: 8
            readonly property int rows: 4
            property real spacing: height * 0.02
            property real buttonHeight: (height - (rows - 1) * spacing) / rows
            property real buttonWidth: buttonHeight * 1.2
            property real gridWidth: buttonWidth * cols + (cols - 1) * spacing

            Grid {
                id: buttonGrid
                columns: buttonContainer.cols
                rows: buttonContainer.rows
                spacing: buttonContainer.spacing
                width: buttonContainer.gridWidth
                anchors.centerIn: parent

                Repeater {
                    model: 32
                    delegate: Button {
                        text: root.getButtonText(index)
                        width: buttonContainer.buttonWidth
                        height: buttonContainer.buttonHeight
                        enabled: text !== ""
                        readonly property int colIndex: index % buttonContainer.cols

                        style: ButtonStyle {
                            background: Rectangle {
                                color: root.getButtonColor(control.text, colIndex, control.pressed, root.secondMode)
                                border.color: "#a0a0a0"
                                border.width: control.enabled ? 1 : 0
                                radius: 5
                            }
                            label: Text {
                                text: control.text
                                font.family: "Microsoft YaHei"
                                font.pixelSize: buttonContainer.buttonHeight * 0.5
                                font.bold: true
                                color: control.enabled ? "#333333" : "transparent"
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                                visible: control.text !== ""
                            }
                        }
                        onClicked: root.onButtonClick(text)
                    }
                }
            }
        }
    }

    // 物理键盘映射
    Item {
        anchors.fill: parent
        focus: true
        Keys.onPressed: {
            var key = event.key;
            var mapped = "";
            if (key >= Qt.Key_0 && key <= Qt.Key_9)
                mapped = String.fromCharCode(key);
            else if (key === Qt.Key_Plus) mapped = "+";
            else if (key === Qt.Key_Minus) mapped = "-";
            else if (key === Qt.Key_Asterisk) mapped = "×";
            else if (key === Qt.Key_Slash) mapped = "÷";
            else if (key === Qt.Key_ParenLeft) mapped = "(";
            else if (key === Qt.Key_ParenRight) mapped = ")";
            else if (key === Qt.Key_Period) mapped = ".";
            else if (key === Qt.Key_Backspace) mapped = "←";
            else if (key === Qt.Key_Delete) mapped = "C";
            else if (key === Qt.Key_Enter || key === Qt.Key_Return) mapped = "=";
            if (mapped) {
                root.onButtonClick(mapped);
                event.accepted = true;
            }
        }
    }
}