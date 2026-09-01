; ==================================================================
; 工具栏通用 UI 组件（选区动作工具栏 / 编辑窗工具栏共用）
;   - 颜色色块：外框 + 内块，亮度自适应文字色，选中态 ✔ + 外框高亮
;   - 扁平文字按钮：Text 控件模拟，统一悬停高亮 / 选中态（窗口级鼠标消息统一处理）
; 依赖：Config.ahk（EDIT_TB_* / EDIT_COLORS 配色常量）
; ==================================================================

; ------------------------------------------------------------------
; 工具栏 DPI 缩放
; 背景：-DPIScale 工具栏的字体（s11）由 AHK 按 DPI 自动放大（按物理点渲染），
;       而控件尺寸是硬编码物理像素不放大 → 高 DPI 下按钮偏小、文字拥挤/裁切。
;       因此只手动等比放大控件尺寸（ToolbarDpi），字体保持原样避免双重放大。
; 各工具栏创建时先 SetToolbarDpiScale 设置缩放因子，再按 ToolbarDpi() 建控件。
; ------------------------------------------------------------------
global ToolbarDpiScale := 1.0

; 物理像素 n 按当前 DPI 缩放因子换算（100% DPI 时 = n，行为不变）
ToolbarDpi(n) {
    global ToolbarDpiScale
    return Round(n * ToolbarDpiScale)
}

; 读取已显示窗口的 DPI（GetDpiForWindow，按窗口所在显示器）并设置全局缩放因子；
; API 取不到时回退 A_ScreenDPI。返回缩放因子。
; 注意：需在窗口 Show 后调用（未 Show 的窗口无有效 DPI/位置），且与工具栏同显示器。
SetToolbarDpiScale(hwnd) {
    global ToolbarDpiScale
    dpi := 96
    try dpi := DllCall("GetDpiForWindow", "Ptr", hwnd, "UInt")
    if !dpi
        dpi := A_ScreenDPI
    ToolbarDpiScale := dpi / 96
    return ToolbarDpiScale
}

; ------------------------------------------------------------------
; 统一分组分隔线 —— 规整工具栏内「组边界」节奏
; 前导 4px 透明留白 + 2px 竖分隔线，均与按钮等高(26)：在工具组/输出组/颜色组之间形成
; 清晰的组边界停顿，但又不喧宾夺主。选区工具栏与编辑窗两行共用，保证三处节奏一致。
; ------------------------------------------------------------------
ToolbarSeparator(tb) {
    global EDIT_TB_SEP
    ; 前导透明留白：拉大与上一组的间距，制造分组停顿（Text 默认透明透出工具栏底色）
    tb.Add("Text", "x+m y0 w" ToolbarDpi(4) " h" ToolbarDpi(26) "", "")
    ; 2px 竖分隔线
    tb.Add("Text", "x+m y0 w" ToolbarDpi(2) " h" ToolbarDpi(26) " Background" EDIT_TB_SEP, "")
}

; ------------------------------------------------------------------
; 颜色亮度 → 文字颜色（浅底黑字、深底白字）
; ------------------------------------------------------------------
SwatchMarker(color) {
    lum := ((color >> 16 & 0xFF) * 299 + (color >> 8 & 0xFF) * 587 + (color & 0xFF) * 114) / 1000
    return lum > 150 ? "cBlack" : "cWhite"
}

; ------------------------------------------------------------------
; 创建颜色色块（外框 + 内块），clickCb 为内块 Click 回调
; 返回 [f, sw]：f 外框控件（选中态高亮用），sw 内块控件
; ------------------------------------------------------------------
SwatchCreate(tb, color, clickCb) {
    global EDIT_TB_RING
    size := ToolbarDpi(26)      ; 色块外框尺寸（物理像素按 DPI 缩放）
    ring := Max(2, ToolbarDpi(2))  ; 外框环宽（最小 2px 保证可见）
    inner := size - 2 * ring    ; 内块尺寸（保证外框环两侧对称）
    rgb := Format("{:06X}", color & 0xFFFFFF)
    marker := SwatchMarker(color)
    ; 外框加 y0：x+m 会继承上一轮内块 sw（yp+2）的 y，导致后续外框顶端低 2px
    f := tb.Add("Text", "x+m y0 w" size " h" size " Background" EDIT_TB_RING, "")
    sw := tb.Add("Text", "xp+" ring " yp+" ring " w" inner " h" inner " Center 0x200 Background" rgb " " marker, "")
    sw.OnEvent("Click", clickCb)
    return [f, sw]
}

; ------------------------------------------------------------------
; 刷新色块选中态：选中时外框高亮（EDIT_TB_RING_SEL）并显示 ✔
; 注意：Opt 仅修改背景色（不附带 c 文字色）时 AHK 不会自动重绘控件，
;       外框颜色变化必须显式 Redraw 才生效（按钮/内块因带 c 选项不受影响）
; ------------------------------------------------------------------
SwatchRefresh(sw, f, color, selected) {
    global EDIT_TB_RING, EDIT_TB_RING_SEL
    rgb := Format("{:06X}", color & 0xFFFFFF)
    sw.Opt("Background" rgb " " SwatchMarker(color))
    sw.Text := selected ? "✔" : ""
    f.Opt("Background" (selected ? EDIT_TB_RING_SEL : EDIT_TB_RING))
    f.Redraw()
}

; ------------------------------------------------------------------
; 刷新图标外框选中态：选中时外框高亮（EDIT_TB_RING_SEL），未选中恢复默认
; 用于无内文变化的图标选择项（如粗细档位图标）；同上纯背景色 Opt 需显式 Redraw
; ------------------------------------------------------------------
RingRefresh(f, selected) {
    global EDIT_TB_RING, EDIT_TB_RING_SEL
    f.Opt("Background" (selected ? EDIT_TB_RING_SEL : EDIT_TB_RING))
    f.Redraw()
}

; ------------------------------------------------------------------
; 创建粗细档位图标（外框 + 内块 + 居中实心圆点），clickCb 为圆点内块 Click 回调
; 返回 [f, b]：f 外框（选中态高亮用）、b 内块（含 ● 圆点）
; 结构同 SwatchCreate：外框 30×30 实心，内块 26×26 盖中心形成 2px 环，
; 圆点用 ● 字符渲染（字号随档位 8/11/15 表示细/中/粗，字体随 DPI 自动放大），
; 圆点图标仅视觉，不随选中变化（选中态由外框白环标识）
; ------------------------------------------------------------------
PenWidthIconCreate(tb, dotSize, clickCb) {
    global EDIT_TB_RING, EDIT_TB_BTN_BG, EDIT_TB_BTN_TEXT
    size := ToolbarDpi(26)      ; 图标外框尺寸（物理像素按 DPI 缩放）
    ring := Max(2, ToolbarDpi(2))  ; 外框环宽（最小 2px 保证可见）
    inner := size - 2 * ring    ; 内块尺寸（保证外框环两侧对称）
    f := tb.Add("Text", "x+m y0 w" size " h" size " Background" EDIT_TB_RING, "")
    f.GetPos(&fx, &fy)
    b := tb.Add("Text", "x" (fx + ring) " y" (fy + ring) " w" inner " h" inner " Center 0x200 Background" EDIT_TB_BTN_BG " c" EDIT_TB_BTN_TEXT, "●")
    b.SetFont("s" dotSize, "Microsoft YaHei")
    b.OnEvent("Click", clickCb)
    return [f, b]
}

; ------------------------------------------------------------------
; 悬停背景微渐变 —— 按钮非选中态在 普通 ↔ 悬停 之间柔和过渡（6 步 × 12ms ≈ 72ms）
; 切换时不瞬时跳变，而从上次底色经通道插值平滑过渡；选中态即时切换（动作更清晰）。
; 定时器以 WinExist + try 兜底，杜绝工具栏销毁后残留定时器报错。
; ------------------------------------------------------------------
global _HoverEase := Map()   ; 按钮控件 -> {timer, step, total, fromBg, toBg, toText}
global _HoverLast := Map()   ; 按钮控件 -> 最近应用的非虚拟底色（作为下一次渐变起点）

; 颜色插值：两个 6 位十六进制 RGB 间按比例 t(0-1) 取中间色，返回 6 位十六进制
HoverLerpColor(h1, h2, t) {
    c1 := Integer("0x" h1), c2 := Integer("0x" h2)
    r := Round(((c1 >> 16) & 0xFF) + (((c2 >> 16) & 0xFF) - ((c1 >> 16) & 0xFF)) * t)
    g := Round(((c1 >> 8) & 0xFF) + (((c2 >> 8) & 0xFF) - ((c1 >> 8) & 0xFF)) * t)
    b := Round((c1 & 0xFF) + ((c2 & 0xFF) - (c1 & 0xFF)) * t)
    return Format("{:02X}{:02X}{:02X}", r, g, b)
}

; 启动按钮背景渐变；toText 为渐变期间固定文字色（随 Background 一起 Opt 触发自动重绘，无需 Redraw）
HoverEaseStart(btn, fromBg, toBg, toText) {
    if _HoverEase.Has(btn) {
        SetTimer _HoverEase[btn].timer, 0
        _HoverEase.Delete(btn)
    }
    st := {btn: btn, fromBg: fromBg, toBg: toBg, toText: toText, step: 0, total: 6}
    st.timer := () => HoverEaseTick(st)
    SetTimer st.timer, 12
    _HoverEase[btn] := st
}

HoverEaseTick(st) {
    st.step++
    btn := st.btn
    ; 工具栏可能已被销毁：安全终止并清理
    if !WinExist("ahk_id " btn.Hwnd) {
        SetTimer st.timer, 0
        if _HoverEase.Has(btn) && _HoverEase[btn] = st
            _HoverEase.Delete(btn)
        return
    }
    if (st.step >= st.total) {
        SetTimer st.timer, 0
        if _HoverEase.Has(btn) && _HoverEase[btn] = st
            _HoverEase.Delete(btn)
        try btn.Opt("Background" st.toBg " c" st.toText)   ; 落定终值
        return
    }
    hex := HoverLerpColor(st.fromBg, st.toBg, st.step / st.total)
    try btn.Opt("Background" hex " c" st.toText)
}

; ------------------------------------------------------------------
; 扁平按钮悬停状态（每个工具栏一个实例，挂到工具栏 Gui 的 HoverState 属性）
; 窗口级 WM_MOUSEMOVE / WM_MOUSELEAVE 经 ToolbarHoverMove/Leave 转发到当前活跃实例
; ------------------------------------------------------------------
class ToolbarHoverState {
    ctrl := 0   ; 当前悬停的按钮控件
    btns := []  ; 全部扁平按钮控件
    rects := [] ; 按钮在工具栏客户区坐标缓存（[x,y,w,h]，Show 后定稿）
    wx := 0, wy := 0, ww := 0, wh := 0  ; 工具栏窗口屏幕坐标/尺寸缓存
    selFn := 0  ; 选中判断回调 fn(ctrl) → bool（工具按钮用；输出按钮恒 false）

    ; 创建扁平按钮：统一 26 高（与色块/分隔线对齐），文字垂直水平居中，登记到悬停列表
    ; 宽 74（图标+文字标签实测最宽 71px，留出居中边距不裁切；按 DPI 缩放）
    Add(tb, text, callback) {
        global EDIT_TB_BTN_BG, EDIT_TB_BTN_TEXT
        c := tb.Add("Text", "x+m w" ToolbarDpi(74) " h" ToolbarDpi(26) " Center 0x200 Background" EDIT_TB_BTN_BG " c" EDIT_TB_BTN_TEXT, text)
        c.OnEvent("Click", callback)
        this.btns.Push(c)
        return c
    }

    ; 工具栏 Show 后缓存按钮客户区坐标（布局定稿后才有效，悬停命中测试用）
    CacheRects() {
        this.rects := []
        for b in this.btns {
            b.GetPos(&bx, &by, &bw, &bh)
            this.rects.Push([bx, by, bw, bh])
        }
    }

    ; 同步工具栏窗口屏幕坐标（Move 后调用，避免每帧 WinGetPos）
    SetWindowPos(x, y, w, h) {
        this.wx := x, this.wy := y, this.ww := w, this.wh := h
    }

    ; 悬停命中刷新（WM_MOUSEMOVE 分发）：命中按钮→高亮；光标离开窗口→复位
    HitTestAndRefresh(hwnd) {
        static TME_LEAVE := 0x2
        tme := Buffer(16, 0)
        NumPut("UInt", 16, tme, 0)          ; cbSize
        NumPut("UInt", TME_LEAVE, tme, 4)   ; dwFlags
        NumPut("Ptr", hwnd, tme, 8)         ; hwndTrack
        DllCall("TrackMouseEvent", "Ptr", tme)
        DllCall("GetCursorPos", "Ptr", buf := Buffer(8))
        mx := NumGet(buf, 0, "Int"), my := NumGet(buf, 4, "Int")
        ; 光标不在工具栏范围内：复位悬停（兜底；正常路径由 WM_MOUSELEAVE 处理）
        if (mx < this.wx || my < this.wy || mx >= this.wx + this.ww || my >= this.wy + this.wh) {
            if this.ctrl {
                old := this.ctrl
                this.ctrl := 0  ; 先清悬停再刷新，避免误判为仍悬停
                this.Apply(old, this.IsSelected(old))
            }
            return
        }
        ; 命中测试：遍历扁平按钮的客户区坐标缓存
        c := 0
        for i, b in this.btns {
            r := this.rects[i]
            if (mx >= this.wx + r[1] && mx < this.wx + r[1] + r[3] && my >= this.wy + r[2] && my < this.wy + r[2] + r[4]) {
                c := b
                break
            }
        }
        if (c = this.ctrl)
            return
        ; 悬停变化：先记录新按钮，再统一刷新新旧状态（普通/悬停/选中 → 重建位图）
        old := this.ctrl
        this.ctrl := c
        if old
            this.Apply(old, this.IsSelected(old))
        if c
            this.Apply(c, this.IsSelected(c))
    }

    ; WM_MOUSELEAVE：光标离开工具栏窗口，复位悬停高亮（避免悬停态"粘住"）
    Leave() {
        if this.ctrl {
            old := this.ctrl
            this.ctrl := 0
            this.Apply(old, this.IsSelected(old))
        }
    }

    ; 应用按钮状态（选中优先，其次悬停，否则普通背景）
    ; 选中态：靛蓝墨底 + 亮靛文字，精制低饱和；即时切换并取消进行中的悬停渐变。
    ; 非选中态：普通 ↔ 悬停 间走微渐变(HoverEaseStart)，柔和过渡。
    Apply(btn, sel) {
        global EDIT_TB_BTN_BG, EDIT_TB_BTN_HOVER, EDIT_TB_BTN_SEL, EDIT_TB_BTN_SEL_TEXT, EDIT_TB_BTN_TEXT
        if sel {
            if _HoverEase.Has(btn) {
                SetTimer _HoverEase[btn].timer, 0
                _HoverEase.Delete(btn)
            }
            btn.Opt("Background" EDIT_TB_BTN_SEL " c" EDIT_TB_BTN_SEL_TEXT)
            _HoverLast[btn] := EDIT_TB_BTN_SEL
            return
        }
        target := (this.ctrl = btn) ? EDIT_TB_BTN_HOVER : EDIT_TB_BTN_BG
        from := _HoverLast.Has(btn) ? _HoverLast[btn] : EDIT_TB_BTN_BG
        _HoverLast[btn] := target
        if (from = target)
            btn.Opt("Background" target " c" EDIT_TB_BTN_TEXT)
        else
            HoverEaseStart(btn, from, target, EDIT_TB_BTN_TEXT)
    }

    ; 工具栏销毁时清理本实例按钮的渐变/底色暂存，避免 Map 残存控件引用导致内存累积
    ClearTransient() {
        for b in this.btns {
            if _HoverEase.Has(b) {
                SetTimer _HoverEase[b].timer, 0
                _HoverEase.Delete(b)
            }
            _HoverLast.Delete(b)
        }
    }

    ; 按钮是否选中（未设置选中回调时恒 false，如输出按钮）
    IsSelected(btn) {
        if this.selFn
            return this.selFn.Call(btn)
        return false
    }

    ; 强制刷新指定按钮（选中态变化时调用，如切换工具）
    Refresh(btn, sel := "") {
        if (sel = "")
            sel := this.IsSelected(btn)
        this.Apply(btn, sel)
    }
}

; ------------------------------------------------------------------
; 悬停消息全局分发（常驻注册一次）：转发给当前活跃工具栏的悬停状态
; ToolbarHoverActive：选区工具栏 / 编辑窗工具栏（第一行）激活时指向对应 HoverState 实例，销毁时清 0
; ToolbarHoverAux：辅助实例（编辑窗第二行颜色行的"清除"按钮等），与主实例同时接收消息
; ------------------------------------------------------------------
global ToolbarHoverActive := 0
global ToolbarHoverAux := 0

ToolbarHoverMove(wParam, lParam, msg, hwnd) {
    global ToolbarHoverActive, ToolbarHoverAux
    if ToolbarHoverActive
        ToolbarHoverActive.HitTestAndRefresh(hwnd)
    if ToolbarHoverAux && ToolbarHoverAux != ToolbarHoverActive
        ToolbarHoverAux.HitTestAndRefresh(hwnd)
}

ToolbarHoverLeave(wParam, lParam, msg, hwnd) {
    global ToolbarHoverActive, ToolbarHoverAux
    if ToolbarHoverActive
        ToolbarHoverActive.Leave()
    if ToolbarHoverAux && ToolbarHoverAux != ToolbarHoverActive
        ToolbarHoverAux.Leave()
}

OnMessage(0x200, ToolbarHoverMove)
OnMessage(0x2A3, ToolbarHoverLeave)

; ------------------------------------------------------------------
; 工具栏淡入：创建后从全透明渐变到不透明（约 13 帧 × 10ms ≈ 130ms）
; 避免工具栏"硬出现"的生硬感；完成时移除透明样式（WinSetTransparent Off）
; 窗口被销毁/异常时由 WinExist + try 兜底安全终止
; ------------------------------------------------------------------
ToolbarFadeIn(hwnd) {
    fade := {hwnd: hwnd, alpha: 0}
    fade.step := () => _ToolbarFadeTick(fade)
    try WinSetTransparent 0, "ahk_id " hwnd
    SetTimer fade.step, 10
}

_ToolbarFadeTick(fade) {
    ; 窗口可能已被销毁（如用户快速取消/切换）：安全终止，不弹错
    if !WinExist("ahk_id " fade.hwnd) {
        SetTimer fade.step, 0
        return
    }
    fade.alpha += 21
    if fade.alpha >= 255 {
        try WinSetTransparent "Off", "ahk_id " fade.hwnd
        SetTimer fade.step, 0
        return
    }
    try WinSetTransparent fade.alpha, "ahk_id " fade.hwnd
}
