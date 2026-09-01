; ==================================================================
; 截图覆盖层共享组件（蒙版 + 边框）
; 选区 / 编辑器 / 钉屏 三阶段复用同一套覆盖层，保证界面视觉一致：
;   - 蒙版：全屏单窗口挖洞（灰色半透明，矩形处露出下层），覆盖所有显示器并集
;   - 边框：4 条半透明窗口围绕矩形（统一为编辑窗天蓝框样式 EDIT_BORDER_COLOR）
; 依赖：Config.ahk（MASK_COLOR / MASK_TRANSPARENCY / EDIT_BORDER_COLOR / EDIT_BORDER_WIDTH）
; ==================================================================

; ------------------------------------------------------------------
; 工具函数
; ------------------------------------------------------------------

; 返回坐标点所在的显示器编号
MonitorIndexAt(x, y) {
    Loop MonitorGetCount() {
        MonitorGet(A_Index, &ml, &mt, &mr, &mb)
        if (x >= ml && x < mr && y >= mt && y < mb)
            return A_Index
    }
    return 1
}

; 所有显示器的并集边界（覆盖全部屏幕，支持负坐标的左侧/上方显示器）
GetAllMonitorsBounds(&mx, &my, &mw, &mh) {
    mx := my := 0x7FFFFFFF
    maxR := maxB := -0x7FFFFFFF
    Loop MonitorGetCount() {
        MonitorGet(A_Index, &l, &t, &r, &b)
        mx := Min(mx, l), my := Min(my, t)
        maxR := Max(maxR, r), maxB := Max(maxB, b)
    }
    mw := maxR - mx, mh := maxB - my
}

; 快速移动/缩放窗口：DllCall SetWindowPos 异步移动（不等待窗口过程/DWM，消除多窗口拖动卡顿）
; 与钉屏 PinMoveWindow 同思路；选区拖动需同时改尺寸，故不设 SWP_NOSIZE；
; 不设 SWP_NOREDRAW：边框为普通窗口，尺寸变化时新区域需重绘避免黑边（纯色填充无闪烁）
; flags：0x0004 SWP_NOZORDER | 0x0010 SWP_NOACTIVATE | 0x0400 SWP_NOSENDCHANGING
;      | 0x2000 SWP_DEFERERASE | 0x4000 SWP_ASYNCWINDOWPOS
MoveWindowFast(hwnd, x, y, w, h) {
    DllCall("SetWindowPos", "Ptr", hwnd, "Ptr", 0, "Int", x, "Int", y, "Int", w, "Int", h, "UInt", 0x6414)
}

; ------------------------------------------------------------------
; 蒙版：全屏单窗口挖洞
; 灰色半透明盖住全屏，矩形处挖洞露出下层（选区 / 编辑窗内容），并拦截非矩形区点击
; 单窗口挖洞仅需 SetWindowRgn 换 region（实测 0.63ms/次），远快于 4 块窗口的
; 尺寸变化重绘（实测 4.6ms/次），且无多窗口接缝线/贯穿全屏的透明线
; ------------------------------------------------------------------

; 创建蒙版，返回对象 {gui, hwnd, shown, last, mx, my, mw, mh}
; shown：是否已 Show（首次 Show 定位，后续仅改挖洞 region）
; last：上次矩形 {x,y,w,h}，未变化时跳过（避免每帧 SetWindowRgn 重绘导致闪烁）
MaskOverlayCreate() {
    global MASK_COLOR, MASK_TRANSPARENCY
    GetAllMonitorsBounds(&mx, &my, &mw, &mh)
    g := Gui("-Caption +ToolWindow +AlwaysOnTop -DPIScale")
    g.BackColor := MASK_COLOR
    WinSetTransparent MASK_TRANSPARENCY, g
    return { gui: g, hwnd: g.Hwnd, shown: false, last: {x: -1, y: -1, w: -1, h: -1}, mx: mx, my: my, mw: mw, mh: mh }
}

; 构建「全屏减矩形」挖洞 region（4 矩形并集），返回 GDI region 句柄
; 注意：句柄传给 SetWindowRgn 后归窗口所有，调用者不得再 DeleteObject
MaskHoleRegion(x, y, w, h, mx, my, mw, mh) {
    rx := x - mx, ry := y - my  ; 矩形在窗口客户区坐标中的位置
    hRgn := DllCall("CreateRectRgn", "Int", 0, "Int", 0, "Int", 0, "Int", 0, "UPtr")
    loop 4 {
        hTmp := DllCall("CreateRectRgn", "Int", 0, "Int", 0, "Int", 0, "Int", 0, "UPtr")
        if (A_Index = 1)
            DllCall("SetRectRgn", "UPtr", hTmp, "Int", 0, "Int", 0, "Int", mw, "Int", Max(0, ry))
        else if (A_Index = 2)
            DllCall("SetRectRgn", "UPtr", hTmp, "Int", 0, "Int", ry + h, "Int", mw, "Int", mh)
        else if (A_Index = 3)
            DllCall("SetRectRgn", "UPtr", hTmp, "Int", 0, "Int", ry, "Int", Max(0, rx), "Int", ry + h)
        else
            DllCall("SetRectRgn", "UPtr", hTmp, "Int", rx + w, "Int", ry, "Int", mw, "Int", ry + h)
        DllCall("CombineRgn", "UPtr", hRgn, "UPtr", hRgn, "UPtr", hTmp, "Int", 2)  ; RGN_OR
        DllCall("DeleteObject", "UPtr", hTmp)
    }
    return hRgn
}

; 把蒙版挖出矩形洞（矩形处透明露出下层，其余灰色半透明并拦截点击）
; 矩形无效（w/h < 1）时全屏遮罩（移除挖洞 region）；矩形未变化时跳过（去重防闪烁）
MaskOverlayHole(ov, x, y, w, h) {
    if (w < 1 || h < 1) {
        ; 矩形无效：全屏遮罩
        if !ov.shown {
            ov.gui.Show("NA x" ov.mx " y" ov.my " w" ov.mw " h" ov.mh)
            ov.shown := true
        }
        DllCall("SetWindowRgn", "UPtr", ov.hwnd, "UPtr", 0, "Int", 1)
        ov.last.x := -1, ov.last.y := -1, ov.last.w := -1, ov.last.h := -1
        return
    }
    if (x = ov.last.x && y = ov.last.y && w = ov.last.w && h = ov.last.h)
        return  ; 矩形未变化，跳过
    if !ov.shown {
        ov.gui.Show("NA x" ov.mx " y" ov.my " w" ov.mw " h" ov.mh)
        ov.shown := true
    }
    hRgn := MaskHoleRegion(x, y, w, h, ov.mx, ov.my, ov.mw, ov.mh)
    DllCall("SetWindowRgn", "UPtr", ov.hwnd, "UPtr", hRgn, "Int", 1)
    ov.last.x := x, ov.last.y := y, ov.last.w := w, ov.last.h := h
}

; 销毁蒙版（幂等）
MaskOverlayDestroy(ov) {
    if ov
        try ov.gui.Destroy()
}

; ------------------------------------------------------------------
; 边框：4 条半透明窗口围绕矩形（统一为编辑窗天蓝框样式）
; 边框画在矩形外侧（不覆盖内容）：
;   - 抓屏区域 = 矩形本身，天然不含边框，矩形内容结束时边框可保持显示直到后续流程就绪，
;     避免「隐藏边框 → 新界面出现」之间的边框消失闪烁
;   - 蒙版挖洞 = 矩形本身，边框落在蒙版上（边框窗口后建、置顶于蒙版之上），显示不受影响
; 原因：单窗口 WinSetRegion 挖洞在矩形尺寸每帧变化时强制整窗重绘导致边框抖动；
;       4 条小窗口只需 Move，零区域重设，拖动平滑
; 点击穿透由 WS_EX_TRANSPARENT (+E0x20) 交给下层窗口统一交互
; ------------------------------------------------------------------

; 创建 4 条边框窗口，返回数组
BorderStripsCreate() {
    global EDIT_BORDER_COLOR
    alpha := (EDIT_BORDER_COLOR >> 24) & 0xFF   ; 半透明度（0xCC=204，半透明天蓝）
    rgb := Format("{:06X}", EDIT_BORDER_COLOR & 0xFFFFFF)
    borders := []
    loop 4 {
        b := Gui("-Caption +ToolWindow +AlwaysOnTop -DPIScale +E0x20")
        b.BackColor := rgb
        WinSetTransparent alpha, b
        borders.Push(b)
    }
    return borders
}

; 移动 4 条边框到矩形外侧（上/下/左/右细条，围绕矩形不覆盖内容）
BorderStripsMove(borders, x, y, w, h) {
    global EDIT_BORDER_WIDTH
    b := EDIT_BORDER_WIDTH
    rects := [
        [x - b, y - b, w + 2 * b, b],    ; 上（矩形外上沿）
        [x - b, y + h, w + 2 * b, b],    ; 下（矩形外下沿）
        [x - b, y, b, h],                ; 左（矩形外左沿）
        [x + w, y, b, h]                 ; 右（矩形外右沿）
    ]
    for i, r in rects
        borders[i].Move(r[1], r[2], r[3], r[4])
}

; 销毁边框窗口数组（幂等）
BorderStripsDestroy(borders) {
    if !IsObject(borders)
        return
    for b in borders
        try b.Destroy()
}
