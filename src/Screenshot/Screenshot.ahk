; ==================================================================
; 简单截图（默认 F1，热键可配置）
; 热键由 Hotkeys.ahk 动态注册（可配置，见 src\Hotkeys\Hotkeys.ahk）
; 可通过设置窗口或 config.ini 的 ScreenshotEnabled 开关
;
; 依赖：Gdip 库（src\Common\Gdip_All_v2.ahk）
;   来源：mmikeww/AHKv2-Gdip（已适配 AHK v2），仅用于屏幕截图与剪贴板
;
; 交互流程：
;   1) 单窗口灰度蒙版（全屏挖洞）：非选区区域灰色半透明并拦截所有点击，选区透明露出下层内容
;   2) 蓝色边框 + 透明内部拦截层：悬停高亮窗口，拖动选择自定义矩形（选区可见下层内容且点击不穿透）
;   3) 拖出矩形后展示动作工具栏并进入微调阶段（选区保持未固定）：
;      选区内部左键拖动整体平移、沿外侧边框/四角拖动改大小（钉屏合并手法，丝滑）；
;      工具栏动作即确认：点击标注工具（矩形/箭头/椭圆/马赛克）→ 自动选中第 1 色（红色）
;      并无缝进入编辑窗（无需再点颜色，工具与颜色状态同步显示），立即可标注；
;      保存/钉屏/复制 → 直接输出到剪贴板/文件/置顶，取消由 Esc / 右键承担
; ==================================================================

#Include "..\Common\Gdip_All_v2.ahk"
#Include "Common\Overlay.ahk"    ; 覆盖层共享组件（全屏挖洞蒙版 + 4 条边框），选区/编辑器/钉屏三阶段复用
#Include "Common\ToolbarUI.ahk"  ; 工具栏通用组件（色块/扁平按钮/悬停），Editor 与选区工具栏共用
#Include "Editor.ahk"

; ------------------------------------------------------------------
; 截图参数（文件名/颜色/透明度/阈值）统一在 Config.ahk 中定义
; ------------------------------------------------------------------

; ------------------------------------------------------------------
; GDI+ 初始化 / 退出清理
; ------------------------------------------------------------------
; 引用的全局配置（值在 Config.ahk 中赋值，此处显式声明供静态分析识别，避免 IDE 误报未赋值）
global SCREENSHOT_FILENAME
global GdipToken := 0
global ScreenshotMaskHwnds := []    ; 截图蒙版窗口 hwnd 数组（单窗口挖洞，供窗口悬停检测跳过）
global ScreenshotSelHwnd := 0       ; 选区透明拦截层 hwnd（供窗口悬停检测跳过）
global ScreenshotBorderHwnds := []  ; 覆盖层边框窗口 hwnd 数组（4 条：上/下/左/右，供窗口悬停检测跳过）
global ScreenshotEscCancel := 0     ; 截图选区阶段的 Esc 取消回调（统一 Esc 分发优先调用；非截图阶段为 0）
global ScreenshotSelOverlays := 0   ; 选区确认后保留的覆盖层（{mask, borders, selGui, toolbar}）；
                                    ; 蒙版/边框由后续流程接管（编辑器就地升级 / 钉屏），拦截层与工具栏按动作销毁
global ScreenshotAdjustCtx := 0     ; 选区微调阶段上下文（{region, borders, selGui, maskGui, mx/my/mw/mh, state, toolbar, drag}），消息钩子/定时器共享
global ScreenshotSaveFilename := "" ; 选区保存确认的保存路径（SelectRegion 内确认后交外层落盘；取消保存不设置）
global ScreenshotSaveBitmap := 0    ; 选区保存确认时已定格的截图位图（SelectRegion 内先抓图再弹框，交外层落盘并释放；取消保存不设置）
global SelToolbarW := 0, SelToolbarH := 0  ; 选区动作工具栏尺寸缓存（创建时获取一次，跟随定位时复用，避免每帧 WinGetPos）
GdipToken := Gdip_Startup()
if !GdipToken {
    MsgBox "GDI+ 初始化失败", "错误", "IconX"
    ExitApp
}
OnExit(Screenshot_OnExit)
; 退出时不调用 Gdip_Shutdown：GDI+ 在最后一次 shutdown 时才释放全部全局对象，
; 截图会话累积的位图/画布对象会使这一步挂起约 2 秒，阻塞 Reload 时旧实例退出
; （新实例被 #SingleInstance 等待，造成"重启慢"）。进程退出时系统自动回收 GDI+ 资源。
Screenshot_OnExit(ExitReason, ExitCode) {
    return
}

; ------------------------------------------------------------------
; 截图区域数据结构（记录屏幕矩形或跟踪的窗口）
; ------------------------------------------------------------------
class RegionSetting {
    win_id := 0
    left := 0, top := 0, right := 0, bottom := 0

    ; 由任意两点（顺序无所谓）设置矩形区域
    SetRegionByPos(x1, y1, x2, y2) {
        this.left   := Min(x1, x2)
        this.top    := Min(y1, y2)
        this.right  := Max(x1, x2)
        this.bottom := Max(y1, y2)
        this.win_id := 0
    }

    ; 由左上角坐标与宽高设置矩形区域
    SetRegionRect(x, y, w, h) {
        this.left := x
        this.top := y
        this.right := x + w
        this.bottom := y + h
        this.win_id := 0
    }

    ; 设置为跟踪指定窗口（悬停高亮窗口时使用）
    SetWinID(win_id) {
        if (this.win_id != win_id) {
            this.win_id := win_id
            this.check_win_id()
        }
    }

    ; 将 win_id 同步为窗口当前屏幕坐标；win_id=0 表示自由矩形
    check_win_id() {
        if (this.win_id = 0)
            return true
        if !WinExist("ahk_id " this.win_id) {
            this.win_id := 0
            return false
        }
        WinGetPos &x, &y, &w, &h, "ahk_id " this.win_id
        this.left := x
        this.top := y
        this.right := x + w
        this.bottom := y + h
        return (w > 0 && h > 0)
    }

    ; 输出 x/y/w/h（会先同步窗口坐标）
    GetRegionRect(&x, &y, &w, &h) {
        this.check_win_id()
        x := this.left
        y := this.top
        w := this.right - this.left
        h := this.bottom - this.top
        return (w > 0 && h > 0)
    }

    ; 用于 Gui.Show 的定位字符串
    GuiString() {
        this.GetRegionRect(&x, &y, &w, &h)
        return "NA x" x " y" y " w" w " h" h
    }

    ; 用于 Gdip_BitmapFromScreen 的屏幕区域字符串
    ScreenString() {
        this.GetRegionRect(&x, &y, &w, &h)
        return x "|" y "|" w "|" h
    }
}

; ------------------------------------------------------------------
; 工具函数
; ------------------------------------------------------------------

; ------------------------------------------------------------------
; 保存对话框：使用系统 FileSelect 对话框，默认由 Windows 自行定位（居中屏幕），
; 不做位置定位（AHK v2 的 FileSelect 打开系统对话框后由独立线程托管，
; 当前线程消息循环被阻塞，钩子无法可靠拦截其激活事件，故放弃跟随截图位置）
; ------------------------------------------------------------------

; 弹出系统保存对话框选取 PNG 保存路径（取消返回 ""）
; 返回已补全 .png 扩展名的完整路径；pBitmap 为截图位图（调用方负责释放）
SelectSaveFilename() {
    global SCREENSHOT_FILENAME
    defaultName := FormatTime(, SCREENSHOT_FILENAME)  ; 对话框默认文件名（如 Screen 20260821-170000.png），作为起始"目录/文件名"传入
    try {
        selected := FileSelect("S", defaultName, "保存截图", "PNG 图片 (*.png)")
    } catch {
        return ""  ; 对话框打开失败（如系统限制），按取消处理
    }
    if selected = ""
        return ""  ; 用户取消保存
    if !RegExMatch(selected, "\.\w+$")
        selected .= ".png"  ; 用户未输入扩展名时自动补 .png
    return selected
}

; 选区保存动作：先按当前选区定格画面，再弹系统保存对话框确认保存路径（对齐 ShareX 先定格再弹框）
; 1) 先隐藏选区拦截层（覆盖整个选区，抓图前必须移开，否则会进入画面），按当前 region 抓取定格位图；
;    蒙版/边框/工具栏均在选区矩形外，不影响抓图内容，弹框前统一隐藏（避免全屏置顶蒙版遮挡对话框）
; 2) 覆盖层隐藏用 Gui.Hide/Show 而非 WinHide/WinShow（非阻塞，避免每窗口同步等待造成保存流程卡顿）
; 3) 用户取消保存（或对话框打开失败/抓图失败）时恢复覆盖层、释放已抓位图返回 ""，
;    由调用方回到选区微调（对齐"取消不结束截图"的交互）；保存成功保持覆盖层隐藏，
;    位图存入全局 ScreenshotSaveBitmap 交外层落盘，返回完整路径
ConfirmSelectionSave(region, maskOv, borders, selGui, toolbar) {
    global ScreenshotSaveBitmap
    ; 先隐藏选区拦截层并定格当前选区画面（此时蒙版/边框仍显示，抓图只取选区矩形内真实内容）
    if IsObject(selGui) && selGui.Hwnd
        selGui.Hide()
    pBitmap := CaptureRegion(region)
    if !pBitmap {
        ; 抓图失败：恢复拦截层后按取消处理（回选区微调）
        if IsObject(selGui) && selGui.Hwnd
            selGui.Show("NA")
        return ""
    }
    if IsObject(maskOv) && maskOv.hwnd
        maskOv.gui.Hide()
    if IsObject(borders)
        for b in borders
            b.Hide()
    if IsObject(toolbar) && toolbar.Hwnd
        toolbar.Hide()
    saved := false
    filename := ""
    try {
        filename := SelectSaveFilename()
        if filename != ""
            saved := true
    } finally {
        ; 仅取消保存时恢复覆盖层（保持选区微调状态继续操作）并释放已抓位图；
        ; 保存成功时覆盖层保持隐藏，避免「恢复→随即销毁」的闪回与停留
        if !saved {
            Gdip_DisposeImage(pBitmap)
            if IsObject(maskOv) && maskOv.hwnd
                maskOv.gui.Show("NA")
            if IsObject(borders)
                for b in borders
                    b.Show("NA")
            if IsObject(selGui) && selGui.Hwnd
                selGui.Show("NA")
            if IsObject(toolbar) && toolbar.Hwnd
                toolbar.Show("NA")
        }
    }
    if saved {
        ScreenshotSaveBitmap := pBitmap  ; 交外层落盘（外层负责释放与复位）
        return filename
    }
    return ""
}

; 获取鼠标下的窗口区域（跳过蒙版/边框/拦截层；桌面则返回整个显示器）
GetWindowRegionFromMouse(region) {
    global ScreenshotMaskHwnds, ScreenshotSelHwnd, ScreenshotBorderHwnds
    MouseGetPos &mx, &my, &overWin, , 2
    ; 蒙版/边框/拦截层置顶会挡住鼠标检测，命中它们时改为取 z-order 下层的真实窗口
    if (overWin = ScreenshotSelHwnd) {
        overWin := GetWindowBelowPoint(mx, my, _BuildOverlaySkipSet())
    } else {
        for h in ScreenshotMaskHwnds {
            if (overWin = h) {
                overWin := GetWindowBelowPoint(mx, my, _BuildOverlaySkipSet())
                break
            }
        }
        if overWin {
            for h in ScreenshotBorderHwnds {
                if (overWin = h) {
                    overWin := GetWindowBelowPoint(mx, my, _BuildOverlaySkipSet())
                    break
                }
            }
        }
    }
    if overWin {
        cls := WinGetClass("ahk_id " overWin)
        if (cls = "WorkerW" || cls = "Progman")
            overWin := 0  ; 桌面
    }
    if overWin {
        region.SetWinID(overWin)
    } else {
        idx := MonitorIndexAt(mx, my)
        MonitorGet(idx, &ml, &mt, &mr, &mb)
        region.SetRegionByPos(ml, mt, mr, mb)
    }
}

; 构造本次截图覆盖层（蒙版 + 边框 4 条 + 拦截层）的 hwnd 跳过集合
_BuildOverlaySkipSet() {
    global ScreenshotMaskHwnds, ScreenshotSelHwnd, ScreenshotBorderHwnds
    skip := Map()
    for h in ScreenshotMaskHwnds
        skip[h] := true
    for h in ScreenshotBorderHwnds
        skip[h] := true
    skip[ScreenshotSelHwnd] := true
    return skip
}

; 屏幕坐标下最顶层的真实窗口（跳过蒙版/边框/拦截层，按 z-order 从上往下找矩形包含该点的可见顶层窗口）
; 说明：GetWindow 的 GW_HWNDNEXT 只遍历同类型窗口，置顶链末尾返回 NULL 无法进入普通窗口，
;       因此改用 EnumWindows 枚举全部顶层窗口（按 z-order 从上到下回调），命中即返回。
GetWindowBelowPoint(mx, my, skipSet) {
    r := Buffer(16)
    found := 0
    ; 闭包回调：命中第一个（z-order 最上）矩形包含该点且非跳过的可见窗口后停止枚举
    EnumWinFn(h) {
        if skipSet.Has(h)
            return true
        if !DllCall("IsWindowVisible", "Ptr", h)
            return true
        if !DllCall("GetWindowRect", "Ptr", h, "Ptr", r.Ptr)
            return true
        l := NumGet(r, 0, "Int"), t := NumGet(r, 4, "Int")
        rt := NumGet(r, 8, "Int"), b := NumGet(r, 12, "Int")
        if (mx >= l && mx < rt && my >= t && my < b) {
            found := h
            return false  ; 停止枚举
        }
        return true
    }
    cb := CallbackCreate(EnumWinFn)
    DllCall("EnumWindows", "Ptr", cb, "Ptr", 0)
    CallbackFree(cb)
    return found
}

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
    global SMALL_DELTA, DRAG_THRESHOLD, SEL_ALPHA, SCREENSHOT_TIMEOUT_MS
    global ScreenshotSelOverlays, ScreenshotEscCancel  ; Esc 取消回调与遗留覆盖层记录（跨线程：EditorEscDispatch 按全局分发）
    global ScreenshotMaskHwnds, ScreenshotBorderHwnds, ScreenshotSelHwnd  ; 覆盖层窗口 hwnd（悬停检测跳过列表）
    global ScreenshotSaveFilename  ; 选区保存确认路径（微调循环内确认后交 SelectRegionToCapture 落盘）

    CoordMode "Mouse", "Screen"

    ; 超时截止点：按 F1 起算，超时未完成则自动取消并恢复屏幕（防止蒙版卡住无法操作）
    deadline := A_TickCount + SCREENSHOT_TIMEOUT_MS

    ; 可变状态对象（供热键与定时器闭包共享；action/tool 由工具栏动作写入）
    state := { canceled: false, confirmed: false, isDragging: false, dragStartX: 0, dragStartY: 0, hoverX: 0, hoverY: 0
        , action: "", tool: "", colorIdx: 0, selTb: 0, toolBtns: Map(), region: region }

    ; 覆盖层（Common\Overlay.ahk 共享组件，编辑器/钉屏接管复用）：
    ;   全屏灰度蒙版（单窗口挖洞：选区处透明露出下层，其余区域灰色半透明并拦截点击）
    ;   + 4 条天蓝边框窗口（统一为编辑窗边框样式）
    ; 原因：单窗口 SetWindowRgn 挖洞仅 0.63ms/次，无 4 块窗口的尺寸变化重绘（4.6ms/次）与接缝线；
    ;       蒙版首次 Show 即为挖出选区洞的最终形态（先检测悬停窗口再显示），
    ;       避免「全屏变灰 → 切洞」的中间帧导致按 F1 瞬间屏幕闪烁
    maskOv := MaskOverlayCreate()
    borders := BorderStripsCreate()

    ; 选区透明拦截层（alpha 极小，几乎不可见，盖住选区防止点击穿透）
    selGui := Gui("-Caption +ToolWindow +AlwaysOnTop -DPIScale")
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

    ; 悬停/拖动定时器句柄与选区动作工具栏（finally 中用于异常兜底关闭）
    hoverFunc := 0
    dragFunc := 0
    toolbar := 0

    try {
        ; 悬停更新：鼠标移动超过阈值时重新检测窗口（10ms 高频刷新，蒙版跟随更平滑减少跳帧闪烁）
        hoverFunc := () => _HoverUpdate(state, region, borders, selGui, maskOv, selLast)
        SetTimer hoverFunc, 10

        ; 等待左键按下（进入拖动阶段）
        while !state.canceled {
            if GetKeyState("LButton") {
                MouseGetPos &tx, &ty
                state.dragStartX := tx
                state.dragStartY := ty
                state.isDragging := false
                break
            }
            if A_TickCount > deadline {
                state.canceled := true  ; 超时未操作，自动取消
                break
            }
            Sleep 10
        }
        SetTimer hoverFunc, 0
        hoverFunc := 0

        if state.canceled
            return "cancel"

        ; 拖动更新：超过阈值即实时绘制矩形（10ms 高频刷新，蒙版/边框跟随更平滑）
        dragFunc := () => _DragUpdate(state, region, borders, selGui, maskOv, selLast)
        SetTimer dragFunc, 10

        while !state.canceled {
            if !GetKeyState("LButton") {
                if state.isDragging {
                    MouseGetPos &tx, &ty
                    region.SetRegionByPos(tx, ty, state.dragStartX, state.dragStartY)
                    _MoveSelectLayers(borders, selGui, region, selLast)
                    region.GetRegionRect(&rx, &ry, &rw, &rh)
                    MaskOverlayHole(maskOv, rx, ry, rw, rh)
                }
                break
            }
            if A_TickCount > deadline {
                state.canceled := true  ; 超时未完成，自动取消
                break
            }
            Sleep 10
        }
        SetTimer dragFunc, 0
        dragFunc := 0

        if state.canceled
            return "cancel"

        ; 拖出矩形后：展示动作工具栏并进入微调阶段（选区保持未固定，可拖动平移/改大小）；
        ; 工具栏动作即确认：点击标注工具 → 自动选中第 1 色（红色）并直接进入编辑窗（无需再点颜色）；
        ; 保存/钉屏/复制 直接输出。仅点击窗口（未拖出矩形）时跳过，保持原快速截图行为（直接进编辑窗）
        ; 保存动作特例：弹保存框确认，取消保存则恢复覆盖层回到选区微调（对齐"取消不结束截图"的交互）
        action := "editor"
        if state.isDragging {
            toolbar := SelToolbarCreate(state, region)
            state.selTb := toolbar
            while true {
                action := SelectRegionAdjust(state, region, borders, selGui, maskOv, deadline, toolbar)
                if action = "cancel"
                    return "cancel"
                if action != "save"
                    break
                ; 保存动作：临时禁用选区取消热键（避免保存框内操作误取消选区）
                Hotkey "*RButton", "Off"
                ScreenshotEscCancel := 0
                EscUnregister()
                ; 先定格当前选区画面、隐藏覆盖层（不销毁）弹系统保存框；
                ; 取消保存恢复覆盖层返回 ""（已释放定格位图）
                ScreenshotSaveFilename := ConfirmSelectionSave(region, maskOv, borders, selGui, toolbar)
                ; 恢复选区取消热键（成功/取消统一恢复，外层确认路径再统一注销）
                Hotkey "*RButton", (*) => (state.canceled := true), "On"
                ScreenshotEscCancel := () => (state.canceled := true)
                EscRegister()
                if ScreenshotSaveFilename != ""
                    break  ; 保存成功，返回 "save" 由外层落盘
                ; 取消保存：重置动作与取消标志并顺延超时截止点，继续选区微调（可再调整/换动作/再保存）
                state.action := ""
                state.canceled := false
                deadline := A_TickCount + SCREENSHOT_TIMEOUT_MS
            }
        }

        ; 选区已确认：蒙版/边框保留不销毁，由后续流程接管（编辑器就地升级 / 钉屏）；
        ; 拦截层与工具栏按动作延迟清理，避免「蒙版销毁 → 新界面就绪」之间整屏全亮造成明暗跳变闪烁
        Hotkey "*RButton", "Off"
        ScreenshotEscCancel := 0
        EscUnregister()
        state.confirmed := true
        ScreenshotSelOverlays := {mask: maskOv, borders: borders, selGui: selGui, toolbar: toolbar}
        initialTool := state.tool      ; 点击标注工具时的预选工具（编辑器初始工具）
        initialColor := state.colorIdx ; 点击标注工具时自动选中的颜色索引（编辑器初始颜色）
        return action
    } finally {
        if hoverFunc
            SetTimer hoverFunc, 0
        if dragFunc
            SetTimer dragFunc, 0
        ; 取消/异常路径立即清理覆盖层；成功路径保留（延迟清理），避免整屏明暗跳变
        if !state.confirmed
            _DestroyOverlays(maskOv, borders, selGui, toolbar)
    }
}

; 底层销毁覆盖层资源（幂等，可安全重复调用）
; 蒙版/边框可能已被后续流程接管（传 0 跳过），拦截层与工具栏始终销毁
_DestroyOverlays(maskOv, borders, selGui, toolbar := 0) {
    global ScreenshotMaskHwnds, ScreenshotSelHwnd, ScreenshotBorderHwnds, ScreenshotEscCancel
    global ToolbarHoverActive
    try Hotkey "*RButton", "Off"
    if ScreenshotEscCancel {
        ScreenshotEscCancel := 0
        EscUnregister()  ; 仅在截图阶段 Esc 仍注册时注销（防止与正常路径重复递减）
    }
    BorderStripsDestroy(borders)
    if selGui
        try selGui.Destroy()
    MaskOverlayDestroy(maskOv)
    if toolbar {
        ; 工具栏销毁后悬停分发不再转发到其状态实例（防止 ToolbarHoverActive 悬空引用）
        if IsObject(toolbar.HoverState) && ToolbarHoverActive = toolbar.HoverState
            ToolbarHoverActive := 0
        try toolbar.HoverState.ClearTransient()  ; 先取消渐变/清理暂存，避免 Map 残存控件引用
        try toolbar.Destroy()
    }
    ScreenshotMaskHwnds := []
    ScreenshotSelHwnd := 0
    ScreenshotBorderHwnds := []
}

; 销毁遗留的选区覆盖层（编辑器环境就绪后由 ShowEditor 回调 / 独立输出动作后调用；异常时兜底，幂等）
; keepMask / keepBorders：蒙版/边框被后续流程接管时保留（编辑器就地升级复用蒙版+边框、钉屏接管边框），
; 其余情况默认全部销毁，避免覆盖层残留卡屏
FinishSelectionOverlays(keepMask := false, keepBorders := false) {
    global ScreenshotSelOverlays
    if !ScreenshotSelOverlays
        return
    ovs := ScreenshotSelOverlays
    ScreenshotSelOverlays := 0
    _DestroyOverlays(keepMask ? 0 : ovs.mask, keepBorders ? 0 : ovs.borders, ovs.selGui, ovs.toolbar)
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
;    （state.tool 记初始工具、state.colorIdx 记初始颜色，编辑器打开时同步该状态，无需再点颜色）；
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
    try {
        ; 等待工具栏动作或取消（动作由工具栏按钮回调写入 state.action）
        while !state.canceled && state.action = "" {
            if A_TickCount > deadline {
                state.canceled := true  ; 超时未确认，自动取消
                break
            }
            Sleep 10
        }
        return state.canceled ? "cancel" : state.action
    } finally {
        OnMessage(0x201, AdjustLButtonDown, 0)
        OnMessage(0x200, AdjustMouseMove, 0)
        OnMessage(0x202, AdjustLButtonUp, 0)
        OnMessage(0x203, AdjustLButtonDblClk, 0)
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
    global ScreenshotAdjustCtx
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
        ctx.state.action := "copy"
}

; 左键按下：判定点击命中区（选区内部=平移 / 外侧边框带=改大小），并启动对应拖动；
; 选区外空白点击不响应（动作统一由工具栏提供）
AdjustLButtonDown(wParam, lParam, msg, hwnd) {
    global ScreenshotAdjustCtx
    ctx := ScreenshotAdjustCtx
    if !ctx || ctx.drag || ctx.state.canceled || ctx.state.confirmed
        return
    ; 仅响应本流程的选区拦截层与蒙版窗口（蒙版/拦截层之外的点击如钉屏窗口不参与微调）
    if (hwnd != ctx.selGui.Hwnd && hwnd != ctx.mask.hwnd)
        return
    MouseGetPos &mx, &my
    ctx.region.GetRegionRect(&l, &t, &w, &h)
    hit := _AdjustHitTest(mx, my, l, t, l + w, t + h)
    if (hit = "confirm")
        return  ; 点击选区外空白：忽略
    ; 双击选区内部 → 直接复制到剪贴板并关闭截图（与工具栏「📋 复制」按钮一致），不进入平移；
    ; 单击仍平移（双击的第一次按下会短暂启动平移、松开即结束，鼠标位移很小，选区不位移）
    if (hit = "move" && _IsSelectionDoubleClick(mx, my)) {
        ctx.state.action := "copy"
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
    if ctx.toolbar
        SelToolbarsReposition(ctx.toolbar, ctx.region)
    d.appliedL := l, d.appliedT := t, d.appliedR := l + w, d.appliedB := t + h
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

; 判定是否为「双击」：与上次按下间隔不超过系统双击时间（GetDoubleClickTime）且位移不超过
; 系统双击矩形（SM_CXDOUBLECLK/SM_CYDOUBLECLK，默认各 4px）——与 Windows/ShareX 原生双击判定一致，
; 用户调大双击容差设置时同样生效；
; 用于「双击选区 → 直接复制」。static 记录上次按下时间与坐标供连续两次按下判定；
; 首按必然返回 false 并记录状态，次按在时间/位移阈值内才判定为双击（不依赖窗口类 CS_DBLCLKS，
; 无需注册 0x203，与选区单击平移共用 0x201 消息钩子）
_IsSelectionDoubleClick(mx, my) {
    static lastTick := 0, lastX := -9999, lastY := -9999
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
; 选区动作工具栏：标注工具 + 保存 / 钉屏 / 复制（与编辑窗工具栏同风格）
; 拖出矩形后展示在选区下方并跟随选区；点击即写入 state.action / state.tool / state.colorIdx
; ------------------------------------------------------------------

; 创建动作工具栏并定位到选区下方（视觉风格与编辑窗工具栏一致，复用其配色常量）
; 标注工具按钮直接展示（矩形/箭头/椭圆/马赛克，顺序与编辑窗一致），点击后自动选中第 1 色（红色）
; 并直接进入编辑窗（无需再点颜色，工具与颜色状态同步显示）；
; 保存/钉屏/复制 直接输出后关闭截图（复制最右，与编辑窗工具栏保持一致）；退出由 Esc / 右键承担
SelToolbarCreate(state, region) {
    global SelToolbarW, SelToolbarH
    global ToolbarHoverActive
    global EDIT_TB_BG, EDIT_TB_SEP
    tb := Gui("-Caption +AlwaysOnTop -DPIScale ToolWindow")
    tb.BackColor := EDIT_TB_BG
    tb.SetFont("s11", "Microsoft YaHei")
    ; DPI 缩放：字体 s11 由 AHK 按 DPI 自动放大，控件尺寸需手动等比放大（ToolbarDpi）。
    ; 未 Show 的窗口无有效 DPI，先临时显示到鼠标位置读取所在显示器 DPI，再按缩放因子建控件
    MouseGetPos &dpiX, &dpiY
    tb.Show("NA x" dpiX " y" dpiY " w10 h10")
    SetToolbarDpiScale(tb.Hwnd)
    tb.MarginX := ToolbarDpi(8)
    tb.MarginY := ToolbarDpi(6)
    ; 通用扁平按钮悬停状态（与编辑窗工具栏共用同一套窗口级鼠标处理）
    tb.HoverState := ToolbarHoverState()
    ToolbarHoverActive := tb.HoverState
    tb.HoverState.selFn := SelIsToolSelected.Bind(state)  ; 仅工具按钮参与选中态
    ; 工具按钮（风格同编辑窗工具栏）；.Bind 捕获动作/state，避免闭包引用循环变量
    ; 标签带 Unicode 图标前缀，一眼识别工具用途（▭矩形 →箭头 ◯椭圆 ▦马赛克）
    tools := [["rect", "▭ 矩形"], ["arrow", "→ 箭头"], ["ellipse", "◯ 椭圆"], ["mosaic", "▦ 马赛克"]]
    for t in tools {
        c := tb.HoverState.Add(tb, t[2], SelToolbarAction.Bind(t[1], state))
        state.toolBtns[t[1]] := c  ; 记录工具按钮，刷新选中态用
    }
    ToolbarSeparator(tb)
    ; 输出按钮：保存 / 钉屏 / 复制（复制最右：复制后关闭截图，与编辑窗工具栏保持一致）
    ; 图标统一为符号字体字符（与工具按钮同风格，避免 emoji 彩色混排）：⤓保存 ⤒钉屏 ⧉复制
    ; （⤓=存入 ⤒=置顶 ⧉=拷贝，缺字时系统回退 Segoe UI Symbol 单色渲染）
    tb.HoverState.Add(tb, "⤓ 保存", SelToolbarAction.Bind("save", state))
    tb.HoverState.Add(tb, "⤒ 钉屏", SelToolbarAction.Bind("pin", state))
    tb.HoverState.Add(tb, "⧉ 复制", SelToolbarAction.Bind("copy", state))
    ; 先 AutoSize 拿到实际尺寸（缓存，跟随定位时复用，避免每帧 WinGetPos），
    ; 再缓存按钮客户区坐标（布局定稿后悬停命中测试用），最后摆到选区下方
    tb.Show("NA AutoSize")
    WinGetPos &tx, &ty, &tw, &th, "ahk_id " tb.Hwnd
    SelToolbarW := tw, SelToolbarH := th
    tb.HoverState.CacheRects()
    SelToolbarsReposition(tb, region)
    ToolbarFadeIn(tb.Hwnd)  ; 淡入出现（约 130ms），避免工具栏"硬出现"
    return tb
}

; 工具栏整体定位：置于选区正下方居中；下方放不下则移到选区上方；贴近屏幕边缘时钳制在所在显示器工作区内
SelToolbarsReposition(toolbar, region) {
    global SelToolbarW, SelToolbarH
    if !WinExist("ahk_id " toolbar.Hwnd)
        return
    region.GetRegionRect(&x, &y, &w, &h)
    MonitorGetWorkArea(MonitorIndexAt(x + w // 2, y + h // 2), &ml, &mt, &mr, &mb)
    tw := SelToolbarW, th := SelToolbarH
    cx := Min(Max(x + w // 2, ml + tw // 2), mr - tw // 2)
    cy := y + h + 8
    if (cy + th > mb)
        cy := Max(y - th - 8, mt)  ; 下方放不下则整体移到选区上方
    px := cx - tw // 2
    py := Max(cy, mt)
    toolbar.Move(px, py, tw, th)
    if IsObject(toolbar.HoverState)
        toolbar.HoverState.SetWindowPos(px, py, tw, th)  ; 同步悬停命中测试的窗口坐标缓存
}

; 工具按钮选中判断（悬停系统选中态回调用；输出按钮等非工具按钮恒 false）
SelIsToolSelected(state, ctrl) {
    for name, c in state.toolBtns
        if (c = ctrl)
            return name = state.tool
    return false
}

; 工具栏按钮回调：
;   标注工具 → 记录预选工具并自动选中第 1 色（红色），隐藏工具栏后直接进入编辑模式（"editor"）；
;              编辑器打开时同步该工具与颜色状态，立即可标注（无需再点颜色）
;   保存/钉屏/复制 → 写入动作由 SelectRegionToCapture 分发；退出由 Esc / 右键承担
SelToolbarAction(action, state, *) {
    if (action = "arrow" || action = "rect" || action = "ellipse" || action = "mosaic") {
        state.tool := action
        state.colorIdx := 1  ; 自动选中第 1 色（红色），编辑器打开时同步该状态
        if state.selTb
            state.selTb.Hide()  ; 隐藏主工具栏（避免截图阶段残留），进入编辑模式
        action := "editor"
    }
    state.action := action
}

; ------------------------------------------------------------------
; 截图：截取指定区域，返回 GDI+ bitmap（调用方负责释放）；失败返回 0
; ------------------------------------------------------------------
CaptureRegion(region) {
    pBitmap := Gdip_BitmapFromScreen(region.ScreenString(), 0x40CC0020)
    if (!pBitmap || pBitmap = -1)
        return 0
    return pBitmap
}

; ------------------------------------------------------------------
; 热键入口（默认 F1，热键可配置，见 Hotkeys.ahk）
; ------------------------------------------------------------------
SelectRegionToCapture() {
    global ScreenshotEnabled, ScreenshotSelOverlays, ScreenshotSaveFilename, ScreenshotSaveBitmap

    ; 功能关闭时直接返回（不透传 F1）
    if !ScreenshotEnabled {
        return
    }

    DebugLog("Screenshot: 热键触发")

    ; 临时启用每显示器 DPI 感知，确保 GDI+ 截图坐标正确（高 DPI / 多显示器）
    prevCtx := DllCall("SetThreadDpiAwarenessContext", "Ptr", -3, "Ptr")
    try {
        region := RegionSetting()
        action := SelectRegion(region, &initialTool, &initialColor)
        if action = "cancel" {
            DebugLog("Screenshot: 已取消")
            return
        }
        ; 选区确认后蒙版/边框仍保留（见 SelectRegion）：仅隐藏选区内的透明拦截层（几乎不可见）；
        ; 边框位于选区外侧（BorderStripsMove），不进入抓屏区域，保持显示直至后续动作
        ; 就绪（由 FinishSelectionOverlays 统一处理），避免释放瞬间边框消失造成闪烁
        ; save 动作例外：位图已在 SelectRegion 内定格（ConfirmSelectionSave 先抓图再弹框），跳过公共抓图
        pBitmap := 0
        if action != "save" {
            if ScreenshotSelOverlays {
                ScreenshotSelOverlays.selGui.Hide()
            }
            pBitmap := CaptureRegion(region)
            if !pBitmap {
                DebugLog("Screenshot: 截图失败")
                FinishSelectionOverlays()  ; 兜底销毁遗留覆盖层，避免蒙版残留卡屏
                return
            }
        }
        ; 按工具栏动作分发：标注 → 编辑窗；复制/保存/钉屏 → 直接输出后关闭截图
        switch action {
            case "copy":
                Gdip_SetBitmapToClipboard(pBitmap)
                Gdip_DisposeImage(pBitmap)
                FinishSelectionOverlays()
                DebugLog("Screenshot: 已复制到剪贴板")
            case "save":
                ; 位图与路径已在选区微调阶段确认（SelectRegion 内先定格画面再弹框，
                ; 取消则恢复覆盖层回到选区微调，不会走到这里），此处仅销毁覆盖层恢复屏幕并落盘
                pBitmap := ScreenshotSaveBitmap
                ScreenshotSaveBitmap := 0  ; 复位，避免残留影响下一次截图
                filename := ScreenshotSaveFilename
                ScreenshotSaveFilename := ""
                FinishSelectionOverlays()
                if pBitmap && Gdip_SaveBitmapToFile(pBitmap, filename) {
                    DebugLog("Screenshot: 已保存 -> " filename)
                } else {
                    DebugLog("Screenshot: 保存失败")
                    TrayTip "截图保存失败", "无法写入文件，请检查磁盘空间或目标目录权限。", "IconX"
                }
                if pBitmap
                    Gdip_DisposeImage(pBitmap)
            case "pin":
                ; 非阻塞钉屏：位图由钉屏会话接管，窗口关闭时自动释放；
                ; 以选区左上角为锚点（topleft）：窗口尺寸与选区一致时精确覆盖选区（无跳位），
                ; 缩图时从选区左上角向右下展开，视觉连续；
                ; 选区边框交接给钉屏会话（拖动跟随、关闭释放），蒙版/拦截层/工具栏销毁
                region.GetRegionRect(&px, &py, &pw, &ph)
                PinCreateAsync(pBitmap, px, py, "topleft", ScreenshotSelOverlays ? ScreenshotSelOverlays.borders : 0)
                FinishSelectionOverlays(false, true)
                DebugLog("Screenshot: 已钉屏")
            default:  ; "editor"：打开标注编辑窗（接管 pBitmap 生命周期，编辑结束时自动释放）
                ; initialTool/initialColor：点击标注工具时自动选中的预选工具与第 1 色（红色），
                ; 编辑器打开时同步该状态，立即可标注；点击窗口路径（未选工具）为空/0 → 编辑器无工具进入，
                ; 左键拖动可移动图片，点击工具栏工具后自动选中第 1 色直接绘制；
                ; 蒙版/边框就地升级给编辑器（洞切换到编辑窗、边框跟随编辑窗），不销毁重建；
                ; 编辑器环境（编辑窗首帧）就绪后由 leftoverCleanup 销毁遗留的拦截层与选区工具栏，消除整屏明暗跳变
                ovs := ScreenshotSelOverlays
                inherited := ovs ? {mask: ovs.mask, borders: ovs.borders} : 0
                try {
                    result := ShowEditor(pBitmap, region, FinishSelectionOverlays.Bind(true, true), initialTool, initialColor, inherited)
                } catch as e {
                    FinishSelectionOverlays()  ; 编辑器初始化异常：兜底销毁遗留覆盖层，避免全屏蒙版卡屏
                    throw
                }
                DebugLog("Screenshot: 编辑结束 -> " result)
        }
    } finally {
        DllCall("SetThreadDpiAwarenessContext", "Ptr", prevCtx, "Ptr")
    }
}
