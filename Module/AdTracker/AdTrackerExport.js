/**
 * 广告抓包记录 - 导出规则生成器
 *
 * 使用方法：在 Surge 中通过「脚本」手动运行此脚本
 * 功能：读取已记录的广告请求，按域名聚合后生成 Surge 拦截规则建议
 *
 * 配置方式：Surge → 脚本 → 创建脚本 → 类型选 cron / 手动运行
 * 或在模块中添加 cron 定时触发
 */

const STORE_KEY = "ad_tracker_log";

let log = [];
try {
  log = JSON.parse($persistentStore.read(STORE_KEY) || "[]");
} catch(e) {
  $notification.post("导出失败", "", "无法读取记录数据: " + e.message);
  $done();
}

if (log.length === 0) {
  $notification.post("广告规则导出", "暂无记录", "请先使用 AdTracker 模块抓包");
  $done();
}

// 按域名聚合
const domainMap = {};
for (const item of log) {
  let domain = "";
  try {
    domain = item.url.match(/^https?:\/\/([^\/]+)/i)?.[1] || "unknown";
  } catch(e) { continue; }

  if (!domainMap[domain]) {
    domainMap[domain] = { count: 0, tags: new Set(), paths: new Set(), fulls: [] };
  }
  domainMap[domain].count++;
  item.tags.forEach(t => domainMap[domain].tags.add(t));

  // 提取路径部分
  try {
    const path = item.url.replace(/^https?:\/\/[^\/]+/, "").split("?")[0];
    if (path) domainMap[domain].paths.add(path);
  } catch(e) {}

  if (domainMap[domain].fulls.length < 5) {
    domainMap[domain].fulls.push(item.full || item.url);
  }
}

// 按命中次数排序
const sorted = Object.entries(domainMap)
  .sort((a, b) => b[1].count - a[1].count);

// ============ 生成规则 ============

let urlRewriteRules = [];
let domainRules = [];
let mitmHosts = new Set();

for (const [domain, info] of sorted) {
  const tagsStr = [...info.tags].join(", ");
  const paths = [...info.paths];

  // 策略1：如果域名本身就是广告域名（ad. 开头或含广告平台标识），直接拦截域名
  if (/^ads?\./i.test(domain) || /adservice|admob|pangolin|pglstatp/i.test(domain)) {
    domainRules.push(`# ${domain} (×${info.count}) [${tagsStr}]`);
    domainRules.push(`DOMAIN,${domain},REJECT`);
    continue;
  }

  // 策略2：如果路径有明显广告特征，生成 URL Rewrite 规则
  if (paths.length > 0) {
    // 如果路径种类少(≤3)，为每个路径生成精确规则
    if (paths.length <= 3) {
      for (const path of paths) {
        // 转义正则特殊字符
        const escapedPath = path.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
        const escapedDomain = domain.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
        urlRewriteRules.push(`# [${tagsStr}] ×${info.count}`);
        urlRewriteRules.push(`^https?:\\/\\/${escapedDomain}${escapedPath} - reject`);
      }
    } else {
      // 路径种类多，找共同前缀
      const commonPrefix = findCommonPrefix(paths);
      if (commonPrefix.length > 1) {
        const escapedDomain = domain.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
        const escapedPrefix = commonPrefix.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
        urlRewriteRules.push(`# [${tagsStr}] ×${info.count} (${paths.length}种路径)`);
        urlRewriteRules.push(`^https?:\\/\\/${escapedDomain}${escapedPrefix} - reject`);
      } else {
        // 无共同前缀，列出样本供人工判断
        urlRewriteRules.push(`# ⚠️ 需人工确认: ${domain} (×${info.count}) [${tagsStr}]`);
        urlRewriteRules.push(`# 样本路径:`);
        for (const p of paths.slice(0, 3)) {
          urlRewriteRules.push(`#   ${p}`);
        }
      }
    }

    mitmHosts.add(domain);
  }
}

function findCommonPrefix(paths) {
  if (paths.length === 0) return "";
  let prefix = paths[0];
  for (let i = 1; i < paths.length; i++) {
    while (paths[i].indexOf(prefix) !== 0) {
      prefix = prefix.substring(0, prefix.length - 1);
      if (prefix === "") return "";
    }
  }
  return prefix;
}

// ============ 输出 ============

let output = "# ===== 自动生成的 Surge 拦截规则建议 =====\n";
output += `# 生成时间: ${new Date().toLocaleString("zh-CN")}\n`;
output += `# 基于 ${log.length} 条抓包记录\n`;
output += `# ⚠️ 请人工审核后再使用，避免误拦正常请求\n\n`;

if (domainRules.length > 0) {
  output += "[Rule]\n";
  output += domainRules.join("\n") + "\n\n";
}

if (urlRewriteRules.length > 0) {
  output += "[URL Rewrite]\n";
  output += urlRewriteRules.join("\n") + "\n\n";
}

if (mitmHosts.size > 0) {
  output += "[MITM]\n";
  output += "hostname = %APPEND% " + [...mitmHosts].join(", ") + "\n";
}

// 通知输出（截断以适应通知长度）
const notifBody = output.length > 800 ? output.substring(0, 800) + "\n...(已截断)" : output;
$notification.post(
  "广告规则导出完成",
  `共分析 ${sorted.length} 个域名，生成 ${domainRules.filter(r => !r.startsWith("#")).length + urlRewriteRules.filter(r => !r.startsWith("#")).length} 条规则`,
  notifBody
);

// 同时写入持久化存储，方便外部读取
$persistentStore.write(output, "ad_tracker_rules");

$done();
