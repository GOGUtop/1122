# 云洞酒馆 iOS v1.8 实时画中画版

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

该 IPA 是未签名安装包，需要用你自己的证书通过 AltStore、SideStore、Sideloadly、爱思助手签名，或在签名工具中重签后安装。GitHub 本身没有你的 Apple 签名证书，因此不能直接生成所有 iPhone 都能安装的已签名 IPA。普通免费的 Apple ID 签名通常需要定期续签。

## 本地开发

需要 macOS、Xcode 和 XcodeGen：

```bash
brew install xcodegen
xcodegen generate
open TavernSwitcher.xcodeproj
```

## 修改名称或网址

- 三个网址和显示名称：`TavernSwitcher/AppState.swift`
- App 显示名称：`TavernSwitcher/Info.plist`
- Bundle ID：`project.yml`

## 已实现

- 三入口玻璃卡片启动页
- 自动记录上次使用入口
- 网页内悬浮按钮切换入口
- 悬浮球拖动、位置记忆与透明度调节
- 长按悬浮球启动 iOS 系统画中画，可悬浮在桌面和其他 App 上
- 服务端实时复制生成流，App 最小化后画中画仍持续显示正在生成的文字
- 原生画中画排版，不再依靠 WKWebView 定时截图
- SillyTavern 自动滚动截图、去重拼接和系统分享
- 完整回复、截断回复、空回三种独立提示音和通知
- 三种提示音均可从“文件”App 自定义导入
- 单次结束只发送一条通知，只响一次、震动一次
- 生成期间申请 iOS 短时后台执行时间
- 后退、刷新、返回首页
- 清除 Cookie、缓存和网页数据
- 支持网页弹窗、新窗口链接、视频内联播放
- GitHub Actions 自动打包 unsigned IPA

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

如果服务端插件没有安装，App 会退回 SillyTavern 前端事件检测；此模式可以通知，但无法保证切到桌面后持续实时更新。

## 自定义提示音

打开悬浮球 → 设置 → 回复提示音，可分别导入：

- 回复完整完成
- 回复被截断
- 本次为空回

支持 `CAF / WAV / AIF / AIFF`，每段不超过 30 秒。

## v1.8 连接修复

- 将 WKWebView 中的酒馆登录 Cookie 同步到原生实时连接。
- 原生请求同时携带 Cookie、User-Agent、Origin 和 Referer。
- 画中画会直接显示 HTTP 状态码或 iOS 网络错误，不再无限停留在“正在连接生成流”。
