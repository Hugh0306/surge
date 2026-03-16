/**
 * 广告抓包记录 - 清空记录
 * 手动运行此脚本可清空所有已记录的数据
 */

$persistentStore.write("[]", "ad_tracker_log");
$persistentStore.write("", "ad_tracker_rules");
$notification.post("广告抓包记录", "已清空", "所有记录已删除");
$done();
