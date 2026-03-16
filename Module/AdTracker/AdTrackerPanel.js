/*
 * AdTracker 面板 - 直接显示完整抓包报告
 */

var log = [];
try {
  log = JSON.parse($persistentStore.read("ad_tracker_log") || "[]");
} catch (e) {
  log = [];
}

if (log.length === 0) {
  $done({
    title: "广告抓包记录",
    content: "暂无记录，开启模块后正常使用 App 即可自动记录",
    icon: "magnifyingglass",
    "icon-color": "#5AC8FA"
  });
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

    if (!dm[domain]) dm[domain] = { c: 0, t: {}, p: {}, last: "", d: domain };
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

    if (item.time) dm[domain].last = item.time;
  }

  var arr = [];
  for (var d in dm) {
    if (dm.hasOwnProperty(d)) arr.push(dm[d]);
  }
  arr.sort(function (a, b) { return b.c - a.c; });

  // 过滤误报
  var filtered = [];
  for (i = 0; i < arr.length; i++) {
    if (arr[i].d === "raw.githubusercontent.com") continue;
    filtered.push(arr[i]);
  }

  var content = "";
  for (i = 0; i < filtered.length; i++) {
    var e = filtered[i];
    var tags = Object.keys(e.t).join(", ");
    var paths = Object.keys(e.p);

    content += (i + 1) + ". " + e.d + "  x" + e.c + "\n";
    content += "   [" + tags + "]";
    if (e.last) content += " " + e.last;
    content += "\n";
    for (var k = 0; k < paths.length; k++) {
      content += "   " + paths[k] + "\n";
    }
    content += "\n";
  }

  content += "────────────────\n";
  content += "Clear→清空记录";

  $done({
    title: "抓包 " + log.length + "条/" + filtered.length + "域名",
    content: content,
    icon: "eye.fill",
    "icon-color": "#FF9500"
  });
}
