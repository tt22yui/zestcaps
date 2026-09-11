; 验证钉屏边框可见性与最小化同步：
;   - PinCreateAsync 新建/接管的 4 条边框必须真实可见（回归：Gui.Move 不会显示隐藏窗口，
;     此前「新建边框后只 Move」的路径导致钉屏后看不到边框）
;   - 钉屏窗口最小化 → 边框隐藏（回归：边框是独立顶层窗口，此前最小化后残留在桌面上）
;   - 还原 → 边框重新显现且位置不变
;   - 关闭 → 边框随会话销毁
; 带看门狗（8 秒强制关闭全部钉屏并非零退出），结果写入 %TEMP%\_tmp_pin_borders.txt（用完即删）
#Requires AutoHotkey v2.0
#SingleInstance Force
#ErrorStdOut
#Warn All, StdOut
#Warn All, Off   ; 独立加载 Pin.ahk 时跨模块全局（EditorHwnd/ScreenshotEscCancel 等）静态误报，按项目约定屏蔽

resultFile := A_Temp "\_tmp_pin_borders.txt"
if FileExist(resultFile)
    try FileDelete(resultFile)

#Include "..\..\src\Config\Config.ahk"
#Include "..\..\src\Common\Gdip_All_v2.ahk"
#Include "..\..\src\Screenshot\Common\Overlay.ahk"
#Include "..\..\src\Screenshot\Pin.ahk"

Gdip_Startup()

; 看门狗：8 秒强制关闭全部钉屏并退出（非零退出，超时视为失败）
SetTimer(Watchdog, -8000)
Watchdog() {
    PinEscClose()
    try FileAppend "TIMEOUT 看门狗触发`n", A_Temp "\_tmp_pin_borders.txt"
    ExitApp 1
}

failCount := 0
Check(cond, label) {
    global failCount
    if cond
        FileAppend "PASS " label "`n", resultFile
    else {
        FileAppend "FAIL " label "`n", resultFile
        failCount++
    }
}
Vis(hwnd) => DllCall("IsWindowVisible", "Ptr", hwnd) ? 1 : 0

; 从边框窗口缓存位置推导钉屏主窗口位置/尺寸（分层窗口不做 WinGetPos，理由见 test_pin_resize.ahk 注释）
MainGeom(s, &x, &y, &w, &h) {
    global EDIT_BORDER_WIDTH
    s.borders[1].GetPos(&bx, &by, &bw)
    s.borders[3].GetPos(&lx, &ly, &lw, &lh)
    x := bx + EDIT_BORDER_WIDTH
    y := by + EDIT_BORDER_WIDTH
    w := bw - 2 * EDIT_BORDER_WIDTH
    h := lh
}

; ---- 构造测试原图 240x160（纯色）----
pBmp := Gdip_CreateBitmap(240, 160)
G := Gdip_GraphicsFromImage(pBmp)
pBrush := Gdip_BrushCreateSolid("0xFF3366CC")
Gdip_FillRectangle(G, pBrush, 0, 0, 240, 160)
Gdip_DeleteBrush(pBrush)
Gdip_DeleteGraphics(G)

; ---- 创建钉屏：新建边框路径（不接管既有覆盖层），验证边框立即可见 ----
MonitorGetWorkArea(1, &wl, &wt, &wr, &wb)
hwnd := PinCreateAsync(pBmp, (wl + wr) // 2, (wt + wb) // 2, "center")
s := PinSessions.Get(hwnd, 0)
Check(IsObject(s), "PinCreateAsync 注册会话")
Sleep 300

if s {
    Check(s.borders.Length = 4, "边框 4 条")
    visCount := 0
    for b in s.borders
        visCount += Vis(b.Hwnd)
    Check(visCount = 4, "钉屏后 4 条边框全部可见 (实际 " visCount "/4)")

    MainGeom(s, &wx0, &wy0, &ww0, &wh0)
    Check(ww0 = 240 && wh0 = 160, "窗口 240x160 (实际 " ww0 "x" wh0 ")")
    s.borders[1].GetPos(&bx0, &by0, , )
    Check(bx0 = wx0 - EDIT_BORDER_WIDTH && by0 = wy0 - EDIT_BORDER_WIDTH, "上边框贴窗口外沿")
}

; ---- 最小化：边框必须随之隐藏（否则桌面上残留 4 条蓝边）----
WinMinimize("ahk_id " hwnd)
Sleep 400
if s {
    minMax := WinGetMinMax("ahk_id " hwnd)
    Check(minMax = -1, "钉屏窗口已最小化 (WinGetMinMax=" minMax ")")
    visCount := 0
    for b in s.borders
        visCount += Vis(b.Hwnd)
    Check(visCount = 0, "最小化后边框全部隐藏 (实际可见 " visCount "/4)")
}

; ---- 还原：边框重新显现且位置不变 ----
WinRestore("ahk_id " hwnd)
Sleep 400
if s {
    Check(WinGetMinMax("ahk_id " hwnd) = 0, "钉屏窗口已还原")
    visCount := 0
    for b in s.borders
        visCount += Vis(b.Hwnd)
    Check(visCount = 4, "还原后边框全部可见 (实际 " visCount "/4)")
    MainGeom(s, &wx1, &wy1, &ww1, &wh1)
    Check(wx1 = wx0 && wy1 = wy0 && ww1 = ww0 && wh1 = wh0, "还原后位置尺寸不变 (实际 " wx1 "," wy1 " " ww1 "x" wh1 ")")
    s.borders[1].GetPos(&bx1, &by1, , )
    Check(bx1 = wx1 - EDIT_BORDER_WIDTH && by1 = wy1 - EDIT_BORDER_WIDTH, "还原后上边框仍贴窗口外沿")
}

; ---- 丢失 WM_LBUTTONUP 的自愈：左键未按下时 PinDragTick 应收尾拖动/缩放状态 ----
if s {
    Check(!GetKeyState("LButton", "P"), "前置条件：本测试期间左键未按下")
    ; tx == lastX/lastY → 收尾不会移动窗口，避免影响后续断言
    s.drag := { mx: wx1, my: wy1, wx: wx1, wy: wy1, tx: wx1, ty: wy1, lastX: wx1, lastY: wy1, active: true }
    PinDragTick()
    Check(!s.drag.active, "左键未按下时应收尾拖动状态（自愈，不再黏鼠标）")
    s.resize := { mx: wx1, my: wy1, anchorX: wx1, anchorY: wy1, cornerX: wx1 + ww1, cornerY: wy1 + wh1, initScale: s.scale, txScale: s.scale, appliedScale: s.scale, active: true, previewed: false }
    PinDragTick()
    Check(!s.resize.active, "左键未按下时应收尾缩放状态（自愈）")
    MainGeom(s, &wx2, &wy2, &ww2, &wh2)
    Check(wx2 = wx1 && wy2 = wy1 && ww2 = ww1 && wh2 = wh1, "自愈收尾不应改变窗口位置尺寸")
}

; ---- 关闭：边框随会话销毁 ----
firstHwnd := s ? s.borders[1].Hwnd : 0
WinClose("ahk_id " hwnd)
Sleep 300
Check(!PinSessions.Has(hwnd), "关闭后会话注销")
if firstHwnd
    Check(!WinExist("ahk_id " firstHwnd), "关闭后边框窗口已销毁")

FileAppend "DONE failCount=" failCount "`n", resultFile
; 回显结果到 stdout（重定向/CI 可见）并清理一次性结果文件
try FileAppend FileRead(resultFile), "*"
try FileDelete(resultFile)
ExitApp failCount ? 1 : 0
