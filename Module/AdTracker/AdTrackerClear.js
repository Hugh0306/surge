/**
 * 广告抓包记录 - 清空记录
 * 手动运行此脚本可清空所有已记录的数据
 */

const STORE_KEY = "ad_tracker_log";
let count = 0;
try {
  const log = JSON.parse($persistentStore.read(STORE_KEY) || "[]");
  count = log.length;
} catch (e) {}

$persistentStore.write("[]", STORE_KEY);
$persistentStore.write("", "ad_tracker_rules");
$persistentStore.write("", "ad_tracker_export");
$notification.post("广告抓包记录", "已清空", `删除了 ${count} 条记录`);
$done({ response: { status: 200, body: `已清空 ${count} 条记录` } });
