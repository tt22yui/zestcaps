#Requires AutoHotkey v2.0
#SingleInstance Force
#ErrorStdOut
#Warn All, Off
; 验证毫秒级时间戳写法（A_MSec 内置变量 + SubStr 补零）用于 DebugLog 精度增强
testFile := A_Temp "\_tmp_timestamp_test.txt"
try FileDelete(testFile)
try {
    ts := FormatTime(, "yyyy-MM-dd HH:mm:ss") "." SubStr("000" A_MSec, -3)
    FileAppend "OK: " ts "`n", testFile
} catch as err {
    FileAppend "FAIL: " err.Message " @" err.Line "`n", testFile
}
ExitApp()
