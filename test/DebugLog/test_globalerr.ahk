; 验证 GlobalError.ahk 的 OnError(GlobalErrorHandler)（处理函数定义在后）在真实加载链中是否抛 "Invalid callback function"
; 镜像 Main.ahk 的 Config + DebugLog + GlobalError 加载顺序
#Requires AutoHotkey v2.0
#ErrorStdOut
#Warn All, StdOut
rf := A_Temp "\_tmp_globalerr.txt"
if FileExist(rf)
    try FileDelete(rf)
#Include "..\..\src\Config\Config.ahk"
#Include "..\..\src\DebugLog\DebugLog.ahk"
#Include "..\..\src\DebugLog\GlobalError.ahk"
try FileAppend "GLOBALERR_OK`n", rf
x := NonExistentFn()  ; 触发运行时错误：若 GlobalErrorHandler 已注册则被捕获，无弹框
try FileAppend "AFTER_ERR`n", rf
ExitApp 0
