; ==================================================================
; GUI 回归：工具栏悬停/选中态状态机与颜色
;
; 为什么需要（重构护栏）：ToolbarUI.ahk 的悬停状态机（HoverEaseTick / ToolbarHoverState.Apply /
; HoverLerpColor）是长函数且带定时器，视觉改动很容易只靠肉眼验证。本测试把「颜色」变成可断言数据：
; 通过给控件父窗口发 WM_CTLCOLORSTATIC 读回它当前使用**背景刷子的真实颜色**，逐态校验：
;   1) HoverLerpColor 纯函数：端点与中点插值（通道级四舍五入）
;   2) 普通态：Apply(sel=false) 且无悬停 → 立刻落到普通底色，且不启动渐变
;   3) 悬停态：ctrl=按钮 → 启动渐变，~72ms 后自停并落定悬停底色（回归：定时器必须自清理）
;   4) 选中态：Apply(sel=true) → 即时切换选中底色并取消进行中的渐变（不被渐变覆盖）
;   5) 离开选中：选中 → 普通 也要走渐变落定
;   6) 工具栏销毁后：HoverEaseTick 遍历到已销毁控件必须安全退出并清理 Map（回归：残留定时器报错）
;   7) ClearTransient：销毁工具栏时清空渐变/底色暂存（Map 不残留控件引用）
;
; 注意：测试会短暂创建一个小工具栏窗口（约 1 秒）；带看门狗（15 秒强制销毁并退出，超时按失败计）；
;       结果写入 %TEMP%\_tmp_toolbar_hover.txt（用完即删）。
; ==================================================================
#Requires AutoHotkey v2.0
#SingleInstance Force
#ErrorStdOut
#Warn All, StdOut

resultFile := A_Temp "\_tmp_toolbar_hover.txt"
if FileExist(resultFile)
    try FileDelete(resultFile)

#Include "..\..\src\Config\Config.ahk"
DEBUG_LOG_ENABLED := false
#Include "..\..\src\DebugLog\DebugLog.ahk"
#Include "..\..\src\Common\Gdip_All_v2.ahk"
#Include "..\..\src\Screenshot\Common\ToolbarUI.ahk"

OnError(TestOnError)
TestOnError(Thrown, Mode) {
    global resultFile, hvGui
    try FileAppend "ERROR: " (Thrown is Error ? Thrown.Message " @" Thrown.Line : String(Thrown)) "`n", resultFile
    if IsObject(hvGui)
        try hvGui.Destroy()
    ExitApp 2
    return 1
}

SetTimer(Watchdog, -15000)
Watchdog() {
    global resultFile, hvGui
    if IsObject(hvGui)
        try hvGui.Destroy()
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

; 读回控件当前背景刷子颜色（RRGGBB）：给父窗口发 WM_CTLCOLORSTATIC(0x0138)，
; 取回的 HBRUSH 用 GetObject 读 LOGBRUSH.lbColor（COLORREF 为 0x00BBGGRR）
CtrlBackColor(ctrl, parentHwnd) {
    hdc := DllCall("GetDC", "ptr", ctrl.Hwnd, "ptr")
    hbr := DllCall("SendMessage", "ptr", parentHwnd, "uint", 0x0138, "ptr", hdc, "ptr", ctrl.Hwnd, "ptr")
    DllCall("ReleaseDC", "ptr", ctrl.Hwnd, "ptr", hdc)
    if !hbr
        return ""
    buf := Buffer(16, 0)
    if !DllCall("GetObject", "ptr", hbr, "int", 12, "ptr", buf)
        return ""
    c := NumGet(buf, 4, "UInt")
    return Format("{:02X}{:02X}{:02X}", c & 0xFF, (c >> 8) & 0xFF, (c >> 16) & 0xFF)
}

; ==================================================================
; 1) 纯函数：颜色通道插值
; ==================================================================
Check(HoverLerpColor("20222A", "2A2D36", 0) = "20222A", "t=0 取起点色")
Check(HoverLerpColor("20222A", "2A2D36", 1) = "2A2D36", "t=1 取终点色")
Check(HoverLerpColor("20222A", "2A2D36", 0.5) = "252830", "t=0.5 通道中点（实际 " HoverLerpColor("20222A", "2A2D36", 0.5) "）")
Check(HoverLerpColor("000000", "FFFFFF", 0.5) = "808080", "黑白中点为 808080（实际 " HoverLerpColor("000000", "FFFFFF", 0.5) "）")
Check(HoverLerpColor("123456", "123456", 0.7) = "123456", "同色插值不变")

; ==================================================================
; 2) 建立工具栏窗口与悬停状态实例
; ==================================================================
hvGui := Gui("-Caption +AlwaysOnTop -DPIScale ToolWindow")
hvGui.BackColor := EDIT_TB_BG
hvState := ToolbarHoverState()
hvBtn := hvState.AddIcon(hvGui, "T", "Segoe UI Symbol", (*) => 0, "测试按钮")
hvGui.Show("NA x0 y0 w200 h60")
Sleep 150
Check(IsObject(hvBtn) && hvBtn.Hwnd ? true : false, "按钮控件已创建")
Check(hvState.btns.Length = 1, "按钮已登记到悬停状态（实际 " hvState.btns.Length "）")

; ---- 普通态（无悬停）：即时落普通底色，不启动渐变 ----
hvState.Apply(hvBtn, false)
Sleep 60
Check(!_HoverEase.Has(hvBtn), "普通态不启动渐变")
Check(CtrlBackColor(hvBtn, hvGui.Hwnd) = EDIT_TB_BTN_BG, "普通态背景色=" EDIT_TB_BTN_BG "（实际 " CtrlBackColor(hvBtn, hvGui.Hwnd) "）")

; ---- 悬停态：启动渐变 → 等待自停 → 落定悬停底色 ----
hvState.ctrl := hvBtn
hvState.Apply(hvBtn, false)
Check(_HoverEase.Has(hvBtn), "悬停态启动了背景渐变")
hvSt := _HoverEase.Has(hvBtn) ? _HoverEase[hvBtn] : 0
Sleep 300   ; 6 步 × 12ms ≈ 72ms，留足余量
Check(!_HoverEase.Has(hvBtn), "渐变结束后自动清理（定时器不残留）")
Check(IsObject(hvSt) && hvSt.step >= hvSt.total, "渐变步进走满（实际 " (IsObject(hvSt) ? hvSt.step : -1) "/" (IsObject(hvSt) ? hvSt.total : -1) "）")
Check(CtrlBackColor(hvBtn, hvGui.Hwnd) = EDIT_TB_BTN_HOVER, "悬停态落定背景色=" EDIT_TB_BTN_HOVER "（实际 " CtrlBackColor(hvBtn, hvGui.Hwnd) "）")

; ---- 选中态：即时切换并取消进行中的渐变 ----
hvState.ctrl := 0
hvState.Apply(hvBtn, true)
Sleep 60
Check(!_HoverEase.Has(hvBtn), "选中态不启动渐变（即时切换）")
Check(CtrlBackColor(hvBtn, hvGui.Hwnd) = EDIT_TB_BTN_SEL, "选中态背景色=" EDIT_TB_BTN_SEL "（实际 " CtrlBackColor(hvBtn, hvGui.Hwnd) "）")

; ---- 离开选中 → 普通：仍走渐变落定 ----
hvState.Apply(hvBtn, false)
Check(_HoverEase.Has(hvBtn), "选中→普通 启动渐变")
Sleep 300
Check(CtrlBackColor(hvBtn, hvGui.Hwnd) = EDIT_TB_BTN_BG, "离开选中后落回普通底色（实际 " CtrlBackColor(hvBtn, hvGui.Hwnd) "）")

; ==================================================================
; 3) 控件已销毁时的安全退出（回归：残留定时器不应报错，且 Map 要清理）
; ==================================================================
ghostGui := Gui("-Caption +AlwaysOnTop -DPIScale ToolWindow")
ghostBtn := ghostGui.Add("Text", "x0 y0 w30 h24 Background" EDIT_TB_BTN_BG, "G")
ghostGui.Show("NA x0 y0 w60 h30")
Sleep 100
HoverEaseStart(ghostBtn, EDIT_TB_BTN_BG, EDIT_TB_BTN_HOVER, EDIT_TB_BTN_TEXT)
ghostSt := _HoverEase.Has(ghostBtn) ? _HoverEase[ghostBtn] : 0
ghostGui.Destroy()
Sleep 120
if IsObject(ghostSt)
    _HoverEase[ghostBtn] := ghostSt     ; 重新挂上，确保此次 tick 命中"窗口已销毁"分支
HoverEaseTick(ghostSt)                  ; 不得抛错（抛错会被 OnError 记为 ERROR 并退出 2）
Check(!_HoverEase.Has(ghostBtn), "控件销毁后 tick 安全退出并清理 Map 条目")

; ==================================================================
; 4) ClearTransient：清空渐变与底色暂存
; ==================================================================
hvState.ctrl := hvBtn
hvState.Apply(hvBtn, false)
Check(_HoverEase.Has(hvBtn) || _HoverLast.Has(hvBtn), "前置条件：渐变或底色暂存已被占用")
hvState.ClearTransient()
Check(!_HoverEase.Has(hvBtn), "ClearTransient 清空渐变条目")
Check(!_HoverLast.Has(hvBtn), "ClearTransient 清空底色暂存")

hvGui.Destroy()
FileAppend "DONE failCount=" failCount "`n", resultFile
try FileAppend FileRead(resultFile), "*"
try FileDelete(resultFile)
ExitApp failCount ? 1 : 0
