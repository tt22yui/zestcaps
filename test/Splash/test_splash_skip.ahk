; ==================================================================
; 回归测试：闪屏关闭时后续模块仍正常加载
; 背景：Splash.ahk 曾用顶层 return 实现开关，导致主脚本后续
;       #Include（托盘菜单/热键等）全部失效 —— 见会话记录
; 本测试模拟 SplashEnabled=false，验证 Startup/TrayMenu 仍加载
; ==================================================================
#Requires AutoHotkey v2.0
#SingleInstance Force
#ErrorStdOut
#Warn All, Off

#Include "..\..\src\Config\Config.ahk"
#Include "..\..\src\DebugLog\DebugLog.ahk"
; 模拟用户关闭闪屏（覆盖 Config.ahk 读取值）
SplashEnabled := false
#Include "..\..\src\Splash\Splash.ahk"
#Include "..\..\src\Startup\Startup.ahk"
#Include "..\..\src\Settings\Settings.ahk"
#Include "..\..\src\TrayMenu\TrayMenu.ahk"

f := A_Temp "\_tmp_splash_skip_test.txt"
try FileDelete(f)
try {
    ok := IsSet(StartupEnabled) && IsSet(SetStartup) && IsSet(OpenSettings) && IsSet(InitTrayMenu)
    FileAppend (ok ? "OK: 闪屏关闭后后续模块加载正常`n" : "FAIL: 后续模块未加载`n"), f
} catch as err {
    FileAppend "FAIL: " err.Message " @" err.Line "`n", f
}
ExitApp()
