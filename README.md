# 云洞酒馆 iOS v2.6 画中画横幅映射版

这是一个 SwiftUI + WKWebView 的 iPhone/iPad 壳应用，内置三个可切换入口：

- `http://aaa.xixisillytavern.top:8000`
- `http://aaa.xixisillytavern.top:8443`
- `http://aaa.xixisillytavern.top:8888`

## 用 GitHub 自动生成 IPA

1. 新建一个 GitHub 仓库，把本项目的全部文件上传到仓库根目录。
2. 打开仓库的 **Actions** 页面。
3. 选择 **Build iOS IPA**，点击 **Run workflow**。
4. 构建完成后，在该次运行底部下载 `TavernSwitcher-unsigned-IPA`。
5. 解压后得到 `TavernSwitcher-unsigned.ipa`。

该 IPA 是未签名安装包，需要用你自己的证书通过 AltStore、SideStore、Sideloadly、爱思助手签名，或在签名工具中重签后安装。

## 已实现

- 三入口玻璃卡片启动页
- 自动记录上次使用入口
- 网页内悬浮按钮切换入口
- 悬浮球拖动、吸边、位置记忆与透明度调节
- 选区长截图：手动设定开头和结尾，只截选中范围
- 长按悬浮球或点击菜单启动 iOS 系统画中画
- 服务端实时复制生成流，App 最小化后画中画继续显示正在生成的文字
- 完整回复、截断回复、空回三种状态在画中画内显示醒目状态条
- v2.6 新增：画中画状态条可同步为系统顶部横幅
- 系统声音和震动保持关闭，避免重复响铃
- 生成期间申请 iOS 短时后台执行时间
- 后退、刷新、返回首页、清除网页数据
- GitHub Actions 自动打包 unsigned IPA

## v2.6 画中画横幅映射

本版不是让三路检测直接弹系统通知，而是：

1. 酒馆回复结束后，画中画内部先显示状态条。
2. 只有这个状态条出现时，才同步发出一次系统顶部横幅。
3. 原生事件、服务端桥接和后台轮询都不再直接弹通知。

这样能最大限度避免“同一条回复弹三四次”。横幅默认无声音、无震动，只负责提示：

- 完整：`已完成回复`
- 截断：`回复已截断`，正文提示建议重 Roll 或继续生成
- 空回：`本次已空回`，正文提示建议重 Roll

可在：悬浮球 → 设置 → 画中画完成提示 中关闭或测试“画中画提示同步为系统横幅”。

如果测试横幅不从顶部弹出，请到：

```text
设置 → 通知 → 云洞酒馆 → 横幅
```

确认横幅已开启。iOS 不允许 App 绕过这个系统开关。

## 必装：实时桥接服务端插件

只有安装服务端插件，App 最小化后才能脱离被冻结的 WKWebView，继续接收 AI 的流式回复。

1. 将项目中的 `SillyTavernServerPlugin` 文件夹复制到 SillyTavern：

```text
plugins/tavern-live-bridge
```

2. 修改 SillyTavern 根目录的 `config.yaml`：

```yaml
enableServerPlugins: true
```

3. 重启 SillyTavern。

4. 浏览器打开：

```text
http://你的酒馆地址/api/plugins/tavern-live-bridge/health
```

看到 `{"ok":true}` 即安装成功。App 会自动建立随机隔离频道并接管生成请求，无需手动填写 WebSocket 地址。

## 三种结束状态

- `complete`：模型正常停止并且存在有效正文。
- `truncated`：达到 token 上限、长度限制、请求取消或用户提前停止。
- `empty`：生成结束后没有有效正文。

如果服务端插件没有安装，App 会退回 SillyTavern 前端事件检测；此模式可以提示，但无法保证切到桌面后持续实时更新。
