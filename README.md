# 云洞酒馆 iOS

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
- SillyTavern 自动滚动截图、去重拼接和系统分享
- 回复生成结束声音与本地通知
- 生成期间申请 iOS 短时后台执行时间
- 后退、刷新、返回首页
- 清除 Cookie、缓存和网页数据
- 支持网页弹窗、新窗口链接、视频内联播放
- GitHub Actions 自动打包 unsigned IPA

## v1.6 修正
- 画中画启动后开启静音后台音频保活，尽量让小窗继续刷新。
- 回复生成期间开启后台轮询，App 在桌面时也会尽量检测回复结束并通知。
- 注意：iOS 仍可能在低电量/系统压力下冻结 WKWebView。若要 100% 长时间后台必达，需要服务端推送插件。
