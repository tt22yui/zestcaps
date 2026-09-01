#Requires AutoHotkey v2.0
#SingleInstance Force
#ErrorStdOut
#Warn All, Off
; 验证 FileSelect / DirSelect 的参数量，确认是否支持 Hwnd 父窗口参数
testFile := A_Temp "\_tmp_fs_test.txt"
try FileDelete(testFile)
try {
    FileAppend "FileSelect MaxParams=" FileSelect.MaxParams "`n", testFile
    FileAppend "DirSelect MaxParams=" DirSelect.MaxParams "`n", testFile
} catch as err {
    FileAppend "FAIL: " err.Message "`n", testFile
}
ExitApp()
