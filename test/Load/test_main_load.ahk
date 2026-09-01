#Requires AutoHotkey v2.0
#SingleInstance Force
#ErrorStdOut
#Warn All, Off
; 完整加载链测试：按 Main.ahk 的真实 #Include 顺序加载全部模块
; 验证启动耗时打点（SCRIPT_LOAD_START + DebugLog）加载无错误
; 测试期间屏蔽日志写入、跳过闪屏，避免污染正式日志与弹窗
#Include "..\..\src\Config\Config.ahk"
DEBUG_LOG_ENABLED := false     ; 屏蔽日志写入，避免污染正式日志
SplashEnabled := false         ; 跳过闪屏窗口
#Include "..\..\src\DebugLog\DebugLog.ahk"
#Include "..\..\src\DebugLog\GlobalError.ahk"
#Include "..\..\src\Splash\Splash.ahk"
#Include "..\..\src\Startup\Startup.ahk"
#Include "..\..\src\Indicator\IME.ahk"
#Include "..\..\src\Indicator\Indicator.ahk"
#Include "..\..\src\InputSwitch\CapsLock.ahk"
#Include "..\..\src\Clipboard\Clipboard.ahk"   ; 剪贴板模块（纯文本粘贴，内含 PastePlain.ahk）
#Include "..\..\src\Screenshot\Screenshot.ahk"
#Include "..\..\src\Hotkeys\Hotkeys.ahk"       ; 自定义快捷键（注册/校验）
#Include "..\..\src\Settings\Settings.ahk"
#Include "..\..\src\TrayMenu\TrayMenu.ahk"

testFile := A_Temp "\_tmp_main_load_test.txt"
try FileDelete(testFile)

; 看门狗：8 秒强制退出，防止测试期间创建的窗口残留
SetTimer(() => ExitApp(), 8000)

; 复现 Main.ahk 的启动耗时打点表达式，验证变量可用、拼接无错
try {
    elapsed := A_TickCount - SCRIPT_LOAD_START
    DebugLog("启动耗时: Splash 加载完成 " elapsed " ms")
    DebugLog("启动耗时: Screenshot 加载完成 " elapsed " ms")
    DebugLog("=== 脚本启动 v" APP_VERSION "（总加载耗时 " elapsed " ms）===")
    FileAppend "OK: 完整加载链通过，耗时 " elapsed " ms`n", testFile
} catch as err {
    FileAppend "FAIL: " err.Message " @" err.Line "`n", testFile
}

; 验证自定义快捷键动态注册（真实模块 + 真实注册函数）
try {
    RegisterCustomHotkeys()
    ; 已注册的热键可用 Hotkey 开关指令探测（未注册会抛错）
    Hotkey PastePlainKey, "On"
    Hotkey ScreenshotKey, "On"
    FileAppend "OK: 自定义快捷键注册成功 (" PastePlainKey " / " ScreenshotKey ")`n", testFile
} catch as err {
    FileAppend "FAIL: 自定义快捷键注册失败: " err.Message " @" err.Line "`n", testFile
}
ExitApp()
