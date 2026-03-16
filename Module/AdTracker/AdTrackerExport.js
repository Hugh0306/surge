/*
 * AdTracker 导出
 * 运行后结果直接显示在脚本界面
 */

var result = "";

try {
  var raw = $persistentStore.read("ad_tracker_log") || "[]";
  var log = JSON.parse(raw);

  if (!log || log.length === 0) {
    result = "暂无抓包记录";
  } else {
    var dm = {};
    var i, item, domain, m, path, t;

    for (i = 0; i < log.length; i++) {
      item = log[i];
      domain = "unknown";
      try {
        m = item.url.match(/^https?:\/\/([^\/]+)/i);
        if (m) domain = m[1];
      } catch (e) {}

      if (!dm[domain]) dm[domain] = { c: 0, t: {}, p: {} };
      dm[domain].c++;

      if (item.tags) {
        for (t = 0; t < item.tags.length; t++) {
          dm[domain].t[item.tags[t]] = 1;
        }
      }

      try {
        path = item.url.replace(/^https?:\/\/[^\/]+/, "").split("?")[0];
        if (path && Object.keys(dm[domain].p).length < 5) {
          dm[domain].p[path] = 1;
        }
      } catch (e) {}
    }

    var arr = [];
    for (var d in dm) {
      if (dm.hasOwnProperty(d)) arr.push({ d: d, c: dm[d].c, t: dm[d].t, p: dm[d].p });
    }
    arr.sort(function (a, b) { return b.c - a.c; });

    result = log.length + " 条记录 / " + arr.length + " 个域名\n";
    result += "========================\n\n";

    for (i = 0; i < arr.length; i++) {
      var e = arr[i];
      var tags = Object.keys(e.t).join(", ");
      var paths = Object.keys(e.p);
      result += e.d + "  x" + e.c + "\n";
      result += "  [" + tags + "]\n";
      for (var k = 0; k < paths.length; k++) {
        result += "  " + paths[k] + "\n";
      }
      result += "\n";
    }
  }
} catch (err) {
  result = "脚本错误: " + err.message + "\nraw长度: " + (raw ? raw.length : "null");
}

$done({ response: { status: 200, body: result } });
