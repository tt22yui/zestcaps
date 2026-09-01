; ==================================================================
; 单元测试聚合运行器 —— 依次运行所有 test_unit_*.ahk，汇总结果
; 运行：AutoHotkey64 test\run_all_tests.ahk
; 判定：任一模块失败 → 整体退出码非 0
; 输出：stdout 逐模块结果 + 各模块独立 junit_unit_*.xml（在各模块子目录下）
; 新增单测：往本文件 tests 列表追加相对路径即可
; ==================================================================
#Requires AutoHotkey v2.0
#SingleInstance Force
#ErrorStdOut
#Warn All, StdOut

; 注册的全部单测脚本（按依赖顺序排列；路径相对本文件所在目录）
tests := [
    "Config\test_unit_config.ahk",
    "DebugLog\test_unit_debuglog.ahk",
    "Hotkeys\test_unit_hotkeys.ahk",
]

; 向 stdout 写入（与 YunitStdOut 同策略：无 stdout 管道/重定向时静默跳过）
; AHK 是 GUI 程序：无重定向时 "*" 句柄无效，裸 FileAppend 抛 (6) 句柄无效并弹框，
; try/catch 静默后，有管道时正常回显、无管道时不弹框
StdOut(text) {
    try FileAppend text, "*"
}

total := 0
failTotal := 0
for t in tests {
    total++
    script := A_ScriptDir "\" t
    logFile := A_Temp "\_tmp_unit_run_" A_Index ".log"
    ; AHK Run 原生重定向：stdout+stderr 合并写入临时日志，/ErrorStdOut 双保险
    code := RunWait(Format('"{1}" /ErrorStdOut "{2}" > "{3}" 2>&1', A_AhkPath, script, logFile), , "Hide")
    StdOut("==== " t " (exit=" code ") ====`n")
    if FileExist(logFile) {
        content := FileRead(logFile)
        if content != ""
            StdOut(content)
        if FileExist(logFile)
            try FileDelete(logFile)
    }
    if code != 0 {
        failTotal++
        StdOut(">>> FAIL: " t "`n")
    }
}
StdOut(Format("==== 汇总: {1}/{2} 通过, {3} 失败 ====`n", total - failTotal, total, failTotal))
ExitApp failTotal ? 1 : 0
