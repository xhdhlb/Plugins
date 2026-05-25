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
    property string pageTitle: ""
    property bool isLoading: false
    property string pageContent: ""
    property string errorMessage: ""
    property int maxChars: 300000
    property var xhr: null
    property int currentRequestId: 0

    property var historyList: []
    property int historyIndex: -1
    property bool ignoreHistoryAdd: false

    property string preLoadUrl: ""

    property real zoomFactor: 1.0
    property bool wrapText: true
    property bool enableHorizontalScroll: false
    property bool showRawContent: false

    property string customSearchTemplate: "https://cn.bing.com/search?q=%1"

    // 默认预设生成函数，每次返回全新数组，避免引用污染
    function getDefaultPresets() {
        return [
            { name: "一言", url: "https://v1.hitokoto.cn/?c=a&encode=text" },
            { name: "必应", url: "https://cn.bing.com" },
            { name: "哔哩哔哩", url: "https://www.bilibili.com" }
        ];
    }
    property var presets: getDefaultPresets()

    property bool menuVisible: false
    property bool keyboardPending: false
    property var db: null

    function initDatabase() {
        db = LocalStorage.openDatabaseSync("TextBrowser", "1.0", "存储浏览状态", 100000)
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
            zoomFactor: zoomFactor,
            wrapText: wrapText,
            enableHorizontalScroll: enableHorizontalScroll,
            showRawContent: showRawContent,
            customSearchTemplate: customSearchTemplate,
            presets: presets
        }
        db.transaction(function(tx) {
            tx.executeSql("INSERT OR REPLACE INTO state(key, value) VALUES('browserState', ?)",
                          [JSON.stringify(state)])
        })
    }

    function loadState() {
        if (!db) return
        db.readTransaction(function(tx) {
            var rs = tx.executeSql("SELECT value FROM state WHERE key='browserState'")
            if (rs.rows.length > 0) {
                var state = JSON.parse(rs.rows.item(0).value)
                if (state.currentUrl) {
                    currentUrl = state.currentUrl
                    historyList = state.historyList || []
                    historyIndex = state.historyIndex !== undefined ? state.historyIndex : -1
                    if (currentUrl) {
                        ignoreHistoryAdd = true
                        loadUrl(currentUrl)
                    }
                }
                if (state.zoomFactor !== undefined) zoomFactor = state.zoomFactor
                if (state.wrapText !== undefined) wrapText = state.wrapText
                if (state.enableHorizontalScroll !== undefined) enableHorizontalScroll = state.enableHorizontalScroll
                if (state.showRawContent !== undefined) showRawContent = state.showRawContent
                if (state.customSearchTemplate !== undefined) customSearchTemplate = state.customSearchTemplate
                if (state.presets !== undefined) presets = state.presets
                else presets = getDefaultPresets()
            } else {
                // 首次运行，使用默认
                presets = getDefaultPresets()
            }
        })
    }

    function extractTitleFromRaw(html) {
        var match = html.match(/<title[^>]*>([\s\S]*?)<\/title>/i)
        return match ? match[1].trim().replace(/\s+/g, ' ') : "无标题"
    }

    function isHtmlContent(text) {
        var lower = text.substring(0, 1000).toLowerCase()
        return /<html\b/i.test(lower) || /<body\b/i.test(lower)
    }

    function escapeHtml(text) {
        return text.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
    }

    function formatUrl(input) {
        var trimmed = input.trim()
        if (trimmed === "") return ""
        if (trimmed.match(/^[a-zA-Z][a-zA-Z0-9+\-.]*:\/\//)) return trimmed
        if (trimmed.match(/^\/\//)) return "https:" + trimmed
        if (trimmed[0] === '/' || trimmed[0] === '~' || trimmed.match(/^[a-zA-Z]:\\/)) {
            return "file://" + trimmed
        }
        if (trimmed.indexOf('.') > 0 && trimmed.indexOf(' ') === -1) return "https://" + trimmed
        if (trimmed === "localhost" || trimmed.match(/^\d+\.\d+\.\d+\.\d+$/)) return "http://" + trimmed
        return "search:" + trimmed
    }

    function loadUrl(url) {
        if (!url) return
        if (url.indexOf("search:") === 0) {
            var query = url.substring(7)
            url = customSearchTemplate.replace("%1", encodeURIComponent(query))
        }
        preLoadUrl = currentUrl
        if (xhr && xhr.readyState === XMLHttpRequest.LOADING) {
            xhr.abort()
            xhr = null
        }
        isLoading = true
        errorMessage = ""
        currentUrl = url
        if (!ignoreHistoryAdd) {
            if (historyIndex >= 0 && historyIndex < historyList.length - 1) {
                historyList = historyList.slice(0, historyIndex + 1)
            }
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
                if (xhr.status === 200) {
                    var raw = xhr.responseText
                    if (raw.length > maxChars) {
                        pageTitle = "无标题"
                        errorMessage = "网页内容过大，无法显示 (超过 " + (maxChars/1000).toFixed(0) + "k 字符)"
                        pageContent = ""
                        xhr = null
                        saveState()
                        return
                    }
                    pageTitle = extractTitleFromRaw(raw)
                    if (showRawContent) {
                        pageContent = "<pre>" + escapeHtml(raw) + "</pre>"
                    } else if (isHtmlContent(raw)) {
                        pageContent = raw
                    } else {
                        pageContent = "<pre>" + escapeHtml(raw) + "</pre>"
                    }
                } else {
                    pageTitle = "无标题"
                    errorMessage = "加载失败: HTTP " + xhr.status
                    pageContent = ""
                }
                saveState()
                xhr = null
            }
        }
        xhr.onerror = function() {
            if (reqId !== currentRequestId) return
            pageTitle = "无标题"
            isLoading = false
            errorMessage = "网络错误，请检查连接"
            pageContent = ""
            saveState()
            xhr = null
        }
        xhr.open("GET", url)
        xhr.send()
    }

    // 修复相对 URL 拼接
    function resolveUrl(base, relative) {
        if (!relative) return base
        if (/^[a-zA-Z][a-zA-Z0-9+\-.]*:\/\//.test(relative)) return relative
        if (relative.indexOf("//") === 0) {
            var m = base.match(/^([a-zA-Z][a-zA-Z0-9+\-.]*):\/\//)
            return (m ? m[1] : "https") + ":" + relative
        }

        // 提取 origin
        var originMatch = base.match(/^([a-zA-Z][a-zA-Z0-9+\-.]*:\/\/[^\/]+)/)
        var origin = originMatch ? originMatch[1] : ""
        var path = base.substring(origin.length)
        if (path === "") path = "/"

        if (relative[0] === '/') {
            return origin + relative
        }

        // 计算基础目录
        var baseDir = path.substring(0, path.lastIndexOf('/') + 1)
        var stack = baseDir.split('/').filter(function(s) { return s !== "" })
        var relParts = relative.split('/')
        for (var i = 0; i < relParts.length; i++) {
            var part = relParts[i]
            if (part === "..") {
                if (stack.length > 0) stack.pop()
            } else if (part !== "." && part !== "") {
                stack.push(part)
            }
        }
        var resolvedPath = "/" + stack.join('/')
        return origin + resolvedPath
    }

    function handleLinkClick(href) { loadUrl(resolveUrl(currentUrl, href)) }

    function goBack() {
        if (currentUrl === "") {
            if (historyList.length > 0 && historyIndex >= 0) {
                ignoreHistoryAdd = true
                loadUrl(historyList[historyIndex])
            }
        } else if (historyIndex > 0) {
            ignoreHistoryAdd = true
            historyIndex--
            loadUrl(historyList[historyIndex])
        }
    }

    function goForward() {
        if (historyIndex < historyList.length - 1) {
            ignoreHistoryAdd = true
            historyIndex++
            loadUrl(historyList[historyIndex])
        }
    }

    function refresh() { if (currentUrl) { ignoreHistoryAdd = true; loadUrl(currentUrl) } }

    function goHome() {
        if (xhr && xhr.readyState === XMLHttpRequest.LOADING) {
            currentRequestId = -1
            xhr.abort()
            xhr = null
        }
        isLoading = false
        errorMessage = ""
        currentUrl = ""
        pageContent = ""
        pageTitle = ""
        saveState()
    }

    function clearHistory() { historyList = []; historyIndex = -1; saveState() }

    function requestExit() { saveState(); backButtonClicked() }

    function _createKeyboard(initialText, callback) {
        if (qmlGlobal.inputPageShowing || keyboardPending) return
        keyboardPending = true
        var comp = qmlCreateComponent("YInputPage")
        if (comp.status === Component.Ready) {
            var incubator = comp.incubateObject(pagePopHelper.containerItem)
            if (incubator.status !== Component.Ready) {
                incubator.onStatusChanged = function(status) {
                    if (status === Component.Ready) {
                        _setupKeyboard(incubator.object, initialText, callback)
                    }
                }
            } else {
                _setupKeyboard(incubator.object, initialText, callback)
            }
        } else {
            keyboardPending = false
        }
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
            if (content && callback) callback(content)
            keyboardPending = false
        })
        keyboardPage.enterText(initialText)
        keyboardPage.show()
        qmlGlobal.inputPageShowing = true
    }

    function requestKeyboard(initialText) {
        _createKeyboard(initialText, function(content) { handleInputSubmit(content) })
    }

    function editSearchTemplate() {
        _createKeyboard(customSearchTemplate, function(newTemplate) {
            if (newTemplate && newTemplate.trim() !== "") {
                var t = newTemplate.trim()
                if (t.indexOf("%1") === -1) {
                    if (settingsLoader.item) settingsLoader.item.showTemplateWarning = true
                    return
                }
                customSearchTemplate = t
                saveState()
            }
        })
    }

    function handleInputSubmit(text) {
        var formatted = formatUrl(text)
        if (!formatted) return
        if (formatted === currentUrl) return
        loadUrl(formatted)
    }

    function showHistoryPage() { menuVisible = false; historyLoader.show() }
    function closeHistory() { historyLoader.hide() }

    function handleHistoryUrlClicked(url, idx) {
        ignoreHistoryAdd = true
        historyIndex = idx
        loadUrl(url)
        closeHistory()
    }

    function handleHistoryClear() { clearHistory() }

    function showSettingsPage() { menuVisible = false; settingsLoader.show() }
    function closeSettings() { settingsLoader.hide() }

    function zoomIn() { if (zoomFactor < 2.0) { zoomFactor = Math.min(2.0, zoomFactor + 0.25); saveState() } }
    function zoomOut() { if (zoomFactor > 0.25) { zoomFactor = Math.max(0.25, zoomFactor - 0.25); saveState() } }
    function resetZoom() { zoomFactor = 1.0; saveState() }

    function editPreset(index) {
        if (index < 0 || index >= presets.length) return
        var preset = presets[index]
        var initialStr = preset.name + "," + preset.url
        _createKeyboard(initialStr, function(newStr) {
            if (newStr === undefined || newStr === null) return
            var processed = newStr.replace(/[\r\n]/g, "").trim()
            if (processed === "") {
                presets.splice(index, 1)
                presets = presets
                saveState()
                return
            }
            var commaIdx = processed.indexOf(",")
            var name, url
            if (commaIdx === -1) {
                name = processed
                url = processed
            } else {
                name = processed.substring(0, commaIdx).trim()
                url = processed.substring(commaIdx + 1).trim()
            }
            if (name === "" || url === "") {
                presets.splice(index, 1)
            } else {
                presets[index].name = name
                presets[index].url = url
            }
            presets = presets
            saveState()
        })
    }

    function addPreset() {
        if (presets.length >= 20) return
        var newPreset = { name: "书签", url: "https://" }
        presets.push(newPreset)
        presets = presets
        saveState()
    }

    TitleBar {
        id: titleBar
        width: parent.width
        height: 20
        title: errorMessage !== "" ? "无标题" : (currentUrl ? pageTitle : "主页")
    }

    Column {
        anchors.top: titleBar.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom

        Item {
            width: parent.width
            height: parent.height - 30
            clip: true
            Flickable {
                id: flickable
                anchors.fill: parent; anchors.leftMargin: 5; anchors.rightMargin: 5
                contentWidth: enableHorizontalScroll ? Math.max(width, contentText.contentWidth * zoomFactor) : width
                contentHeight: contentText.contentHeight * zoomFactor
                flickableDirection: enableHorizontalScroll ? Flickable.HorizontalAndVerticalFlick : Flickable.VerticalFlick
                boundsBehavior: Flickable.StopAtBounds; clip: true
                Text {
                    id: contentText
                    width: wrapText ? flickable.width / zoomFactor : contentText.implicitWidth
                    textFormat: Text.RichText
                    wrapMode: wrapText ? Text.Wrap : Text.NoWrap
                    font.family: "Microsoft YaHei"; font.pixelSize: 13; color: "#000000"
                    text: pageContent; visible: pageContent !== ""
                    transform: Scale { origin.x: 0; origin.y: 0; xScale: zoomFactor; yScale: zoomFactor }
                    onLinkActivated: handleLinkClick(link)
                }
                Text {
                    id: errorText; width: flickable.width; wrapMode: Text.Wrap; font.family: "Microsoft YaHei"
                    font.pixelSize: 13; color: "#D32F2F"; horizontalAlignment: Text.AlignHCenter
                    text: errorMessage; visible: errorMessage !== ""; anchors.verticalCenter: parent.verticalCenter
                }
            }

            Item {
                id: homePresets
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                height: parent.height
                visible: pageContent === "" && errorMessage === "" && currentUrl === ""
                z: 1

                ListView {
                    anchors.fill: parent
                    model: presets
                    delegate: Rectangle {
                        width: parent.width
                        height: 30
                        color: itemArea.pressed ? "#E0E0E0" : "transparent"
                        Row {
                            anchors.fill: parent
                            anchors.leftMargin: 5
                            anchors.rightMargin: 5
                            Text {
                                anchors.centerIn: parent
                                width: parent.width
                                horizontalAlignment: Text.AlignHCenter
                                text: modelData.url
                                font.family: "Microsoft YaHei"
                                font.pixelSize: 16
                                color: "#000000"
                                visible: modelData.name === modelData.url
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 90
                                text: modelData.name.substring(0, 5)
                                font.family: "Microsoft YaHei"
                                font.pixelSize: 16
                                color: "#000000"
                                visible: modelData.name !== modelData.url
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.right: parent.right
                                width: parent.width - 90
                                text: modelData.url
                                font.family: "Microsoft YaHei"
                                font.pixelSize: 16
                                color: "#000000"
                                elide: Text.ElideRight
                                horizontalAlignment: Text.AlignRight
                                visible: modelData.name !== modelData.url
                            }
                        }
                        MouseArea {
                            id: itemArea
                            anchors.fill: parent
                            onClicked: loadUrl(modelData.url)
                            onPressAndHold: editPreset(index)
                        }
                    }
                    footer: Item {
                        width: parent.width
                        height: presets.length < 20 ? 30 : 0
                        visible: presets.length < 20
                        Rectangle {
                            anchors.fill: parent
                            color: plusArea.pressed ? "#E0E0E0" : "transparent"
                            Text {
                                anchors.centerIn: parent
                                text: "添加书签"
                                font.family: "Microsoft YaHei"
                                font.pixelSize: 16
                                color: "#000000"
                            }
                            MouseArea {
                                id: plusArea
                                anchors.fill: parent
                                onClicked: addPreset()
                            }
                        }
                    }
                    boundsBehavior: Flickable.StopAtBounds
                    clip: true
                }
            }
        }

        Rectangle {
            width: parent.width; height: 30; color: "#EEEEEE"; border.color: "#CCCCCC"; border.width: 0.5
            Row {
                anchors.fill: parent; anchors.leftMargin: 4; anchors.rightMargin: 4; spacing: 4
                Rectangle {
                    width: parent.width - 53; height: 26; anchors.verticalCenter: parent.verticalCenter; radius: 3
                    color: "#FFFFFF"; border.color: "#CCCCCC"; border.width: 0.5
                    Text {
                        anchors.fill: parent; anchors.leftMargin: 6; anchors.rightMargin: 6
                        verticalAlignment: Text.AlignVCenter
                        text: currentUrl ? currentUrl : "输入网址或搜索词"
                        font.family: "Microsoft YaHei"; font.pixelSize: 12; color: currentUrl ? "#000000" : "#AAAAAA"
                        elide: Text.ElideRight
                    }
                    MouseArea { anchors.fill: parent; onClicked: requestKeyboard(currentUrl) }
                }
                Rectangle {
                    width: 45; height: 26; anchors.verticalCenter: parent.verticalCenter; radius: 3
                    color: menuBtnArea.pressed ? "#D0D0D0" : "#E0E0E0"; border.color: "#B0B0B0"; border.width: 0.5
                    Text { anchors.centerIn: parent; text: "菜单"; font.family: "Microsoft YaHei"; font.pixelSize: 13; color: "#000000" }
                    MouseArea { id: menuBtnArea; anchors.fill: parent; onClicked: menuVisible = !menuVisible }
                }
            }
        }
    }

    Rectangle {
        visible: isLoading; x: (root.width - 135) / 2; y: 20; z: 10; width: 135; height: 30; radius: 6
        color: "#FFFFFF"; border.color: "#DDDDDD"; border.width: 1
        Text { anchors.centerIn: parent; text: "加载中（点击取消）"; font.family: "Microsoft YaHei"; font.pixelSize: 13; color: "#000000" }
        MouseArea {
            anchors.fill: parent
            onClicked: {
                if (xhr) { currentRequestId = 0; xhr.abort(); isLoading = false; currentUrl = preLoadUrl }
            }
        }
    }

    Rectangle {
        visible: menuVisible; x: parent.width - 156 - 6; y: parent.height - 30 - 96 - 2; width: 156; height: 96
        radius: 4; color: "#FFFFFF"; border.color: "#AAAAAA"; border.width: 1; z: 98
        Grid {
            anchors.fill: parent; anchors.margins: 3; columns: 3; rows: 3; spacing: 0
            MenuItem { text: "返回"; enabled: (currentUrl === "" && historyList.length > 0) || historyIndex > 0; onTriggered: { goBack(); menuVisible = false } }
            MenuItem { text: "前进"; enabled: historyIndex < historyList.length - 1; onTriggered: { goForward(); menuVisible = false } }
            MenuItem { text: "刷新"; onTriggered: { refresh(); menuVisible = false } }
            MenuItem { text: "主页"; onTriggered: { goHome(); menuVisible = false } }
            MenuItem { text: "设置"; onTriggered: showSettingsPage() }
            MenuItem { text: "历史"; onTriggered: showHistoryPage() }
            MenuItem { text: "退出"; onTriggered: { requestExit(); menuVisible = false } }
            MenuItem { text: "放大"; onTriggered: { zoomIn(); menuVisible = false } }
            MenuItem { text: "缩小"; onTriggered: { zoomOut(); menuVisible = false } }
        }
        MouseArea { anchors.fill: parent; anchors.margins: -10; z: -1; onClicked: menuVisible = false }
    }

    MouseArea { visible: menuVisible; anchors.fill: parent; z: 90; onClicked: menuVisible = false }

    component MenuItem: Rectangle {
        width: 50; height: 30; radius: 2; color: itemArea.pressed ? "#E0E0E0" : "transparent"
        property alias text: label.text; property alias enabled: itemArea.enabled; signal triggered()
        Text { id: label; anchors.centerIn: parent; font.family: "Microsoft YaHei"; font.pixelSize: 16; color: itemArea.enabled ? "#000000" : "#AAAAAA" }
        MouseArea { id: itemArea; anchors.fill: parent; onClicked: parent.triggered() }
    }

    Loader {
        id: historyLoader; anchors.fill: parent; z: 95; active: false; source: "history.qml"
        onLoaded: {
            item.historyModel = Qt.binding(function() { return historyList })
            item.urlClicked.connect(handleHistoryUrlClicked)
            item.clearHistoryRequested.connect(handleHistoryClear)
            item.backRequested.connect(closeHistory)
        }
        function show() { active = true }
        function hide() { active = false }
    }

    Loader {
        id: settingsLoader; anchors.fill: parent; z: 95; active: false; source: "settings.qml"
        onLoaded: {
            item.zoomPercent = Qt.binding(function() { return Math.round(zoomFactor * 100) })
            item.wrapTextEnabled = Qt.binding(function() { return wrapText })
            item.horizontalScrollEnabled = Qt.binding(function() { return enableHorizontalScroll })
            item.showRawContentEnabled = Qt.binding(function() { return showRawContent })
            item.searchTemplate = Qt.binding(function() { return customSearchTemplate })
            item.resetZoomRequested.connect(resetZoom)
            item.wrapTextToggled.connect(function(val) { wrapText = val; saveState() })
            item.horizontalScrollToggled.connect(function(val) { enableHorizontalScroll = val; saveState() })
            item.showRawContentToggled.connect(function(val) { showRawContent = val; saveState() })
            item.editSearchTemplate.connect(editSearchTemplate)
            item.resetSettingsRequested.connect(function() {
                wrapText = true
                enableHorizontalScroll = false
                showRawContent = false
                customSearchTemplate = "https://cn.bing.com/search?q=%1"
                presets = getDefaultPresets()   // 重置预设
                saveState()
            })
            item.backRequested.connect(closeSettings)
        }
        function show() { active = true }
        function hide() { active = false }
    }

    YPagePopHelper {
        id: pagePopHelper
        z: 99
        property var containerItem: this
        isShowing: qmlGlobal.inputPageShowing
        objectName: "from_TextBrowser"
    }

    Component.onCompleted: {
        currentTime = Qt.formatDateTime(new Date(), "hh:mm:ss")
        initDatabase()
    }
    Component.onDestruction: { saveState() }
}