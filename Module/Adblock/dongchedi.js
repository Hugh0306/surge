/**
 * 懂车帝去开屏广告脚本
 *
 * 原理：拦截广告接口的响应，返回空广告数据，
 * 让 App 认为"没有广告可展示"，而非请求失败。
 *
 * 适配接口（真实 API 域名: dcarapi.com）：
 *  1. /motor/ad/api/v1/common — 主广告接口（开屏、插屏）
 *  2. /motor/brand/v6/launch — 启动配置（含广告策略）
 *  3. /api/ad/ — dongchedi.com 域名下的广告接口
 *  4. /service/N/app_config — 启动配置
 */

const url = $request.url;

if ($response) {
  let body = $response.body;

  try {
    let obj = JSON.parse(body);

    // dcarapi.com/motor/ad/ — 懂车帝主广告接口
    if (/\/motor\/ad\//i.test(url)) {
      // 深度清理所有广告相关字段
      deepCleanAds(obj);
      body = JSON.stringify(obj);
    }

    // dcarapi.com/motor/brand/.../launch — 启动接口
    else if (/\/launch/i.test(url) && /dcarapi/i.test(url)) {
      deepCleanAds(obj);
      body = JSON.stringify(obj);
    }

    // dongchedi.com/api/ad/ 和 snssdk.com/api/ad/
    else if (/\/api\/ad\//i.test(url)) {
      deepCleanAds(obj);
      body = JSON.stringify(obj);
    }

    // app_config 启动配置
    else if (/\/service\/\d\/app_config/i.test(url)) {
      deepCleanAds(obj);
      body = JSON.stringify(obj);
    }

  } catch (e) {
    // 非 JSON 响应（如广告素材），返回空
    if (/\/obj\/ad-tetris-site\//i.test(url) || /\/ad\.union\.api/i.test(url)) {
      body = "";
    }
  }

  $done({ body: body });
} else {
  $done({});
}

/**
 * 深度清理 JSON 对象中的广告相关字段
 * 支持嵌套对象递归处理
 */
function deepCleanAds(obj) {
  if (!obj || typeof obj !== "object") return;

  const adKeys = [
    "ad", "ads", "ad_data", "ad_list", "ad_info", "ad_items",
    "splash", "splash_ad", "splash_data", "splash_info",
    "open_screen", "openscreen", "preload_ad", "preload_ads",
    "launch_ad", "launch_ads", "interstitial",
    "rewarded", "banner_ad", "feed_ad", "native_ad"
  ];

  const intervalKeys = [
    "interval", "splash_interval", "show_interval",
    "ad_interval", "request_interval", "display_interval",
    "load_interval", "refresh_interval"
  ];

  for (let key of Object.keys(obj)) {
    const lk = key.toLowerCase();

    // 清空广告数据字段
    if (adKeys.includes(lk) || (lk.includes("ad") && (lk.includes("data") || lk.includes("list") || lk.includes("info")))) {
      if (Array.isArray(obj[key])) {
        obj[key] = [];
      } else if (typeof obj[key] === "object" && obj[key] !== null) {
        obj[key] = {};
      } else if (typeof obj[key] === "string") {
        obj[key] = "";
      } else if (typeof obj[key] === "number") {
        obj[key] = 0;
      } else if (typeof obj[key] === "boolean") {
        obj[key] = false;
      }
      continue;
    }

    // 设置广告间隔为极大值
    if (intervalKeys.some(ik => lk === ik || lk.includes(ik))) {
      if (typeof obj[key] === "number") {
        obj[key] = 999999999;
      }
      continue;
    }

    // 递归处理嵌套对象（只处理第一层嵌套，避免性能问题）
    if (typeof obj[key] === "object" && obj[key] !== null && !Array.isArray(obj[key])) {
      for (let subKey of Object.keys(obj[key])) {
        const slk = subKey.toLowerCase();
        if (adKeys.includes(slk)) {
          if (Array.isArray(obj[key][subKey])) {
            obj[key][subKey] = [];
          } else if (typeof obj[key][subKey] === "object") {
            obj[key][subKey] = {};
          }
        }
      }
    }
  }
}
