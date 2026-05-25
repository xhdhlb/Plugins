import QtQuick 2.15
import QtQuick.LocalStorage 2.0
import "qrc:/qml/commons"

Rectangle {
    id: root
    width: 320
    height: 170
    color: "#F5F5F5"

    signal backButtonClicked()

    property string currentUrl: ""
    property string fileName: ""
    property bool isLoading: false
    property string statusMessage: ""
    property var xhr: null
    property int currentRequestId: 0

    property var historyList: []
    property int historyIndex: -1
    property bool ignoreHistoryAdd: false

    property int baseFontSize: 13
    property bool showLineNumbers: true
    property var lineStarts: []

    // 书签列表，默认为空
    property var presets: []

    // 编辑器是否可用
    property bool editorAvailable: currentUrl !== "" &&
                                   !currentUrl.endsWith("/") &&
                                   !currentUrl.endsWith("\\") &&
                                   statusMessage === ""

    property bool modified: false
    property int lineHeight: baseFontSize + 2

    property bool menuVisible: false
    property bool editMenuVisible: false
    property bool keyboardPending: false
    property var db: null

    // 隐藏文本编辑，用于复制到剪贴板
    TextEdit {
        id: clipboardHelper
        visible: false
    }

    // ---- 辅助函数 ----
    function stripFilePrefix(url) {
        if (typeof url !== "string") return url
        if (url.indexOf("file://") === 0) return url.substring(7)
        return url
    }
    function addFilePrefix(path) {
        if (typeof path !== "string" || path.trim() === "") return ""
        path = path.trim()
        if (path.indexOf("file://") === 0) return path
        return "file://" + path
    }

    // ---- 数据库 ----
    function initDatabase() {
        db = LocalStorage.openDatabaseSync("TextEditor", "1.0", "存储编辑器状态", 100000)
        db.transaction(function(tx) {
            tx.executeSql("CREATE TABLE IF NOT EXISTS state(key TEXT PRIMARY KEY, value TEXT)")
        })
        loadState()
    }
    function saveState() {
        if (!db) return
        var state = {
            currentUrl: currentUrl,
            historyList: historyList,
            historyIndex: historyIndex,
            presets: presets,
            showLineNumbers: showLineNumbers
        }
        db.transaction(function(tx) {
            tx.executeSql("INSERT OR REPLACE INTO state(key, value) VALUES('editorState', ?)",
                          [JSON.stringify(state)])
        })
    }
    function loadState() {
        if (!db) return
        db.readTransaction(function(tx) {
            var rs = tx.executeSql("SELECT value FROM state WHERE key='editorState'")
            if (rs.rows.length > 0) {
                var state = JSON.parse(rs.rows.item(0).value)
                if (state.currentUrl) {
                    currentUrl = state.currentUrl
                    historyList = state.historyList || []
                    historyIndex = state.historyIndex !== undefined ? state.historyIndex : -1
                    if (currentUrl) {
                        ignoreHistoryAdd = true
                        loadFile(currentUrl)
                    }
                }
                if (state.presets !== undefined) presets = state.presets
                if (state.showLineNumbers !== undefined) showLineNumbers = state.showLineNumbers
            }
        })
    }

    // ---- 文件操作 ----
    function loadFile(url) {
        if (!url) return
        if (url.endsWith("/") || url.endsWith("\\")) {
            isLoading = false
            statusMessage = "请输入文件路径"
            editorArea.text = ""
            xhr = null
            modified = false
            saveState()
            return
        }

        if (xhr && xhr.readyState === XMLHttpRequest.LOADING) {
            xhr.abort()
            xhr = null
        }
        isLoading = true
        statusMessage = ""
        currentUrl = url
        var parts = url.replace(/\\/g, "/").split("/")
        fileName = parts[parts.length - 1] || "未命名"
        modified = false

        if (!ignoreHistoryAdd) {
            if (historyIndex >= 0 && historyIndex < historyList.length - 1)
                historyList = historyList.slice(0, historyIndex + 1)
            if (historyList.length >= 50) {
                historyList.shift()
                historyIndex--
            }
            historyList.push(url)
            historyIndex = historyList.length - 1
        }
        ignoreHistoryAdd = false

        var reqId = ++currentRequestId
        xhr = new XMLHttpRequest()
        xhr.onreadystatechange = function() {
            if (reqId !== currentRequestId) return
            if (xhr.readyState === XMLHttpRequest.DONE) {
                isLoading = false
                if (xhr.status === 200 || xhr.status === 0) {
                    var maxSize = 300 * 1024
                    if (xhr.responseText.length > maxSize) {
                        editorArea.text = ""
                        statusMessage = "文件过大"
                    } else {
                        editorArea.text = xhr.responseText
                        updateLineStarts()
                        statusMessage = ""
                    }
                } else {
                    editorArea.text = ""
                    statusMessage = "无法打开文件" + (xhr.status > 0 ? " (HTTP " + xhr.status + ")" : "")
                }
                modified = false
                saveState()
                xhr = null
            }
        }
        xhr.onerror = function() {
            if (reqId !== currentRequestId) return
            isLoading = false
            editorArea.text = ""
            statusMessage = "无法打开文件"
            modified = false
            saveState()
            xhr = null
        }
        xhr.open("GET", url)
        xhr.send()
    }

    function saveFile() {
        if (!editorAvailable) return
        if (xhr && xhr.readyState === XMLHttpRequest.LOADING) {
            xhr.abort()
            xhr = null
        }
        isLoading = true
        var reqId = ++currentRequestId
        xhr = new XMLHttpRequest()
        xhr.onreadystatechange = function() {
            if (reqId !== currentRequestId) return
            if (xhr.readyState === XMLHttpRequest.DONE) {
                isLoading = false
                if (xhr.status === 200 || xhr.status === 0 || xhr.status === 201) {
                    modified = false
                }
                saveState()
                xhr = null
            }
        }
        xhr.onerror = function() {
            if (reqId !== currentRequestId) return
            isLoading = false
            xhr = null
        }
        xhr.open("PUT", currentUrl)
        xhr.send(editorArea.text)
    }

    function updateLineStarts() {
        var text = editorArea.text
        var starts = [0]
        for (var i = 0; i < text.length; i++)
            if (text[i] === '\n') starts.push(i + 1)
        lineStarts = starts
    }

    // ---- 导航 ----
    function goBack() {
        if (currentUrl === "") {
            if (historyList.length > 0 && historyIndex >= 0) {
                ignoreHistoryAdd = true
                loadFile(historyList[historyIndex])
            }
        } else if (historyIndex > 0) {
            ignoreHistoryAdd = true
            historyIndex--
            loadFile(historyList[historyIndex])
        }
    }
    function goForward() {
        if (historyIndex < historyList.length - 1) {
            ignoreHistoryAdd = true
            historyIndex++
            loadFile(historyList[historyIndex])
        }
    }
    function refresh() {
        if (currentUrl) {
            ignoreHistoryAdd = true
            loadFile(currentUrl)
        }
    }
    function goHome() {
        if (xhr && xhr.readyState === XMLHttpRequest.LOADING) {
            currentRequestId = -1
            xhr.abort()
            xhr = null
        }
        isLoading = false
        statusMessage = ""
        currentUrl = ""
        fileName = ""
        editorArea.text = ""
        modified = false
        saveState()
    }
    function clearHistory() { historyList = []; historyIndex = -1; saveState() }
    function requestExit() { saveState(); backButtonClicked() }

    // ---- 编辑操作 ----
    function insertTextKeyboard() {
        var init = (editorArea.selectionStart !== editorArea.selectionEnd) ? editorArea.selectedText : ""
        _createKeyboard(init, function(text) { insertAtCursor(text) })
    }
    function insertAtCursor(text) {
        if (editorArea.selectionStart !== editorArea.selectionEnd)
            editorArea.remove(editorArea.selectionStart, editorArea.selectionEnd)
        editorArea.insert(editorArea.cursorPosition, text)
        updateLineStarts()
    }
    function deleteAtCursor() {
        if (editorArea.selectionStart !== editorArea.selectionEnd)
            editorArea.remove(editorArea.selectionStart, editorArea.selectionEnd)
        else if (editorArea.cursorPosition > 0)
            editorArea.remove(editorArea.cursorPosition - 1, editorArea.cursorPosition)
        updateLineStarts()
    }
    function copySelection() { editorArea.copy() }
    function pasteFromClipboard() { editorArea.paste(); updateLineStarts() }
    function cutSelection() { editorArea.cut(); updateLineStarts() }
    function selectAll() { editorArea.selectAll() }
    function insertReturn() { insertAtCursor("\n") }
    function insertSpace() { insertAtCursor(" ") }
    function jumpToLine() {
        _createKeyboard("", function(text) {
            var lineNum = parseInt(text)
            if (isNaN(lineNum) || lineNum < 1) return
            var targetLine = Math.min(lineNum, lineStarts.length)
            var pos = lineStarts[targetLine - 1]
            var rect = editorArea.positionToRectangle(pos)
            if (editorFlickable) editorFlickable.contentY = rect.y
        })
    }

    // ---- 滚动辅助 ----
    function scrollByLines(delta) {
        if (editorFlickable) {
            editorFlickable.contentY = Math.max(0, Math.min(
                editorFlickable.contentHeight - editorFlickable.height,
                editorFlickable.contentY + delta * lineHeight
            ))
        }
    }

    // ---- 键盘 ----
    function _createKeyboard(initialText, callback) {
        if (qmlGlobal.inputPageShowing || keyboardPending) return
        keyboardPending = true
        var comp = qmlCreateComponent("YInputPage")
        if (comp.status === Component.Ready) {
            var incubator = comp.incubateObject(pagePopHelper.containerItem)
            if (incubator.status !== Component.Ready) {
                incubator.onStatusChanged = function(status) {
                    if (status === Component.Ready) _setupKeyboard(incubator.object, initialText, callback)
                }
            } else _setupKeyboard(incubator.object, initialText, callback)
        } else keyboardPending = false
    }
    function _setupKeyboard(keyboardPage, initialText, callback) {
        keyboardPage.backButtonClicked.connect(function() {
            qmlGlobal.inputPageShowing = false
            keyboardPage.todoDestroy()
            keyboardPage = null
            keyboardPending = false
        })
        keyboardPage.inputFinished.connect(function(content) {
            qmlGlobal.inputPageShowing = false
            keyboardPage.todoDestroy()
            if (content !== undefined && callback) callback(content)
            keyboardPending = false
        })
        keyboardPage.enterText(initialText)
        keyboardPage.show()
        qmlGlobal.inputPageShowing = true
    }
    function requestKeyboard(initialText) {
        _createKeyboard(initialText, function(content) { handleInputSubmit(content) })
    }
    function handleInputSubmit(text) {
        var withoutPrefix = text.trim()
        var formatted = addFilePrefix(withoutPrefix)
        currentUrl = formatted

        if (formatted === "") {
            goHome()
            return
        }
        if (withoutPrefix.endsWith("/") || withoutPrefix.endsWith("\\")) {
            statusMessage = "请输入文件路径"
            editorArea.text = ""
            modified = false
            saveState()
            return
        }
        if (formatted === currentUrl && editorAvailable) {
            refresh()
            return
        }
        loadFile(formatted)
    }

    // ---- 书签操作 ----
    function addBookmark() {
        presets.push({
            name: "书签",
            url: "file:///userdisk/text.txt"
        })
        presets = presets
        saveState()
    }

    // 添加当前地址为书签（名称和url相同）
    function addBookmarkFromCurrent() {
        if (!editorAvailable) return
        var path = stripFilePrefix(currentUrl)
        if (!path) return
        presets.push({
            name: path,
            url: "file://" + path
        })
        presets = presets
        saveState()
    }

    function editPreset(index) {
        var preset = presets[index]
        if (!preset) return
        var init = preset.name + "," + stripFilePrefix(preset.url)
        _createKeyboard(init, function(newStr) {
            if (newStr === undefined || newStr === null) return
            var cleaned = newStr.replace(/[\r\n]/g, '').trim()
            if (cleaned === "") {
                presets.splice(index, 1)
                presets = presets
                saveState()
                return
            }
            var commaIdx = cleaned.indexOf(",")
            var name, path
            if (commaIdx === -1) {
                name = cleaned
                path = cleaned
            } else {
                name = cleaned.substring(0, commaIdx).trim()
                path = cleaned.substring(commaIdx + 1).trim()
            }
            if (name === "" || path === "") {
                presets.splice(index, 1)
                presets = presets
                saveState()
                return
            }
            presets[index].name = name
            presets[index].url = addFilePrefix(path)
            presets = presets
            saveState()
        })
    }

    // ---- 界面 ----
    Column {
        anchors.fill: parent

        TitleBar {
            width: parent.width
            title: {
                if (currentUrl === "") return "主页"
                if (!editorAvailable && statusMessage !== "") return "错误"
                var prefix = modified ? "*" : ""
                return prefix + fileName
            }
            currentChars: editorAvailable ? editorArea.cursorPosition : -1
            totalChars: editorAvailable ? editorArea.text.length : -1
        }

        // 内容区域
        Item {
            id: contentArea
            width: parent.width; height: parent.height - 50; clip: true

            // 行号面板（背景色 #E8E8E8，右对齐，右边距2）
            Rectangle {
                id: lineNumberPanel
                visible: showLineNumbers && editorAvailable
                width: visible ? Math.max(10, (String(lineStarts.length).length) * 5 + 5) : 0
                anchors.top: parent.top; anchors.bottom: parent.bottom; anchors.left: parent.left
                color: "#E8E8E8"
                Canvas {
                    id: lineCanvas
                    anchors.fill: parent
                    onPaint: {
                        var ctx = getContext("2d")
                        ctx.clearRect(0, 0, width, height)
                        if (!visible || !editorFlickable || lineStarts.length === 0) return
                        var fontSize = editorArea.font.pixelSize
                        ctx.font = fontSize + "px Microsoft YaHei"
                        ctx.fillStyle = "#888888"
                        ctx.textAlign = "right"
                        var viewY = editorFlickable.contentY
                        var viewHeight = height
                        for (var i = 0; i < lineStarts.length; i++) {
                            var rect = editorArea.positionToRectangle(lineStarts[i])
                            var lineY = rect.y
                            var lineH = rect.height
                            if (lineY + lineH < viewY || lineY > viewY + viewHeight) continue
                            ctx.fillText((i + 1), width - 2, lineY - viewY + fontSize * 0.85)
                        }
                    }
                    Connections {
                        target: editorFlickable
                        onContentYChanged: lineCanvas.requestPaint()
                        onContentHeightChanged: lineCanvas.requestPaint()
                    }
                    Connections {
                        target: editorArea
                        onTextChanged: lineCanvas.requestPaint()
                    }
                }
            }

            // 编辑器容器
            Item {
                anchors.left: lineNumberPanel.visible ? lineNumberPanel.right : parent.left
                anchors.right: parent.right
                anchors.top: parent.top; anchors.bottom: parent.bottom
                visible: editorAvailable

                Flickable {
                    id: editorFlickable
                    anchors.left: parent.left
                    anchors.right: scrollBar.left
                    anchors.top: parent.top; anchors.bottom: parent.bottom
                    contentWidth: width
                    contentHeight: editorArea.implicitHeight
                    boundsBehavior: Flickable.StopAtBounds
                    clip: true

                    TextEdit {
                        id: editorArea
                        width: editorFlickable.width
                        height: Math.max(editorFlickable.height, implicitHeight)
                        font.family: "Microsoft YaHei"
                        font.pixelSize: baseFontSize
                        color: "#000000"
                        wrapMode: TextEdit.Wrap
                        selectByMouse: true
                        onTextChanged: {
                            updateLineStarts()
                            if (!isLoading && editorAvailable) modified = true
                        }
                    }
                }

                // 自定义滚动条（含上下按钮）
                Rectangle {
                    id: scrollBar
                    width: 14
                    anchors.right: parent.right
                    anchors.top: parent.top; anchors.bottom: parent.bottom
                    visible: editorFlickable.contentHeight > editorFlickable.height
                    color: "#E0E0E0"

                    Rectangle {
                        id: scrollUpBtn
                        width: parent.width; height: width
                        anchors.top: parent.top
                        color: upMa.pressed ? "#C0C0C0" : "transparent"
                        Text {
                            anchors.centerIn: parent
                            text: "▲"
                            font.family: "Microsoft YaHei"
                            font.pixelSize: 10
                            color: "#000000"
                        }
                        MouseArea {
                            id: upMa
                            anchors.fill: parent
                            onClicked: scrollByLines(-3)
                            onPressAndHold: scrollUpTimer.start()
                            onReleased: scrollUpTimer.stop()
                        }
                        Timer {
                            id: scrollUpTimer
                            interval: 100; repeat: true
                            onTriggered: scrollByLines(-3)
                        }
                    }

                    Rectangle {
                        id: scrollDownBtn
                        width: parent.width; height: width
                        anchors.bottom: parent.bottom
                        color: downMa.pressed ? "#C0C0C0" : "transparent"
                        Text {
                            anchors.centerIn: parent
                            text: "▼"
                            font.family: "Microsoft YaHei"
                            font.pixelSize: 10
                            color: "#000000"
                        }
                        MouseArea {
                            id: downMa
                            anchors.fill: parent
                            onClicked: scrollByLines(3)
                            onPressAndHold: scrollDownTimer.start()
                            onReleased: scrollDownTimer.stop()
                        }
                        Timer {
                            id: scrollDownTimer
                            interval: 100; repeat: true
                            onTriggered: scrollByLines(3)
                        }
                    }

                    Item {
                        id: scrollTrack
                        anchors.top: scrollUpBtn.bottom
                        anchors.bottom: scrollDownBtn.top
                        anchors.left: parent.left
                        anchors.right: parent.right

                        property real viewH: editorFlickable.height
                        property real contentH: editorFlickable.contentHeight
                        property real ratio: viewH / contentH
                        property real handleH: Math.max(20, height * ratio)
                        property real maxY: height - handleH
                        property real contentY: editorFlickable.contentY
                        property real maxContentY: contentH - viewH

                        Rectangle {
                            id: scrollHandle
                            width: parent.width
                            radius: 2
                            color: "#888888"
                            height: scrollTrack.handleH
                            y: scrollTrack.maxY > 0 ? (scrollTrack.maxY * (scrollTrack.contentY / scrollTrack.maxContentY)) : 0
                        }

                        property bool dragging: false
                        property real lastMouseY: 0
                        MouseArea {
                            anchors.fill: parent
                            onPressed: {
                                scrollTrack.dragging = true
                                scrollTrack.lastMouseY = mouseY
                            }
                            onReleased: scrollTrack.dragging = false
                            onPositionChanged: {
                                if (scrollTrack.dragging) {
                                    var dy = mouseY - scrollTrack.lastMouseY
                                    var ratioMove = dy / (scrollTrack.height - scrollHandle.height)
                                    var newCY = scrollTrack.contentY + ratioMove * scrollTrack.maxContentY
                                    newCY = Math.max(0, Math.min(scrollTrack.maxContentY, newCY))
                                    editorFlickable.contentY = newCY
                                    scrollTrack.lastMouseY = mouseY
                                }
                            }
                        }
                    }
                }
            }

            // 错误信息
            Text {
                anchors.centerIn: parent
                visible: !editorAvailable && currentUrl !== ""
                text: statusMessage
                font.family: "Microsoft YaHei"
                font.pixelSize: 18
                color: "#D32F2F"
                horizontalAlignment: Text.AlignHCenter
                width: parent.width - 20
                wrapMode: Text.Wrap
            }

            // 主页书签列表
            ListView {
                id: bookmarkList
                anchors.fill: parent
                visible: currentUrl === ""
                z: 1
                model: presets.length + 1
                delegate: Rectangle {
                    width: parent.width
                    height: 30
                    color: itemArea.pressed ? "#E0E0E0" : "transparent"
                    property bool isAddButton: index === presets.length

                    Row {
                        anchors.fill: parent
                        anchors.leftMargin: 5
                        anchors.rightMargin: 5
                        visible: !isAddButton
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: {
                                var urlStripped = stripFilePrefix(presets[index].url)
                                if (presets[index].name === urlStripped)
                                    return urlStripped
                                else
                                    return presets[index].name.substring(0, 5)
                            }
                            width: presets[index].name === stripFilePrefix(presets[index].url) ? parent.width : 90
                            font.family: "Microsoft YaHei"
                            font.pixelSize: 16
                            color: "#000000"
                            elide: Text.ElideRight
                        }
                        Text {
                            visible: presets[index].name !== stripFilePrefix(presets[index].url)
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.right: parent.right
                            width: parent.width - 90
                            text: stripFilePrefix(presets[index].url)
                            font.family: "Microsoft YaHei"
                            font.pixelSize: 16
                            color: "#000000"
                            elide: Text.ElideRight
                            horizontalAlignment: Text.AlignRight
                        }
                    }

                    Text {
                        anchors.centerIn: parent
                        visible: isAddButton
                        text: "添加书签"
                        font.family: "Microsoft YaHei"
                        font.pixelSize: 16
                        color: "#000000"
                    }

                    MouseArea {
                        id: itemArea
                        anchors.fill: parent
                        onClicked: {
                            if (isAddButton) addBookmark()
                            else loadFile(presets[index].url)
                        }
                        onPressAndHold: {
                            if (!isAddButton) editPreset(index)
                        }
                    }
                }
                boundsBehavior: Flickable.StopAtBounds
                clip: true
            }
        }

        // 底部栏
        Rectangle {
            width: parent.width; height: 30; color: "#EEEEEE"; border.color: "#CCCCCC"; border.width: 0.5
            Row {
                anchors.fill: parent
                anchors.leftMargin: 4
                anchors.rightMargin: 1
                spacing: 4

                // 地址输入框（宽度调整为容纳三个按钮）
                Rectangle {
                    width: parent.width - 152
                    height: 26
                    anchors.verticalCenter: parent.verticalCenter
                    radius: 3
                    color: "#FFFFFF"
                    border.color: "#CCCCCC"
                    border.width: 0.5
                    Text {
                        anchors.fill: parent
                        anchors.leftMargin: 6; anchors.rightMargin: 6
                        verticalAlignment: Text.AlignVCenter
                        text: currentUrl ? stripFilePrefix(currentUrl) : "输入文本文件路径"
                        font.family: "Microsoft YaHei"; font.pixelSize: 12
                        color: currentUrl ? "#000000" : "#AAAAAA"
                        elide: Text.ElideRight
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: requestKeyboard(currentUrl ? stripFilePrefix(currentUrl) : "")
                        onPressAndHold: {
                            var text = currentUrl ? stripFilePrefix(currentUrl) : ""
                            if (text) {
                                clipboardHelper.text = text
                                clipboardHelper.selectAll()
                                clipboardHelper.copy()
                                clipboardHelper.text = ""
                            }
                        }
                    }
                }

                // 输入按钮
                Rectangle {
                    width: 45; height: 26
                    anchors.verticalCenter: parent.verticalCenter
                    radius: 3
                    color: {
                        if (!editorAvailable) return "#C0C0C0"
                        return inputBtnArea.pressed ? "#D0D0D0" : "#E0E0E0"
                    }
                    border.color: "#B0B0B0"
                    border.width: 0.5
                    Text {
                        anchors.centerIn: parent
                        text: "输入"
                        font.family: "Microsoft YaHei"
                        font.pixelSize: 14
                        color: editorAvailable ? "#000000" : "#AAAAAA"
                    }
                    MouseArea {
                        id: inputBtnArea
                        anchors.fill: parent
                        enabled: editorAvailable
                        onClicked: insertTextKeyboard()
                    }
                }

                // 编辑按钮（移到控制栏）
                Rectangle {
                    width: 45; height: 26
                    anchors.verticalCenter: parent.verticalCenter
                    radius: 3
                    color: {
                        if (!editorAvailable) return "#C0C0C0"
                        return editBtnArea.pressed ? "#D0D0D0" : "#E0E0E0"
                    }
                    border.color: "#B0B0B0"
                    border.width: 0.5
                    Text {
                        anchors.centerIn: parent
                        text: "编辑"
                        font.family: "Microsoft YaHei"
                        font.pixelSize: 14
                        color: editorAvailable ? "#000000" : "#AAAAAA"
                    }
                    MouseArea {
                        id: editBtnArea
                        anchors.fill: parent
                        enabled: editorAvailable
                        onClicked: { editMenuVisible = !editMenuVisible; menuVisible = false }
                    }
                }

                // 菜单按钮
                Rectangle {
                    width: 45; height: 26
                    anchors.verticalCenter: parent.verticalCenter
                    radius: 3
                    color: menuBtnArea.pressed ? "#D0D0D0" : "#E0E0E0"
                    border.color: "#B0B0B0"
                    border.width: 0.5
                    Text {
                        anchors.centerIn: parent
                        text: "菜单"
                        font.family: "Microsoft YaHei"
                        font.pixelSize: 14
                        color: "#000000"
                    }
                    MouseArea {
                        id: menuBtnArea
                        anchors.fill: parent
                        onClicked: { menuVisible = !menuVisible; editMenuVisible = false }
                    }
                }
            }
        }
    }

    // 加载提示
    Rectangle {
        visible: isLoading
        x: (root.width - 120) / 2; y: 20; z: 10; width: 120; height: 30; radius: 6
        color: "#FFFFFF"; border.color: "#DDDDDD"; border.width: 1
        Text { anchors.centerIn: parent; text: "加载中..."; font.family: "Microsoft YaHei"; font.pixelSize: 13; color: "#000000" }
        MouseArea { anchors.fill: parent; onClicked: { if (xhr) { currentRequestId = 0; xhr.abort(); isLoading = false } } }
    }

    // ---- 一级菜单（3x3，收藏替换编辑位置） ----
    Rectangle {
        visible: menuVisible && !editMenuVisible
        x: parent.width - 151; y: parent.height - 30 - 94 - 2
        width: 145; height: 94
        radius: 4; color: "#FFFFFF"; border.color: "#AAAAAA"; border.width: 1; z: 98
        Grid {
            anchors.fill: parent; anchors.margins: 3
            columns: 3; rows: 3; spacing: 2
            MenuItem { text: "返回"; enabled: (currentUrl === "" && historyList.length > 0) || historyIndex > 0; onTriggered: { goBack(); menuVisible = false } }
            MenuItem { text: "主页"; onTriggered: { goHome(); menuVisible = false } }
            MenuItem { text: "历史"; onTriggered: { menuVisible = false; historyLoader.show() } }

            MenuItem { text: "前进"; enabled: historyIndex < historyList.length - 1; onTriggered: { goForward(); menuVisible = false } }
            MenuItem { text: "设置"; onTriggered: { menuVisible = false; settingsLoader.show() } }
            MenuItem { text: "退出"; onTriggered: { requestExit(); menuVisible = false } }

            MenuItem { text: "保存"; enabled: editorAvailable; onTriggered: { saveFile(); menuVisible = false } }
            MenuItem { text: "跳行"; enabled: editorAvailable; onTriggered: { jumpToLine(); menuVisible = false } }
            MenuItem { text: "收藏"; enabled: editorAvailable; onTriggered: { addBookmarkFromCurrent(); menuVisible = false } }
        }
        MouseArea { anchors.fill: parent; anchors.margins: -10; z: -1; onClicked: menuVisible = false }
    }

    // 二级菜单（编辑，3x3）
    Rectangle {
        visible: editMenuVisible && editorAvailable
        x: parent.width - 151; y: parent.height - 30 - 94 - 2
        width: 145; height: 94
        radius: 4; color: "#FFFFFF"; border.color: "#AAAAAA"; border.width: 1; z: 99
        Grid {
            anchors.fill: parent; anchors.margins: 3
            columns: 3; rows: 3; spacing: 2
            MenuItem { text: "撤销"; enabled: editorArea.canUndo; onTriggered: { editorArea.undo(); editMenuVisible = false } }
            MenuItem { text: "重做"; enabled: editorArea.canRedo; onTriggered: { editorArea.redo(); editMenuVisible = false } }
            MenuItem { text: "空格"; onTriggered: { insertSpace(); editMenuVisible = false } }
            MenuItem { text: "复制"; onTriggered: { copySelection(); editMenuVisible = false } }
            MenuItem { text: "粘贴"; onTriggered: { pasteFromClipboard(); editMenuVisible = false } }
            MenuItem { text: "剪切"; onTriggered: { cutSelection(); editMenuVisible = false } }
            MenuItem { text: "删除"; onTriggered: { deleteAtCursor(); editMenuVisible = false } }
            MenuItem { text: "换行"; onTriggered: { insertReturn(); editMenuVisible = false } }
            MenuItem { text: "全选"; onTriggered: { selectAll(); editMenuVisible = false } }
        }
        MouseArea { anchors.fill: parent; anchors.margins: -10; z: -1; onClicked: editMenuVisible = false }
    }

    MouseArea { visible: menuVisible || editMenuVisible; anchors.fill: parent; z: 90; onClicked: { menuVisible = false; editMenuVisible = false } }

    component MenuItem: Rectangle {
        width: 45; height: 28; radius: 2
        color: itemArea.enabled && itemArea.pressed ? "#E0E0E0" : "transparent"
        property alias text: label.text
        property alias enabled: itemArea.enabled
        signal triggered()
        Text {
            id: label
            anchors.centerIn: parent
            font.family: "Microsoft YaHei"
            font.pixelSize: 16
            color: itemArea.enabled ? "#000000" : "#AAAAAA"
        }
        MouseArea {
            id: itemArea
            anchors.fill: parent
            onClicked: parent.triggered()
        }
    }

    // 历史记录加载器
    Loader {
        id: historyLoader
        anchors.fill: parent; z: 95; active: false; source: "history.qml"
        onLoaded: {
            item.historyModel = Qt.binding(function() { return historyList.map(function(url) { return stripFilePrefix(url) }) })
            item.urlClicked.connect(function(path, idx) {
                ignoreHistoryAdd = true; historyIndex = idx; loadFile(addFilePrefix(path)); historyLoader.active = false
            })
            item.clearHistoryRequested.connect(clearHistory)
            item.backRequested.connect(function() { historyLoader.active = false })
        }
        function show() { active = true }
        function hide() { active = false }
    }

    // 设置加载器
    Loader {
        id: settingsLoader
        anchors.fill: parent; z: 95; active: false; source: "settings.qml"
        onLoaded: {
            item.showLineNumbersEnabled = Qt.binding(function() { return showLineNumbers })
            item.showLineNumbersToggled.connect(function(val) { showLineNumbers = val; saveState() })
            item.resetSettingsRequested.connect(function() {
                showLineNumbers = true
                presets = []
                saveState()
            })
            item.backRequested.connect(function() { settingsLoader.active = false })
        }
        function show() { active = true }
        function hide() { active = false }
    }

    YPagePopHelper {
        id: pagePopHelper; z: 99; property var containerItem: this
        isShowing: qmlGlobal.inputPageShowing; objectName: "from_TextBrowser"
    }

    Component.onCompleted: {
        initDatabase()
    }
    Component.onDestruction: { saveState() }
}