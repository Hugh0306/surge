/**
 * 懂车帝去开屏广告脚本
 *
 * 原理：拦截广告接口的响应，返回空广告数据，
 * 让 App 认为"没有广告可展示"，而非请求失败。
 *
 * 适配接口：
 *  1. /api/ad/ 系列 — 主广告接口（开屏、插屏、信息流）
 *  2. /obj/ad-tetris-site/ — 广告素材资源
 *  3. /service/2/app_config/ — 启动配置（含广告策略）
 *  4. /motor/grpc/sdk.ad/ — gRPC 广告请求
 */

const url = $request.url;

// 广告接口响应处理
if ($response) {
  let body = $response.body;

  try {
    // /api/ad/ 系列接口 — 开屏、插屏等
    if (/\/api\/ad\//i.test(url)) {
      let obj = JSON.parse(body);

      // 清空广告数据列表
      if (obj.data) {
        // 常见结构：data.ad_data / data.ads / data.ad_list
        if (obj.data.ad_data) obj.data.ad_data = [];
        if (obj.data.ads) obj.data.ads = [];
        if (obj.data.ad_list) obj.data.ad_list = [];
        if (obj.data.splash) obj.data.splash = null;
        if (obj.data.splash_ad) obj.data.splash_ad = null;

        // 设置广告间隔为极大值，减少后续请求
        if (obj.data.interval !== undefined) obj.data.interval = 999999;
        if (obj.data.splash_interval !== undefined) obj.data.splash_interval = 999999;
        if (obj.data.show_interval !== undefined) obj.data.show_interval = 999999;
      }

      // 顶层可能有 ads 字段
      if (obj.ads) obj.ads = [];
      if (obj.ad_data) obj.ad_data = [];

      body = JSON.stringify(obj);
    }

    // app_config 启动配置 — 可能包含广告开关和策略
    else if (/\/service\/\d\/app_config/i.test(url)) {
      let obj = JSON.parse(body);

      // 递归清理含 ad/splash 关键字的字段
      function cleanAds(o) {
        if (!o || typeof o !== "object") return;
        for (let key of Object.keys(o)) {
          const lk = key.toLowerCase();
          if (lk.includes("splash") || lk === "ad" || lk === "ads" || lk === "ad_data"
              || lk.includes("ad_") || lk.includes("_ad") || lk === "advert") {
            if (Array.isArray(o[key])) {
              o[key] = [];
            } else if (typeof o[key] === "object" && o[key] !== null) {
              o[key] = {};
            } else if (typeof o[key] === "number") {
              o[key] = 0;
            } else if (typeof o[key] === "boolean") {
              o[key] = false;
            }
          }
        }
      }

      if (obj.data) cleanAds(obj.data);
      cleanAds(obj);

      body = JSON.stringify(obj);
    }

  } catch (e) {
    // JSON 解析失败说明不是 JSON 响应，直接返回空
    // 可能是广告素材（图片/视频），返回空 body
    if (/\/obj\/ad-tetris-site\//i.test(url) || /\/ad\.union\.api/i.test(url)) {
      body = "";
    }
  }

  $done({ body: body });
} else {
  $done({});
}
