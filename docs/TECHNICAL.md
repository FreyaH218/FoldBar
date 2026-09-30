# 技术说明

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

