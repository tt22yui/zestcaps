# ZestCaps

> v0.1.0 — [MIT License](LICENSE)

[![license](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)

macOS 式 CapsLock 输入法切换增强工具：短按切中英、长按切大小写，并集成输入状态指示器、纯文本粘贴、区域截图等日常小工具。基于 AutoHotkey v2 编写，绿色免安装。

## 缘起

一直觉得 macOS 上的 CapsLock 切换输入法功能很好用，但 Windows 平台上似乎没有特别好的替代品。于是借着 AI 的东风，自己打造了一个 CapsLock 切换输入法工具，并加入了日常常用的小工具，如截图、纯文本粘贴等功能。

## 主要功能

### 1. CapsLock 键增强

- **短按**（0.3 秒内释放）：切换中英文输入法
- **长按**（超过 0.3 秒）：切换 CapsLock 大小写状态

### 2. 输入状态指示器

- 鼠标处于文本输入形态时，在光标旁实时显示当前输入法状态：`中` / `英` / `A`
- 基于 `WM_IME_CONTROL` 消息**实时检测**真实状态，无需手动同步，兼容微信输入法等 TSF 输入法
- **按窗口独立记忆**输入法状态，切换窗口自动恢复
- 状态缓存 + 变化时才重绘，防闪烁、低资源占用
- 设置窗口可随时开关

### 3. 纯文本粘贴（Ctrl+Shift+V）

- 粘贴时自动去除剪贴板格式与首尾空白
- 设置窗口可随时开关

### 4. 区域截图（F1）

- 灰色半透明蒙版挖洞高亮选区 + 天蓝边框，悬停自动吸附窗口，拖动选择任意矩形区域
- 双击选区快速复制到剪贴板并关闭，或经工具栏标注/保存/钉屏/复制；`Esc` 或右键取消，超时自动取消
- 确认后自动打开**标注编辑窗**：矩形/箭头/椭圆/马赛克，支持清除，也可复制/保存/钉屏
- 支持一键**钉屏**（置顶显示、可拖动、右键关闭）、复制或保存为 PNG
- 设置窗口可随时开关

### 5. 启动闪屏动画

- 启动时显示暗色圆角卡片：标题 + 底部 `中/英/A` 芯片循环点亮（绿→蓝→橙）
- 淡入淡出自动关闭，定时器驱动，不阻塞热键注册
- 基于 GDI+ 分层窗口绘制，无需任何图片资源

### 6. 开机自启

- 设置窗口一键开关

## 输入法检测原理

```text
实时查询（WM_IME_CONTROL，主手段）→ 每 80ms 一次，兼容微信输入法等 TSF 输入法
   ↓ 查询失败时
按窗口状态缓存（Map，上限 200 条自动清理）
   ↓ 新窗口无缓存时
键盘布局推测（非中文布局 → 英文）
```

## 文件结构

```text
src\
├── Main.ahk            主入口：加载模块（CapsLock 固定热键 + 可配置热键注册）
├── config.ini          功能开关状态与可配置快捷键（设置窗口保存时自动写回）
├── Config\
│   └── Config.ahk      配置（参数与功能开关，从 config.ini 读取）
├── DebugLog\
│   ├── DebugLog.ahk    调试日志
│   └── GlobalError.ahk 全局未捕获错误处理（写日志、防弹框）
├── Startup\
│   └── Startup.ahk     开机启动检测与切换
├── Splash\
│   └── Splash.ahk      启动闪屏动画（GDI+ 分层窗口，纯代码绘制）
├── Indicator\
│   ├── IME.ahk         输入法中/英文状态检测（WM_IME_CONTROL）
│   └── Indicator.ahk   输入状态指示器（GUI、跟随鼠标、防闪烁缓存）
├── InputSwitch\
│   └── CapsLock.ahk    CapsLock 键行为实现（短按/长按分发、修饰键释放）
├── Clipboard\
│   ├── Clipboard.ahk   剪贴板模块入口（纯文本粘贴）
│   └── PastePlain.ahk  纯文本粘贴（默认 Ctrl+Shift+V，可配置）
├── Hotkeys\
│   └── Hotkeys.ahk     可配置快捷键（读取/注册/校验，存 [Hotkeys] 段）
├── Settings\
│   └── Settings.ahk    设置窗口（功能开关 + 快捷键配置）
├── Screenshot\
│   ├── Screenshot.ahk  区域截图主流程（选区 overlay/截图/标注编辑窗）
│   ├── Editor.ahk      标注编辑窗（绘制工具/清除/钉屏/复制/保存）
│   ├── Pin.ahk         截图钉屏（置顶/拖动/右键关闭）
│   └── Common\
│       ├── Overlay.ahk     覆盖层共享组件（蒙版挖洞 + 4 条边框）
│       └── ToolbarUI.ahk   工具栏通用组件（色块/扁平按钮/悬停）
├── Common\
│   └── Gdip_All_v2.ahk  Gdip 库（截图/闪屏，唯一第三方依赖）
└── TrayMenu\
    └── TrayMenu.ahk     托盘菜单初始化（设置/重启/退出）
build.bat                编译脚本（输出 output\zestcaps.exe）
```

> 约定：CapsLock 固定热键定义在 `src\Main.ahk`，其余快捷键在 `src\Hotkeys\Hotkeys.ahk` 动态注册（可配置）；各功能实现放在 `src\<模块名>\` 文件夹内，便于后续扩展与维护。

## 配置说明

- `config.ini`：功能开关与可配置快捷键
  - 功能开关初始状态（`IndicatorEnabled`、`PastePlainEnabled`、`ScreenshotEnabled`），设置窗口保存时自动写回
  - 可配置快捷键（`[Hotkeys]` 段：`PastePlain`、`Screenshot`），在设置窗口「快捷键」文本框直接填写 AHK 原生格式（如 `^v`、`F1`），保存后重启生效
- `src\Config\Config.ahk`：其余参数硬编码
  - 菜单文字（`MENU_TITLE`、`MENU_SETTINGS`、`MENU_RESTART`、`MENU_EXIT`）
  - 指示器文字/颜色/尺寸/偏移/字体（`IND_*`）
  - CapsLock 短按/长按判定阈值（`CAPS_*`）
  - 启动闪屏尺寸/时长/配色（`SPLASH_*`）
  - 截图/选区/标注编辑窗参数（`SCREENSHOT_FILENAME`、`SEL_*`、`EDIT_*`、`SCREENSHOT_TIMEOUT_MS` 等）

修改后需重启脚本生效。

## 安装使用

1. 安装 [AutoHotkey v2.0](https://www.autohotkey.com/) 或更高版本
2. 克隆或下载本仓库
3. 双击 `src\Main.ahk` 运行
4. 托盘图标右键「设置...」或在设置窗口中控制各功能开关与快捷键

## 构建

运行 `build.bat` 可将脚本编译为独立的 `output\zestcaps.exe`（需已安装 AutoHotkey v2 及编译器 Ahk2Exe）。

## License

本项目基于 [MIT License](LICENSE) 开源发布，允许自由使用、修改与分发，详情见 [LICENSE](LICENSE) 文件。
