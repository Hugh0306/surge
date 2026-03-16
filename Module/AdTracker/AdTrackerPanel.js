/*
 * AdTracker 面板
 * - 默认显示抓包摘要
 * - 运行 Export 后显示完整导出报告（可长按复制）
 * - 运行 Clear 后自动清除导出缓存
 */

var STORE_KEY = "ad_tracker_log";
var EXPORT_KEY = "ad_tracker_export";

// 检查是否有导出结果需要展示
var exported = $persistentStore.read(EXPORT_KEY) || "";

if (exported.length > 10) {
  // 有导出结果，展示完整报告（长按面板可复制）
  // 展示后清除导出缓存，下次刷新回到正常摘要
  $persistentStore.write("", EXPORT_KEY);
  $done({
    title: "AdTracker 导出报告 (长按复制)",
    content: exported,
    icon: "doc.on.clipboard",
    "icon-color": "#34C759"
  });
} else {
  // 正常摘要模式
  var log = [];
  try {
    log = JSON.parse($persistentStore.read(STORE_KEY) || "[]");
  } catch (e) {
    log = [];
  }

  if (log.length === 0) {
    $done({
      title: "广告抓包记录",
      content: "暂无记录\n开启模块后正常使用 App 即可自动记录",
      icon: "magnifyingglass",
      "icon-color": "#5AC8FA"
    });
  } else {
    var total = log.length;
    var dm = {};
    var i, item, domain, m;

    for (i = 0; i < log.length; i++) {
      item = log[i];
      domain = "unknown";
      try {
        m = item.url.match(/^https?:\/\/([^\/]+)/i);
        if (m) domain = m[1];
      } catch (e) {}
      if (!dm[domain]) dm[domain] = { c: 0, t: {} };
      dm[domain].c++;
      if (item.tags) {
        for (var t = 0; t < item.tags.length; t++) {
          dm[domain].t[item.tags[t]] = 1;
        }
      }
    }

    var arr = [];
    for (var d in dm) {
      if (dm.hasOwnProperty(d)) arr.push({ d: d, c: dm[d].c, t: dm[d].t });
    }
    arr.sort(function (a, b) { return b.c - a.c; });

    var content = "共 " + total + " 条 | " + arr.length + " 个域名\n";
    content += "──────────────\n";

    var top = arr.length > 8 ? 8 : arr.length;
    for (i = 0; i < top; i++) {
      var tags = Object.keys(arr[i].t).slice(0, 2).join(",");
      content += arr[i].d + "\n  x" + arr[i].c + " [" + tags + "]\n";
    }

    content += "──────────────\n";

    var recent = log.slice(-3).reverse();
    for (i = 0; i < recent.length; i++) {
      var r = recent[i];
      var rd = "unknown";
      try {
        var rm = r.url.match(/^https?:\/\/([^\/]+)/i);
        if (rm) rd = rm[1];
      } catch (e) {}
      var rp = "";
      try { rp = r.url.replace(/^https?:\/\/[^\/]+/, "").substring(0, 25); } catch (e) {}
      content += (r.time || "") + " " + rd + rp + "\n";
    }

    content += "──────────────\n";
    content += "Export→导出报告  Clear→清空";

    $done({
      title: "广告抓包 (" + total + "条/" + arr.length + "域名)",
      content: content,
      icon: "eye.fill",
      "icon-color": "#FF9500"
    });
  }
}
