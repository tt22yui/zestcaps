; 验证 GlobalError.ahk 单独加载是否正常（不触发运行时错误）
#Requires AutoHotkey v2.0
#ErrorStdOut
#Warn All, StdOut
rf := A_Temp "\_tmp_globalerr2.txt"
if FileExist(rf)
    try FileDelete(rf)
#Include "..\..\src\Config\Config.ahk"
#Include "..\..\src\DebugLog\DebugLog.ahk"
#Include "..\..\src\DebugLog\GlobalError.ahk"
FileAppend "GLOBALERR_LOADED`n", rf
ExitApp 0
