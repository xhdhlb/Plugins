import QtQuick 2.15
import QtQuick.LocalStorage 2.15

Rectangle {
    id: root
    width: 320
    height: 170
    gradient: Gradient {
        GradientStop { position: 0.0; color: "#E6F0FA" }
        GradientStop { position: 1.0; color: "#B8D8F0" }
    }

    signal backButtonClicked()

    // ---------- 持久化设置 ----------
    property bool showGeo: true
    property bool enableLog: false
    property bool keepDecimal: true
    property bool extendTimeout: false

    function saveSetting(key, value) {
        executeSql('INSERT OR REPLACE INTO settings(key, value) VALUES(?, ?)', [key, String(value)]);
    }

    function loadSettings() {
        executeSql('SELECT key, value FROM settings', [], function(ok, rs) {
            if (!ok) return;
            for (var i = 0; i < rs.rows.length; i++) {
                var row = rs.rows.item(i);
                if (row.key === "showGeo") showGeo = (row.value === "true");
                else if (row.key === "enableLog") enableLog = (row.value === "true");
                else if (row.key === "keepDecimal") keepDecimal = (row.value !== "false");
                else if (row.key === "extendTimeout") extendTimeout = (row.value === "true");
            }
        });
    }

    onShowGeoChanged: saveSetting("showGeo", showGeo)
    onEnableLogChanged: saveSetting("enableLog", enableLog)
    onKeepDecimalChanged: saveSetting("keepDecimal", keepDecimal)
    onExtendTimeoutChanged: saveSetting("extendTimeout", extendTimeout)

    property var cityList: []
    property string currentCity: "北京"

    property bool loadingWeather: false
    property string weatherDesc: ""
    property string temp: ""
    property string feelsLike: ""
    property string humidity: ""
    property string wind: ""
    property string sunrise: ""
    property string sunset: ""
    property string errorMsg: ""
    property string errorDetail: ""
    property string currentRequestCity: ""

    property var hourlyForecast: []
    property var dailyForecast: []

    property string currentDateTime: ""
    property string currentGeoLat: ""
    property string currentGeoLon: ""

    // 全局请求ID
    property int weatherRequestId: 0

    Timer {
        interval: 1000; running: true; repeat: true
        onTriggered: currentDateTime = Qt.formatDateTime(new Date(), "hh:mm")
    }

    property var wmoMap: {
        "0": "晴天",
        "1": "大部晴朗",
        "2": "多云",
        "3": "阴天",
        "45": "雾",
        "48": "雾凇",
        "51": "小毛毛雨",
        "53": "中毛毛雨",
        "55": "大毛毛雨",
        "61": "小雨",
        "63": "中雨",
        "65": "大雨",
        "71": "小雪",
        "73": "中雪",
        "75": "大雪",
        "80": "小阵雨",
        "81": "中阵雨",
        "82": "大阵雨",
        "95": "雷暴",
        "96": "雷暴伴冰雹"
    }

    // ---------- 日志队列 ----------
    property var logQueue: []
    property bool logWriting: false
    property int maxLogLines: 500

    function log(message) {
        if (!enableLog) return;
        var timestamp = new Date().toISOString();
        var entry = "[" + timestamp + "] " + message + "\n";
        logQueue.push(entry);
        processLogQueue();
    }

    function processLogQueue() {
        if (logWriting || logQueue.length === 0) return;
        logWriting = true;
        var entry = logQueue.shift();
        var path = "file:///userdisk/PenMods/plugins/weather/weatherlog.txt";
        var getXhr = new XMLHttpRequest();
        getXhr.open("GET", path, true);
        getXhr.onreadystatechange = function() {
            if (getXhr.readyState === XMLHttpRequest.DONE) {
                var old = (getXhr.status === 200 || getXhr.status === 0) ? (getXhr.responseText || "") : "";
                var lines = old.split("\n");
                if (lines.length > maxLogLines) {
                    lines = lines.slice(lines.length - maxLogLines);
                    old = lines.join("\n");
                }
                var newContent = old + entry;
                var putXhr = new XMLHttpRequest();
                putXhr.open("PUT", path, true);
                putXhr.setRequestHeader("Content-Type", "text/plain");
                putXhr.onreadystatechange = function() {
                    if (putXhr.readyState === XMLHttpRequest.DONE) {
                        logWriting = false;
                        processLogQueue();
                    }
                };
                putXhr.send(newContent);
            }
        };
        getXhr.send();
    }

    // ---------- 请求管理 ----------
    property var geoXhr: null
    property var weatherXhr: null

    function abortWeather() {
        loadingWeather = false;
        if (geoXhr && geoXhr.readyState === XMLHttpRequest.LOADING) {
            geoXhr.abort();
            geoXhr = null;
        }
        if (weatherXhr && weatherXhr.readyState === XMLHttpRequest.LOADING) {
            weatherXhr.abort();
            weatherXhr = null;
        }
    }

    // ---------- 数据库封装 ----------
    function openDB() {
        try {
            return LocalStorage.openDatabaseSync("WeatherDB", "1.0", "City database", 1000000);
        } catch (e) {
            log("openDB error: " + e);
            return null;
        }
    }

    function executeSql(sql, params, callback) {
        var db = openDB();
        if (!db) {
            if (callback) callback(false);
            return;
        }
        try {
            db.transaction(function(tx) {
                var rs = tx.executeSql(sql, params);
                if (callback) callback(true, rs);
            });
        } catch (e) {
            log("executeSql error: " + e + " sql=" + sql);
            if (callback) callback(false);
        }
    }

    function initDB() {
        var db = openDB();
        if (!db) return;
        try {
            db.transaction(function(tx) {
                tx.executeSql('CREATE TABLE IF NOT EXISTS city_list (city_name TEXT PRIMARY KEY)');
                tx.executeSql('CREATE TABLE IF NOT EXISTS selected_city (id INTEGER PRIMARY KEY, city_name TEXT)');
                tx.executeSql('CREATE TABLE IF NOT EXISTS geo_cache (city_name TEXT PRIMARY KEY, lat TEXT, lon TEXT)');
                tx.executeSql('CREATE TABLE IF NOT EXISTS settings (key TEXT PRIMARY KEY, value TEXT)');
            });
        } catch (e) {
            log("initDB error: " + e);
        }
    }

    Component.onCompleted: {
        currentDateTime = Qt.formatDateTime(new Date(), "hh:mm");
        initDB();
        loadSettings();
        initAndFetch();
    }

    function initAndFetch() {
        var loaded = [];
        executeSql('SELECT city_name FROM city_list', [], function(ok, rs) {
            if (!ok) {
                fallbackDefault();
                return;
            }
            for (var i = 0; i < rs.rows.length; i++) {
                loaded.push(rs.rows.item(i).city_name);
            }
            if (loaded.length === 0) {
                log("City list empty, inserting 北京.");
                executeSql('INSERT OR IGNORE INTO city_list(city_name) VALUES(?)', ["北京"]);
                executeSql('INSERT OR IGNORE INTO geo_cache(city_name, lat, lon) VALUES(?,?,?)', ["北京", "39.9042", "116.4074"]);
                loaded = ["北京"];
            }
            cityList = loaded;

            var selCity = "";
            executeSql('SELECT city_name FROM selected_city WHERE id=1', [], function(ok2, rs2) {
                if (ok2 && rs2.rows.length > 0) selCity = rs2.rows.item(0).city_name;
                if (selCity === "" || cityList.indexOf(selCity) === -1) {
                    selCity = cityList[0];
                    executeSql('INSERT OR REPLACE INTO selected_city(id, city_name) VALUES(1, ?)', [selCity]);
                }
                currentCity = selCity;
                log("Current city: " + currentCity);
                fetchWeather(currentCity);
            });
        });
    }

    function fallbackDefault() {
        log("Falling back to default 北京.");
        cityList = ["北京"];
        currentCity = "北京";
        fetchWeather(currentCity);
    }

    // ---------- 经纬度获取 ----------
    function getGeo(city, callback) {
        log("Getting geo for " + city);
        executeSql('SELECT lat, lon FROM geo_cache WHERE city_name = ?', [city], function(ok, rs) {
            if (ok && rs.rows.length > 0) {
                var lat = rs.rows.item(0).lat;
                var lon = rs.rows.item(0).lon;
                log("Geo cache hit: " + lat + "," + lon);
                callback(lat, lon, "");
                return;
            }
            log("Geo cache miss, requesting wttr.in");
            if (geoXhr) geoXhr.abort();
            geoXhr = new XMLHttpRequest();
            geoXhr.open("GET", "https://wttr.in/" + encodeURIComponent(city) + "?format=j2", true);

            var finished = false;
            var timeoutMs = extendTimeout ? 30000 : 10000;
            var timer = Qt.createQmlObject("import QtQuick 2.15; Timer { interval: " + timeoutMs + "; running: true; repeat: false }", root);
            timer.triggered.connect(function() {
                if (finished) return;
                finished = true;
                if (geoXhr && geoXhr.readyState === XMLHttpRequest.LOADING) {
                    geoXhr.abort();
                    geoXhr = null;
                }
                timer.destroy();
                callback(null, null, "请求超时");
            });

            geoXhr.onreadystatechange = function() {
                if (geoXhr && geoXhr.readyState === XMLHttpRequest.DONE) {
                    if (finished) return;
                    finished = true;
                    timer.destroy();
                    var xhr = geoXhr;
                    geoXhr = null;
                    if (xhr.status === 200) {
                        try {
                            var j = JSON.parse(xhr.responseText);
                            var area = j.nearest_area[0];
                            var latFetched = area.latitude;
                            var lonFetched = area.longitude;
                            log("Fetched geo: " + latFetched + "," + lonFetched);
                            executeSql('INSERT OR REPLACE INTO geo_cache(city_name, lat, lon) VALUES(?,?,?)', [city, latFetched, lonFetched]);
                            callback(latFetched, lonFetched, "");
                        } catch (e) {
                            log("wttr.in parse error: " + e);
                            callback(null, null, "数据解析错误");
                        }
                    } else if (xhr.status === 0) {
                        log("Geo network error (status 0)");
                        callback(null, null, "网络连接异常");
                    } else {
                        log("Geo HTTP error: " + xhr.status);
                        callback(null, null, "网络错误 HTTP" + xhr.status);
                    }
                }
            };
            geoXhr.send();
        });
    }

    // ---------- 城市管理 ----------
    function addCity(name) {
        if (name === "" || cityList.indexOf(name) >= 0) return false;
        cityList.push(name);
        cityList = cityList;
        executeSql('INSERT OR IGNORE INTO city_list(city_name) VALUES(?)', [name]);
        log("City added: " + name);
        return true;
    }

    function removeCity(name) {
        if (cityList.length <= 1) return;
        var idx = cityList.indexOf(name);
        if (idx < 0) return;
        cityList.splice(idx, 1);
        cityList = cityList;
        if (name === currentCity) {
            currentCity = cityList[0];
            saveCurrentCity();
            fetchWeather(currentCity);
        }
        executeSql('DELETE FROM city_list WHERE city_name = ?', [name]);
        log("City removed: " + name);
    }

    function saveCurrentCity() {
        executeSql('INSERT OR REPLACE INTO selected_city(id, city_name) VALUES(1, ?)', [currentCity]);
    }

    // ---------- 温度格式化 ----------
    function formatTemp(value) {
        if (keepDecimal) return value.toFixed(1);
        else return Math.round(value).toString();
    }

    // ---------- 天气请求 ----------
    function fetchWeather(city) {
        abortWeather();
        var requestId = ++weatherRequestId;
        loadingWeather = true;
        weatherDesc = "";
        temp = "";
        feelsLike = "";
        humidity = "";
        wind = "";
        sunrise = "";
        sunset = "";
        errorMsg = "";
        errorDetail = "";
        hourlyForecast = [];
        dailyForecast = [];
        currentGeoLat = "";
        currentGeoLon = "";
        currentRequestCity = city;
        log("Fetching weather for " + city + " (id=" + requestId + ")");

        getGeo(city, function(lat, lon, geoError) {
            if (requestId !== weatherRequestId) return;
            if (geoError !== "") {
                loadingWeather = false;
                errorMsg = geoError;
                errorDetail = "经纬度获取失败";
                log("Geo error: " + geoError);
                return;
            }
            var url = "https://api.open-meteo.com/v1/forecast?latitude=" + lat + "&longitude=" + lon;
            url += "&current=temperature_2m,relative_humidity_2m,apparent_temperature,wind_speed_10m,weather_code";
            url += "&hourly=temperature_2m,relative_humidity_2m,weather_code";
            url += "&daily=sunrise,sunset,weather_code,temperature_2m_max,temperature_2m_min,temperature_2m_mean,apparent_temperature_mean,precipitation_sum,precipitation_hours,wind_speed_10m_max,cloudcover_mean,relative_humidity_2m_mean";
            url += "&past_days=1&forecast_days=7&timezone=auto";
            log("Open-Meteo request: " + url);

            if (weatherXhr) weatherXhr.abort();
            weatherXhr = new XMLHttpRequest();
            weatherXhr.open("GET", url, true);

            var finished = false;
            var timeoutMs = extendTimeout ? 30000 : 10000;
            var timer = Qt.createQmlObject("import QtQuick 2.15; Timer { interval: " + timeoutMs + "; running: true; repeat: false }", root);
            timer.triggered.connect(function() {
                if (finished) return;
                finished = true;
                if (weatherXhr && weatherXhr.readyState === XMLHttpRequest.LOADING) {
                    weatherXhr.abort();
                    weatherXhr = null;
                }
                timer.destroy();
                if (requestId !== weatherRequestId) return;
                loadingWeather = false;
                errorMsg = "请求超时";
                errorDetail = "天气获取失败";
                log("Weather timeout");
            });

            weatherXhr.onreadystatechange = function() {
                if (weatherXhr && weatherXhr.readyState === XMLHttpRequest.DONE) {
                    if (finished) return;
                    finished = true;
                    timer.destroy();
                    if (requestId !== weatherRequestId) return;
                    var xhr = weatherXhr;
                    weatherXhr = null;
                    loadingWeather = false;
                    if (xhr.status === 200) {
                        try {
                            var j = JSON.parse(xhr.responseText);
                            updateWeatherFromJSON(j);
                        } catch (e) {
                            errorMsg = "数据解析错误";
                            errorDetail = "天气获取失败";
                            log("Open-Meteo parse error: " + e);
                        }
                    } else if (xhr.status === 0) {
                        errorMsg = "网络连接异常";
                        errorDetail = "天气获取失败";
                        log("Weather network error (status 0)");
                    } else {
                        errorMsg = "网络错误 HTTP" + xhr.status;
                        errorDetail = "天气获取失败";
                        log("Open-Meteo HTTP error: " + xhr.status);
                    }
                }
            };
            weatherXhr.send();
        });
    }

    function weatherDescByCode(code) {
        var key = String(code);
        return wmoMap[key] || ("代码" + key);
    }

    function updateWeatherFromJSON(json) {
        var c = json.current;
        weatherDesc = weatherDescByCode(c.weather_code);
        temp = formatTemp(c.temperature_2m) + "°C";
        feelsLike = formatTemp(c.apparent_temperature);
        humidity = c.relative_humidity_2m + "%";
        wind = c.wind_speed_10m + "km/h";

        if (json.latitude !== undefined && json.longitude !== undefined) {
            currentGeoLat = parseFloat(json.latitude).toFixed(2);
            currentGeoLon = parseFloat(json.longitude).toFixed(2);
        }

        var now = new Date();
        var todayStr = Qt.formatDate(now, "yyyy-MM-dd");
        var todayDateStr = Qt.formatDate(now, "MM-dd");

        if (json.daily) {
            var todayIdx = 0;
            for (var j = 0; j < json.daily.time.length; j++) {
                if (json.daily.time[j] === todayStr) {
                    todayIdx = j;
                    break;
                }
            }
            if (json.daily.sunrise && json.daily.sunset) {
                sunrise = "日出 " + json.daily.sunrise[todayIdx].slice(11,16);
                sunset = "日落 " + json.daily.sunset[todayIdx].slice(11,16);
            }

            var dlist = [];
            for (var k = 0; k < json.daily.time.length; k++) {
                var dateT = new Date(json.daily.time[k]);
                var dateStr = Qt.formatDate(dateT, "MM-dd");
                var isToday = (dateStr === todayDateStr);
                var desc = weatherDescByCode(json.daily.weather_code[k]);
                var low = json.daily.temperature_2m_min[k];
                var high = json.daily.temperature_2m_max[k];
                var meanTemp = json.daily.temperature_2m_mean ? json.daily.temperature_2m_mean[k] : undefined;
                var meanApparent = json.daily.apparent_temperature_mean ? json.daily.apparent_temperature_mean[k] : undefined;
                var precip = json.daily.precipitation_sum[k];
                var precipHours = json.daily.precipitation_hours ? json.daily.precipitation_hours[k] : undefined;
                var maxWind = json.daily.wind_speed_10m_max ? json.daily.wind_speed_10m_max[k] : undefined;
                var cloudcover = json.daily.cloudcover_mean ? json.daily.cloudcover_mean[k] : undefined;
                var humidityMean = json.daily.relative_humidity_2m_mean ? json.daily.relative_humidity_2m_mean[k] : undefined;
                var daySunrise = (json.daily.sunrise && json.daily.sunrise[k]) ? ("日出 " + json.daily.sunrise[k].slice(11,16)) : "";
                var daySunset = (json.daily.sunset && json.daily.sunset[k]) ? ("日落 " + json.daily.sunset[k].slice(11,16)) : "";

                dlist.push({
                    date: dateStr,
                    desc: desc,
                    low: formatTemp(low),
                    high: formatTemp(high),
                    meanTemp: meanTemp !== undefined ? formatTemp(meanTemp) : undefined,
                    meanApparent: meanApparent !== undefined ? formatTemp(meanApparent) : undefined,
                    precip: precip,
                    precipHours: precipHours,
                    maxWind: maxWind !== undefined ? maxWind.toFixed(1) : undefined,
                    cloudcover: cloudcover,
                    humidity: humidityMean,
                    sunrise: daySunrise,
                    sunset: daySunset,
                    isToday: isToday
                });
            }
            dailyForecast = dlist;
        }

        if (json.hourly) {
            var todayStart = new Date(todayStr + "T00:00:00").getTime();
            var list = [];
            var currentHour = now.getHours();
            var currentHourIndex = -1;

            for (var i = 0; i < json.hourly.time.length; i++) {
                var t = new Date(json.hourly.time[i]);
                if (t.getTime() < todayStart) continue;

                var hour = t.getHours();
                var timeStr = "";
                if (hour === 0) {
                    timeStr = Qt.formatDate(t, "MM-dd");
                } else {
                    timeStr = String(hour).padStart(2, '0') + ":00";
                }
                var isNow = (Qt.formatDate(t, "yyyy-MM-dd") === todayStr && hour === currentHour);
                if (isNow) currentHourIndex = list.length;
                var desc = weatherDescByCode(json.hourly.weather_code[i]);
                list.push({
                    time: timeStr,
                    tempC: formatTemp(json.hourly.temperature_2m[i]),
                    humidity: json.hourly.relative_humidity_2m[i],
                    desc: desc,
                    isNow: isNow,
                    isDate: (hour === 0)
                });
            }
            hourlyForecast = list;

            if (currentHourIndex >= 0) {
                var targetIndex = currentHourIndex > 0 ? currentHourIndex - 1 : 0;
                Qt.callLater(function() {
                    hourListView.positionViewAtIndex(targetIndex, ListView.Beginning);
                    hourListView.contentX -= 7;
                });
            }
        }
    }

    // ---------- 界面 ----------
    Text {
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 6
        text: currentDateTime
        color: "#2C3E50"
        font.family: "Microsoft YaHei"
        font.pixelSize: 14
        opacity: 0.8
        z: 2
    }

    Rectangle {
        id: weatherArea
        anchors.left: parent.left
        anchors.right: sidebar.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        color: "transparent"

        Flickable {
            id: weatherFlickable
            anchors.fill: parent
            contentWidth: weatherColumn.width
            contentHeight: weatherColumn.height
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            flickableDirection: Flickable.VerticalFlick

            Column {
                id: weatherColumn
                width: weatherFlickable.width
                spacing: 8

                Column {
                    width: parent.width
                    spacing: 3
                    topPadding: 10

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: currentCity
                        color: "#2C3E50"
                        font.family: "Microsoft YaHei"
                        font.pixelSize: 22
                        font.bold: true
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: errorMsg ? errorMsg : ""
                        color: "#E74C3C"
                        font.family: "Microsoft YaHei"
                        font.pixelSize: 20
                        visible: errorMsg !== ""
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: errorDetail ? errorDetail : ""
                        color: "#E74C3C"
                        font.family: "Microsoft YaHei"
                        font.pixelSize: 20
                        visible: errorDetail !== ""
                    }

                    // 加载中或天气描述（单独一行）
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: loadingWeather ? "加载天气中..." : (errorMsg ? "" : weatherDesc)
                        color: "#2C3E50"
                        font.family: "Microsoft YaHei"
                        font.pixelSize: 20
                        visible: errorMsg === "" && !(loadingWeather && errorMsg !== "")
                    }

                    // 温度 + 湿度（单独一行）
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: loadingWeather ? "" : (errorMsg ? "" : "温度 " + temp + "  湿度 " + humidity)
                        color: "#2C3E50"
                        font.family: "Microsoft YaHei"
                        font.pixelSize: 20
                        visible: errorMsg === "" && !loadingWeather
                    }

                    // 体感/风速/日出日落/经纬度（合并显示）
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: loadingWeather ? "" : (errorMsg ? "" : [
                            "体感 " + feelsLike + "°C  风速 " + wind,
                            (sunrise && sunset) ? (sunrise + "  " + sunset) : "",
                            (currentGeoLat && currentGeoLon && showGeo) ? ("经度 " + currentGeoLon + "°E  纬度 " + currentGeoLat + "°N") : ""
                        ].filter(function(s) { return s !== "" }).join("\n"))
                        color: "#2C3E50"
                        font.family: "Microsoft YaHei"
                        font.pixelSize: 18
                        horizontalAlignment: Text.AlignHCenter
                        visible: errorMsg === "" && text !== ""
                    }
                }

                // 第一条分割线（逐小时或逐日存在时显示）
                Rectangle {
                    width: parent.width - 16
                    height: 1
                    anchors.horizontalCenter: parent.horizontalCenter
                    color: Qt.rgba(0,0,0,0.1)
                    visible: (hourlyForecast.length > 0 || dailyForecast.length > 0) && errorMsg === ""
                }

                // 逐小时预报（放在前面）
                Column {
                    width: parent.width
                    spacing: 4
                    visible: hourlyForecast.length > 0 && errorMsg === ""

                    Text {
                        text: currentCity + " 逐小时预报"
                        font.family: "Microsoft YaHei"
                        font.pixelSize: 14
                        font.bold: true
                        color: "#2C3E50"
                        anchors.left: parent.left
                        anchors.leftMargin: 12
                    }

                    ListView {
                        id: hourListView
                        width: parent.width
                        height: 90
                        orientation: ListView.Horizontal
                        clip: true
                        model: hourlyForecast
                        spacing: 8
                        leftMargin: 12
                        rightMargin: 12
                        boundsBehavior: Flickable.StopAtBounds

                        delegate: weatherCardComponent
                    }
                }

                // 第二条分割线（两者都存在时显示）
                Rectangle {
                    width: parent.width - 16
                    height: 1
                    anchors.horizontalCenter: parent.horizontalCenter
                    color: Qt.rgba(0,0,0,0.1)
                    visible: hourlyForecast.length > 0 && dailyForecast.length > 0 && errorMsg === ""
                }

                // 逐日预报
                Column {
                    width: parent.width
                    spacing: 4
                    visible: dailyForecast.length > 0 && errorMsg === ""

                    Text {
                        text: currentCity + " 逐日预报"
                        font.family: "Microsoft YaHei"
                        font.pixelSize: 14
                        font.bold: true
                        color: "#2C3E50"
                        anchors.left: parent.left
                        anchors.leftMargin: 12
                    }

                    ListView {
                        id: dayListView
                        width: parent.width
                        height: 90
                        orientation: ListView.Horizontal
                        clip: true
                        model: dailyForecast
                        spacing: 8
                        leftMargin: 12
                        rightMargin: 12
                        boundsBehavior: Flickable.StopAtBounds

                        delegate: Item {
                            width: 90; height: 88
                            Rectangle {
                                anchors.fill: parent; anchors.bottomMargin: 3; radius: 8
                                color: Qt.rgba(0,0,0,0.03); border.color: Qt.rgba(0,0,0,0.1); border.width: 1
                            }
                            Column {
                                anchors.centerIn: parent; spacing: 2
                                Text { text: modelData.date; font.family: "Microsoft YaHei"; font.pixelSize: 13; font.bold: true; color: modelData.isToday ? "#E74C3C" : "#2C3E50"; anchors.horizontalCenter: parent.horizontalCenter }
                                Text { text: modelData.low + "~" + modelData.high + "°C"; font.family: "Microsoft YaHei"; font.pixelSize: 14; color: "#000000"; anchors.horizontalCenter: parent.horizontalCenter }
                                Text { text: modelData.precip + "mm"; font.family: "Microsoft YaHei"; font.pixelSize: 13; color: "#1A5276"; anchors.horizontalCenter: parent.horizontalCenter }
                                Text { text: modelData.desc; font.family: "Microsoft YaHei"; font.pixelSize: 13; color: "#7F8C8D"; anchors.horizontalCenter: parent.horizontalCenter; horizontalAlignment: Text.AlignHCenter; width: 70 }
                            }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    log("Day card clicked: " + modelData.date + " (index=" + index + ")");
                                    daydetailLoader.dataIndex = index;
                                    daydetailLoader.active = false;
                                    daydetailLoader.active = true;
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    Component {
        id: weatherCardComponent
        Item {
            width: 90; height: 88
            Rectangle {
                anchors.fill: parent; anchors.bottomMargin: 3; radius: 8
                color: Qt.rgba(0,0,0,0.03); border.color: Qt.rgba(0,0,0,0.1); border.width: 1
            }
            Column {
                anchors.centerIn: parent; spacing: 2
                Text { text: modelData.time; font.family: "Microsoft YaHei"; font.pixelSize: 13; font.bold: true; color: modelData.isNow ? "#E74C3C" : (modelData.isDate ? "#FF8C00" : "#2C3E50"); anchors.horizontalCenter: parent.horizontalCenter }
                Text { text: modelData.tempC + "°C"; font.family: "Microsoft YaHei"; font.pixelSize: 14; color: "#000000"; anchors.horizontalCenter: parent.horizontalCenter }
                Text { text: modelData.humidity + "%"; font.family: "Microsoft YaHei"; font.pixelSize: 13; color: "#1A5276"; anchors.horizontalCenter: parent.horizontalCenter }
                Text { text: modelData.desc; font.family: "Microsoft YaHei"; font.pixelSize: 13; color: "#7F8C8D"; anchors.horizontalCenter: parent.horizontalCenter; horizontalAlignment: Text.AlignHCenter; width: 70 }
            }
        }
    }

    // 右侧按钮栏
    Rectangle {
        id: sidebar
        width: 52
        height: parent.height - 8
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        color: "transparent"

        Column {
            anchors.bottom: parent.bottom
            width: parent.width
            spacing: 4

            Item {
                width: parent.width; height: 30
                Rectangle {
                    width: 48; height: 28; anchors.centerIn: parent
                    color: mouseSettings.pressed ? "#357ABD" : "#4A90E2"; radius: 4; border.color: "#2C6B9E"
                    Text { text: "设置"; color: "white"; font.family: "Microsoft YaHei"; font.pixelSize: 14; anchors.centerIn: parent }
                    MouseArea { id: mouseSettings; anchors.fill: parent; onClicked: settingsLoader.active = true }
                }
            }
            Item {
                width: parent.width; height: 30
                Rectangle {
                    width: 48; height: 28; anchors.centerIn: parent
                    color: mouseRefresh.pressed ? "#357ABD" : "#4A90E2"; radius: 4; border.color: "#2C6B9E"
                    Text { text: "刷新"; color: "white"; font.family: "Microsoft YaHei"; font.pixelSize: 14; anchors.centerIn: parent }
                    MouseArea {
                        id: mouseRefresh
                        anchors.fill: parent
                        onClicked: {
                            abortWeather();
                            fetchWeather(currentCity);
                        }
                    }
                }
            }
            Item {
                width: parent.width; height: 30
                Rectangle {
                    width: 48; height: 28; anchors.centerIn: parent
                    color: mouseLocations.pressed ? "#357ABD" : "#4A90E2"; radius: 4; border.color: "#2C6B9E"
                    Text { text: "地点"; color: "white"; font.family: "Microsoft YaHei"; font.pixelSize: 14; anchors.centerIn: parent }
                    MouseArea { id: mouseLocations; anchors.fill: parent; onClicked: locationLoader.active = true }
                }
            }
            Item {
                width: parent.width; height: 30
                Rectangle {
                    width: 48; height: 28; anchors.centerIn: parent
                    color: mouseExit.pressed ? "#357ABD" : "#4A90E2"; radius: 4; border.color: "#2C6B9E"
                    Text { text: "退出"; color: "white"; font.family: "Microsoft YaHei"; font.pixelSize: 14; anchors.centerIn: parent }
                    MouseArea { id: mouseExit; anchors.fill: parent; onClicked: root.backButtonClicked() }
                }
            }
        }
    }

    // 设置页面
    Loader {
        id: settingsLoader
        anchors.fill: parent
        z: 100
        active: false
        source: "settings.qml"
        onLoaded: {
            item.mainApp = root;
            item.back.connect(function() { settingsLoader.active = false; });
        }
    }

    // 地点页面
    Loader {
        id: locationLoader
        anchors.fill: parent
        z: 100
        active: false
        source: "locations.qml"
        onLoaded: {
            item.mainApp = root;
            item.cityListModel = Qt.binding(function() { return root.cityList; });
            item.currentCity = Qt.binding(function() { return root.currentCity; });
            item.back.connect(function() { locationLoader.active = false; });
        }
    }

    // 日详情页面
    Loader {
        id: daydetailLoader
        anchors.fill: parent
        z: 100
        active: false
        source: "daydetail.qml"
        property int dataIndex: -1
        onLoaded: {
            item.mainApp = root;
            if (dataIndex >= 0 && dataIndex < dailyForecast.length) {
                item.dayData = dailyForecast[dataIndex];
            }
            item.back.connect(function() { daydetailLoader.active = false; });
        }
    }
}