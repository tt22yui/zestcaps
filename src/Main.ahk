#Requires AutoHotkey v2.0.26  ; 声明需要AutoHotkey v2.0.26版本
; 软件版本号见 src\Config\Config.ahk 的 APP_VERSION（模块化：快捷键集中定义，实现分散到 src）
#SingleInstance Force      ; 确保脚本只能运行一个实例
#UseHook False             ; 禁用钩子，避免与系统默认行为冲突
OnExit ReleaseAllModifiers ; 退出时强制释放所有修饰键，防止按键卡死

; ==================================================================
; 加载模块（各功能实现位于 src\<模块名>\ 文件夹中）
; ==================================================================
#Include "Config\Config.ahk"          ; 所有可调参数
#Include "DebugLog\DebugLog.ahk"      ; 调试日志
#Include "DebugLog\GlobalError.ahk"   ; 全局未捕获错误处理（依赖 DebugLog）
#Include "Splash\Splash.ahk"          ; 启动闪屏动画（尽早加载，覆盖后续模块加载过程）
DebugLog("启动耗时: Splash 加载完成 " (A_TickCount - SCRIPT_LOAD_START) " ms")
#Include "Startup\Startup.ahk"        ; 开机启动
#Include "DesktopShortcut\DesktopShortcut.ahk"  ; 桌面快捷方式
#Include "Indicator\IME.ahk"            ; 输入法状态检测
#Include "Indicator\Indicator.ahk"    ; 输入状态指示器
#Include "InputSwitch\CapsLock.ahk"    ; CapsLock 键行为
#Include "Clipboard\Clipboard.ahk"            ; 剪贴板模块（纯文本粘贴）
#Include "Screenshot\Screenshot.ahk"  ; 简单截图
DebugLog("启动耗时: Screenshot 加载完成 " (A_TickCount - SCRIPT_LOAD_START) " ms")
#Include "RecycleBin\RecycleBin.ahk"      ; 定时清空回收站
#Include "Hotkeys\Hotkeys.ahk"        ; 可配置快捷键（读取/注册/校验）
#Include "Settings\Settings.ahk"      ; 设置窗口
#Include "TrayMenu\TrayMenu.ahk"      ; 托盘菜单
; ==================================================================
DebugLog("=== 脚本启动 v" APP_VERSION "（总加载耗时 " (A_TickCount - SCRIPT_LOAD_START) " ms）===")
; ==================================================================

; ==================================================================
; 所有快捷键定义（实现逻辑见各模块文件）
; 新增功能：在此添加热键，并在对应模块文件夹中实现处理函数
; ==================================================================

; 热键名称: CapsLock
; 功能描述: 短按切换输入法 / 长按切换大小写（固定热键，不可配置）
CapsLock::HandleCapsLock()

; 其余快捷键（纯文本粘贴 / 区域截图）均可自定义：见 src\Hotkeys\Hotkeys.ahk，
; 动态注册，配置存 config.ini [Hotkeys] 段，设置窗口「快捷键」文本框直接填写 AHK 原生格式
RegisterCustomHotkeys()
