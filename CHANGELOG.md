# 更新日志

本文件记录 ZestCaps 各版本的更新内容。格式遵循 [Keep a Changelog](https://keepachangelog.com/zh-CN/)，版本号遵循 [语义化版本](https://semver.org/lang/zh-CN/)。

## [Unreleased]

## [0.1.0] - 2026-09-01

首版开源发布。

### 新增

- **CapsLock 键增强**：短按切换中英文输入法，长按切换 CapsLock 大小写
- **输入状态指示器**：光标旁实时显示 `中 / 英 / A`
  - 基于 `WM_IME_CONTROL` 消息实时检测真实状态，兼容微信输入法等 TSF 输入法
  - 按窗口独立记忆输入法状态，切换窗口自动恢复
  - 状态缓存 + 变化时才重绘，防闪烁、低资源占用
- **纯文本粘贴**（`Ctrl+Shift+V`，可配置）：粘贴时自动去除剪贴板格式与首尾空白
- **区域截图**（`F1`，可配置）：
  - 灰色半透明蒙版挖洞高亮选区 + 天蓝边框，悬停自动吸附窗口
  - 双击快速复制，或经工具栏标注/保存/钉屏；`Esc` / 右键 / 超时自动取消
  - 标注编辑窗：矩形 / 箭头 / 椭圆 / 马赛克，支持清除、复制、保存、钉屏
- **启动闪屏动画**：暗色圆角卡片，`中/英/A` 芯片循环点亮，淡入淡出自动关闭（GDI+ 分层窗口，纯代码绘制）
- **开机自启**：设置窗口一键开关
- **设置窗口 + 托盘菜单**：功能开关与可配置快捷键集中管理

### 工程

- 基于 AutoHotkey v2，绿色免安装；`build.bat` 可编译为独立 `zestcaps.exe`
- 全局未捕获错误处理与调试日志，配备按键看门狗防假死

[Unreleased]: https://github.com/tt22yui/zestcaps/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/tt22yui/zestcaps/releases/tag/v0.1.0