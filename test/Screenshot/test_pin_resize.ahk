; 验证钉屏缩放（右下角缩放手柄）：
;   - PinClampScale 范围钳制（1/4x ~ 4x）
;   - PinCreateAsync 会话初始状态（尺寸/缩放系数/手柄尺寸）
;   - PinApplyResize 窗口尺寸更新、左上角锚点固定、边框跟随、缩放源重绘
;   - 缩小钳制到下限、关闭后会话注销
; 带看门狗（5 秒强制关闭全部钉屏并退出），结果写入 %TEMP%\_tmp_pin_resize.txt
#Requires AutoHotkey v2.0
#SingleInstance Force
#ErrorStdOut
#Warn All, StdOut
#Warn All, Off   ; 独立加载 Pin.ahk 时跨模块全局（EditorHwnd/ScreenshotEscCancel 等）静态误报，按项目约定屏蔽

resultFile := A_Temp "\_tmp_pin_resize.txt"
if FileExist(resultFile)
    try FileDelete(resultFile)

#Include "..\..\src\Config\Config.ahk"
#Include "..\..\src\Common\Gdip_All_v2.ahk"
#Include "..\..\src\Screenshot\Common\Overlay.ahk"
#Include "..\..\src\Screenshot\Pin.ahk"

Gdip_Startup()

; 看门狗：5 秒强制关闭全部钉屏并退出（防止窗口残留/卡死打扰用户）
SetTimer(Watchdog, -5000)
Watchdog() {
    PinEscClose()
    try FileAppend "TIMEOUT 看门狗触发`n", A_Temp "\_tmp_pin_resize.txt"
    ExitApp 0
}

failCount := 0
Check(cond, label) {
    global failCount
    if cond
        FileAppend "PASS " label "`n", A_Temp "\_tmp_pin_resize.txt"
    else {
        FileAppend "FAIL " label "`n", A_Temp "\_tmp_pin_resize.txt"
        failCount++
    }
}

; 从边框窗口缓存位置推导钉屏主窗口真实位置/尺寸，完全规避对分层窗口 WinGetPos
; （探针实测：分层窗口经 UpdateLayeredWindow 改尺寸后立即 WinGetPos 偶发触发系统消息死锁卡死；
;  边框用 Gui.Move 同步定位、AHK 缓存实时，GetPos 零系统消息、确定性强）
; 边框布局（EDIT_BORDER_WIDTH=3）：
;   top [x-3, y-3, w+6, 3] → 主窗口 x=topX+3, y=topY+3, w=topW-6
;   left[x-3, y, 3, h]     → 主窗口 h=leftH
MainGeom(s, &x, &y, &w, &h) {
    global EDIT_BORDER_WIDTH
    s.borders[1].GetPos(&bx, &by, &bw)
    s.borders[3].GetPos(&lx, &ly, &lw, &lh)
    x := bx + EDIT_BORDER_WIDTH
    y := by + EDIT_BORDER_WIDTH
    w := bw - 2 * EDIT_BORDER_WIDTH
    h := lh
}

; ---- 缩放系数范围钳制（1/4x ~ 4x，对齐 Snipaste）----
Check(PinClampScale(0.1) = 0.25, "PinClampScale 下限 0.1→0.25")
Check(PinClampScale(10) = 4.0, "PinClampScale 上限 10→4")
Check(PinClampScale(2.0) = 2.0, "PinClampScale 中值 2.0 不变")

; ---- 构造测试原图 400x300（纯色，便于比对）----
pBmp := Gdip_CreateBitmap(400, 300)
G := Gdip_GraphicsFromImage(pBmp)
Gdip_SetSmoothingMode(G, 4)
pBrush := Gdip_BrushCreateSolid("0xFFCC3344")
Gdip_FillRectangle(G, pBrush, 0, 0, 400, 300)
Gdip_DeleteBrush(pBrush)
Gdip_DeleteGraphics(G)

; ---- 创建钉屏（锚定显示器工作区中心），验证会话初始状态 ----
MonitorGetWorkArea(1, &wl, &wt, &wr, &wb)
cx := (wl + wr) // 2
cy := (wt + wb) // 2
hwnd := PinCreateAsync(pBmp, cx, cy, "center")
s := PinSessions.Get(hwnd, 0)
Check(IsObject(s), "PinCreateAsync 注册会话")
if s {
    Check(s.winW = 400 && s.winH = 300, "初始窗口尺寸 400x300 (实际 " s.winW "x" s.winH ")")
    Check(s.scale = 1.0, "初始缩放系数 1.0 (实际 " s.scale ")")
    Check(s.handle >= 16, "手柄尺寸 >= 16 (实际 " s.handle ")")
    Check(IsObject(s.borders) && s.borders.Length = 4, "边框数组 4 条")
    MainGeom(s, &wx0, &wy0, &ww0, &wh0)
    Check(ww0 = 400 && wh0 = 300, "窗口实际尺寸 400x300 (实际 " ww0 "x" wh0 ")")
}

; ---- 缩放应用（放大 2x）：窗口尺寸/中心锚定/边框跟随 ----
; 注1：新建钉屏窗口后先等待其/DWM 稳定再缩放——探针实测，窗口创建后立即重绘（且光标悬停其上）偶发与
;     鼠标消息处理死锁（阻塞 GDI+ 绘制）；真实用户拖动手柄时窗口早已稳定，此延时仅保证测试确定性
; 注2：所有位置/尺寸校验一律从边框窗口 Gui.GetPos 缓存推导（MainGeom），零系统消息。
;     分层窗口经 UpdateLayeredWindow 改尺寸后立即 WinGetPos 偶发触发系统级消息死锁（探针实测卡死），
;     边框用 Gui.Move 同步定位、AHK 缓存实时，GetPos 确定性读取、无此风险
Sleep 300
s.resize := { anchorX: wx0, anchorY: wy0, centerX: cx, centerY: cy, cornerX: 0, cornerY: 0, txScale: 2.0, appliedScale: 1.0, active: true }
PinApplyResize(s, hwnd, 2.0)
Sleep 100
MainGeom(s, &wx1, &wy1, &ww1, &wh1)
Check(ww1 = 800 && wh1 = 600, "放大 2x 后窗口 800x600 (实际 " ww1 "x" wh1 ")")
; 预期位置 = 固定左上角锚点推导 + 工作区钳制（与 PinApplyResize 同一公式）
ex1 := Min(Max(wx0, wl), Max(wl, wr - 800))
ey1 := Min(Max(wy0, wt), Max(wt, wb - 600))
Check(wx1 = ex1 && wy1 = ey1, "放大后左上角锚点不动+钳制 (实际 " wx1 "," wy1 " 预期 " ex1 "," ey1 ")")
Check(s.winW = 800 && s.winH = 600, "会话 winW/winH 更新为 800x600")
Check(s.work != 0 && s.scale = 2.0, "会话 work/scale 更新")
s.borders[1].GetPos(&bx1, &by1, , )
Check(bx1 = wx1 - 3 && by1 = wy1 - 3, "上边框贴窗口外沿 (实际 " bx1 "," by1 ")")

; ---- 缩放预览（拖动中轻量重渲染）：尺寸/状态更新、不改 scale、松手全量提交 ----
Sleep 100
s.resize := { anchorX: wx1, anchorY: wy1, centerX: cx, centerY: cy, appliedScale: 1.0, txScale: 1.5, active: true, previewed: false }
PinApplyResizePreview(s, hwnd, 1.5)
Sleep 100
MainGeom(s, &wxp, &wyp, &wwp, &whp)
Check(wwp = 600 && whp = 450, "预览放大 1.5x 后窗口 600x450 (实际 " wwp "x" whp ")")
Check(s.winW = 600 && s.winH = 450, "预览更新会话 winW/winH 为 600x450")
Check(s.scale = 2.0, "预览不改 scale（提交前保持上一提交值 2.0，实际 " s.scale ")")
Check(s.resize.appliedScale = 1.5 && s.resize.previewed, "预览记录 appliedScale=1.5 与 previewed 标记")
expx := Min(Max(wx1, wl), Max(wl, wr - 600))
expy := Min(Max(wy1, wt), Max(wt, wb - 450))
Check(wxp = expx && wyp = expy, "预览左上角锚点不动+钳制 (实际 " wxp "," wyp " 预期 " expx "," expy ")")
; 松手提交：预览后全量精渲 → 窗口 600x450、scale=1.5
PinApplyResize(s, hwnd, 1.5)
Sleep 100
MainGeom(s, &wxc, &wyc, &wwc, &whc)
Check(wwc = 600 && whc = 450, "预览后提交窗口 600x450 (实际 " wwc "x" whc ")")
Check(s.scale = 1.5, "提交后 scale=1.5 (实际 " s.scale ")")

; ---- 缩小钳制（0.1 → 0.25 下限）----
Sleep 100
s.resize.txScale := 0.1
PinApplyResize(s, hwnd, 0.1)
Sleep 100
MainGeom(s, &wx2, &wy2, &ww2, &wh2)
Check(ww2 = 100 && wh2 = 75, "缩小钳制到 0.25x 后窗口 100x75 (实际 " ww2 "x" wh2 ")")
Check(s.winW = 100 && s.winH = 75, "会话 winW/winH 更新为 100x75")
Check(s.scale = 0.25, "会话 scale 钳制为 0.25 (实际 " s.scale ")")

; ---- 关闭钉屏：会话注销 ----
WinClose("ahk_id " hwnd)
Sleep 100
Check(!PinSessions.Has(hwnd), "关闭后会话注销")

FileAppend "DONE failCount=" failCount "`n", resultFile
ExitApp failCount ? 1 : 0
