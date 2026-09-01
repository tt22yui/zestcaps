; ==================================================================
; 验证四件套头部（#ErrorStdOut + #Warn All, StdOut）下警告不弹框：
;   触发 VarUnset 警告（引用未赋值的局部变量），预期警告写入 stdout
;   而非默认的 MsgBox 弹框，脚本正常执行完成并输出 DONE。
;   try/catch 兜底运行时错误（#ErrorStdOut 不覆盖运行时错误）。
;   看门狗：若意外弹框阻塞线程，5 秒后强制退出，防止弹框残留。
; 运行：& "C:\Program Files\AutoHotkey\v2\AutoHotkey.exe" test_warn_stdout.ahk *>&1
;   通过检查输出判定：警告应出现在 stdout，且无弹框（管道不会卡 5 秒）。
; ==================================================================
#Requires AutoHotkey v2.0
#SingleInstance Force
#ErrorStdOut
#Warn All, StdOut

; 看门狗：弹框阻塞当前线程时定时器仍会触发，到期强制退出避免残留
SetTimer Watchdog, 5000
Watchdog() {
    ExitApp 1
}

FileAppend "DIAG A_Temp=" A_Temp "`n", "*"   ; 诊断：确认 A_Temp 实际路径（全部走 stdout，避开沙箱写文件限制）

TriggerWarning() {
    localVar := UnsetVar + 1   ; UnsetVar 从未赋值 → 触发 VarUnset 警告（应走 stdout）
    return localVar
}

try {
    r := TriggerWarning()
    FileAppend "DONE r=" r "`n", "*"
    SetTimer Watchdog, 0        ; 正常完成，取消看门狗
    ExitApp 0
} catch as e {
    FileAppend "CAUGHT: " e.Message " @ " e.File ":" e.Line "`n", "*"
    SetTimer Watchdog, 0
    ExitApp 2
}
