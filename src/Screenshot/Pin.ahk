; ==================================================================
; 截图钉屏（支持多实例）
; 将截图（含标注）以置顶窗口显示，可拖动，右键关闭单个，Esc 关闭全部
;
; 多钉屏原理：每个钉屏窗口一个会话（PinSessions: hwnd → 状态对象），
; 拖动/关闭等消息钩子常驻注册，按 hwnd 查表分发，互不干扰。
; 两种来源：
;   1) 就地钉屏（推荐，无感）：编辑窗点击「钉屏」后不关窗，仅移除工具栏/蒙版，
;      画面原地保留并注册为钉屏会话 —— 见 Editor.ahk 的 EditorPinInPlace()
;   2) 独立钉屏：ShowPin(pBitmap) 弹出新窗口接管位图（通用入口）
;
; 依赖：Gdip 库（src\Common\Gdip_All_v2.ahk，由 Screenshot.ahk 先行引入）
; ==================================================================

; ------------------------------------------------------------------
; 钉屏全局状态（模块内维护）
; ------------------------------------------------------------------
global PinSessions := Map()  ; 活跃钉屏窗口：hwnd → { hwnd, gui, borders, winW, winH, drag, resize, src, work, imgW, imgH, scale, handle }
                              ; borders：覆盖层边框数组（Common\Overlay.ahk，就地从选区/编辑器接管或新建，关闭时释放）
                              ; drag：拖动状态；resize：右下角手柄缩放状态（previewed 标记拖动中是否已走轻量预览，松手据此触发全量精渲提交）
                              ; src：缩放源位图（原图分辨率，缩放重绘用；编辑器来源为原图+标注的合成图）
                              ; work：当前显示工作位图（窗口尺寸，关闭/替换时释放）
                              ; imgW/imgH：src 原始尺寸；scale：当前缩放系数（winW/imgW，等比）
                              ; handle：右下角缩放手柄像素尺寸
global EscNeed := 0          ; Esc 热键需求计数（编辑主循环 / 钉屏会话各 +1，归零时注销热键）

; 钉屏交互消息钩子：模块加载时注册一次，按会话表分发（非钉屏窗口直接忽略）
OnMessage(0x201, PinLButtonDown)
OnMessage(0x200, PinMouseMove)
OnMessage(0x202, PinLButtonUp)
OnMessage(0x204, PinRButtonDown)

; ------------------------------------------------------------------
; Esc 热键需求管理（编辑 / 钉屏流程间共享，统一分发）
; ------------------------------------------------------------------
; 需求 +1 并确保热键注册（回调固定为统一分发函数，按当前状态分流）
EscRegister() {
    global EscNeed
    EscNeed++
    Hotkey "Esc", EditorEscDispatch, "On"
}

; 需求 -1，归零时注销热键
EscUnregister() {
    global EscNeed
    if EscNeed > 0
        EscNeed--
    if EscNeed = 0
        Hotkey "Esc", "Off"
}

; 统一 Esc 分发（编辑 / 截图选区 / 钉屏 共享热键，按当前状态分流）：
;   1) 截图选区阶段：取消选区
;   2) 编辑窗存在：取消编辑
;   3) 否则：关闭全部钉屏
EditorEscDispatch(*) {
    global EditorHwnd, ScreenshotEscCancel
    if ScreenshotEscCancel {
        ScreenshotEscCancel.Call()   ; 截图选区：取消选区（Screenshot.ahk 设置）
        return
    }
    if WinExist("ahk_id " EditorHwnd) {
        EditorEscClose()             ; 编辑模式：取消当前编辑（Editor.ahk 定义）
        return
    }
    PinEscClose()                    ; 钉屏模式：关闭全部钉屏
}

; ------------------------------------------------------------------
; 钉屏会话注册 / 注销
; ------------------------------------------------------------------
PinRegister(hwnd, gui, borders, winW, winH, srcBmp, work, imgW, imgH, handle) {
    global PinSessions
    PinSessions[hwnd] := { hwnd: hwnd, gui: gui, borders: borders, winW: winW, winH: winH, drag: 0, resize: 0, src: srcBmp, work: work, imgW: imgW, imgH: imgH, scale: winW / imgW, handle: handle }
    EscRegister()
}
PinRemove(hwnd) {
    global PinSessions
    PinSessions.Delete(hwnd)
    EscUnregister()
}

; ------------------------------------------------------------------
; 创建钉屏窗口并注册会话（不阻塞）
; pBitmap：待钉屏的 GDI+ bitmap（原图分辨率），由钉屏会话接管，窗口关闭时自动释放
; centerX/centerY：可选，定位锚点（屏幕坐标）；缺省时以鼠标所在显示器中心定位
; align："center"（默认）以锚点为窗口中心居中；"topleft" 以锚点为窗口左上角
;   （选区钉屏传选区左上角：窗口与选区视觉连续，无跳位；缩图时从选区左上角向右下展开，更符合直觉）
; inheritedBorders：可选，接管既有覆盖层边框（Common\Overlay.ahk 组件，选区/编辑器就地移交），
;   钉屏窗口与选区/编辑器共用同一套天蓝边框，视觉连续；缺省则新建
; 返回值：钉屏窗口 hwnd
; ------------------------------------------------------------------
PinCreateAsync(pBitmap, centerX := "", centerY := "", align := "center", inheritedBorders := 0) {
    global PIN_MAX_RATIO

    Gdip_GetImageDimensions(pBitmap, &imgW, &imgH)

    ; 定位显示器：优先用锚点，缺省用鼠标所在显示器
    if (centerX = "" || centerY = "") {
        MouseGetPos &mx, &my
        MonitorGetWorkArea(MonitorIndexAt(mx, my), &wl, &wt, &wr, &wb)
        cx := wl + (wr - wl) // 2
        cy := wt + (wb - wt) // 2
    } else {
        MonitorGetWorkArea(MonitorIndexAt(centerX, centerY), &wl, &wt, &wr, &wb)
        cx := centerX
        cy := centerY
    }
    ; 等比缩放适配目标显示器工作区（只缩小不放大，防止超屏）
    scale := Min(1.0, (wr - wl) * PIN_MAX_RATIO / imgW, (wb - wt) * PIN_MAX_RATIO / imgH)
    winW := Round(imgW * scale)
    winH := Round(imgH * scale)
    if (align = "topleft") {
        ; 左上角锚定：窗口左上角对准锚点（钳制在工作区内）
        x := Min(Max(cx, wl), wr - winW)
        y := Min(Max(cy, wt), wb - winH)
    } else {
        ; 中心锚定（默认）：以锚点居中，并钳制在工作区内（防止窗口超出屏幕）
        x := Min(Max(cx - winW // 2, wl), wr - winW)
        y := Min(Max(cy - winH // 2, wt), wb - winH)
    }

    ; 分层窗口：把图片渲染为窗口内容
    pinGui := Gui("-Caption +AlwaysOnTop -DPIScale +E0x80000")
    pinGui.MarginX := 0
    pinGui.MarginY := 0
    pinGui.Show("NA x" x " y" y " w" winW " h" winH)
    hwnd := pinGui.Hwnd
    handle := PinHandleSize(hwnd)   ; 右下角缩放手柄像素尺寸（按窗口 DPI 缩放）

    pWork := Gdip_CreateBitmap(winW, winH)
    G := Gdip_GraphicsFromImage(pWork)
    Gdip_SetSmoothingMode(G, 4)
    Gdip_DrawImage(G, pBitmap, 0, 0, winW, winH, 0, 0, imgW, imgH)
    PinDrawGrip(G, winW, winH, handle)  ; 右下角叠加缩放手柄
    Gdip_DeleteGraphics(G)
    _PinUpdateLayer(hwnd, pWork)

    ; 覆盖层边框：优先接管既有（选区/编辑器就地移交，三阶段同一套天蓝框），否则新建；
    ; 围绕钉屏窗口，拖动/缩放时跟随、关闭时随会话释放
    borders := inheritedBorders
    if !IsObject(borders)
        borders := BorderStripsCreate()
    BorderStripsMove(borders, x, y, winW, winH)

    ; 注册为钉屏会话（消息钩子常驻，按 hwnd 分发；位图/尺寸随会话保存，缩放/关闭复用）
    PinRegister(hwnd, pinGui, borders, winW, winH, pBitmap, pWork, imgW, imgH, handle)

    ; 不阻塞等待关闭：清理挂到窗口 Close 事件（右键 / Esc → WinClose → WM_CLOSE 触发），
    ; 调用方立即返回，可继续截/钉下一张图（多张钉屏）
    pinGui.OnEvent("Close", (*) => PinCleanupAsync(hwnd))
    return hwnd
}

; 钉屏会话关闭清理（Close 事件回调）：注销会话并释放位图资源与覆盖层边框
; 每步独立 try 保护：单项失败不阻断其余资源释放
PinCleanupAsync(hwnd) {
    s := PinSessions.Get(hwnd, 0)
    if s {
        BorderStripsDestroy(s.borders)  ; 释放钉屏会话持有的覆盖层边框
        try Gdip_DisposeImage(s.work)   ; 释放当前显示工作位图（缩放替换过的旧位图已即时释放）
        try Gdip_DisposeImage(s.src)    ; 释放缩放源位图
        try PinRemove(hwnd)
    }
    return 0
}

; ------------------------------------------------------------------
; 独立钉屏（阻塞，通用入口）：创建钉屏窗口，等待用户关闭后返回
; ------------------------------------------------------------------
ShowPin(pBitmap, centerX := "", centerY := "") {
    hwnd := PinCreateAsync(pBitmap, centerX, centerY)
    try WinWaitClose("ahk_id " hwnd)
}

; 把工作 bitmap 渲染到钉屏分层窗口
_PinUpdateLayer(hwnd, pBmp) {
    Gdip_GetImageDimensions(pBmp, &w, &h)
    hBitmap := Gdip_CreateHBITMAPFromBitmap(pBmp)
    hdc := CreateCompatibleDC()
    obm := SelectObject(hdc, hBitmap)
    UpdateLayeredWindow(hwnd, hdc, , , w, h)
    SelectObject(hdc, obm)
    DeleteObject(hBitmap)
    DeleteDC(hdc)
}

; ------------------------------------------------------------------
; 缩放手柄（右下角）辅助
; ------------------------------------------------------------------
; 手柄像素尺寸：按窗口 DPI 缩放（GetDpiForWindow，回退 A_ScreenDPI），最小 16px 保证可点
PinHandleSize(hwnd) {
    dpi := 96
    try dpi := DllCall("GetDpiForWindow", "Ptr", hwnd, "UInt")
    if !dpi
        dpi := A_ScreenDPI
    return Max(16, Round(20 * dpi / 96))
}

; 在 graphics 右下角绘制缩放手柄（3 条斜线），w/h 为位图尺寸，handle 为手柄像素尺寸
; 深色主 + 浅色偏移描边两遍绘制，保证深/浅底色画面上都可见
PinDrawGrip(G, w, h, handle) {
    pad := Max(2, handle // 4)   ; 距右下角内边距
    step := Max(4, handle // 4)  ; 斜线间距
    loop 2 {
        pen := Gdip_CreatePen(A_Index = 1 ? "0xC0000000" : "0xC0FFFFFF", Max(1, handle // 10))
        off := A_Index = 2 ? 1 : 0  ; 浅色描边向右下偏移 1px
        loop 3 {
            k := A_Index
            Gdip_DrawLine(G, pen, w - pad - k * step + off, h - pad + off, w - pad + off, h - pad - k * step + off)
        }
        Gdip_DeletePen(pen)
    }
}

; 在已有位图右下角叠加缩放手柄（编辑窗就地钉屏等已渲染完成位图复用）
PinDrawGripOnto(pBmp, handle) {
    Gdip_GetImageDimensions(pBmp, &w, &h)
    G := Gdip_GraphicsFromImage(pBmp)
    Gdip_SetSmoothingMode(G, 4)
    PinDrawGrip(G, w, h, handle)
    Gdip_DeleteGraphics(G)
}

; 快速移动钉屏窗口：DllCall SetWindowPos 替代 WinMove
; 原因：AHK 的 WinMove 每次调用后会自动附带 A_WinDelay 延迟（默认 100ms，且每个新线程
;       都会重置为默认值），拖动时即使定时器周期调到 1ms 也仍被卡在 100ms 上；
;       此处用 SetWindowPos 异步移动（不重绘、不激活、不变 z-order），彻底绕开该延迟
; 标志组合：
;   0x0001 SWP_NOSIZE | 0x0004 SWP_NOZORDER | 0x0008 SWP_NOREDRAW | 0x0010 SWP_NOACTIVATE
;   | 0x0400 SWP_NOSENDCHANGING | 0x2000 SWP_DEFERERASE | 0x4000 SWP_ASYNCWINDOWPOS
PinMoveWindow(hwnd, x, y) {
    DllCall("SetWindowPos", "Ptr", hwnd, "Ptr", 0, "Int", x, "Int", y, "Int", 0, "Int", 0, "UInt", 0x641D)
}

; 左键按下：命中右下角缩放手柄则启动缩放（窗口中心为锚点），否则启动移动拖动
PinLButtonDown(wParam, lParam, msg, hwnd) {
    global PinSessions
    s := PinSessions.Get(hwnd, 0)
    if !s
        return
    SetWinDelay(-1)  ; 消除 WinGetPos 自带的 100ms 延迟（仅当前线程）
    mx := lParam << 48 >> 48   ; 客户区坐标 x（与编辑窗取法一致）
    my := lParam << 32 >> 48   ; 客户区坐标 y
    ; 右下角缩放手柄命中：启动缩放（左上角为锚点，固定不动，向右下展开/收缩）
    if (mx >= s.winW - s.handle && my >= s.winH - s.handle) {
        MouseGetPos &sx, &sy
        WinGetPos &wx, &wy, , , "ahk_id " hwnd
        ; mx/my：缩放起点鼠标屏幕坐标；anchorX/Y：左上角锚点（缩放时固定不动，右下角手柄拖动展开）
        ; cornerX/Y：初始右下角屏幕坐标；initScale：起始缩放系数（换算起始系数用）
        s.resize := { mx: sx, my: sy, anchorX: wx, anchorY: wy, cornerX: wx + s.winW, cornerY: wy + s.winH, initScale: s.scale, txScale: s.scale, appliedScale: s.scale, active: true, previewed: false }
        DllCall("SetCapture", "Ptr", hwnd)
        SetTimer PinDragTick, 10
        return
    }
    ; 移动拖动：记录起点（屏幕坐标）与窗口位置
    MouseGetPos &mx2, &my2
    WinGetPos &wx, &wy, , , "ahk_id " hwnd
    ; tx/ty：拖动目标位置（鼠标移动只更新目标，由定时器合并应用）
    s.drag := { mx: mx2, my: my2, wx: wx, wy: wy, tx: wx, ty: wy, lastX: wx, lastY: wy, active: true }
    DllCall("SetCapture", "Ptr", hwnd)
    SetTimer PinDragTick, 10
}

; 鼠标移动：拖动/缩放中只记录目标（轻量），实际应用由 PinDragTick 定时器合并；
; 非拖动状态悬停缩放手柄时切换为斜向缩放光标（IDC_SIZENWSE）
PinMouseMove(wParam, lParam, msg, hwnd) {
    global PinSessions
    s := PinSessions.Get(hwnd, 0)
    if !s
        return
    if s.resize && s.resize.active {
        ; 缩放：以左上角为锚点，右下角角点跟手换算目标缩放系数（绝对系数，含起始缩放）
        ; 系数 = 新角点（鼠标）到锚点的距离 ÷ 原图尺寸 → 新窗口角点与鼠标 1:1 对齐
        MouseGetPos &mx, &my
        dx := mx - s.resize.mx
        dy := my - s.resize.my
        if Abs(dx) >= Abs(dy)
            f := (s.resize.cornerX + dx - s.resize.anchorX) / s.imgW
        else
            f := (s.resize.cornerY + dy - s.resize.anchorY) / s.imgH
        s.resize.txScale := PinClampScale(f)
        DllCall("SetCursor", "Ptr", DllCall("LoadCursor", "Ptr", 0, "Ptr", 32642))  ; IDC_SIZENWSE
        return
    }
    if s.drag && s.drag.active {
        MouseGetPos &mx, &my
        s.drag.tx := s.drag.wx + (mx - s.drag.mx)
        s.drag.ty := s.drag.wy + (my - s.drag.my)
        return
    }
    ; 非拖动/缩放状态：悬停右下角手柄时切换斜向缩放光标
    mx := lParam << 48 >> 48
    my := lParam << 32 >> 48
    if (mx >= s.winW - s.handle && my >= s.winH - s.handle)
        DllCall("SetCursor", "Ptr", DllCall("LoadCursor", "Ptr", 0, "Ptr", 32642))  ; IDC_SIZENWSE
}

; 拖动/缩放合并定时器：10ms 合并应用一次，目标未变化时跳过冗余操作；
; 无活动拖动/缩放时自动停止（避免窗口异常关闭后空转）
PinDragTick() {
    global PinSessions
    active := false
    for h, s in PinSessions {
        if s.drag && s.drag.active {
            active := true
            if (s.drag.tx != s.drag.lastX || s.drag.ty != s.drag.lastY) {
                PinMoveWindow(h, s.drag.tx, s.drag.ty)
                BorderStripsMove(s.borders, s.drag.tx, s.drag.ty, s.winW, s.winH)  ; 边框跟随窗口（同一套天蓝框，拖动丝滑）
                s.drag.lastX := s.drag.tx
                s.drag.lastY := s.drag.ty
            }
        }
        if s.resize && s.resize.active {
            active := true
            if (s.resize.txScale != s.resize.appliedScale)
                PinApplyResizePreview(s, h, s.resize.txScale)  ; 拖动中走轻量预览，松手才全量精渲
        }
    }
    if !active
        SetTimer PinDragTick, 0  ; 无残留拖动/缩放会话时自停
}

; 缩放系数钳制（对齐 Snipaste 范围：1/4x ~ 4x，相对原图）
PinClampScale(x) {
    return Min(4.0, Max(0.25, x))
}

; 应用缩放：以左上角为锚点等比重绘位图并更新窗口尺寸/位置/边框
; 1) 新尺寸 = 原图尺寸 × 系数（保持宽高比）；新位置由固定左上角锚点推导，钳制在工作区内（放大超屏尽量可见）
; 2) 重绘显示位图：缩放源（原图或编辑器合成图）等比缩放 + 右下角重画手柄，替换旧工作位图并释放
PinApplyResize(s, hwnd, scale) {
    scale := PinClampScale(scale)  ; 钳制缩放系数（1/4x ~ 4x）。交互路径已在 PinMouseMove 钳制，此处兜底防御
    newW := Max(1, Round(s.imgW * scale))
    newH := Max(1, Round(s.imgH * scale))
    ; 左上角为锚点：新窗口位置由固定左上角推导（无需 WinGetPos，避免定时器线程 100ms 延迟）
    nx := s.resize.anchorX
    ny := s.resize.anchorY
    ; 钳制在锚点所在显示器工作区内（放大超屏时尽量保持可见）
    MonitorGetWorkArea(MonitorIndexAt(s.resize.anchorX, s.resize.anchorY), &wl, &wt, &wr, &wb)
    nx := Min(Max(nx, wl), Max(wl, wr - newW))
    ny := Min(Max(ny, wt), Max(wt, wb - newH))
    ; 重绘显示位图（缩放源 + 右下角手柄）
    pNew := Gdip_CreateBitmap(newW, newH)
    G := Gdip_GraphicsFromImage(pNew)
    Gdip_SetSmoothingMode(G, 4)
    Gdip_DrawImage(G, s.src, 0, 0, newW, newH, 0, 0, s.imgW, s.imgH)
    PinDrawGrip(G, newW, newH, s.handle)
    Gdip_DeleteGraphics(G)
    ; 更新会话状态与窗口（尺寸由 UpdateLayeredWindow 设置，位置用 SetWindowPos 移动）
    old := s.work
    s.work := pNew
    s.winW := newW
    s.winH := newH
    s.scale := scale
    _PinUpdateLayer(hwnd, pNew)
    PinMoveWindow(hwnd, nx, ny)
    BorderStripsMove(s.borders, nx, ny, newW, newH)
    if old
        Gdip_DisposeImage(old)
    s.resize.appliedScale := scale
}

; 缩放预览（拖动中）：轻量重渲染，保证拖动手感流畅（参考 ShareX 钉屏思路：拖动按需轻量渲染、松手才精渲）
; 与 PinApplyResize（全量精渲）的区别：
;   1) 采样源用「当前工作位图 s.work」（显示分辨率）而非原图 s.src —— 源更小，重采样开销大幅降低
;   2) 插值/平滑降级（NearestNeighbor + HighSpeed）—— 预览期画面略糊可接受，
;      鼠标松开由 PinLButtonUp 触发 PinApplyResize 从 src 全量精渲覆盖，清晰度最终到位
; 位置/尺寸/边框更新逻辑与 PinApplyResize 一致（左上角锚点 + 工作区钳制 + 边框跟随）
PinApplyResizePreview(s, hwnd, scale) {
    scale := PinClampScale(scale)  ; 钳制缩放系数（1/4x ~ 4x）
    newW := Max(1, Round(s.imgW * scale))
    newH := Max(1, Round(s.imgH * scale))
    ; 左上角为锚点：新窗口位置由固定左上角推导（与全量路径同一公式）
    nx := s.resize.anchorX
    ny := s.resize.anchorY
    MonitorGetWorkArea(MonitorIndexAt(s.resize.anchorX, s.resize.anchorY), &wl, &wt, &wr, &wb)
    nx := Min(Max(nx, wl), Max(wl, wr - newW))
    ny := Min(Max(ny, wt), Max(wt, wb - newH))
    ; 轻量重绘：从当前工作位图快速拉伸（低质量插值），叠加手柄
    pNew := Gdip_CreateBitmap(newW, newH)
    G := Gdip_GraphicsFromImage(pNew)
    Gdip_SetSmoothingMode(G, 1)      ; HighSpeed：预览期低质量
    Gdip_SetInterpolationMode(G, 5)  ; NearestNeighbor：最快（大图时性能关键）
    Gdip_DrawImage(G, s.work, 0, 0, newW, newH, 0, 0, s.winW, s.winH)
    PinDrawGrip(G, newW, newH, s.handle)
    Gdip_DeleteGraphics(G)
    ; 更新会话状态与窗口（复用全量路径的层更新/移动/边框逻辑）
    old := s.work
    s.work := pNew
    s.winW := newW
    s.winH := newH
    _PinUpdateLayer(hwnd, pNew)
    PinMoveWindow(hwnd, nx, ny)
    BorderStripsMove(s.borders, nx, ny, newW, newH)
    if old
        Gdip_DisposeImage(old)
    s.resize.appliedScale := scale
    s.resize.previewed := true  ; 标记已预览，松手必须全量提交
}

; 左键松开：结束拖动/缩放，应用最后一帧（避免松开瞬间的滞后）
PinLButtonUp(wParam, lParam, msg, hwnd) {
    global PinSessions
    s := PinSessions.Get(hwnd, 0)
    if !s
        return
    DllCall("ReleaseCapture")
    if s.drag && s.drag.active {
        s.drag.active := false
        if (s.drag.tx != s.drag.lastX || s.drag.ty != s.drag.lastY) {
            PinMoveWindow(hwnd, s.drag.tx, s.drag.ty)
            BorderStripsMove(s.borders, s.drag.tx, s.drag.ty, s.winW, s.winH)  ; 最后一帧边框同步跟随
        }
    }
    if s.resize && s.resize.active {
        s.resize.active := false
        ; 松手：发生过预览（或目标系数仍有变化）即从 src 全量精渲提交，清晰度到位
        if s.resize.previewed || (s.resize.txScale != s.resize.appliedScale)
            PinApplyResize(s, hwnd, s.resize.txScale)  ; 全量精渲提交
        s.resize.previewed := false
    }
}

; 右键：关闭单个钉屏窗口
PinRButtonDown(wParam, lParam, msg, hwnd) {
    global PinSessions
    if PinSessions.Has(hwnd)
        WinClose("ahk_id " hwnd)
}

; Esc：关闭全部钉屏窗口（右键支持逐个关）
; 先收集句柄列表再逐个关闭：WinClose 同步触发会话删除（PinRemove），
; 避免遍历 PinSessions 时修改 Map 导致漏关
; 注：列表可能残留已销毁窗口，关窗前须先确认存在，否则 WinClose 会一直等待
PinEscClose(*) {
    global PinSessions
    list := []
    for h in PinSessions
        list.Push(h)
    for h in list {
        if WinExist("ahk_id " h)
            WinClose("ahk_id " h)
    }
}
