import QtQuick 2.15
import QtQuick.Controls 1.4
import QtQuick.Layouts 1.15
import QtQuick.Controls.Styles 1.4
import QtQuick.LocalStorage 2.0

Rectangle {
    id: root
    width: 320
    height: 170
    color: "#faf8ef"

    // 添加返回信号，供插件宿主调用
    signal backButtonClicked()

    // 存储新生成方块的索引（0-15）
    property var newTileIndices: ({})

    property var grid: [[0,0,0,0],[0,0,0,0],[0,0,0,0],[0,0,0,0]]
    property int score: 0
    property bool gameOver: false
    property bool gameWon: false
    readonly property int winTile: 2048
    readonly property int maxTile: 8192

    property var db: null

    // 初始化数据库
    function initDatabase() {
        db = LocalStorage.openDatabaseSync("2048Game", "1.0", "2048 Game Save Data", 1000000);
        db.transaction(function(tx) {
            tx.executeSql('CREATE TABLE IF NOT EXISTS game(id INTEGER PRIMARY KEY, grid TEXT, score INTEGER, gameOver INTEGER, gameWon INTEGER)');
        });
    }

    // 保存游戏
    function saveGame() {
        if (!db) return;
        var gridStr = JSON.stringify(grid);
        db.transaction(function(tx) {
            tx.executeSql('DELETE FROM game');
            tx.executeSql('INSERT INTO game(id, grid, score, gameOver, gameWon) VALUES(1, ?, ?, ?, ?)',
                         [gridStr, score, gameOver ? 1 : 0, gameWon ? 1 : 0]);
        });
        console.log("游戏已自动保存");
    }

    // 加载游戏
    function loadGame() {
        if (!db) return;
        db.transaction(function(tx) {
            var rs = tx.executeSql('SELECT grid, score, gameOver, gameWon FROM game WHERE id = 1');
            if (rs.rows.length > 0) {
                var row = rs.rows.item(0);
                try {
                    var loadedGrid = JSON.parse(row.grid);
                    if (Array.isArray(loadedGrid) && loadedGrid.length === 4 &&
                        loadedGrid.every(row => Array.isArray(row) && row.length === 4)) {
                        grid = loadedGrid;
                        score = row.score;
                        gameOver = row.gameOver === 1;
                        gameWon = row.gameWon === 1;
                        newTileIndices = {};
                        refreshGrid();
                        console.log("加载存档成功");
                        return;
                    }
                } catch (e) {
                    console.log("存档损坏");
                }
            }
            resetGame();
        });
    }

    Component.onCompleted: {
        initDatabase();
        loadGame();
    }

    // 退出时自动保存
    Component.onDestruction: saveGame()

    function refreshGrid() {
        var temp = grid.map(row => row.slice());
        grid = temp;
    }

    function resetGame() {
        grid = [[0,0,0,0],[0,0,0,0],[0,0,0,0],[0,0,0,0]];
        score = 0;
        gameOver = false;
        gameWon = false;
        newTileIndices = {};
        addRandomTile();
        addRandomTile();
        refreshGrid();
    }

    function addRandomTile() {
        var empty = [];
        for (var i=0; i<4; i++)
            for (var j=0; j<4; j++)
                if (grid[i][j] === 0) empty.push({row: i, col: j});
        if (empty.length === 0) return;
        var pos = empty[Math.floor(Math.random() * empty.length)];
        grid[pos.row][pos.col] = Math.random() < 0.9 ? 2 : 4;
        var idx = pos.row * 4 + pos.col;
        newTileIndices[idx] = true;
    }

    function moveRowLeft(row) {
        var arr = row.filter(v => v !== 0);
        var gain = 0;
        for (var i=0; i<arr.length-1; i++) {
            if (arr[i] === arr[i+1]) {
                arr[i] *= 2;
                gain += arr[i];
                arr.splice(i+1, 1);
            }
        }
        while (arr.length < 4) arr.push(0);
        return {newRow: arr, scoreGain: gain};
    }

    function moveRowRight(row) {
        var rev = row.slice().reverse();
        var result = moveRowLeft(rev);
        return {newRow: result.newRow.reverse(), scoreGain: result.scoreGain};
    }

    function getMaxTile() {
        var max = 0;
        for (var i=0; i<4; i++)
            for (var j=0; j<4; j++)
                if (grid[i][j] > max) max = grid[i][j];
        return max;
    }

    function isGameOver() {
        for (var i=0; i<4; i++)
            for (var j=0; j<4; j++)
                if (grid[i][j] === 0) return false;
        for (i=0; i<4; i++)
            for (j=0; j<3; j++)
                if (grid[i][j] === grid[i][j+1]) return false;
        for (j=0; j<4; j++)
            for (i=0; i<3; i++)
                if (grid[i][j] === grid[i+1][j]) return false;
        return true;
    }

    function move(direction) {
        if (gameOver) return false;

        var moved = false;
        var totalGain = 0;
        var oldGrid = grid.map(row => row.slice());

        if (direction === "left") {
            for (var r=0; r<4; r++) {
                var result = moveRowLeft(grid[r]);
                if (result.newRow.some((val, idx) => val !== grid[r][idx])) moved = true;
                grid[r] = result.newRow;
                totalGain += result.scoreGain;
            }
        } else if (direction === "right") {
            for (r=0; r<4; r++) {
                result = moveRowRight(grid[r]);
                if (result.newRow.some((val, idx) => val !== grid[r][idx])) moved = true;
                grid[r] = result.newRow;
                totalGain += result.scoreGain;
            }
        } else if (direction === "up") {
            for (var c=0; c<4; c++) {
                var col = grid.map(row => row[c]);
                result = moveRowLeft(col);
                if (result.newRow.some((val, idx) => val !== col[idx])) moved = true;
                for (r=0; r<4; r++) grid[r][c] = result.newRow[r];
                totalGain += result.scoreGain;
            }
        } else if (direction === "down") {
            for (c=0; c<4; c++) {
                col = grid.map(row => row[c]);
                result = moveRowRight(col);
                if (result.newRow.some((val, idx) => val !== col[idx])) moved = true;
                for (r=0; r<4; r++) grid[r][c] = result.newRow[r];
                totalGain += result.scoreGain;
            }
        }

        if (moved) {
            score += totalGain;
            addRandomTile();
            if (!gameWon && getMaxTile() >= winTile) gameWon = true;
            if (isGameOver()) gameOver = true;
            refreshGrid();
        }
        return moved;
    }

    // 主布局（与原Window中完全一致，但所有尺寸基于root）
    Row {
        anchors.fill: parent
        anchors.margins: parent.height * 0.03
        spacing: parent.width * 0.03

        Item {
            id: leftArea
            width: parent.width * 0.6
            height: parent.height

            property real spacing: leftArea.width * 0.02
            property real cellSize: Math.min(
                (width - spacing * 3) / 4,
                (height - spacing * 3) / 4
            )

            Grid {
                columns: 4
                spacing: leftArea.spacing
                anchors.centerIn: parent

                Repeater {
                    model: 16
                    delegate: Rectangle {
                        id: cell
                        width: leftArea.cellSize
                        height: leftArea.cellSize
                        color: {
                            var val = grid[Math.floor(index/4)][index%4]
                            if (val === 0) return "#cdc1b4"
                            if (val === 2) return "#eee4da"
                            if (val === 4) return "#ede0c8"
                            if (val === 8) return "#f2b179"
                            if (val === 16) return "#f59563"
                            if (val === 32) return "#f67c5f"
                            if (val === 64) return "#f65e3b"
                            if (val === 128) return "#edcf72"
                            if (val === 256) return "#edcc61"
                            if (val === 512) return "#edc850"
                            if (val === 1024) return "#edc53f"
                            if (val === 2048) return "#edc22e"
                            return "#3c3a32"
                        }
                        radius: 5
                        scale: 1.0

                        property bool isNew: false

                        Timer {
                            id: delayTimer
                            interval: 100
                            running: false
                            repeat: false
                            onTriggered: {
                                if (cell.isNew) {
                                    cell.scale = 0
                                    appearAnim.restart()
                                    cell.isNew = false
                                }
                            }
                        }

                        SequentialAnimation {
                            id: appearAnim
                            running: false
                            NumberAnimation { target: cell; property: "scale"; from: 0; to: 1; duration: 250; easing.type: Easing.OutBack }
                        }

                        SequentialAnimation {
                            id: mergeAnim
                            running: false
                            NumberAnimation { target: cell; property: "scale"; to: 1.2; duration: 150; easing.type: Easing.OutQuad }
                            NumberAnimation { target: cell; property: "scale"; to: 1.0; duration: 150; easing.type: Easing.InQuad }
                        }

                        Text {
                            id: cellText
                            anchors.centerIn: parent
                            text: grid[Math.floor(index/4)][index%4] === 0 ? "" : grid[Math.floor(index/4)][index%4]
                            font.pixelSize: parent.height * 0.4
                            font.bold: true
                            color: grid[Math.floor(index/4)][index%4] > 4 ? "white" : "#776e65"

                            onTextChanged: {
                                var curVal = text === "" ? 0 : parseInt(text)
                                if (curVal > 0) {
                                    if (newTileIndices[index]) {
                                        cell.isNew = true
                                        cell.scale = 0
                                        delayTimer.start()
                                        delete newTileIndices[index]
                                    } else {
                                        mergeAnim.restart()
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        Item {
            width: parent.width * 0.35
            height: parent.height

            ColumnLayout {
                anchors.fill: parent
                spacing: parent.height * 0.02

                Text {
                    text: "得分: " + score
                    font.family: "Microsoft YaHei"
                    font.pixelSize: parent.height * 0.1
                    color: "#776e65"
                    horizontalAlignment: Text.AlignHCenter
                    Layout.preferredHeight: parent.height * 0.12
                    Layout.fillWidth: true
                }

                GridLayout {
                    columns: 2
                    rowSpacing: parent.width * 0.04
                    columnSpacing: parent.width * 0.04
                    Layout.preferredHeight: parent.height * 0.4
                    Layout.fillWidth: true

                    Button {
                        text: "↑"
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        onClicked: move("up")
                        style: ButtonStyle {
                            label: Label {
                                text: control.text
                                font.family: "Microsoft YaHei"
                                font.pixelSize: Math.min(root.height * 0.12, 60)
                                font.bold: true
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                        }
                    }
                    Button {
                        text: "↓"
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        onClicked: move("down")
                        style: ButtonStyle {
                            label: Label {
                                text: control.text
                                font.family: "Microsoft YaHei"
                                font.pixelSize: Math.min(root.height * 0.12, 60)
                                font.bold: true
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                        }
                    }
                    Button {
                        text: "←"
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        onClicked: move("left")
                        style: ButtonStyle {
                            label: Label {
                                text: control.text
                                font.family: "Microsoft YaHei"
                                font.pixelSize: Math.min(root.height * 0.12, 60)
                                font.bold: true
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                        }
                    }
                    Button {
                        text: "→"
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        onClicked: move("right")
                        style: ButtonStyle {
                            label: Label {
                                text: control.text
                                font.family: "Microsoft YaHei"
                                font.pixelSize: Math.min(root.height * 0.12, 60)
                                font.bold: true
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                        }
                    }
                }

                Button {
                    text: "新游戏"
                    Layout.preferredHeight: parent.height * 0.15
                    Layout.fillWidth: true
                    onClicked: resetGame()
                    style: ButtonStyle {
                        label: Label {
                            text: control.text
                            font.family: "Microsoft YaHei"
                            font.pixelSize: Math.min(root.height * 0.09, 40)
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                    }
                }

                Button {
                    text: "退出"
                    Layout.preferredHeight: parent.height * 0.15
                    Layout.fillWidth: true
                    onClicked: {
                        saveGame();
                        root.backButtonClicked(); // 改为发送信号
                    }
                    style: ButtonStyle {
                        label: Label {
                            text: control.text
                            font.family: "Microsoft YaHei"
                            font.pixelSize: Math.min(root.height * 0.09, 40)
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                    }
                }

                Item { Layout.fillHeight: true }
            }
        }
    }

    // 游戏结束/胜利遮罩
    Rectangle {
        anchors.fill: parent
        color: "#80ffffff"
        visible: gameOver || gameWon
        Column {
            anchors.centerIn: parent
            spacing: parent.height * 0.05
            Text {
                font.family: "Microsoft YaHei"
                text: gameWon ? "你赢了！" : "游戏结束"
                font.pixelSize: parent.parent.height * 0.1
                color: "#776e65"
            }
            Button {
                text: "再来一局"
                onClicked: resetGame()
                style: ButtonStyle {
                    label: Label {
                        text: control.text
                        font.family: "Microsoft YaHei"
                        font.pixelSize: Math.min(root.height * 0.09, 40)
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                }
            }
        }
    }

    // 键盘控制（可选，保留但可能需要焦点）
    Item {
        anchors.fill: parent
        focus: true
        Keys.onPressed: {
            if (event.key === Qt.Key_Left) move("left")
            else if (event.key === Qt.Key_Right) move("right")
            else if (event.key === Qt.Key_Up) move("up")
            else if (event.key === Qt.Key_Down) move("down")
            else if (event.key === Qt.Key_R) resetGame()
            event.accepted = true
        }
    }
}