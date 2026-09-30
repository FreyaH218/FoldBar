# 叠栏 · FoldBar

macOS 刘海屏原生菜单栏图标管理工具 · 1.4 紧凑预览版

点击菜单栏的 **···**，在一条磨砂圆角浮条里查看隐藏的菜单栏项目。平时只显示图标，悬停显示名称，设置统一收进右侧齿轮。默认图标条高 52 pt，宽度随项目数量调整，最长 720 pt；超出一排可滚动或翻页。

需要调整顶部菜单栏时，打开 **齿轮 → 整理图标**：上排是常驻菜单栏的原生项目，下排是隐藏项目。移动后核对原生窗口位置，顶部仍由原应用绘制图标和菜单。验证范围见 [VALIDATION.md](VALIDATION.md)。

## 下载与安装

在 GitHub 的 Releases 页面下载 `FoldBar-macOS-AppleSilicon.zip`，解压后将 `FoldBar.app` 放到固定位置，再打开应用。应用需要辅助功能权限才能读取和移动其他应用的菜单栏项目。

当前提供 Apple Silicon 构建，属于开发预览版，尚未进行 Developer ID 签名和 Apple 公证。若 macOS 阻止首次启动，可选择从源码构建；不要关闭系统安全检查。

## 使用

1. 打开 `FoldBar.app`，在辅助功能中允许 FoldBar。点击菜单栏 **···** 或按 `⌥⌘B` 打开图标条。
2. 单击图标，打开对应原菜单；应用没有提供菜单打开接口时，将其原图标移到顶部。悬停可以查看该项目的操作提示。
3. 右键项目，可选择“常驻菜单栏”或“收回隐藏区”。
4. 选择 **齿轮 → 整理图标**，把下排项目拖到上排，即可常驻；在上排拖到目标图标前面可排序；拖回下排可隐藏。点“完成”返回单排。
5. 选择 **齿轮 → 搜索图标…**，搜索全部菜单项目。关闭搜索后恢复隐藏项目视图。
6. 通过齿轮菜单展开 / 收起原菜单栏、刷新、管理登录启动和退出。

移动失败时保留展开状态，并显示可关闭的简短提示。时钟、控制中心等系统固定控件可能无法移动，当前不保证支持全部应用。完整拖拽手势的当前版本验收仍待完成；右键操作提供相同的显示 / 隐藏入口。

## 本机更新后的辅助功能处理

开发版本使用临时签名。在已验证的机器上，更新应用后单纯关闭再开启开关不能恢复授权，需要：

1. 系统设置 → 隐私与安全性 → 辅助功能。
2. 选中 **FoldBar**，用“－”移除该项。
3. 用“＋”添加更新后的 **FoldBar.app**。
4. 返回叠栏，等待菜单栏项目出现或点击刷新。

只处理 FoldBar，不重置其他应用的权限。

## 快捷操作

| 操作 | 方式 |
| --- | --- |
| 打开 / 关闭面板 | 菜单栏 **···** 或 `⌥⌘B` |
| 收起 / 展开隐藏区 | `⇧⌥⌘B`、`⌥` 点击 **···**、或点击分隔线 |
| 手动整理原图标 | 按住 `⌘` 拖动；分隔线左侧收起，右侧保留 |
| 恢复分隔线 | 齿轮菜单 → 恢复分隔线位置 |
| 退出 | 齿轮菜单 → 退出叠栏 |

## 当前边界

- 实际菜单栏空间有限，所有项目不能同时挤进刘海右侧。
- 识别结合公开的状态窗口清单与辅助功能菜单条目，过滤零尺寸的系统占位条目。
- 已遮挡项目仅在能定位其原生窗口时尝试定向拖动；不在未知坐标盲点其他应用。
- 移动通过 Core Graphics 鼠标事件实现，并核对原窗口位置。辅助功能读取和菜单打开使用 AX API。
- 无网络请求、分析 SDK 或屏幕录制。面板不截取其他应用的实时图标图像。
- 隐藏窗口定位增加了动态加载的 WindowServer 兼容接口（未公开 API）。缺少接口或 macOS 27 及以后会回退公开清单，不绕过辅助功能权限。
- 尚未验证所有第三方应用、多显示器、全屏空间、重启后的排序恢复。
- 系统后台状态窗口须匹配真实 AX 菜单项目才展示，减少“控制中心”占位项；仍未逐一核对全部应用。
- 以 Apple Silicon / macOS 26 构建；macOS 13–15、Intel 未实机验证，macOS 27 起停用折叠。
- 当前应用采用临时签名，未做 Developer ID 公证。

## 源码与检查

```bash
bash scripts/build.sh
bash scripts/check-core.sh
```

无外部依赖，需要 Apple Command Line Tools 或 Xcode / Swift 5.9 及以上。构建路径可通过 `FOLDBAR_BUILD_DIR`、`FOLDBAR_OUTPUT_DIR` 设置。

50 项现有基础检查覆盖坐标、遮挡、搜索、菜单身份、旧展示栏数据和原生位置核对。它们不替代真实应用图标拖动的实机验证。

- `NativeStatusWindow.swift`：真实状态窗口清单。
- `MenuWindowBridge.swift`：隐藏状态窗口的兼容接口与公开 API 回退。
- `AccessibilityService.swift`：读取菜单项目、匹配原生窗口。
- `NativeMenuMover.swift`：移动单个原图标并检查位置。
- `PinnedShelfView.swift` / `ShelfView.swift`：单排图标条、搜索、翻页及按需展开的整理区。

接口参考：[NSStatusItem](https://developer.apple.com/documentation/appkit/nsstatusitem)、[CGEvent](https://developer.apple.com/documentation/coregraphics/cgevent)、[AXExtrasMenuBar](https://developer.apple.com/documentation/applicationservices/kaxextrasmenubarattribute)。

兼容接口 ABI 核对参考：[Ice 的 WindowServer 桥接声明](https://github.com/jordanbaird/Ice/tree/main/Ice/Bridging)。本项目未引入其实现源码。

## 许可证

[MIT](LICENSE)。
