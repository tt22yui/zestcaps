; 最小实验：OnError 在 try 块内在前，LogErr 定义在后
#Requires AutoHotkey v2.0
#ErrorStdOut
#Warn All, StdOut
rf := A_Temp "\_tmp_try2.txt"
if FileExist(rf)
    try FileDelete(rf)
try {
    OnError(LogErr)
    FileAppend "TRY2_OK`n", rf
} catch as e {
    FileAppend "TRY2_EXC " Type(e) ": " e.Message "`n", rf
}
LogErr(e) {
    return true
}
ExitApp 0
