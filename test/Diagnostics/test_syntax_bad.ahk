; 阳性对照脚本：故意含语法错误，仅用于验证 Start-Process + #ErrorStdOut 能捕获编译错误
; （预期 EXIT=2 且 stderr 有报错）。请勿当作正常脚本运行。
#Requires AutoHotkey v2.0
#ErrorStdOut
#Warn All, StdOut
THIS IS NOT VALID AHK ((((
ExitApp 0
