/*
 * AdTracker 导出 - 手动运行
 * 通知发送抓包记录，长按通知可复制
 */

var STORE_KEY = "ad_tracker_log";
var raw = $persistentStore.read(STORE_KEY);
var log = [];

try {
  log = JSON.parse(raw || "[]");
} catch (e) {
  log = [];
}

if (log.length === 0) {
  $notification.post("AdTracker", "暂无记录", "请先抓包");
  $done("暂无记录，请先使用 AdTracker 模块抓包");
} else {
  // 按域名聚合（不用 Set，用普通对象）
  var dm = {};
  for (var i = 0; i < log.length; i++) {
    var item = log[i];
    var domain = "unknown";
    try {
      var m = item.url.match(/^https?:\/\/([^\/]+)/i);
      if (m) domain = m[1];
    } catch (e) {}

    if (!dm[domain]) {
      dm[domain] = { count: 0, tags: {}, paths: {} };
    }
    dm[domain].count++;

    // tags 去重
    if (item.tags) {
      for (var t = 0; t < item.tags.length; t++) {
        dm[domain].tags[item.tags[t]] = 1;
      }
    }

    // paths 去重，最多5个
    try {
      var path = item.url.replace(/^https?:\/\/[^\/]+/, "").split("?")[0];
      if (path && Object.keys(dm[domain].paths).length < 5) {
        dm[domain].paths[path] = 1;
      }
    } catch (e) {}
  }

  // 排序
  var entries = [];
  for (var d in dm) {
    entries.push([d, dm[d]]);
  }
  entries.sort(function (a, b) { return b[1].count - a[1].count; });

  // 构建文本
  var text = log.length + "条 / " + entries.length + "域名\n\n";
  for (var j = 0; j < entries.length; j++) {
    var dn = entries[j][0];
    var info = entries[j][1];
    var tags = Object.keys(info.tags).join(",");
    var paths = Object.keys(info.paths);
    text += dn + " x" + info.count + " [" + tags + "]\n";
    for (var k = 0; k < paths.length; k++) {
      text += "  " + paths[k] + "\n";
    }
    text += "\n";
  }

  // 分段发通知（每段800字）
  var partNum = 1;
  for (var pos = 0; pos < text.length; pos += 800) {
    var chunk = text.substring(pos, pos + 800);
    $notification.post(
      "抓包导出(" + partNum + ")",
      "长按可复制",
      chunk
    );
    partNum++;
  }

  $persistentStore.write(text, "ad_tracker_export");
  // 截取前2000字符显示在脚本结果界面
  var preview = text.length > 2000 ? text.substring(0, 2000) + "\n...(已截断)" : text;
  $done(preview);
}
