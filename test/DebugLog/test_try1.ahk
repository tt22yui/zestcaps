; 最小实验：LogErr 先定义，OnError 在 try 块内 —— 是否抛 "Invalid callback function"？
#Requires AutoHotkey v2.0
#ErrorStdOut
#Warn All, StdOut
rf := A_Temp "\_tmp_try1.txt"
if FileExist(rf)
    try FileDelete(rf)
LogErr(e) {
    return true
}
try {
    OnError(LogErr)
    FileAppend "TRY1_OK`n", rf
} catch as e {
    FileAppend "TRY1_EXC " Type(e) ": " e.Message "`n", rf
}
ExitApp 0
