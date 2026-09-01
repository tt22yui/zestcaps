#Requires AutoHotkey v2.0
#SingleInstance Force
#ErrorStdOut
#Warn All, StdOut
; 设置窗口加载测试：验证 Settings.ahk 加载无错误、OpenSettings 能正常创建窗口
#Include "..\..\src\Config\Config.ahk"
#Include "..\..\src\Hotkeys\Hotkeys.ahk"   ; Settings 的「快捷键」页依赖（校验）
#Include "..\..\src\Settings\Settings.ahk"

testFile := A_Temp "\_tmp_settings_test.txt"
if FileExist(testFile)
    FileDelete testFile

; 看门狗：5 秒后强制关闭窗口并退出，防止窗口残留
SetTimer Watchdog, 5000
Watchdog() {
    if WinExist("设置 - " MENU_TITLE)
        WinClose("设置 - " MENU_TITLE)
    ExitApp()
}

OpenSettings()

if WinExist("设置 - " MENU_TITLE) {
    FileAppend "OK: 设置窗口已创建`n", testFile
} else {
    FileAppend "FAIL: 设置窗口未创建`n", testFile
}
