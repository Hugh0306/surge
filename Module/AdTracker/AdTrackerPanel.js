/**
 * 广告抓包记录 - 面板展示脚本
 *
 * 功能：
 *  - 展示最近捕获的疑似广告请求
 *  - 按 App (User-Agent) 分组统计
 *  - 提供快速生成 reject 规则的参考
 */

const STORE_KEY = "ad_tracker_log";

let log = [];
try {
  log = JSON.parse($persistentStore.read(STORE_KEY) || "[]");
} catch(e) {
  log = [];
}

if (log.length === 0) {
  $done({
    title: "广告抓包记录",
    content: "暂无记录\n\n开启模块后正常使用 App，疑似广告请求会被自动记录。",
    icon: "magnifyingglass",
    "icon-color": "#5AC8FA"
  });
} else {
  // 统计信息
  const total = log.length;

  // 按域名聚合
  const domainMap = {};
  for (const item of log) {
    let domain = "";
    try {
      domain = item.url.match(/^https?:\/\/([^\/]+)/i)?.[1] || "unknown";
    } catch(e) {
      domain = "unknown";
    }
    if (!domainMap[domain]) {
      domainMap[domain] = { count: 0, tags: new Set(), urls: [] };
    }
    domainMap[domain].count++;
    item.tags.forEach(t => domainMap[domain].tags.add(t));
    if (domainMap[domain].urls.length < 3) {
      domainMap[domain].urls.push(item.url);
    }
  }

  // 按命中次数排序，取 Top 8
  const sorted = Object.entries(domainMap)
    .sort((a, b) => b[1].count - a[1].count)
    .slice(0, 8);

  // 最近 5 条记录
  const recent = log.slice(-5).reverse();

  // 构建展示内容
  let content = `📊 共记录 ${total} 条疑似广告请求\n`;
  content += `━━━━━━━━━━━━━━━━\n`;
  content += `🔝 高频域名 Top ${sorted.length}:\n`;

  for (const [domain, info] of sorted) {
    const tagsStr = [...info.tags].slice(0, 2).join(",");
    content += `  ${domain}\n    ×${info.count} [${tagsStr}]\n`;
  }

  content += `━━━━━━━━━━━━━━━━\n`;
  content += `🕐 最近捕获:\n`;

  for (const item of recent) {
    const domain = item.url.match(/^https?:\/\/([^\/]+)/)?.[1] || "";
    const path = item.url.replace(/^https?:\/\/[^\/]+/, "").substring(0, 40);
    content += `  ${item.time}\n  ${domain}${path}…\n  [${item.tags.join(",")}]\n\n`;
  }

  content += `━━━━━━━━━━━━━━━━\n`;
  content += `💡 使用 "导出规则" 脚本生成拦截规则\n`;
  content += `🗑️ 长按面板可清空记录`;

  $done({
    title: `广告抓包记录 (${total}条)`,
    content: content,
    icon: "eye.fill",
    "icon-color": "#FF9500"
  });
}
