; 对照：纯 Sleep 脚本，验证沙箱错误是否与运行时长/后台 WeType 写日志有关（无 include、无 GUI）
#Requires AutoHotkey v2.0
#ErrorStdOut
#Warn All, StdOut
try FileAppend "SLEEP_START`n", A_Temp "\_tmp_sleep.txt"
Sleep 3000
try FileAppend "SLEEP_END`n", A_Temp "\_tmp_sleep.txt"
ExitApp 0
