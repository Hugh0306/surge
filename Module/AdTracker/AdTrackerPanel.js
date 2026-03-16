/**
 * 广告抓包记录 - 面板展示脚本
 *
 * 功能：
 *  - 展示最近捕获的疑似广告请求摘要
 *  - 按域名分组统计
 *  - 通过 $input.select 提供操作菜单：导出详情 / 清空记录
 *  - 导出时通过通知发送完整记录（可从通知中心长按复制）
 */

const STORE_KEY = "ad_tracker_log";
const ACTION_KEY = "ad_tracker_action";

// 检查是否有待执行的操作（从上次面板交互传入）
const pendingAction = $persistentStore.read(ACTION_KEY);
if (pendingAction) {
  $persistentStore.write("", ACTION_KEY);

  if (pendingAction === "export") {
    doExport();
  } else if (pendingAction === "clear") {
    doClear();
  }
}

let log = [];
try {
  log = JSON.parse($persistentStore.read(STORE_KEY) || "[]");
} catch (e) {
  log = [];
}

if (log.length === 0) {
  $done({
    title: "广告抓包记录",
    content: "暂无记录\n\n开启模块后正常使用 App，疑似广告请求会被自动记录。\n\n提示：Surge → 脚本 → 手动运行 AdTrackerClear 可清空",
    icon: "magnifyingglass",
    "icon-color": "#5AC8FA"
  });
} else {
  const total = log.length;

  // 按域名聚合
  const domainMap = {};
  for (const item of log) {
    let domain = "";
    try {
      domain = item.url.match(/^https?:\/\/([^\/]+)/i)?.[1] || "unknown";
    } catch (e) {
      domain = "unknown";
    }
    if (!domainMap[domain]) {
      domainMap[domain] = { count: 0, tags: new Set(), paths: new Set() };
    }
    domainMap[domain].count++;
    item.tags.forEach(t => domainMap[domain].tags.add(t));
    try {
      const path = item.url.replace(/^https?:\/\/[^\/]+/, "").split("?")[0];
      if (path && domainMap[domain].paths.size < 3) domainMap[domain].paths.add(path);
    } catch (e) {}
  }

  // 按命中次数排序，取 Top 8
  const sorted = Object.entries(domainMap)
    .sort((a, b) => b[1].count - a[1].count)
    .slice(0, 8);

  // 最近 5 条
  const recent = log.slice(-5).reverse();

  let content = `共 ${total} 条 | 涉及 ${Object.keys(domainMap).length} 个域名\n`;
  content += `──────────────\n`;

  for (const [domain, info] of sorted) {
    const tagsStr = [...info.tags].slice(0, 2).join(",");
    content += `${domain}\n  x${info.count} [${tagsStr}]\n`;
  }

  content += `──────────────\n`;
  content += `最近:\n`;

  for (const item of recent) {
    const domain = (item.url.match(/^https?:\/\/([^\/]+)/)?.[1] || "").substring(0, 35);
    const path = item.url.replace(/^https?:\/\/[^\/]+/, "").substring(0, 30);
    content += `${item.time} ${domain}${path}\n`;
  }

  content += `──────────────\n`;
  content += `操作: 脚本列表中运行\n`;
  content += `  AdTrackerExport → 导出到通知(可复制)\n`;
  content += `  AdTrackerClear → 清空所有记录`;

  $done({
    title: `广告抓包 (${total}条/${Object.keys(domainMap).length}域名)`,
    content: content,
    icon: "eye.fill",
    "icon-color": "#FF9500"
  });
}

// ========== 导出功能 ==========
function doExport() {
  let exportLog = [];
  try {
    exportLog = JSON.parse($persistentStore.read(STORE_KEY) || "[]");
  } catch (e) {
    $notification.post("导出失败", "", "无法读取记录");
    return;
  }

  if (exportLog.length === 0) {
    $notification.post("广告抓包", "暂无记录", "");
    return;
  }

  // 按域名聚合，生成可复制的文本
  const dm = {};
  for (const item of exportLog) {
    let d = "";
    try { d = item.url.match(/^https?:\/\/([^\/]+)/i)?.[1] || ""; } catch (e) {}
    if (!dm[d]) dm[d] = { count: 0, tags: new Set(), paths: new Set() };
    dm[d].count++;
    item.tags.forEach(t => dm[d].tags.add(t));
    try {
      const p = item.url.replace(/^https?:\/\/[^\/]+/, "").split("?")[0];
      if (p && dm[d].paths.size < 5) dm[d].paths.add(p);
    } catch (e) {}
  }

  const sorted = Object.entries(dm).sort((a, b) => b[1].count - a[1].count);
  let text = `广告抓包记录导出 (${exportLog.length}条)\n\n`;

  for (const [domain, info] of sorted) {
    text += `${domain} x${info.count} [${[...info.tags].join(",")}]\n`;
    for (const p of info.paths) {
      text += `  ${p}\n`;
    }
    text += `\n`;
  }

  // 通知内容有长度限制，分段发送
  const maxLen = 800;
  if (text.length <= maxLen) {
    $notification.post("广告抓包导出", `${sorted.length}个域名`, text);
  } else {
    // 分段
    let part = 1;
    for (let i = 0; i < text.length; i += maxLen) {
      const chunk = text.substring(i, i + maxLen);
      $notification.post(`广告抓包导出 (${part})`, "", chunk);
      part++;
    }
  }
}

// ========== 清空功能 ==========
function doClear() {
  $persistentStore.write("[]", STORE_KEY);
  $notification.post("广告抓包记录", "已清空", "所有记录已删除，刷新面板查看");
}
