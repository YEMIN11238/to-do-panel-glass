# TO-DO Panel Glass Preview

TO-DO Panel 的 macOS 玻璃 UI 改造预览，基于 [xiaopu-ai/TO-DO-Panel](https://github.com/xiaopu-ai/TO-DO-Panel) 1.1.2。原作者为 xiaopu-ai；本仓库提供界面与交互改造，不是原项目官方发布。

## 下载与使用

在 [Releases](https://github.com/YEMIN11238/to-do-panel-glass/releases) 下载 macOS Apple Silicon 预览包，解压后打开 `TO-DO Glass Fixed Preview.app`。启动前用 ⌘Q 退出其他 TO-DO 预览版本。

- 液态玻璃、毛玻璃与标准界面。
- 跟随系统、手动浅色和深色；透明度设置。
- 点击顶部或从顶端垂直下拉，在原位置打开面板。
- 顶部空白处或底部边缘上推收起；点击窗口外或 Escape 收起。
- 保留待办、笔记、链接、录制、音乐、番茄钟和镜子等功能。

液态玻璃需要支持 NSGlassEffectView 的 macOS 26 或更高版本；此预览包为 arm64。本地开发签名，未经过 Apple 公证。

## 源码

`src/` 来自改造后应用的 Electron 资源目录；不包含个人工作区、凭据、运行缓存、Electron 二进制或 node_modules。主入口为 `src/main.js`，界面在 `src/renderer/`，原生玻璃桥在 `src/native/`。

安装 Node.js 与 Electron 后可在 src 目录运行：

```sh
npm install
npm install --no-save electron@44.0.0
node native/build-native.mjs --outdir native
npx electron .
```

原生桥编译需要 macOS 26 SDK、Xcode Command Line Tools 和 Node.js 的 node_api.h。若 Node 头文件不在默认路径，设置 `NODE_HEADERS_DIR`。Electron 版本以发布包实际运行版本为准，开发环境启动流程尚未独立验收。

## 预览状态

发布的是 2026-10-08 的材质修正版，2026-10-13 整理上传。此前通过了材质/主题逻辑、下拉与上推逻辑、签名检查及部分实际窗口交互测试。仍需在不同桌面背景下检查视觉效果，欢迎提交 issue。

## 授权与来源

保留原项目 MIT LICENSE 和作者信息。附带的用户指定封面图片仅用于该界面预览；代码许可证不代表图片的再授权。
