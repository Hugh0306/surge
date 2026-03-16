/**
 * 广告抓包记录 - 导出详情 + 规则建议
 *
 * 使用方法：Surge → 脚本列表 → 手动运行 AdTrackerExport
 * 输出：通过多条通知分段发送，可从通知中心长按复制
 */

(function () {
  const STORE_KEY = "ad_tracker_log";

  let log = [];
  try {
    log = JSON.parse($persistentStore.read(STORE_KEY) || "[]");
  } catch (e) {
    $notification.post("导出失败", "", "数据解析错误: " + e.message);
    return $done({});
  }

  if (log.length === 0) {
    $notification.post("广告抓包导出", "暂无记录", "请先使用 AdTracker 模块抓包");
    return $done({});
  }

  // 按域名聚合
  const domainMap = {};
  for (const item of log) {
    let domain = "";
    try {
      domain = item.url.match(/^https?:\/\/([^\/]+)/i)?.[1] || "unknown";
    } catch (e) { continue; }

    if (!domainMap[domain]) {
      domainMap[domain] = { count: 0, tags: new Set(), paths: new Set() };
    }
    domainMap[domain].count++;
    item.tags.forEach(t => domainMap[domain].tags.add(t));
    try {
      const path = item.url.replace(/^https?:\/\/[^\/]+/, "").split("?")[0];
      if (path) domainMap[domain].paths.add(path);
    } catch (e) {}
  }

  const sorted = Object.entries(domainMap).sort((a, b) => b[1].count - a[1].count);

  // ===== 通知: 域名 + 路径详情（可复制） =====
  let detail = `${log.length}条记录 / ${sorted.length}个域名\n\n`;
  for (const [domain, info] of sorted) {
    detail += `${domain} x${info.count} [${[...info.tags].join(",")}]\n`;
    for (const p of [...info.paths].slice(0, 5)) {
      detail += `  ${p}\n`;
    }
    detail += "\n";
  }

  // 分段发送通知
  const chunks = splitText(detail, 800);
  chunks.forEach((chunk, i) => {
    $notification.post(
      `抓包详情 (${i + 1}/${chunks.length})`,
      `长按通知可复制`,
      chunk
    );
  });

  // ===== 生成 Surge 规则建议 =====
  let rules = "# 规则建议\n";
  let mitmHosts = [];

  for (const [domain, info] of sorted) {
    const paths = [...info.paths];

    if (/^ads?\./i.test(domain) || /adservice|admob|pangolin|pglstatp/i.test(domain)) {
      rules += `DOMAIN,${domain},REJECT\n`;
      continue;
    }

    if (paths.length > 0 && paths.length <= 3) {
      for (const path of paths) {
        const ed = domain.replace(/\./g, "\\.");
        const ep = path.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
        rules += `^https?:\\/\\/${ed}${ep} - reject\n`;
      }
    } else if (paths.length > 3) {
      const prefix = findCommonPrefix(paths);
      if (prefix.length > 1) {
        const ed = domain.replace(/\./g, "\\.");
        const ep = prefix.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
        rules += `^https?:\\/\\/${ed}${ep} - reject\n`;
      } else {
        rules += `# ${domain} x${info.count} (需人工确认)\n`;
      }
    }
    mitmHosts.push(domain);
  }

  if (mitmHosts.length > 0) {
    rules += `\nhostname = %APPEND% ${mitmHosts.slice(0, 20).join(", ")}\n`;
  }

  const ruleChunks = splitText(rules, 800);
  ruleChunks.forEach((chunk, i) => {
    $notification.post(
      `规则建议 (${i + 1}/${ruleChunks.length})`,
      "仅供参考",
      chunk
    );
  });

  // 写入持久化存储
  $persistentStore.write(detail + "\n---RULES---\n" + rules, "ad_tracker_export");

  return $done({});

  function splitText(text, maxLen) {
    const chunks = [];
    for (let i = 0; i < text.length; i += maxLen) {
      chunks.push(text.substring(i, i + maxLen));
    }
    return chunks.length > 0 ? chunks : [""];
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
})();
