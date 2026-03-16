/**
 * Surge Panel - IP 信息 + IPPure 纯净度
 * 数据来源：ip-api.com / my.ippure.com
 */

const IPAPI_URL = "http://ip-api.com/json";
const IPPURE_URL = "https://my.ippure.com/v1/info";

function fetchData(url) {
  return new Promise((resolve, reject) => {
    $httpClient.get({ url, headers: { "User-Agent": "Surge" } }, (err, resp, data) => {
      if (err) reject(err);
      else resolve(data);
    });
  });
}

function getFlagEmoji(code) {
  if (code.toUpperCase() === "TW") code = "CN";
  return String.fromCodePoint(
    ...code.toUpperCase().split("").map(c => 127397 + c.charCodeAt())
  );
}

function cleanIsp(isp) {
  return isp
    .replace(/\(.*?\)|[-,.]/g, "")
    .replace(/\b(Hong Kong|Mass internet|Communications?|Company|Pty|LTD|information|international|Technolog(y|ies)|ESolutions?|Services Limited|Magix Services)\b/gi, "")
    .replace(/(munications?)/gi, "")
    .replace(/\s+/g, " ")
    .trim();
}

Promise.all([fetchData(IPAPI_URL), fetchData(IPPURE_URL)])
  .then(([ipapiRaw, ippureRaw]) => {
    const ipapi = JSON.parse(ipapiRaw);
    const { country, countryCode, city, isp, query: ip } = ipapi;
    const emoji = getFlagEmoji(countryCode);
    const loc = country === city ? `${emoji} │ ${country}` : `${emoji} ${countryCode} │ ${city}`;

    let pureLine = "纯净度：查询失败";
    let asnLine = "";
    let nativeLine = "";
    try {
      const pure = JSON.parse(ippureRaw);
      const s = pure.fraudScore;
      if (typeof s === "number") {
        const tag = s <= 20 ? "🟢 极佳" : s <= 50 ? "🟡 一般" : s <= 80 ? "🟠 较差" : "🔴 极差";
        pureLine = `纯净度：${s} ${tag}`;
      }
      if (pure.asn) asnLine = `ASN：${pure.asn} (${pure.asOrganization || ""})`;
      nativeLine = `原生IP：${pure.isResidential ? "🟢 Yes" : "🔴 No"}`;
    } catch (e) {}

    const lines = [
      `IP地址：${ip}`,
      `运营商：${cleanIsp(isp)}`,
      `所在地：${loc}`,
      asnLine,
      pureLine,
      nativeLine,
    ].filter(Boolean).join("\n");

    $done({
      title: "节点信息",
      content: lines,
      icon: "globe.asia.australia",
      "icon-color": "#3D90ED",
    });
  })
  .catch((err) => {
    $done({
      title: "节点信息",
      content: "查询失败：" + err,
      icon: "xmark.circle",
      "icon-color": "#FF3B30",
    });
  });
