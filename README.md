# 叠栏 · FoldBar

macOS 刘海屏原生菜单栏图标管理工具 · 1.5.1 原图预览版

点击菜单栏的 **···**，在一条磨砂圆角浮条里查看隐藏的菜单栏项目。读取原生菜单栏小窗口的静态图像，按原始点尺寸显示，保留应用图标及文字状态。悬停显示名称，设置统一收进右侧齿轮。默认图标条高 52 pt，宽度随项目数量调整，最长 720 pt；超出一排可滚动或翻页。

可直接把图标拖到屏幕顶部省略号右侧的接收区，松手后移动原生项目。需要在面板内整理时，打开 **齿轮 → 管理常驻图标**：上排是常驻菜单栏的原生项目，下排是隐藏项目。移动后核对原生窗口位置，顶部仍由原应用绘制图标和菜单。验证范围见 [VALIDATION.md](VALIDATION.md)。

## 下载与安装

在 GitHub 的 Releases 页面下载 `FoldBar-macOS-AppleSilicon.zip`，解压后将 `FoldBar.app` 放到固定位置，再打开应用。应用需要辅助功能权限才能读取和移动其他应用的菜单栏项目；读取真实图标另外需要 macOS 的“录屏与系统录音”权限。应用仅取得已识别菜单栏小窗口的静态图像，不录音、不采集普通应用窗口、不保存或上传图像。

当前提供 Apple Silicon 构建，属于开发预览版，尚未进行 Developer ID 签名和 Apple 公证。若 macOS 阻止首次启动，可选择从源码构建；不要关闭系统安全检查。

## 使用

1. 打开 `FoldBar.app`，允许辅助功能及原始图标读取。点击菜单栏 **···** 或按 `⌥⌘B` 打开图标条。
2. 单击图标，打开对应原菜单；应用没有提供菜单打开接口时，将其原图标移到顶部。悬停可以查看该项目的操作提示。
3. 把隐藏图标拖到顶部省略号右侧，蓝色接收区中松手即可申请常驻。移到桌面其他位置或取消拖动不会移动原图标。也可右键选择“常驻菜单栏”或“收回隐藏区”。
4. 选择 **齿轮 → 管理常驻图标**，把下排项目拖到上排，即可常驻；在上排拖到目标图标前面可排序；拖回下排可隐藏。点“完成”返回单排。
5. 选择 **齿轮 → 搜索图标…**，搜索全部菜单项目。关闭搜索后恢复隐藏项目视图。
6. 通过齿轮菜单展开 / 收起原菜单栏、刷新、查看原图读取数量、管理登录启动和退出。

移动失败时保留展开状态，并显示可关闭的简短提示。时钟、控制中心等系统固定控件可能无法移动，当前不保证支持全部应用。完整拖拽手势的当前版本验收仍待完成；右键操作提供相同的显示 / 隐藏入口。

## 本机更新后的权限处理

开发版本使用临时签名。在已验证的机器上，更新应用后单纯关闭再开启开关不能恢复授权，需要：

1. 系统设置 → 隐私与安全性 → 辅助功能。
2. 选中 **FoldBar**，用“－”移除该项。
3. 用“＋”添加更新后的 **FoldBar.app**。
4. 如果仍显示“允许读取原始菜单栏图标”，在“录屏与系统录音”中同样仅移除 FoldBar，再添加当前应用；按系统提示退出并重新打开。
5. 返回叠栏，等待菜单栏项目出现或点击刷新。

只处理 FoldBar，不重置其他应用的权限。

## 快捷操作

| 操作 | 方式 |
| --- | --- |
| 打开 / 关闭面板 | 菜单栏 **···** 或 `⌥⌘B` |
| 收起 / 展开隐藏区 | `⇧⌥⌘B` 或 `⌥` 点击 **···** |
| 手动整理原图标 | 从隐藏条拖到顶部接收区，或在管理面板拖动 |
| 恢复默认边界 | 齿轮菜单 → 恢复菜单栏布局 |
| 退出 | 齿轮菜单 → 退出叠栏 |

## 当前边界

- 实际菜单栏空间有限，所有项目不能同时挤进刘海右侧。
- 识别结合公开的状态窗口清单与辅助功能菜单条目，过滤零尺寸的系统占位条目。
- 已遮挡项目仅在能定位其原生窗口时尝试定向拖动；不在未知坐标盲点其他应用。
- 菜单栏入口为独立、固定宽度的原生省略号按钮；收起隐藏区不会加宽或移除入口。无图像的隐藏项只在折叠时存在于入口左侧，展开时完全移除，不留斜杠或空白槽位。
- 移动先向原生状态窗口发送定向事件；系统不接受时，仅对已确认可见的原图标执行一次隐藏指针的插入事件，并恢复指针。没有横向逐步移动动画；底层仍使用鼠标事件。移动后核对原窗口位置。
- macOS 26 上由控制中心托管的第三方窗口，依据唯一的 AX 内容位置匹配，保留原应用菜单身份。
- 无网络请求、分析 SDK、音频采集或持续录像。图标图像仅驻留内存，在打开面板或刷新时更新；图标缓存使用稳定的菜单身份，系统在折叠时返回透明图像，会保留内存里最近一次可读的原图；从未读取到时显示名称缩写，不替换成应用启动图标。
- 图像读取优先使用经权限检查的窗口数组截取，回退菜单栏窗口兼容接口。仅 macOS 14–15 尝试 ScreenCaptureKit 备用路径；macOS 26 不再重复发起不支持的菜单窗口请求。
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

73 项基础检查覆盖坐标、遮挡、搜索、菜单身份、旧展示栏数据、原生位置核对、顶部拖放区域及控制中心托管窗口匹配。它们不替代真实应用图标拖动的实机验证。

- `NativeStatusWindow.swift`：真实状态窗口清单。
- `MenuWindowBridge.swift` / `NativeIconCapture.swift`：已识别状态窗口的原图读取和兼容回退。
- `AccessibilityService.swift`：读取菜单项目、匹配原生窗口。
- `NativeMenuMover.swift`：移动单个原图标并检查位置。
- `DraggableMenuIcon.swift` / `MenuBarDropTarget.swift`：原始尺寸绘制、原生拖动会话和顶部接收区。
- `PinnedShelfView.swift` / `ShelfView.swift`：单排图标条、搜索、翻页及按需展开的整理区。

接口参考：[NSStatusItem](https://developer.apple.com/documentation/appkit/nsstatusitem)、[CGEvent](https://developer.apple.com/documentation/coregraphics/cgevent)、[AXExtrasMenuBar](https://developer.apple.com/documentation/applicationservices/kaxextrasmenubarattribute)。

兼容接口 ABI 核对参考：[Ice 的 WindowServer 桥接声明](https://github.com/jordanbaird/Ice/tree/main/Ice/Bridging)。窗口截取 ABI 另参考 [yabai 的声明](https://github.com/asmvik/yabai/blob/master/src/misc/extern.h)。窗口数组截取参考 [Ice 的 ScreenCapture API 用法](https://github.com/jordanbaird/Ice/blob/main/Ice/Utilities/ScreenCapture.swift)。本项目未引入第三方实现源码。

## 许可证

[MIT](LICENSE)。
