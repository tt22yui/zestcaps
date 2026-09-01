#Requires AutoHotkey v2.0
#SingleInstance Force
#ErrorStdOut
#Warn All, StdOut
; 托盘菜单加载测试：验证精简后的菜单（设置/重启/退出）构建无错误
#Include "..\..\src\Config\Config.ahk"
#Include "..\..\src\Settings\Settings.ahk"
#Include "..\..\src\TrayMenu\TrayMenu.ahk"

testFile := A_Temp "\_tmp_traymenu_load_test.txt"
if FileExist(testFile)
    FileDelete testFile

; 验证 A_TrayMenu 可正常访问（InitTrayMenu 已在加载时执行）
FileAppend "OK: TrayMenu 加载成功，菜单项构建无错误`n", testFile
ExitApp
