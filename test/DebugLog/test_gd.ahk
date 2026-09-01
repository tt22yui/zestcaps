; 逐步定位：Config + DebugLog（不含 GlobalError）是否正常
#Requires AutoHotkey v2.0
#ErrorStdOut
#Warn All, StdOut
rf := A_Temp "\_tmp_gd.txt"
if FileExist(rf)
    try FileDelete(rf)
#Include "..\..\src\Config\Config.ahk"
try FileAppend "CFG_OK`n", rf
#Include "..\..\src\DebugLog\DebugLog.ahk"
try FileAppend "DBG_OK`n", rf
ExitApp 0
