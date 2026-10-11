# 应用设置

设置定义集中在 `lib/foundation/app_setting_keys.dart`，每个 key 都有中文用途说明，默认值集中在 `defaultAppSettings`。原有 97 个槽位保留 75 个有效设置，另将字体纳入统一仓库，共 76 项。

## 存储格式

应用数据目录下的 `settings` 文件直接保存 JSON 对象。导出文件与 WebDAV 使用同样的对象作为 `settings` 字段。程序不读取旧的 value 数组，也不做运行时旧格式迁移。

```json
{
  "networkBackend": "rhttp",
  "networkProtocol": "auto",
  "parallelDownloads": "6",
  "showNetworkSpeedBall": "0",
  "font": ""
}
```

value 沿用现有字符串编码：布尔值使用 `"1"`/`"0"`，数值存为数字字符串，列表及复合配置的编码在对应 key 的注释中说明。部分 key 缺失时使用默认值；未知 key 不纳入有效设置。

## 读取与修改

- Widget 使用 `appSettingsProvider` 或其派生 Provider 观察快照，使用 Notifier 的 `setValue`/`setValues` 修改配置。
- 滑块预览可使用 `persist: false`，拖动结束再调用 `save()`。
- 无 WidgetRef 的设置弹窗从当前 `ProviderScope` 读取同一个 Notifier。
- 网络及后台业务使用 `appdata.getSetting(AppSettingKeys.xxx)` 同步读取；底层内存更新经 `setSetting` 通知 Provider，不能直接修改只读 `settings` Map。
- 用户数据导入保留本机的下载目录与身份验证配置。隐式界面状态、首次使用提示和已有独立主题 Provider 维持各自存储边界。

## 清理的失效项

移除了旧转发开关、旧搜索排序入口、首次使用冗余开关、旧收藏浏览方式、旧禁漫分类/搜索排序、旧漫画源开关、废弃分类/探索页面、旧主题颜色/深色/纯黑配置、旧缓存数量限制、未使用的翻页动画、旧 nhentai 排序/域名、旧收藏开关、旧禁漫域名、旧工具栏配置、本地收藏显示数量、自定义源更新开关，以及没有业务读取的常亮开关。

阅读器当前使用 `WakelockPlus`，常亮开关的删除保持现有阅读行为。Hosts 虽已提示不再受支持，但仍有代理运行时依赖，因此继续保留。
