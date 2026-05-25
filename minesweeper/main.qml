import QtQuick 2.15
import QtQuick.Controls 1.4
import QtQuick.Controls.Styles 1.4

Rectangle {
    id: pluginRoot
    width: 320
    height: 170
    color: "#f0f0f0"

    signal backButtonClicked()

    readonly property int rows: 9
    readonly property int cols: 9
    readonly property int mineCount: 10

    property var grid: []          // -1:雷, 0-8:数字
    property var cellState: []     // 0:未翻开, 1:翻开, 2:标记旗子
    property bool gameOver: false
    property bool gameWin: false
    property string currentMode: "none"   // "dig", "mark", "none" → 显示"查看"
    property bool firstClick: true
    property bool wrongFlagShowFlag: true
    property real zoomScale: 1.0

    readonly property real marginFactor: 0.9

    // 自实现双击检测相关属性
    property int clickCount: 0
    property point lastClickPos
    property date lastClickTime

    // 闪烁定时器
    Timer {
        id: blinkTimer
        interval: 500
        running: gameOver && !gameWin
        repeat: true
        onTriggered: wrongFlagShowFlag = !wrongFlagShowFlag
    }

    // 双击检测重置定时器
    Timer {
        id: doubleClickResetTimer
        interval: 300
        onTriggered: clickCount = 0
    }

    function getImageSource(r, c) {
        if (gameOver && !gameWin) {
            if (grid[r][c] === -1) {
                if (cellState[r][c] === 1) return "image/12.png"
                else if (cellState[r][c] === 0) return "image/11.png"
                else if (cellState[r][c] === 2) return "image/10.png"
            } else {
                if (cellState[r][c] === 2) {
                    return wrongFlagShowFlag ? "image/10.png" : ("image/" + grid[r][c] + ".png")
                }
            }
        }
        if (cellState[r][c] === 0) return "image/9.png"
        if (cellState[r][c] === 1) return "image/" + grid[r][c] + ".png"
        if (cellState[r][c] === 2) return "image/10.png"
        return "image/9.png"
    }

    // ---------- 游戏逻辑 ----------
    function resetBoard() {
        grid = []
        for (var r = 0; r < rows; ++r) {
            var row = []
            for (var c = 0; c < cols; ++c) row.push(0)
            grid.push(row)
        }
        cellState = []
        for (r = 0; r < rows; ++r) {
            var stRow = []
            for (c = 0; c < cols; ++c) stRow.push(0)
            cellState.push(stRow)
        }
        gameOver = false
        gameWin = false
        firstClick = true
        wrongFlagShowFlag = true
        zoomScale = 1.0
        centerGrid()
    }

    function generateMines(safeR, safeC) {
        grid = []
        for (var r = 0; r < rows; ++r) {
            var row = []
            for (var c = 0; c < cols; ++c) row.push(0)
            grid.push(row)
        }
        var excluded = {}
        for (var dr = -1; dr <= 1; ++dr) {
            for (var dc = -1; dc <= 1; ++dc) {
                var nr = safeR + dr
                var nc = safeC + dc
                if (nr >= 0 && nr < rows && nc >= 0 && nc < cols)
                    excluded[nr + "," + nc] = true
            }
        }
        var placed = 0
        while (placed < mineCount) {
            var rr = Math.floor(Math.random() * rows)
            var cc = Math.floor(Math.random() * cols)
            var key = rr + "," + cc
            if (grid[rr][cc] !== -1 && !excluded[key]) {
                grid[rr][cc] = -1
                ++placed
            }
        }
        for (r = 0; r < rows; ++r) {
            for (c = 0; c < cols; ++c) {
                if (grid[r][c] === -1) continue
                var cnt = 0
                for (var dr2 = -1; dr2 <= 1; ++dr2) {
                    for (var dc2 = -1; dc2 <= 1; ++dc2) {
                        if (dr2 === 0 && dc2 === 0) continue
                        var nr2 = r + dr2, nc2 = c + dc2
                        if (nr2 >= 0 && nr2 < rows && nc2 >= 0 && nc2 < cols && grid[nr2][nc2] === -1) ++cnt
                    }
                }
                grid[r][c] = cnt
            }
        }
    }

    function openCell(r, c) {
        if (r < 0 || r >= rows || c < 0 || c >= cols) return
        if (cellState[r][c] !== 0) return
        if (grid[r][c] === -1) {
            cellState[r][c] = 1
            gameOver = true
            return
        }
        cellState[r][c] = 1
        if (grid[r][c] === 0) {
            for (var dr = -1; dr <= 1; ++dr) {
                for (var dc = -1; dc <= 1; ++dc) {
                    if (dr === 0 && dc === 0) continue
                    openCell(r + dr, c + dc)
                }
            }
        }
    }

    function checkWin() {
        var opened = 0
        for (var r = 0; r < rows; ++r)
            for (var c = 0; c < cols; ++c)
                if (cellState[r][c] === 1) ++opened
        if (opened === rows * cols - mineCount) {
            for (r = 0; r < rows; ++r)
                for (c = 0; c < cols; ++c)
                    if (cellState[r][c] === 0) cellState[r][c] = 2
            gameWin = true
            gameOver = true
        }
    }

    function cellClicked(r, c) {
        if (gameOver) return
        if (currentMode === "none") return
        if (currentMode === "mark") {
            if (cellState[r][c] === 0) cellState[r][c] = 2
            else if (cellState[r][c] === 2) cellState[r][c] = 0
            cellState = cellState.map(row => row.slice())
            return
        }
        if (currentMode === "dig") {
            if (cellState[r][c] !== 0) return
            if (firstClick) {
                generateMines(r, c)
                firstClick = false
            }
            openCell(r, c)
            checkWin()
            cellState = cellState.map(row => row.slice())
            grid = grid.map(row => row.slice())
        }
    }

    function newGame() {
        resetBoard()
        grid = grid.map(row => row.slice())
        cellState = cellState.map(row => row.slice())
    }

    // 居中网格（左上角对齐视口中心）
    function centerGrid() {
        var vpW = viewport.width
        var vpH = viewport.height
        var visualW = container.width * zoomScale
        var visualH = container.height * zoomScale
        container.x = (vpW - visualW) / 2
        container.y = (vpH - visualH) / 2
    }

    // 通用按钮样式
    Component {
        id: fixedButtonStyle
        ButtonStyle {
            label: Text {
                text: control.text
                font.pixelSize: 14
                color: "black"
                font.family: "Microsoft YaHei"
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }
        }
    }

    // ---------- UI ----------
    Row {
        anchors.fill: parent
        spacing: 8

        // 左侧游戏区域
        Item {
            id: leftArea
            width: parent.width * 0.62
            height: parent.height

            Item {
                id: viewport
                anchors.fill: parent
                clip: true

                // 网格容器（缩放原点为左上角，x/y即左上角坐标）
                Item {
                    id: container
                    width: cols * effectiveCellSize
                    height: rows * effectiveCellSize

                    transform: Scale {
                        origin.x: 0
                        origin.y: 0
                        xScale: zoomScale
                        yScale: zoomScale
                    }

                    property real effectiveCellSize: Math.min(leftArea.width / cols, leftArea.height / rows) * marginFactor

                    Grid {
                        columns: cols
                        spacing: 0
                        anchors.fill: parent

                        Repeater {
                            model: rows * cols

                            Rectangle {
                                width: container.effectiveCellSize
                                height: container.effectiveCellSize
                                color: "transparent"
                                border.color: "#808080"
                                border.width: 1

                                property int row: Math.floor(index / cols)
                                property int col: index % cols

                                Image {
                                    anchors.fill: parent
                                    anchors.margins: 1
                                    source: pluginRoot.getImageSource(row, col)
                                    fillMode: Image.PreserveAspectFit
                                }
                            }
                        }
                    }
                }
            }

            // 鼠标区域（整合点击、拖拽、双击检测）
            MouseArea {
                id: mouseArea
                anchors.fill: parent
                property bool isDragging: false
                property point pressPos

                onPressed: {
                    isDragging = false
                    pressPos = Qt.point(mouse.x, mouse.y)
                }
                onPositionChanged: {
                    // 判断是否开始拖拽（移动超过5像素）
                    if (!isDragging && (Math.abs(mouse.x - pressPos.x) > 5 || Math.abs(mouse.y - pressPos.y) > 5)) {
                        isDragging = true
                    }
                    // 放大且拖拽中移动网格
                    if (isDragging && zoomScale !== 1.0) {
                        var dx = mouse.x - pressPos.x
                        var dy = mouse.y - pressPos.y
                        container.x += dx
                        container.y += dy

                        var vpW = viewport.width
                        var vpH = viewport.height
                        var visualW = container.width * zoomScale
                        var visualH = container.height * zoomScale
                        // 左右：至少一半可见
                        var minX = -visualW / 2
                        var maxX = vpW - visualW / 2
                        // 上下：至少保留120像素可见（简化表达式）
                        var minY = 120 - visualH
                        var maxY = vpH - 120
                        container.x = Math.max(minX, Math.min(maxX, container.x))
                        container.y = Math.max(minY, Math.min(maxY, container.y))

                        pressPos = Qt.point(mouse.x, mouse.y)
                    }
                }
                onReleased: {
                    // 双击检测仅在“查看”模式下且未拖拽时进行
                    if (!isDragging && currentMode === "none") {
                        var now = new Date()
                        if (clickCount === 1 && (now - lastClickTime) < 300 &&
                            Math.abs(mouse.x - lastClickPos.x) < 10 &&
                            Math.abs(mouse.y - lastClickPos.y) < 10) {
                            // 双击：切换缩放并居中
                            zoomScale = (zoomScale === 1.0 ? 2.0 : 1.0)
                            centerGrid()
                            clickCount = 0
                            doubleClickResetTimer.stop()
                        } else {
                            // 记录单击
                            clickCount = 1
                            lastClickTime = now
                            lastClickPos = Qt.point(mouse.x, mouse.y)
                            doubleClickResetTimer.restart()
                        }
                    } else {
                        clickCount = 0
                    }
                }
                onClicked: {
                    // 仅当非拖拽且非“查看”模式时执行游戏逻辑
                    if (isDragging) return
                    if (currentMode === "none") return
                    var mx = mouse.x - container.x
                    var my = mouse.y - container.y
                    var col = Math.floor(mx / (container.effectiveCellSize * zoomScale))
                    var row = Math.floor(my / (container.effectiveCellSize * zoomScale))
                    if (row >= 0 && row < rows && col >= 0 && col < cols) {
                        cellClicked(row, col)
                    }
                }
            }
        }

        // 右侧控制区（顶部留边距）
        Rectangle {
            width: parent.width * 0.34
            height: parent.height
            color: "transparent"

            Column {
                anchors.fill: parent
                anchors.topMargin: 8
                spacing: parent.height * 0.05

                Text {
                    text: "模式: " + (currentMode === "dig" ? "翻开" : (currentMode === "mark" ? "标记" : "查看"))
                    font.pixelSize: parent.height * 0.12
                    font.family: "Microsoft YaHei"
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    height: parent.height * 0.15
                    wrapMode: Text.WordWrap
                }

                Grid {
                    columns: 2
                    spacing: parent.width * 0.05
                    width: parent.width
                    height: parent.height * 0.55

                    Button {
                        text: "标记"
                        width: (parent.width - parent.spacing) / 2
                        height: (parent.height - parent.spacing) / 2
                        style: fixedButtonStyle
                        onClicked: {
                            if (currentMode === "mark") currentMode = "none"
                            else currentMode = "mark"
                        }
                    }

                    Button {
                        text: "翻开"
                        width: (parent.width - parent.spacing) / 2
                        height: (parent.height - parent.spacing) / 2
                        style: fixedButtonStyle
                        onClicked: {
                            if (currentMode === "dig") currentMode = "none"
                            else currentMode = "dig"
                        }
                    }

                    Button {
                        text: "新游戏"
                        width: (parent.width - parent.spacing) / 2
                        height: (parent.height - parent.spacing) / 2
                        style: fixedButtonStyle
                        onClicked: newGame()
                    }

                    Button {
                        text: "退出"
                        width: (parent.width - parent.spacing) / 2
                        height: (parent.height - parent.spacing) / 2
                        style: fixedButtonStyle
                        onClicked: pluginRoot.backButtonClicked()
                    }
                }

                Text {
                    text: gameWin ? "胜利！" : (gameOver ? "游戏结束" : "")
                    font.pixelSize: parent.height * 0.12
                    font.family: "Microsoft YaHei"
                    color: "red"
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    height: parent.height * 0.12
                }
            }
        }
    }

    Component.onCompleted: {
        newGame()
    }
}