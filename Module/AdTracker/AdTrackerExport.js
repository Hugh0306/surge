/*
 * AdTracker 导出
 * 长按脚本运行，点击通知 → 自动复制到剪贴板
 */

var raw = $persistentStore.read("ad_tracker_log") || "[]";
var log = [];

try {
  log = JSON.parse(raw);
} catch (e) {
  $notification.post("AdTracker", "数据解析错误", e.message);
  $done();
}

if (!log || log.length === 0) {
  $notification.post("AdTracker", "暂无记录", "请先开启抓包模块");
  $done();
}

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

var filtered = [];
for (i = 0; i < arr.length; i++) {
  if (arr[i].d === "raw.githubusercontent.com") continue;
  filtered.push(arr[i]);
}

var result = "AdTracker " + log.length + "条/" + filtered.length + "域名\n\n";

for (i = 0; i < filtered.length; i++) {
  var e = filtered[i];
  var tags = Object.keys(e.t).join(", ");
  var paths = Object.keys(e.p);

  result += (i + 1) + ". " + e.d + " x" + e.c + "\n";
  result += "   [" + tags + "]";
  if (e.last) result += " " + e.last;
  result += "\n";
  for (var k = 0; k < paths.length; k++) {
    result += "   " + paths[k] + "\n";
  }
  result += "\n";
}

// 点击通知 → 自动复制完整报告到剪贴板
$notification.post(
  "AdTracker 导出完成",
  filtered.length + "个域名 → 点击通知复制到剪贴板",
  result.length > 800 ? result.substring(0, 800) + "..." : result,
  { action: "clipboard", text: result }
);

$done();
