/*
 * AdTracker 导出
 * 结果写入持久化存储，通过通知提示完成
 * 然后刷新面板即可看到完整导出内容
 */

var raw = "";
var result = "";

try {
  raw = $persistentStore.read("ad_tracker_log") || "[]";
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

    result = "AdTracker 抓包报告\n";
    result += "共 " + log.length + " 条 / " + filtered.length + " 个域名\n";
    result += "────────────────────\n\n";

    for (i = 0; i < filtered.length; i++) {
      var e = filtered[i];
      var tags = Object.keys(e.t).join(", ");
      var paths = Object.keys(e.p);

      result += (i + 1) + ". " + e.d + "\n";
      result += "   命中: " + e.c + " 次";
      if (e.last) result += "  最近: " + e.last;
      result += "\n";
      result += "   标签: " + tags + "\n";
      if (paths.length > 0) {
        result += "   路径:\n";
        for (var k = 0; k < paths.length; k++) {
          result += "     " + paths[k] + "\n";
        }
      }
      result += "\n";
    }

    result += "────────────────────\n";
    result += "Surge 规则建议\n\n";

    for (i = 0; i < filtered.length; i++) {
      var f = filtered[i];
      if (/^ads?\./i.test(f.d) || /adservice|admob|pangolin|pglstatp/i.test(f.d)) {
        result += "DOMAIN," + f.d + ",REJECT\n";
      }
    }
  }
} catch (err) {
  result = "脚本错误: " + err.message;
}

// 写入持久化存储，面板脚本会读取并展示
$persistentStore.write(result, "ad_tracker_export");
$notification.post("AdTracker 导出完成", "共导出 " + result.split("\n").length + " 行", "请刷新面板查看完整内容，面板内容可长按复制");
$done();
