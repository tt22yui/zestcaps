; ==================================================================
; GUI 回归测试聚合运行器 —— 依次运行所有「窗口类」集成测试，汇总结果
; 运行：AutoHotkey64 test\run_gui_tests.ahk
; 判定：任一模块失败（退出码非 0）→ 整体退出码非 0
;
; 与 run_all_tests.ahk 的分工：
;   - run_all_tests.ahk：Yunit 纯逻辑单测（无窗口、CI 里跑）；
;   - 本文件：会创建真实窗口的 GUI/交互回归测试（需要可交互桌面，本地跑，CI 默认不跑）。
;
; 前置要求：每个 GUI 测试必须自带看门狗（超时自杀），否则本运行器会一起挂住。
; 提示：运行期间屏幕上会短暂出现工具栏/蒙版/编辑窗/钉屏等窗口（每个用例约 1~3 秒）。
;
; 未纳入本套件（原因）：
;   - test\Startup、test\DesktopShortcut：会真实创建/删除开始菜单与桌面快捷方式，副作用落到用户系统；
;   - test\Splash、test\TrayMenu、test\Load\*：加载型检查，已由 test\Load\test_main_load.ahk 覆盖。
; ==================================================================
#Requires AutoHotkey v2.0
#SingleInstance Force
#ErrorStdOut
#Warn All, StdOut

tests := [
    ; 工具栏 / 覆盖层
    "Screenshot\test_toolbar_dpi.ahk",
    "Screenshot\test_toolbar_promote.ahk",
    "Screenshot\test_toolbar_hover.ahk",
    "Screenshot\test_dblclick_copy.ahk",
    ; 选区 → 编辑 → 钉屏 全流程
    "Screenshot\test_selection_cancel.ahk",
    "Screenshot\test_editor_lifecycle.ahk",
    "Screenshot\test_pin_borders.ahk",
    "Screenshot\test_pin_resize.ahk",
    ; 设置窗口
    "Settings\test_settings_gui.ahk",
]

; 向 stdout 写入（无重定向时 "*" 句柄无效，try 静默：与 run_all_tests.ahk 同策略）
StdOut(text) {
    try FileAppend text, "*"
}

total := 0
failTotal := 0
for t in tests {
    total++
    script := A_ScriptDir "\" t
    logFile := A_Temp "\_tmp_gui_run_" A_Index ".log"
    ; AHK RunWait 原生重定向：stdout+stderr 合并写入临时日志
    code := RunWait(Format('"{1}" /ErrorStdOut "{2}" > "{3}" 2>&1', A_AhkPath, script, logFile), , "Hide")
    StdOut("==== " t " (exit=" code ") ====`n")
    if FileExist(logFile) {
        ; 只回显失败/错误/汇总行，避免每个用例的 PASS 明细刷屏（需要明细时单跑该用例）
        content := FileRead(logFile)
        for line in StrSplit(content, "`n") {
            if (line ~= "^(FAIL|ERROR|TIMEOUT|DONE)")
                StdOut("  " line "`n")
        }
        try FileDelete(logFile)
    }
    if code != 0 {
        failTotal++
        StdOut(">>> FAIL: " t "`n")
    }
}
StdOut(Format("==== 汇总: {1}/{2} 通过, {3} 失败 ====`n", total - failTotal, total, failTotal))
ExitApp failTotal ? 1 : 0
