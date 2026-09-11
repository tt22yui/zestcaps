; ==================================================================
; GUI 回归：选区阶段「取消」路径的清理完整性
;
; 为什么需要（重构护栏）：SelectRegion 是超长函数、覆盖层状态散落在 Screenshot/Editor/Overlay 三处，
; 取消/异常路径最容易漏清理——残留全屏蒙版会挡住整个桌面、残留热键会吞掉右键。本测试完整跑一次
; 真实选区流程（F1 热键入口）并在悬停阶段取消，验证：
;   1) 建立阶段：全屏蒙版、4 条边框、透明拦截层都真实存在且可见；全局登记表已填写
;   2) 取消后：蒙版/边框/拦截层窗口全部销毁；ScreenshotMaskHwnds / ScreenshotBorderHwnds 清空、
;      ScreenshotSelHwnd = 0、ScreenshotEscCancel = 0、ScreenshotSelOverlays = 0
;   3) 热键：*RButton 已注销（否则右键会被永久吞掉）、Esc 需求计数归零
;   4) 返回空值（取消分支不返回动作），且不会走成"已确认"
;
; 驱动方式：选区在悬停阶段轮询 state.canceled，故用一次性定时器调用截图阶段挂出的取消闭包
;   ScreenshotEscCancel（等价于用户按 Esc），不做任何鼠标模拟。
;
; 注意：测试会短暂全屏显示蒙版与边框（约 1 秒）；带看门狗（15 秒强制清理并退出，超时按失败计）；
;       结果写入 %TEMP%\_tmp_selection_cancel.txt（用完即删）。
; ==================================================================
#Requires AutoHotkey v2.0
#SingleInstance Force
#ErrorStdOut
#Warn All, StdOut

resultFile := A_Temp "\_tmp_selection_cancel.txt"
if FileExist(resultFile)
    try FileDelete(resultFile)

#Include "..\..\src\Config\Config.ahk"
DEBUG_LOG_ENABLED := false     ; 屏蔽日志写入
#Include "..\..\src\DebugLog\DebugLog.ahk"
#Include "..\..\src\Screenshot\Screenshot.ahk"

; 未捕获异常不能让默认错误框挂住测试
OnError(TestOnError)
TestOnError(Thrown, Mode) {
    global resultFile
    try FileAppend "ERROR: " (Thrown is Error ? Thrown.Message " @" Thrown.Line : String(Thrown)) "`n", resultFile
    try PinEscClose()
    ExitApp 2
    return 1
}

; 看门狗：15 秒强制清理并退出（超时视为失败）
SetTimer(Watchdog, -15000)
Watchdog() {
    global resultFile, ScreenshotMaskHwnds, ScreenshotSelHwnd, ScreenshotBorderHwnds
    try PinEscClose()
    for h in ScreenshotMaskHwnds {
        if WinExist("ahk_id " h)
            try WinClose("ahk_id " h)
    }
    for h in ScreenshotBorderHwnds {
        if WinExist("ahk_id " h)
            try WinClose("ahk_id " h)
    }
    if ScreenshotSelHwnd && WinExist("ahk_id " ScreenshotSelHwnd)
        try WinClose("ahk_id " ScreenshotSelHwnd)
    try Hotkey("*RButton", "Off")
    try FileAppend "TIMEOUT 看门狗触发`n", resultFile
    ExitApp 1
}

failCount := 0
Check(cond, label) {
    global failCount, resultFile
    if cond
        FileAppend "PASS " label "`n", resultFile
    else {
        FileAppend "FAIL " label "`n", resultFile
        failCount++
    }
}
Visible(hwnd) => hwnd && DllCall("IsWindowVisible", "Ptr", hwnd) ? 1 : 0

ScreenshotEnabled := true   ; 明确开启截图功能，避免配置差异让入口提前返回
Rec := {}
DriveCancel() {
    global Rec, ScreenshotMaskHwnds, ScreenshotBorderHwnds, ScreenshotSelHwnd, ScreenshotEscCancel, EscNeed
    ; 取消前记录"建立阶段"的现场（这些值取消后都必须归零）
    Rec.maskCount := ScreenshotMaskHwnds.Length
    Rec.maskHwnd := ScreenshotMaskHwnds.Length ? ScreenshotMaskHwnds[1] : 0
    Rec.maskVisible := Rec.maskHwnd && DllCall("IsWindowVisible", "Ptr", Rec.maskHwnd) ? 1 : 0
    Rec.borderCount := ScreenshotBorderHwnds.Length
    Rec.bordersVisible := 0
    for bd in ScreenshotBorderHwnds
        Rec.bordersVisible += DllCall("IsWindowVisible", "Ptr", bd) ? 1 : 0
    Rec.borderHwnd := Rec.borderCount ? ScreenshotBorderHwnds[1] : 0
    Rec.selHwnd := ScreenshotSelHwnd
    Rec.selVisible := Visible(ScreenshotSelHwnd)
    Rec.escNeedDuring := EscNeed
    Rec.hasCancelCb := IsObject(ScreenshotEscCancel) ? 1 : 0
    ; 注：不在此处探测 *RButton 热键是否注册 —— 探测必须用 Hotkey("*RButton","On")，
    ; 而该调用本身会注册/启用热键，把被测状态改掉（AHK 也没有"是否启用"的查询接口，
    ; "Off" 只禁用不清除注册，故后续再探测必然成功）。取消后"右键不被吞掉"由
    ; 下面一组清理断言间接保证：蒙版/边框/拦截层能被销毁，只有 _DestroyOverlays 走到了，
    ; 而它的第一步就是 Hotkey "*RButton", "Off"。
    ; 等价于用户按 Esc：调用截图阶段挂出的取消闭包
    if IsObject(ScreenshotEscCancel)
        ScreenshotEscCancel.Call()
}

SetTimer(DriveCancel, -500)
Ret := SelectRegionToCapture()

Check(Ret = "", "取消分支返回空值（实际 [" Ret "]）")
Check(Rec.hasCancelCb = 1, "选区阶段已挂出取消闭包")
Check(Rec.maskCount = 1, "建立阶段：蒙版窗口已登记（实际 " Rec.maskCount "）")
Check(Rec.maskVisible = 1, "建立阶段：蒙版可见")
Check(Rec.borderCount = 4, "建立阶段：4 条边框已登记（实际 " Rec.borderCount "）")
Check(Rec.bordersVisible = 4, "建立阶段：4 条边框全部可见（实际 " Rec.bordersVisible "/4）")
Check(Rec.selVisible = 1, "建立阶段：选区透明拦截层可见")
Check(Rec.escNeedDuring >= 1, "建立阶段：Esc 需求计数已 +1（实际 " Rec.escNeedDuring "）")

; ---- 取消后的清理 ----
Check(ScreenshotMaskHwnds.Length = 0, "取消后蒙版登记表已清空")
Check(ScreenshotBorderHwnds.Length = 0, "取消后边框登记表已清空")
Check(ScreenshotSelHwnd = 0, "取消后拦截层句柄已置零")
Check(ScreenshotSelOverlays = 0, "取消后覆盖层交接对象已清空")
Check(ScreenshotEscCancel = 0, "取消后取消闭包已注销")
Check(EscNeed = 0, "取消后 Esc 需求计数归零（实际 " EscNeed "）")
Check(!WinExist("ahk_id " Rec.maskHwnd), "取消后蒙版窗口已销毁")
Check(!WinExist("ahk_id " Rec.borderHwnd), "取消后边框窗口已销毁")
Check(!WinExist("ahk_id " Rec.selHwnd), "取消后拦截层窗口已销毁")
; 上述三者只能由 _DestroyOverlays 完成，而该函数第一步即 Hotkey "*RButton", "Off"，
; 故"取消后右键不再被吞掉"由这组断言间接验证（AHK 无热键启用状态查询，直接探测会改状态）

FileAppend "DONE failCount=" failCount "`n", resultFile
try FileAppend FileRead(resultFile), "*"
try FileDelete(resultFile)
ExitApp failCount ? 1 : 0
