; ==================================================================
; Screenshot 选区子模块：Select（由 Screenshot.ahk 机械拆分，仅搬运、逻辑不变）
; ==================================================================

; ------------------------------------------------------------------
; 移动选区拦截层与 4 条边框到当前选区（蒙版挖洞由 MaskOverlayHole 单独处理）
; selLast：拦截层上次的 {x,y,w,h}，位置尺寸未变化时跳过操作（避免每帧移动导致边缘抖动）
; ------------------------------------------------------------------
_MoveSelectLayers(borders, selGui, region, selLast) {
    region.GetRegionRect(&x, &y, &w, &h)
    if (x = selLast.x && y = selLast.y && w = selLast.w && h = selLast.h)
        return  ; 选区未变化，跳过全部操作
    MoveWindowFast(selGui.Hwnd, x, y, w, h)
    BorderStripsMove(borders, x, y, w, h)
    selLast.x := x, selLast.y := y, selLast.w := w, selLast.h := h
}

; ------------------------------------------------------------------
; 区域选择：返回动作字符串 "cancel"|"editor"|"copy"|"save"|"pin"
; （"editor" 为仅点击窗口未拖出矩形时的快速截图路径，或点击标注工具后的编辑路径）
; initialTool：ByRef 输出参数，点击标注工具时返回预选工具名（arrow/rect/ellipse/mosaic），
;              非工具动作或快速截图路径返回 ""（编辑器以无工具状态进入，可拖动移动图片）
; initialColor：ByRef 输出参数，点击标注工具时自动选中第 1 色（红色）返回其索引；
;               非工具动作或快速截图路径返回 0（编辑器用默认第 1 色）
; ------------------------------------------------------------------
SelectRegion(region, &initialTool := "", &initialColor := 0) {
    global SCREENSHOT_TIMEOUT_MS
    global EditorTool, EditorColorIdx, ToolbarPhase, ScreenToolbarResult

    CoordMode "Mouse", "Screen"

    ; 超时截止点：按 F1 起算，超时未完成则自动取消并恢复屏幕（防止蒙版卡住无法操作）
    deadline := A_TickCount + SCREENSHOT_TIMEOUT_MS

    ; 重置工具栏单一真源与结果通道：防止上一会话的工具栏选中态/阶段残留误判
    ; （EditorTool 一空 → 编辑无预选工具进入，与「仅点窗口」快速截图行为一致）
    EditorTool := ""
    EditorColorIdx := 1
    ToolbarPhase := "selection"
    ScreenToolbarResult := ""

    ; 可变状态对象（供热键与定时器闭包共享；动作结果走全局 ScreenToolbarResult）
    state := { canceled: false, confirmed: false, isDragging: false, dragStartX: 0, dragStartY: 0, hoverX: 0, hoverY: 0
        , region: region }

    ovl := _SelectionCreate(region, state)
    toolbar := 0
    try {
        if !_SelectionWaitPress(state, region, ovl, deadline)
            return "cancel"
        if !_SelectionWaitDrag(state, region, ovl, deadline)
            return "cancel"

        ; 拖出矩形后展示动作工具栏并进入微调；仅点击窗口（未拖出矩形）时保持原快速截图行为（直接进编辑窗）
        action := "editor"
        if state.isDragging {
            toolbar := SelToolbarCreate(state, region)
            _ResetSelectionDoubleClick()  ; 进入微调前复位双击判定，避免上一会话的按下被算作本次双击
            action := _SelectionAdjustLoop(state, region, ovl, deadline, toolbar)
            if action = "cancel"
                return "cancel"
        }

        ; 选区已确认：蒙版/边框保留不销毁，由后续流程接管（编辑器就地升级 / 钉屏）
        _SelectionConfirm(state, ovl, toolbar)
        initialTool := EditorTool      ; 点击标注工具时的预选工具（编辑器初始工具，单一真源）
        initialColor := EditorColorIdx ; 点击标注工具时自动选中的颜色索引（编辑器初始颜色）
        return action
    } finally {
        ; 取消/异常路径立即清理覆盖层；成功路径保留（延迟清理），避免整屏明暗跳变
        if !state.confirmed
            _DestroyOverlays(ovl.mask, ovl.borders, ovl.selGui, toolbar)
    }
}

; ------------------------------------------------------------------
; 选区流程子步骤（由 SelectRegion 按阶段拆分，行为不变）
; ------------------------------------------------------------------

; 创建选区覆盖层（蒙版 + 4 边框 + 拦截层）与取消热键，并登记 HWND 跳过表
; 返回覆盖层对象 {mask, borders, selGui, selLast}
_SelectionCreate(region, state) {
    global SEL_ALPHA
    global ScreenshotMaskHwnds, ScreenshotBorderHwnds, ScreenshotSelHwnd, ScreenshotEscCancel

    ; 覆盖层（Common\Overlay.ahk 共享组件）：全屏灰度蒙版（单窗口挖洞）+ 4 条天蓝边框窗口
    maskOv := MaskOverlayCreate()
    borders := BorderStripsCreate()

    ; 选区透明拦截层（alpha 极小，几乎不可见，盖住选区防止点击穿透）
    ; +E0x08000000(WS_EX_NOACTIVATE)：点击不激活/不抬升 z-order，避免拖动选区后把自身顶到
    ; 动作工具栏之上导致工具栏按钮被拦截点不动（蒙版同理，见 Overlay.ahk MaskOverlayCreate）
    selGui := Gui("-Caption +ToolWindow +AlwaysOnTop -DPIScale +E0x08000000")
    selGui.BackColor := "Black"
    WinSetTransparent SEL_ALPHA, selGui

    ; 记录蒙版/边框/拦截层 hwnd，供窗口悬停检测跳过
    ScreenshotMaskHwnds := [maskOv.hwnd]
    ScreenshotBorderHwnds := []
    for b in borders
        ScreenshotBorderHwnds.Push(b.Hwnd)
    ScreenshotSelHwnd := selGui.Hwnd

    ; 初始即高亮鼠标下的窗口（z-order 从底到顶：拦截层 → 蒙版 → 4 条边框）
    GetWindowRegionFromMouse(region)
    selGui.Show(region.GuiString())
    region.GetRegionRect(&sx, &sy, &sw, &sh)
    MaskOverlayHole(maskOv, sx, sy, sw, sh)
    for b in borders
        b.Show("NA x" sx " y" sy " w1 h1")
    BorderStripsMove(borders, sx, sy, sw, sh)
    selLast := {x: sx, y: sy, w: sw, h: sh}  ; 拦截层上次位置，用于跳过无变化操作
    MouseGetPos &tx, &ty
    state.hoverX := tx
    state.hoverY := ty

    ; 取消热键：右键（独立）；Esc 走统一分发（截图阶段优先取消选区，不覆盖钉屏热键）
    Hotkey "*RButton", (*) => (state.canceled := true), "On"
    ScreenshotEscCancel := () => (state.canceled := true)
    EscRegister()

    return {mask: maskOv, borders: borders, selGui: selGui, selLast: selLast}
}

; 等待左键按下（进入拖动阶段）：返回 true=已按下，false=取消/超时
_SelectionWaitPress(state, region, ovl, deadline) {
    hoverFunc := 0
    try {
        ; 悬停更新：鼠标移动超过阈值时重新检测窗口（10ms 高频刷新，蒙版跟随更平滑减少跳帧闪烁）
        hoverFunc := () => _HoverUpdate(state, region, ovl.borders, ovl.selGui, ovl.mask, ovl.selLast)
        SetTimer hoverFunc, 10
        while !state.canceled {
            if GetKeyState("LButton") {
                MouseGetPos &tx, &ty
                state.dragStartX := tx
                state.dragStartY := ty
                state.isDragging := false
                return true
            }
            if A_TickCount > deadline {
                state.canceled := true  ; 超时未操作，自动取消
                return false
            }
            Sleep 10
        }
        return false
    } finally {
        if hoverFunc
            SetTimer hoverFunc, 0
    }
}

; 等待左键松开并落定最终选区：返回 true=正常松开，false=取消/超时
_SelectionWaitDrag(state, region, ovl, deadline) {
    dragFunc := 0
    try {
        ; 拖动更新：超过阈值即实时绘制矩形（10ms 高频刷新，蒙版/边框跟随更平滑）
        dragFunc := () => _DragUpdate(state, region, ovl.borders, ovl.selGui, ovl.mask, ovl.selLast)
        SetTimer dragFunc, 10
        while !state.canceled {
            if !GetKeyState("LButton") {
                if state.isDragging {
                    MouseGetPos &tx, &ty
                    region.SetRegionByPos(tx, ty, state.dragStartX, state.dragStartY)
                    _MoveSelectLayers(ovl.borders, ovl.selGui, region, ovl.selLast)
                    region.GetRegionRect(&rx, &ry, &rw, &rh)
                    MaskOverlayHole(ovl.mask, rx, ry, rw, rh)
                }
                return !state.canceled
            }
            if A_TickCount > deadline {
                state.canceled := true  ; 超时未完成，自动取消
                return false
            }
            Sleep 10
        }
        return false
    } finally {
        if dragFunc
            SetTimer dragFunc, 0
    }
}

; 选区微调循环：处理工具栏动作与「保存」子流程（取消保存则回到微调）
; 返回工具栏动作 "editor"|"copy"|"save"|"pin" 或 "cancel"
_SelectionAdjustLoop(state, region, ovl, deadline, toolbar) {
    global SCREENSHOT_TIMEOUT_MS, ScreenshotEscCancel, ScreenshotSaveFilename, ScreenToolbarResult
    while true {
        action := SelectRegionAdjust(state, region, ovl.borders, ovl.selGui, ovl.mask, deadline, toolbar)
        if action = "cancel"
            return "cancel"
        if action != "save"
            return action
        ; 保存动作：临时禁用选区取消热键（避免保存框内操作误取消选区）
        Hotkey "*RButton", "Off"
        ScreenshotEscCancel := 0
        EscUnregister()
        ; 先定格当前选区画面、隐藏覆盖层（不销毁）弹系统保存框；取消保存恢复覆盖层返回 ""
        ScreenshotSaveFilename := ConfirmSelectionSave(region, ovl.mask, ovl.borders, ovl.selGui, toolbar)
        ; 恢复选区取消热键（成功/取消统一恢复，外层确认路径再统一注销）
        Hotkey "*RButton", (*) => (state.canceled := true), "On"
        ScreenshotEscCancel := () => (state.canceled := true)
        EscRegister()
        if ScreenshotSaveFilename != ""
            return "save"  ; 保存成功，由外层落盘
        ; 取消保存：重置动作与取消标志并顺延超时截止点，继续选区微调（可再调整/换动作/再保存）
        ScreenToolbarResult := ""
        state.canceled := false
        deadline := A_TickCount + SCREENSHOT_TIMEOUT_MS
    }
}

; 选区确认：注销取消热键、标记 confirmed，并把覆盖层交给后续流程（编辑器就地升级 / 钉屏）
_SelectionConfirm(state, ovl, toolbar) {
    global ScreenshotSelOverlays, ScreenshotEscCancel
    Hotkey "*RButton", "Off"
    ScreenshotEscCancel := 0
    EscUnregister()
    state.confirmed := true
    ScreenshotSelOverlays := {mask: ovl.mask, borders: ovl.borders, selGui: ovl.selGui, toolbar: toolbar}
}

; 底层销毁覆盖层资源（幂等，可安全重复调用）
; 蒙版/边框可能已被后续流程接管（传 0 跳过），拦截层始终销毁；
; keepToolbar=true：选区工具栏交给编辑器接管（跨阶段持久，不销毁、不清 ToolbarHoverActive）
_DestroyOverlays(maskOv, borders, selGui, toolbar := 0, keepToolbar := false) {
    global ScreenshotMaskHwnds, ScreenshotSelHwnd, ScreenshotBorderHwnds, ScreenshotEscCancel
    global ToolbarHoverActive, EditorToolbar, EditorScrollButton, EditorScrollExtraW, EditorScrollAfterCtrls
    try Hotkey "*RButton", "Off"
    if ScreenshotEscCancel {
        ScreenshotEscCancel := 0
        EscUnregister()  ; 仅在截图阶段 Esc 仍注册时注销（防止与正常路径重复递减）
    }
    BorderStripsDestroy(borders)
    if selGui
        try selGui.Destroy()
    MaskOverlayDestroy(maskOv)
    if toolbar && !keepToolbar {
        ; 工具栏销毁后悬停分发不再转发到其状态实例（防止 ToolbarHoverActive 悬空引用）
        if IsObject(toolbar.HoverState) && ToolbarHoverActive = toolbar.HoverState
            ToolbarHoverActive := 0
        try toolbar.HoverState.ClearTransient()  ; 先取消渐变/清理暂存，避免 Map 残存控件引用
        try toolbar.Destroy()
        if toolbar = EditorToolbar
            EditorToolbar := 0  ; 选区路径销毁 row1 时同步清全局，防残留非零引用误判下一会话 promote
        EditorScrollButton := 0  ; 滚动截图按钮随 row1 一起销毁，清引用防悬空
        EditorScrollExtraW := 0
        EditorScrollAfterCtrls := []
    }
    ScreenshotMaskHwnds := []
    ScreenshotSelHwnd := 0
    ScreenshotBorderHwnds := []
}

; 销毁遗留的选区覆盖层（编辑器环境就绪后由 ShowEditor 回调 / 独立输出动作后调用；异常时兜底，幂等）
; keepMask / keepBorders：蒙版/边框被后续流程接管时保留（编辑器就地升级复用蒙版+边框、钉屏接管边框），
; keepToolbar：选区工具栏被编辑器接管（跨阶段持久）时保留，其所有权移交 EditorCleanup 统一销毁
; 其余情况默认全部销毁，避免覆盖层残留卡屏
FinishSelectionOverlays(keepMask := false, keepBorders := false, keepToolbar := false) {
    global ScreenshotSelOverlays
    if !ScreenshotSelOverlays
        return
    ovs := ScreenshotSelOverlays
    ScreenshotSelOverlays := 0
    _DestroyOverlays(keepMask ? 0 : ovs.mask, keepBorders ? 0 : ovs.borders, ovs.selGui, ovs.toolbar, keepToolbar)
}

; 悬停更新回调
_HoverUpdate(state, region, borders, selGui, maskOv, selLast) {
    global SMALL_DELTA
    if state.canceled
        return
    MouseGetPos &tx, &ty
    if (Abs(tx - state.hoverX) + Abs(ty - state.hoverY) > SMALL_DELTA) {
        ; 直接用 Move 移动/缩放，避免 Hide/Show 造成的闪烁
        GetWindowRegionFromMouse(region)
        _MoveSelectLayers(borders, selGui, region, selLast)
        region.GetRegionRect(&rx, &ry, &rw, &rh)
        MaskOverlayHole(maskOv, rx, ry, rw, rh)
        state.hoverX := tx
        state.hoverY := ty
    }
}

; 拖动更新回调
_DragUpdate(state, region, borders, selGui, maskOv, selLast) {
    global DRAG_THRESHOLD
    if state.canceled
        return
    MouseGetPos &tx, &ty
    if (Abs(tx - state.dragStartX) > DRAG_THRESHOLD || Abs(ty - state.dragStartY) > DRAG_THRESHOLD) {
        state.isDragging := true
        region.SetRegionByPos(tx, ty, state.dragStartX, state.dragStartY)
        _MoveSelectLayers(borders, selGui, region, selLast)
        region.GetRegionRect(&rx, &ry, &rw, &rh)
        MaskOverlayHole(maskOv, rx, ry, rw, rh)
    }
}

; ------------------------------------------------------------------
; 选区微调阶段（仅拖出矩形后进入）：选区保持未固定，可继续调整
;  - 选区内部左键拖动：整体平移选区（钉屏合并手法：消息回调只记录目标矩形，定时器统一应用，移动顺滑）
;  - 选区外侧边框/四角左键拖动：调整选区大小（保持 MIN_SEL_SIZE 最小宽高）
;  - 选区动作工具栏（标注工具 + 保存/钉屏/复制）：点击即确认并返回对应动作；
;    标注工具（arrow/rect/ellipse/mosaic）→ 自动选中第 1 色（红色）并返回 "editor"
;    （EditorTool 记初始工具、EditorColorIdx 记初始颜色，编辑器打开时同步该状态，无需再点颜色）；
;    保存/钉屏/复制 → 对应动作；取消由 Esc / 右键 / 超时承担
; 返回值："editor"|"copy"|"save"|"pin"（工具栏动作），"cancel"（取消）
; ------------------------------------------------------------------
SelectRegionAdjust(state, region, borders, selGui, maskOv, deadline, toolbar) {
    global ScreenshotAdjustCtx
    ScreenshotAdjustCtx := { region: region, borders: borders, selGui: selGui, mask: maskOv
        , state: state, toolbar: toolbar, drag: 0 }
    ; 消息钩子常驻注册（与钉屏/编辑窗同一手法：回调按 hwnd/拖动状态分发，避免误伤其它窗口）
    ; 注意：选区拦截层/蒙版窗口类自带 CS_DBLCLKS（实测类样式 0x8），真实双击的第二次按下
    ; 系统发送 WM_LBUTTONDBLCLK(0x203) 而非 0x201，故除 0x201 单击平移外必须另注册 0x203
    ; （否则第二次按下消息丢失，自维护的双击判定永远只看到一次按下、双击失效）
    OnMessage(0x201, AdjustLButtonDown)
    OnMessage(0x200, AdjustMouseMove)
    OnMessage(0x202, AdjustLButtonUp)
    OnMessage(0x203, AdjustLButtonDblClk)
    OnMessage(0x20, AdjustSetCursor)  ; WM_SETCURSOR：悬停选区边角/内部时切换方向光标
    try {
        ; 等待工具栏动作或取消（动作由工具栏按钮回调写入全局 ScreenToolbarResult）
        while !state.canceled && ScreenToolbarResult = "" {
            if A_TickCount > deadline {
                state.canceled := true  ; 超时未确认，自动取消
                break
            }
            Sleep 10
        }
        return state.canceled ? "cancel" : ScreenToolbarResult
    } finally {
        OnMessage(0x201, AdjustLButtonDown, 0)
        OnMessage(0x200, AdjustMouseMove, 0)
        OnMessage(0x202, AdjustLButtonUp, 0)
        OnMessage(0x203, AdjustLButtonDblClk, 0)
        OnMessage(0x20, AdjustSetCursor, 0)
        SetTimer AdjustDragTick, 0
        ScreenshotAdjustCtx := 0
    }
}

; 双击（WM_LBUTTONDBLCLK，0x203）：选区窗口类自带 CS_DBLCLKS，系统已按
; GetDoubleClickTime 与双击矩形（SM_CXDOUBLECLK/SM_CYDOUBLECLK）判定双击，
; 第二次按下直接发送 0x203（与 Windows/ShareX 原生双击一致，用户调大双击容差设置时同样生效）。
; 此处只需命中选区内（hit="move"）即触发「复制并关闭截图」（与工具栏「📋 复制」按钮一致）；
; 单击仍由 0x201 走平移（双击第一次按下短暂启动平移、松开即结束，鼠标位移很小，选区不位移）
AdjustLButtonDblClk(wParam, lParam, msg, hwnd) {
    global ScreenshotAdjustCtx, ScreenToolbarResult
    ctx := ScreenshotAdjustCtx
    if !ctx || ctx.drag || ctx.state.canceled || ctx.state.confirmed
        return
    ; 仅响应本流程的选区拦截层与蒙版窗口
    if (hwnd != ctx.selGui.Hwnd && hwnd != ctx.mask.hwnd)
        return
    MouseGetPos &mx, &my
    ctx.region.GetRegionRect(&l, &t, &w, &h)
    hit := _AdjustHitTest(mx, my, l, t, l + w, t + h)
    if (hit = "move")
        ScreenToolbarResult := "copy"
}

; 左键按下：判定点击命中区（选区内部=平移 / 外侧边框带=改大小），并启动对应拖动；
; 选区外空白点击不响应（动作统一由工具栏提供）
AdjustLButtonDown(wParam, lParam, msg, hwnd) {
    global ScreenshotAdjustCtx, ScreenToolbarResult
    ctx := ScreenshotAdjustCtx
    if !ctx || ctx.drag || ctx.state.canceled || ctx.state.confirmed
        return
    ; 仅响应本流程的选区拦截层与蒙版窗口（蒙版/拦截层之外的点击如钉屏窗口不参与微调）
    if (hwnd != ctx.selGui.Hwnd && hwnd != ctx.mask.hwnd)
        return
    ; 蒙版/拦截层被按下时会因激活被系统抬到工具栏之上（WS_EX_NOACTIVATE 亦不能完全避免），
    ; 这里立即把工具栏重新抬回最前，保证随后的工具栏点击不被半透明蒙版拦截
    _RaiseAdjustToolbar(ctx)
    MouseGetPos &mx, &my
    ctx.region.GetRegionRect(&l, &t, &w, &h)
    hit := _AdjustHitTest(mx, my, l, t, l + w, t + h)
    if (hit = "confirm")
        return  ; 点击选区外空白：忽略
    ; 双击选区内部 → 直接复制到剪贴板并关闭截图（与工具栏「📋 复制」按钮一致），不进入平移；
    ; 单击仍平移（双击的第一次按下会短暂启动平移、松开即结束，鼠标位移很小，选区不位移）
    if (hit = "move" && _IsSelectionDoubleClick(mx, my)) {
        ScreenToolbarResult := "copy"
        return
    }
    mode := SubStr(hit, 1, 4)                  ; "move" 或 "resi"（resize）
    handle := (mode = "resi") ? SubStr(hit, 8) : ""
    ctx.drag := { mode: mode, handle: handle
        , startMX: mx, startMY: my
        , l0: l, t0: t, r0: l + w, b0: t + h
        , targetL: l, targetT: t, targetR: l + w, targetB: t + h
        , appliedL: l, appliedT: t, appliedR: l + w, appliedB: t + h
        , active: true }
    DllCall("SetCapture", "Ptr", hwnd)
    SetTimer AdjustDragTick, 10
}

; 拖动中：只更新目标矩形（轻量），实际移动由 AdjustDragTick 定时器合并应用（避免高频消息同步移动导致掉帧）
AdjustMouseMove(wParam, lParam, msg, hwnd) {
    global ScreenshotAdjustCtx, MIN_SEL_SIZE
    ctx := ScreenshotAdjustCtx
    if !ctx || !ctx.drag || !ctx.drag.active
        return
    MouseGetPos &mx, &my
    d := ctx.drag
    ; 拖动中保持方向光标：改大小时选区边缘跟手，「move」命中判定会抢在 resize 之前，
    ; 故按拖动模式/手柄显式设定，避免拖动途中光标在缩放与移动之间跳变
    _ApplyAdjustCursor(ctx)
    if (d.mode = "move") {
        ; 整体平移：选区左上角跟随鼠标位移，尺寸不变
        d.targetL := d.l0 + mx - d.startMX
        d.targetT := d.t0 + my - d.startMY
        d.targetR := d.r0 + mx - d.startMX
        d.targetB := d.b0 + my - d.startMY
        return
    }
    ; 改大小：按拖动手柄更新对应边，并钳制最小宽高
    l := d.l0, t := d.t0, r := d.r0, b := d.b0
    dx := mx - d.startMX, dy := my - d.startMY
    if InStr(d.handle, "l")
        l := Min(d.l0 + dx, r - MIN_SEL_SIZE)
    if InStr(d.handle, "r")
        r := Max(d.r0 + dx, l + MIN_SEL_SIZE)
    if InStr(d.handle, "t")
        t := Min(d.t0 + dy, b - MIN_SEL_SIZE)
    if InStr(d.handle, "b")
        b := Max(d.b0 + dy, t + MIN_SEL_SIZE)
    d.targetL := l, d.targetT := t, d.targetR := r, d.targetB := b
}

; 左键松开：结束拖动并应用最后一帧（确认动作统一由工具栏提供）
AdjustLButtonUp(wParam, lParam, msg, hwnd) {
    global ScreenshotAdjustCtx
    ctx := ScreenshotAdjustCtx
    if !ctx || !ctx.drag
        return
    DllCall("ReleaseCapture")
    d := ctx.drag
    if d.active {
        d.active := false
        _ApplyAdjustRect(ctx)
    }
    ctx.drag := 0
    SetTimer AdjustDragTick, 0
    ; 松开后按当前位置恢复光标（缩放方向光标 → 平移/箭头）
    _ApplyAdjustCursor(ctx)
    _RaiseAdjustToolbar(ctx)  ; 按下时蒙版被抬到工具栏之上的情况在此复位
}

; 拖动合并定时器（10ms）：把高频鼠标消息的目标矩形聚合成稳定的窗口移动/缩放；无活动拖动时自停
AdjustDragTick() {
    global ScreenshotAdjustCtx
    ctx := ScreenshotAdjustCtx
    if !ctx || !ctx.drag || !ctx.drag.active {
        SetTimer AdjustDragTick, 0
        return
    }
    _ApplyAdjustRect(ctx)
}

; 应用调整目标矩形：移动/缩放拦截层与 4 条边框、更新蒙版挖洞、跟随动作工具栏，并同步选区 region
; 目标未变化时跳过（去重，避免定时器高频触发冗余窗口移动/区域重设导致闪烁）
_ApplyAdjustRect(ctx) {
    d := ctx.drag
    if !d
        return
    if (d.targetL = d.appliedL && d.targetT = d.appliedT && d.targetR = d.appliedR && d.targetB = d.appliedB)
        return
    l := d.targetL, t := d.targetT
    w := d.targetR - d.targetL, h := d.targetB - d.targetT
    MoveWindowFast(ctx.selGui.Hwnd, l, t, w, h)
    BorderStripsMove(ctx.borders, l, t, w, h)
    MaskOverlayHole(ctx.mask, l, t, w, h)
    ctx.region.SetRegionRect(l, t, w, h)
    ; 工具栏跟随选区（与选区微调同步定位）
    if ctx.toolbar {
        SelToolbarsReposition(ctx.toolbar, ctx.region)
        _RaiseAdjustToolbar(ctx)  ; 拖动中蒙版可能被抬到工具栏之上，逐帧复位
    }
    d.appliedL := l, d.appliedT := t, d.appliedR := l + w, d.appliedB := t + h
}

; 把动作工具栏抬回最前（HWND_TOPMOST=-1；SWP_NOSIZE|NOMOVE|NOACTIVATE=0x13）
; 背景：选区蒙版/拦截层每次被点击都会因激活被系统提到同类置顶层最前，盖住工具栏并拦截点击，
;       仅靠 WS_EX_NOACTIVATE 不足以完全避免，故在选区交互（按下/拖动/松开）后显式复位
_RaiseAdjustToolbar(ctx) {
    if ctx && IsObject(ctx.toolbar)
        DllCall("SetWindowPos", "Ptr", ctx.toolbar.Hwnd, "Ptr", -1, "Int", 0, "Int", 0, "Int", 0, "Int", 0, "UInt", 0x13)
}

; 判定点击点相对选区矩形的命中区："move"（内部平移）| "resize:lt/rt/lb/rb/l/r/t/b"（外侧边框带改大小）| "confirm"（空白，忽略）
_AdjustHitTest(mx, my, l, t, r, b) {
    global RESIZE_GRAB
    g := RESIZE_GRAB
    if (mx >= l && mx <= r && my >= t && my <= b)
        return "move"
    ; 外侧抓取带（选区外沿 g 像素）：四角优先于边
    if (mx >= l - g && mx <= r + g && my >= t - g && my <= b + g) {
        nearL := mx <= l + g, nearR := mx >= r - g
        nearT := my <= t + g, nearB := my >= b - g
        if nearL && nearT
            return "resize:lt"
        if nearR && nearT
            return "resize:rt"
        if nearL && nearB
            return "resize:lb"
        if nearR && nearB
            return "resize:rb"
        if nearL
            return "resize:l"
        if nearR
            return "resize:r"
        if nearT
            return "resize:t"
        return "resize:b"
    }
    return "confirm"
}

; ------------------------------------------------------------------
; 鼠标光标反馈：悬停选区边角/内部时切换方向光标（与 Pin.ahk 的缩放手柄提示一致）
; 走 WM_SETCURSOR（0x20）而非在 WM_MOUSEMOVE 里 SetCursor：
;   系统在鼠标移动/点击时主动询问窗口光标，鼠标静止时也能给出正确提示
; ------------------------------------------------------------------

; WM_SETCURSOR：仅响应本流程的选区拦截层与蒙版窗口，按当前命中区切换方向光标
; 返回 true=已设置（阻止默认箭头覆盖）；非本流程窗口用裸 return（返回 ""）交回默认处理
; 注意：AHK v2 中返回整数（含 false/0）会作为消息应答并终止后续处理，故此处不可写 return false，
; 否则会话期间其他窗口（如动作工具栏）的 WM_SETCURSOR 会被吞掉、默认光标不生效
AdjustSetCursor(wParam, lParam, msg, hwnd) {
    global ScreenshotAdjustCtx
    ctx := ScreenshotAdjustCtx
    if !ctx || ctx.state.canceled || ctx.state.confirmed
        return
    if (hwnd != ctx.selGui.Hwnd && hwnd != ctx.mask.hwnd)
        return
    _ApplyAdjustCursor(ctx)
    return true
}

; 设置当前应显示的光标：拖动中按拖动模式/手柄（选区边缘跟手，命中判定不可靠）；
; 非拖动时按鼠标位置的命中区（边/角 → 对应方向缩放；内部 → 移动；空白 → 箭头）
_ApplyAdjustCursor(ctx) {
    if ctx.drag {
        DllCall("SetCursor", "Ptr", DllCall("LoadCursor", "Ptr", 0, "Ptr"
            , _AdjustCursorId(ctx.drag.mode = "move" ? "move" : "resize:" ctx.drag.handle)))
        return
    }
    MouseGetPos &mx, &my
    ctx.region.GetRegionRect(&l, &t, &w, &h)
    hit := _AdjustHitTest(mx, my, l, t, l + w, t + h)
    DllCall("SetCursor", "Ptr", DllCall("LoadCursor", "Ptr", 0, "Ptr", _AdjustCursorId(hit)))
}

; 命中区 → 系统光标资源 ID
_AdjustCursorId(hit) {
    switch hit {
        case "move":                      return 32646  ; IDC_SIZEALL（整体平移）
        case "resize:l", "resize:r":      return 32644  ; IDC_SIZEWE（左右改宽）
        case "resize:t", "resize:b":      return 32645  ; IDC_SIZENS（上下改高）
        case "resize:lt", "resize:rb":    return 32642  ; IDC_SIZENWSE（左上/右下）
        case "resize:rt", "resize:lb":    return 32643  ; IDC_SIZENESW（右上/左下）
        default:                          return 32512  ; IDC_ARROW（空白）
    }
}

; 判定是否为「双击」：与上次按下间隔不超过系统双击时间（GetDoubleClickTime）且位移不超过
; 系统双击矩形（SM_CXDOUBLECLK/SM_CYDOUBLECLK，默认各 4px）——与 Windows/ShareX 原生双击判定一致，
; 用户调大双击容差设置时同样生效；
; 用于「双击选区 → 直接复制」。static 记录上次按下时间与坐标供连续两次按下判定；
; 首按必然返回 false 并记录状态，次按在时间/位移阈值内才判定为双击（不依赖窗口类 CS_DBLCLKS，
; 无需注册 0x203，与选区单击平移共用 0x201 消息钩子）
; 复位双击判定状态：每次进入选区微调（新会话）时调用
; 否则 static 跨会话保留，上一次截图结束时的按下若落在双击时间/位移窗内，
; 新会话的首次单击平移会被误判为「双击 → 直接复制」并提前结束会话
_ResetSelectionDoubleClick() {
    _IsSelectionDoubleClick(0, 0, true)
}

_IsSelectionDoubleClick(mx, my, reset := false) {
    static lastTick := 0, lastX := -9999, lastY := -9999
    if reset {
        lastTick := 0, lastX := -9999, lastY := -9999
        return false
    }
    now := A_TickCount
    dx := DllCall("GetSystemMetrics", "Int", 36)  ; SM_CXDOUBLECLK
    dy := DllCall("GetSystemMetrics", "Int", 37)  ; SM_CYDOUBLECLK
    double := (now - lastTick <= DllCall("GetDoubleClickTime")) && Abs(mx - lastX) <= dx && Abs(my - lastY) <= dy
    lastTick := now
    lastX := mx
    lastY := my
    return double
}

; ------------------------------------------------------------------
; 选区动作工具栏：标注工具 + 保存 / 钉屏 / 复制（与编辑工具栏共用同一行 row1，跨阶段持久）
; 拖出矩形后展示在选区下方并跟随选区；点击动作写入全局 ScreenToolbarResult
; ------------------------------------------------------------------

; 创建选区动作工具栏并定位到选区下方（复用编辑 row1 的构建 ScreenToolbarCreateRow1；选中态与
; 点击行为由全局 ToolbarPhase="selection" 驱动：工具 → 选工具 + 自动选第 1 色 + 进入编辑）
; 保存/钉屏/复制 直接输出后关闭截图（复制最右）；退出由 Esc / 右键承担
SelToolbarCreate(state, region) {
    global ToolbarPhase
    tb := ScreenToolbarCreateRow1(0)  ; 幂等构建 row1（选区 DPI：内部临时 Show 读鼠标所在屏）
    ToolbarPhase := "selection"
    SelToolbarsReposition(tb, region)
    tb.Show("NA")  ; 已在最终位置，直接显示，避免从默认位置跳变闪烁
    ToolbarFadeIn(tb.Hwnd)  ; 淡入出现（约 130ms），避免工具栏"硬出现"
    return tb
}

; 工具栏整体定位：置于选区正下方居中；下方放不下则移到选区上方；贴近屏幕边缘时钳制在所在显示器工作区内
SelToolbarsReposition(toolbar, region) {
    global EditorToolbarW, EditorToolbarH
    ; 门卫只要求持有有效工具栏实例：Move/GetPos 均走 AHK 缓存，隐藏或离屏窗口同样可定位（不依赖可见性）
    if !IsObject(toolbar)
        return
    ; DPI 一致性：region 由截图线程（per-monitor aware）产出物理像素坐标；
    ; 定位（MonitorGetWorkArea）与移动（Move）若在 unaware 默认线程计算会与物理像素
    ; 单位错配，Windows 显示缩放 >100%（如 125/150%）下工具栏会整体偏右下。
    ; 故定位整体包在 per-monitor aware 上下文内，region/工作区/坐标系全为物理一致
    prevDpi := DllCall("SetThreadDpiAwarenessContext", "Ptr", -3, "Ptr")
    try {
        region.GetRegionRect(&x, &y, &w, &h)
        ; 交给公共定位（ToolbarUI.ahk）：选区矩形为锚点，选区中心所在显示器工作区为边界
        ToolbarPlaceUnder([{hb: toolbar, w: EditorToolbarW, h: EditorToolbarH}], {l: x, t: y, r: x + w, b: y + h})
    } finally {
        DllCall("SetThreadDpiAwarenessContext", "Ptr", prevDpi, "Ptr")
    }
}
