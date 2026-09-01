#Requires AutoHotkey v2.0
#SingleInstance Force
#ErrorStdOut
#Warn All, Off
; Reload 机制耗时测试：第一次运行记录 t1 并 Reload，新实例记录 t2
; 对比 t1/t2 间隔，判断重启慢是否来自 Reload 机制本身的固有延迟
resultFile := A_Temp "\_tmp_reload_timing.txt"
if !FileExist(resultFile) {
    FileAppend "t1=" FormatTime(, "HH:mm:ss.fff") "`n", resultFile
    Reload()
    FileAppend "reload-failed`n", resultFile
} else {
    FileAppend "t2=" FormatTime(, "HH:mm:ss.fff") "`n", resultFile
}
ExitApp()
