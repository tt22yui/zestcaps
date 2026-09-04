; ==================================================================
; 桌面快捷方式模块验证：SetDesktopShortcut 往返切换 + 启动自动补齐
; 按 Main.ahk 真实顺序加载：Config → DebugLog → DesktopShortcut
; 结果写入 %TEMP%\_tmp_desktopshortcut_test.txt，测试结束恢复初始状态
; ==================================================================
#Requires AutoHotkey v2.0
#SingleInstance Force
#ErrorStdOut
#Warn All, Off

#Include "..\..\src\Config\Config.ahk"
#Include "..\..\src\DebugLog\DebugLog.ahk"
#Include "..\..\src\DesktopShortcut\DesktopShortcut.ahk"

resultFile := A_Temp "\_tmp_desktopshortcut_test.txt"
try FileDelete(resultFile)

; 备份初始状态，测试结束后恢复，不影响用户原有设置
backupState := IsDesktopShortcutCreated()
lnk := DesktopShortcutPath()
try {
    SetDesktopShortcut(true)
    r1 := IsDesktopShortcutCreated()          ; 启用后应检测到快捷方式
    r2 := FileExist(lnk) != ""                ; 快捷方式文件确实存在

    SetDesktopShortcut(false)
    r3 := !IsDesktopShortcutCreated()         ; 关闭后应检测不到
    r4 := FileExist(lnk) = ""                 ; 快捷方式文件已删除

    SetDesktopShortcut(true)                  ; 再次启用
    r5 := IsDesktopShortcutCreated()

    ; 启动自动补齐：手动删除快捷方式后，CreateDesktopShortcut 应补建
    FileDelete(lnk)
    CreateDesktopShortcut()
    r6 := FileExist(lnk) != ""

    if (r1 && r2 && r3 && r4 && r5 && r6)
        FileAppend "OK: 桌面快捷方式逻辑全部通过", resultFile, "UTF-8"
    else
        FileAppend "FAIL: r1=" r1 " r2=" r2 " r3=" r3 " r4=" r4 " r5=" r5 " r6=" r6, resultFile, "UTF-8"
} catch as err {
    FileAppend "FAIL: " err.Message " @" err.Line, resultFile, "UTF-8"
} finally {
    SetDesktopShortcut(backupState)   ; 恢复用户初始状态
}
ExitApp()