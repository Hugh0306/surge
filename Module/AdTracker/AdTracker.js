/**
 * 广告请求抓包记录器
 *
 * 功能：拦截所有 HTTP(S) 请求，通过关键词 + 路径特征识别疑似广告请求并记录
 * 存储：使用 $persistentStore 持久化，key = "ad_tracker_log"
 *
 * 记录内容：URL、时间、请求方法、匹配到的特征标签
 */

const url = $request.url;
const method = $request.method;
const headers = $request.headers;

// ============ 特征规则 ============

// 路径关键词（高权重 - 直接命中广告路径）
const AD_PATH_KEYWORDS = [
  { pattern: /\/splash/i, tag: "splash(开屏)" },
  { pattern: /\/startup/i, tag: "startup(启动)" },
  { pattern: /\/launch/i, tag: "launch(启动)" },
  { pattern: /\/preload.*ad/i, tag: "preload-ad" },
  { pattern: /\/ad\/preload/i, tag: "ad-preload" },
  { pattern: /\/ad\/realtime/i, tag: "ad-realtime" },
  { pattern: /\/ad\/show/i, tag: "ad-show" },
  { pattern: /\/ad\/get/i, tag: "ad-get" },
  { pattern: /\/ad\/loading/i, tag: "ad-loading" },
  { pattern: /\/ad\/ser\//i, tag: "ad-service" },
  { pattern: /\/openscreen/i, tag: "openscreen(开屏)" },
  { pattern: /\/interstitial/i, tag: "interstitial(插屏)" },
  { pattern: /\/rewarded/i, tag: "rewarded(激励)" },
  { pattern: /\/sdkad/i, tag: "sdk-ad" },
  { pattern: /\/wbpullad/i, tag: "pull-ad" },
  { pattern: /\/startpicture/i, tag: "start-picture" },
  { pattern: /\/delivery.*deliver/i, tag: "ad-delivery" },
  { pattern: /\/adx?\//i, tag: "adx" },
  { pattern: /\/cappuccino\/splash/i, tag: "splash(拼多多)" },
];

// 域名关键词（中权重 - 广告平台域名）
const AD_DOMAIN_KEYWORDS = [
  { pattern: /^ads?\./i, tag: "ad-domain" },
  { pattern: /adservice/i, tag: "ad-service" },
  { pattern: /adstrategy/i, tag: "ad-strategy" },
  { pattern: /admob/i, tag: "admob" },
  { pattern: /adcolony/i, tag: "adcolony" },
  { pattern: /applovin/i, tag: "applovin" },
  { pattern: /inmobi/i, tag: "inmobi" },
  { pattern: /unity3d.*ads/i, tag: "unity-ads" },
  { pattern: /pangolin/i, tag: "pangolin(穿山甲)" },
  { pattern: /pglstatp/i, tag: "bytedance-ad" },
  { pattern: /tobapplog/i, tag: "bytedance-log" },
  { pattern: /zijieapi/i, tag: "bytedance-api" },
  { pattern: /gdt\.qq\.com/i, tag: "广点通" },
  { pattern: /cmgadx/i, tag: "移动广告" },
  { pattern: /mobads/i, tag: "百度广告" },
  { pattern: /alimama/i, tag: "阿里妈妈" },
  { pattern: /optimus-ads/i, tag: "optimus-ads" },
];

// 路径中的通用广告标识（低权重 - 需要域名或路径辅助判断）
const AD_GENERIC_KEYWORDS = [
  { pattern: /functionId=delivery/i, tag: "delivery-api" },
  { pattern: /\/banner.*ad/i, tag: "banner-ad" },
  { pattern: /\/native.*ad/i, tag: "native-ad" },
  { pattern: /\/feed.*ad/i, tag: "feed-ad" },
];

// ============ 匹配逻辑 ============

function matchFeatures(url) {
  const tags = [];

  // 提取域名部分用于域名匹配
  let domain = "";
  try {
    domain = url.match(/^https?:\/\/([^\/]+)/i)?.[1] || "";
  } catch(e) {}

  // 高权重：路径关键词
  for (const rule of AD_PATH_KEYWORDS) {
    if (rule.pattern.test(url)) {
      tags.push(rule.tag);
    }
  }

  // 中权重：域名关键词
  for (const rule of AD_DOMAIN_KEYWORDS) {
    if (rule.pattern.test(domain)) {
      tags.push(rule.tag);
    }
  }

  // 低权重：通用标识
  for (const rule of AD_GENERIC_KEYWORDS) {
    if (rule.pattern.test(url)) {
      tags.push(rule.tag);
    }
  }

  return tags;
}

// ============ 记录逻辑 ============

const tags = matchFeatures(url);

if (tags.length > 0) {
  try {
    const STORE_KEY = "ad_tracker_log";
    const MAX_RECORDS = 300;

    let log = [];
    try {
      log = JSON.parse($persistentStore.read(STORE_KEY) || "[]");
    } catch(e) {
      log = [];
    }

    // 提取简短域名 + 路径
    let shortUrl = url;
    try {
      const u = url.match(/^(https?:\/\/[^\/]+)(\/[^\?]{0,80})?/);
      shortUrl = u ? (u[1] + (u[2] || "/")) : url.substring(0, 120);
    } catch(e) {}

    // 去重：同一 URL 5分钟内不重复记录
    const now = Date.now();
    const isDuplicate = log.some(item =>
      item.url === shortUrl && (now - item.ts) < 300000
    );

    if (!isDuplicate) {
      log.push({
        url: shortUrl,
        full: url.substring(0, 500),
        method: method,
        tags: tags,
        ts: now,
        time: new Date().toLocaleString("zh-CN", {
          hour12: false,
          month: "2-digit", day: "2-digit",
          hour: "2-digit", minute: "2-digit", second: "2-digit"
        }),
        // 尝试记录 User-Agent 来辅助识别 App
        ua: (headers?.["User-Agent"] || headers?.["user-agent"] || "").substring(0, 100)
      });

      // 超出上限时删除最旧的记录
      if (log.length > MAX_RECORDS) {
        log = log.slice(-MAX_RECORDS);
      }

      $persistentStore.write(JSON.stringify(log), STORE_KEY);
    }
  } catch(e) {
    console.log("AdTracker error: " + e.message);
  }
}

$done({});
