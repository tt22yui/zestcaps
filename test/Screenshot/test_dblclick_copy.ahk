; 验证选区微调「双击选区 → 直接复制并关闭截图」的判定逻辑：
;   - _IsSelectionDoubleClick 双击判定（首按 false / 同点快速次按 true / 位移阈值内 true /
;     位移超 4px false / 超过系统双击时间 false / 重置后再次双击 true）
; 双击仅写入 state.action := "copy"，输出链路复用工具栏「复制」的 case "copy"（既有路径），
; 此处只验证新增的判定逻辑本身；纯逻辑无窗口，无需看门狗；结果写入 %TEMP%\_tmp_dblclick_copy.txt
#Requires AutoHotkey v2.0
#SingleInstance Force
#ErrorStdOut
#Warn All, StdOut
#Warn All, Off   ; 独立加载 Screenshot 模块链时跨模块全局静态误报，按项目约定屏蔽

resultFile := A_Temp "\_tmp_dblclick_copy.txt"
if FileExist(resultFile)
    try FileDelete(resultFile)

#Include "..\..\src\Config\Config.ahk"
#Include "..\..\src\DebugLog\DebugLog.ahk"
#Include "..\..\src\Screenshot\Screenshot.ahk"

failCount := 0
Check(cond, label) {
    global failCount
    if cond
        FileAppend "PASS " label "`n", A_Temp "\_tmp_dblclick_copy.txt"
    else {
        FileAppend "FAIL " label "`n", A_Temp "\_tmp_dblclick_copy.txt"
        failCount++
    }
}

; ---- 双击判定序列（static 状态按调用顺序推进，与真实两次按下的时序一致）----
; 阈值取系统双击矩形（SM_CXDOUBLECLK/SM_CYDOUBLECLK，默认各 4px），测试随系统设置自适应
dx := DllCall("GetSystemMetrics", "Int", 36)
dy := DllCall("GetSystemMetrics", "Int", 37)
Check(dx >= 4 && dy >= 4, "系统双击矩形 >= 4px (实际 " dx "x" dy ")")
; 首按必然 false（仅记录状态）
Check(!_IsSelectionDoubleClick(100, 100), "首按返回 false")
; 同点快速次按 → 判定双击
Check(_IsSelectionDoubleClick(100, 100), "同点快速次按判定双击")
; 位移不超过系统双击矩形（边界）仍判定双击
Check(_IsSelectionDoubleClick(100 + dx, 100), "位移在系统双击矩形内判定双击")
; 位移超过系统双击矩形（相对上一步位置再超出 dx）→ 判为两次单击
Check(!_IsSelectionDoubleClick(100 + 2 * dx + 2, 100), "位移超系统双击矩形判定非双击")
; 超过系统双击时间 → 判为两次单击
dct := DllCall("GetDoubleClickTime")
Sleep dct + 100
Check(!_IsSelectionDoubleClick(100 + 2 * dx + 2, 100), "超时判定非双击")
; 超时后同点快速次按 → 又判定双击（状态已重置）
Check(_IsSelectionDoubleClick(100 + 2 * dx + 2, 100), "重置后快速次按判定双击")

FileAppend "DONE failCount=" failCount "`n", resultFile
ExitApp failCount ? 1 : 0
