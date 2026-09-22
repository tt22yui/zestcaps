; ==================================================================
; Editor 子模块：Toolbar（由 Editor.ahk 机械拆分，仅搬运、逻辑不变）
; ==================================================================

; ------------------------------------------------------------------
; 悬浮工具栏（置于编辑窗下方）
; ------------------------------------------------------------------
EditorCreateToolbar() {
    global EditorHwnd, ToolbarPhase
    ; 快捷路径（无选区工具栏 promote）进入编辑：全量构建两行，复用编辑窗 DPI
    if EditorToolbar
        return  ; 已被选区 promote，不该走全量（防御）
    SetToolbarDpiScale(EditorHwnd)
    ScreenToolbarCreateRow1(EditorHwnd)
    ScreenToolbarCreateRow2()
    ToolbarPhase := "editor"
    ShowToolbarRows()
}

; ------------------------------------------------------------------
; 构建工具栏第一行（工具 + 保存/钉屏/复制）：选区与编辑共用同一行、跨阶段持久
; dpiFrom > 0：复用该已显示窗口 DPI（编辑窗路径）；否则按选区写法临时显示读鼠标所在屏 DPI
; 幂等：已存在则直接返回，避免同一控件二次 OnEvent 注册（AHK v2 二次注册是追加 handler）
; ------------------------------------------------------------------
ScreenToolbarCreateRow1(dpiFrom := 0) {
    global EditorToolbar, EditorToolbarW, EditorToolbarH
    global EditorToolButtons
    global EditorScrollButton
    global ToolbarHoverActive
    global EDIT_TB_BG, EDIT_TB_SEP
    if EditorToolbar
        return EditorToolbar
    ; 防御性重置（正常流程中清理函数已清空，这里兜底防重复调用时累积）
    EditorToolButtons := Map()
    ; 深色主题面板，微软雅黑字体（按钮统一 24 高：文字按钮/色块/分隔线对齐）
    ; +E0x08000000(WS_EX_NOACTIVATE)：工具栏不抢焦点/不激活，点击无需「先激活再点击」，
    ; 首次点击即触发按钮（否则从其它前台应用切来时首击会被激活吞掉，表现为「点了没反应」）
    EditorToolbar := Gui("-Caption +AlwaysOnTop -DPIScale ToolWindow +E0x08000000")
    EditorToolbar.BackColor := EDIT_TB_BG
    EditorToolbar.SetFont("s11", "Microsoft YaHei")
    tb := EditorToolbar
    if dpiFrom > 0
        SetToolbarDpiScale(dpiFrom)
    else {
        ; 未 Show 的窗口无有效 DPI：先临时显示到鼠标位置读取所在显示器 DPI，再按缩放因子建控件
        MouseGetPos &dpiX, &dpiY
        tb.Show("NA x" dpiX " y" dpiY " w10 h10")
        SetToolbarDpiScale(tb.Hwnd)
        tb.Hide()  ; 读完 DPI 立即隐藏，剩余构建全程不可见，仅以离屏方式量尺寸
    }
    tb.MarginX := ToolbarDpi(6)
    tb.MarginY := ToolbarDpi(5)
    ; 通用扁平按钮悬停状态（选区工具栏与编辑窗工具栏共用同一套窗口级鼠标处理）
    tb.HoverState := ToolbarHoverState()
    ToolbarHoverActive := tb.HoverState
    tb.HoverState.selFn := EditorIsSelectedTool.Bind(EditorToolButtons)  ; 仅工具按钮参与选中态

    ; 工具按钮区（PixPin 风格：矩形 / 箭头 / 椭圆 / 马赛克，选中态由 EditorToolbarRefresh 刷新）
    ; 点击行为由 ToolbarPhase 分流：选区阶段=选工具+自动选第1色+进入编辑；编辑阶段=仅切工具
    ; 统一用 Segoe MDL2 Assets：同一字体下各字形共用固定字宽与一致字面高度，
    ; 天然对齐、光学尺寸接近；此前的几何字形（Segoe UI Symbol，▭→◯▦✎）字面大小/基线不一，
    ; 与输出组 MDL2 图标混排时「大小不一、不齐」（E739 方框 / E72A 箭头 / EA3A 圆环 /
    ; E8D2 文字 / ECA5 马赛克 / ED64 画笔）
    tools := [[Chr(0xE739), "rect", "矩形"], [Chr(0xE72A), "arrow", "箭头"], [Chr(0xEA3A), "ellipse", "椭圆"], [Chr(0xE8D2), "text", "文本"], [Chr(0xECA5), "mosaic", "马赛克"], [Chr(0xED64), "brush", "画笔"]]
    for t in tools {
        c := tb.HoverState.AddIcon(tb, t[1], "Segoe MDL2 Assets", ToolbarToolClick.Bind(t[2]), t[3])
        EditorToolButtons[t[2]] := c
    }

    ; 分隔线 + 输出按钮：保存 / 钉屏 / 复制（复制最右），点击行为由 ToolbarPhase 分流
    ; 系统动作类统一用 Segoe MDL2 Assets（E74E 保存 / E840 钉屏 / E8C8 复制）
    ToolbarSeparator(tb)
    ; 滚动截图入口：仅选区阶段（dpiFrom=0）显示，位于输出组最前（保存左侧）；
    ; 进入编辑阶段由 EditorHideScrollButton **仅隐藏并保留该槽位**（不左移、不收窄），
    ; 以免工具栏变窄后重新居中而水平右移（详见 EditorHideScrollButton 注释）
    if (dpiFrom = 0)
        EditorScrollButton := tb.HoverState.AddIcon(tb, Chr(0xEC8F), "Segoe MDL2 Assets", ToolbarScrollClick, "滚动截图")  ; ScrollUpDown
    else
        EditorScrollButton := 0
    tb.HoverState.AddIcon(tb, Chr(0xE74E), "Segoe MDL2 Assets", ToolbarOutputClick.Bind("save"), "保存")
    tb.HoverState.AddIcon(tb, Chr(0xE840), "Segoe MDL2 Assets", ToolbarOutputClick.Bind("pin"), "钉屏")  ; 实心图钉 PinnedFill
    tb.HoverState.AddIcon(tb, Chr(0xE8C8), "Segoe MDL2 Assets", ToolbarOutputClick.Bind("copy"), "复制")

    ; 先 AutoSize 拿实际尺寸（缓存，拖动定位时复用，避免每帧 WinGetPos），
    ; 再缓存按钮客户区坐标（布局定稿后悬停命中测试用）。
    ; 离屏测量（x-32000）：量尺寸全程不可见，两行量好后由调用方统一定位再显示，杜绝「先闪现再跳位」
    tb.Show("NA x-32000 y-32000 AutoSize")
    WinGetPos &tx, &ty, &tw, &th, "ahk_id " EditorToolbar.Hwnd
    EditorToolbarW := tw, EditorToolbarH := th
    tb.HoverState.CacheRects()
    tb.Hide()
    return EditorToolbar
}

; ------------------------------------------------------------------
; 构建工具栏第二行（色块 + 三档线宽 + 清除）—— 仅编辑阶段显示，选区阶段隐藏
; 幂等：已存在则直接返回
; ------------------------------------------------------------------
ScreenToolbarCreateRow2() {
    global EditorColorToolbar, EditorColorToolbarW, EditorColorToolbarH
    global EditorColorSwatches, EditorSwatchFrames, EditorPenWidthFrames
    global ToolbarHoverAux
    global EDIT_COLORS, EDIT_TB_BG, EDIT_LINE_WIDTHS, EDIT_LINE_WIDTH_DISPLAY
    if EditorColorToolbar
        return EditorColorToolbar
    EditorColorSwatches := []
    EditorSwatchFrames := []
    EditorPenWidthFrames := []
    EditorColorToolbar := Gui("-Caption +AlwaysOnTop -DPIScale ToolWindow +E0x08000000")
    EditorColorToolbar.MarginX := ToolbarDpi(6)
    EditorColorToolbar.MarginY := ToolbarDpi(5)
    EditorColorToolbar.BackColor := EDIT_TB_BG
    EditorColorToolbar.SetFont("s11", "Microsoft YaHei")
    ctb := EditorColorToolbar
    ; 色块组直接从面板最左开始（无前导竖线），保持与下方工具行(row1)的紧凑对齐
    for i, color in EDIT_COLORS {
        pair := SwatchCreate(ctb, color, EditorSetColor.Bind(i))
        EditorSwatchFrames.Push(pair[1])
        EditorColorSwatches.Push(pair[2])
    }
    ; 颜色块组与笔触粗细组之间的分隔线（组间边界，与工具行/输出组节奏一致）
    ToolbarSeparator(ctb)
    ; 三档粗细图标（细/中/粗）：结构与色块一致（外框 30×30 + 内块 26×26 盖中心形成 2px 环），
    ; 内块中央 ● 圆点表示线宽档位（字号 8/11/15 对应细/中/粗）；选中态外框白环（同色块），点击切换线宽档位
    for i, w in EDIT_LINE_WIDTHS {
        pair := PenWidthIconCreate(ctb, EDIT_LINE_WIDTH_DISPLAY[i], EditorSetPenWidth.Bind(i))
        EditorPenWidthFrames.Push(pair[1])
    }
    ; 分隔线 + 清除（ToolbarSeparator 前导留白含 y0，打断色块内块 yp+2 的 y 继承，保证按钮顶端对齐）
    ToolbarSeparator(ctb)
    ctb.HoverState := ToolbarHoverState()  ; 清除按钮走同一套悬停样式（独立实例，经 ToolbarHoverAux 分发）
    ctb.HoverState.AddIcon(ctb, Chr(0xE74D), "Segoe MDL2 Assets", EditorClear, "清除")  ; MDL2 Delete 清除
    ToolbarHoverAux := ctb.HoverState
    ctb.Show("NA x-32000 y-32000 AutoSize")  ; 离屏测量，避免在系统默认放置点闪现后跳位
    WinGetPos &ctx, &cty, &ctw, &cth, "ahk_id " EditorColorToolbar.Hwnd
    EditorColorToolbarW := ctw, EditorColorToolbarH := cth
    ctb.HoverState.CacheRects()
    ctb.Hide()
    return EditorColorToolbar
}

; ------------------------------------------------------------------
; 显示已构建的工具栏行并定位到编辑窗下方、淡入（row1 可单独存在，row2 存在则一并显示）
; ------------------------------------------------------------------
ShowToolbarRows() {
    global EditorToolbar, EditorColorToolbar
    EditorRepositionToolbar()
    EditorToolbar.Show("NA")
    if EditorColorToolbar
        EditorColorToolbar.Show("NA")
    ToolbarFadeIn(EditorToolbar.Hwnd)
    if EditorColorToolbar
        ToolbarFadeIn(EditorColorToolbar.Hwnd)
}

; ------------------------------------------------------------------
; 选区 → 编辑「完整过渡动画」：row1 保持不透明、平滑移动到编辑窗锚点第一行（不重淡入，
; 消除「重淡入闪白」）；row2 从 row1 下缘向下展开 + 淡入，衔接两种模式更丝滑
; ------------------------------------------------------------------
ShowToolbarRowsAnimated() {
    global EditorToolbar, EditorToolbarW, EditorToolbarH
    global EditorColorToolbar, EditorColorToolbarW, EditorColorToolbarH
    global EditorHwnd, EditorWinW, EditorWinH
    if !EditorToolbar || !IsObject(EditorColorToolbar)
        return
    ; 起点：row1 当前坐标（选区下方；编辑窗覆盖选区后的原位）
    EditorToolbar.GetPos(&sx, &sy)
    ; 用编辑窗锚点一次性算出两行最终布局（居中 + 工作区钳制，与 EditorRepositionToolbar 同法）
    WinGetPos &ex, &ey, , , "ahk_id " EditorHwnd
    rows := [{hb: EditorToolbar, w: EditorToolbarW, h: EditorToolbarH}
        , {hb: EditorColorToolbar, w: EditorColorToolbarW, h: EditorColorToolbarH}]
    ToolbarPlaceUnder(rows, {l: ex, t: ey, r: ex + EditorWinW, b: ey + EditorWinH})
    EditorToolbar.GetPos(&fx, &fy)           ; row1 目标（第一行）
    EditorColorToolbar.GetPos(&cx, &cy)      ; row2 目标（第二行）
    ; 回滚到动画起点：row1 回原位；row2 用**自己的居中 X(cx)**、紧贴 row1 下缘且先全透明（从贴合处向下展开）
    ; 注意：row2 与 row1 宽度不同，不能复用 row1 的 X(fx)，否则动画落地后颜色行会偏左、两行中心不对齐
    EditorToolbar.Move(sx, sy)
    r2StartY := fy + EditorToolbarH
    EditorColorToolbar.Move(cx, r2StartY)
    try WinSetTransparent 0, "ahk_id " EditorColorToolbar.Hwnd
    ; 显示两行（row1 本就可见，Show 无副作用；row2 首次 Show）
    EditorToolbar.Show("NA")
    EditorColorToolbar.Show("NA")
    _ToolbarTransitionRun({r1: EditorToolbar, r2: EditorColorToolbar
        , sx: sx, sy: sy, fx: fx, fy: fy
        , w1: EditorToolbarW, h1: EditorToolbarH, w2: EditorColorToolbarW, h2: EditorColorToolbarH
        , r2x: cx, r2sy: r2StartY, r2ey: cy, dur: 160})
}

; ---------------------------------------------------------------
; 编排过渡动画：10ms 步进，ease-out（Cubic）；row1 平移插值到目标位，row2 展开 + 透明度渐升
; ---------------------------------------------------------------
_ToolbarTransitionRun(anim) {
    anim.elapsed := 0
    anim.then := A_TickCount
    anim.tick := _ToolbarTransitionTick.Bind(anim)
    SetTimer anim.tick, 10
}

_ToolbarTransitionTick(anim) {
    ; 窗口可能已中途销毁（用户取消/切换）：安全终止
    if !WinExist("ahk_id " anim.r1.Hwnd) || !WinExist("ahk_id " anim.r2.Hwnd) {
        SetTimer anim.tick, 0
        return
    }
    now := A_TickCount
    anim.elapsed += now - anim.then
    anim.then := now
    t := Min(1, anim.elapsed / anim.dur)
    e := 1 - (1 - t) ** 3            ; easeOutCubic
    r1x := anim.sx + (anim.fx - anim.sx) * e
    r1y := anim.sy + (anim.fy - anim.sy) * e
    r2y := anim.r2sy + (anim.r2ey - anim.r2sy) * e
    anim.r1.Move(Round(r1x), Round(r1y))
    anim.r2.Move(anim.r2x, Round(r2y))
    try WinSetTransparent Round(255 * e), "ahk_id " anim.r2.Hwnd
    if t >= 1 {
        try WinSetTransparent "Off", "ahk_id " anim.r2.Hwnd
        ; 动画落地：同步悬停命中测试的窗口坐标缓存（与 ToolbarPlaceUnder 一致）
        if IsObject(anim.r1.HoverState)
            anim.r1.HoverState.SetWindowPos(anim.fx, anim.fy, anim.w1, anim.h1)
        if IsObject(anim.r2.HoverState)
            anim.r2.HoverState.SetWindowPos(anim.r2x, anim.r2ey, anim.w2, anim.h2)
        SetTimer anim.tick, 0
    }
}

; 选区 → 编辑过渡：row1 已在选区阶段持久存在，这里只补行2、切阶段、把锚点从「选区矩形」
; 重锚到「编辑窗」并播完整过渡动画（row1 平滑归位 + row2 展开淡入）
EditorPromoteSelectionToolbar() {
    global EditorHwnd, ToolbarPhase
    SetToolbarDpiScale(EditorHwnd)  ; row2 与编辑窗同屏，复用其 DPI
    EditorHideScrollButton()        ; 编辑阶段去除「滚动截图」入口（最右按钮，隐藏后收缩工具栏即可）
    ScreenToolbarCreateRow2()
    ToolbarPhase := "editor"
    ShowToolbarRowsAnimated()
}

; ------------------------------------------------------------------
; 工具栏按钮回调（阶段分发，单一回调避免 OnEvent 二次注册追加 handler）
; ------------------------------------------------------------------
; 工具按钮：选区阶段 = 选工具 + 自动选第 1 色（红）+ 进入编辑（ScreenToolbarResult）；
;          编辑阶段 = 仅切工具（颜色/线宽独立，不重置）
ToolbarToolClick(name, *) {
    global ToolbarPhase, EditorTool, EditorColorIdx, ScreenToolbarResult
    if ToolbarPhase = "selection" {
        EditorTool := name
        EditorColorIdx := 1
        ScreenToolbarResult := "editor"
        return
    }
    ; 文本输入会话期间点击工具 = 先提交当前文本再切换工具
    if EditorTextSessionActive()
        EditorTextCommit()
    EditorTool := name
    EditorToolbarRefresh()
    ; 切到画笔/马赛克立刻应用圆环光标；其他工具恢复标准箭头（鼠标静止时 WM_SETCURSOR 不触发，需主动刷新；
    ; 注意不可用 SetCursor(NULL)——NULL 会把光标隐藏直到下次 WM_SETCURSOR，表现为「鼠标偶发被遮挡」）
    if (name = "brush" || name = "mosaic")
        EditorApplyCircleCursor()
    else
        DllCall("SetCursor", "Ptr", DllCall("LoadCursor", "Ptr", 0, "Ptr", 32512))  ; IDC_ARROW=32512 标准箭头
}

; 输出按钮：选区阶段 = 写结果给选区调度；编辑阶段 = 转发编辑器动作
ToolbarOutputClick(action, *) {
    global ToolbarPhase, ScreenToolbarResult
    if ToolbarPhase = "selection" {
        ScreenToolbarResult := action
        return
    }
    ; 输出前先提交进行中的文本输入，确保其被纳入保存/复制/钉屏
    if EditorTextSessionActive()
        EditorTextCommit()
    switch action {
        case "save": EditorSave()
        case "pin": EditorPin()
        case "copy": EditorCopy()
    }
}

; 滚动截图按钮：仅选区阶段存在，点击即写结果通道，由选区调度进入滚动截图流程
ToolbarScrollClick(*) {
    global ScreenToolbarResult
    ScreenToolbarResult := "scroll"
}

; ------------------------------------------------------------------
; 隐藏「滚动截图」按钮（进入编辑阶段时调用）
; 仅隐藏，**不左移后续控件、不收缩窗口**：滚动按钮槽位保留为空白，工具栏宽度与中心都不变，
; 于是「选区 → 编辑」过渡动画里 row1 的水平位移为 0，不再出现整条右移。
; （原实现隐藏后左移输出按钮并收窄窗口：整条变窄后重新居中的副作用是左缘右移约半个按钮宽，
;   看起来就是「点工具进入编辑时工具栏往右挪一下」。）
; 同时把该按钮从悬停命中列表移除，避免空白槽位仍触发悬停高亮 /「滚动截图」提示。
; ------------------------------------------------------------------
EditorHideScrollButton() {
    global EditorToolbar, EditorScrollButton
    if !EditorScrollButton || !EditorToolbar
        return
    try EditorScrollButton.Visible := false
    if IsObject(EditorToolbar.HoverState) {
        try EditorToolbar.HoverState.RemoveIcon(EditorScrollButton)
        EditorToolbar.HoverState.CacheRects()
    }
    EditorScrollButton := 0
}

; ------------------------------------------------------------------
; 选区工具栏被销毁时的 Editor 侧清理（由选区 _DestroyOverlays 回调调用）
; 目的：选区块不再直接写 Editor 的全局引用（去除「下层模块清理上层内部状态」的反向依赖），
;       改由 Editor 自己清理。仅当被销毁的正是 Editor 当前 row1 时清引用与滚动按钮，
;       否则不动（避免误清仍在使用的状态）。
; ------------------------------------------------------------------
EditorOnToolbarDestroyed(toolbar) {
    global EditorToolbar, EditorScrollButton
    if (toolbar && toolbar = EditorToolbar) {
        EditorToolbar := 0       ; 防残留非零引用误判下一会话 promote
        EditorScrollButton := 0  ; 滚动截图按钮随 row1 一起销毁，清引用防悬空
    }
}

; ------------------------------------------------------------------
; 扁平按钮悬停/选中态：统一由 Common\ToolbarUI.ahk 的 ToolbarHoverState 处理
; （创建按钮用 tb.HoverState.Add，刷新选中态用 tb.HoverState.Refresh）
; ------------------------------------------------------------------

; 工具按钮选中判断（悬停系统选中态回调用；输出按钮等非工具按钮恒 false）
EditorIsSelectedTool(toolButtons, ctrl) {
    global EditorTool
    for name, c in toolButtons
        if (c = ctrl)
            return name = EditorTool
    return false
}

; 工具栏定位：置于编辑窗正下方居中（拖动编辑窗时也调用，保持跟随）
; 两行整体定位（工具行 + 颜色行，与选区工具栏同一手法）；交给公共定位（ToolbarUI.ahk），
; 以编辑窗为锚点矩形，边界用编辑窗中心所在显示器工作区（修复原蒙版全屏并集导致的跨屏/压任务栏）
EditorRepositionToolbar() {
    global EditorToolbar, EditorToolbarW, EditorToolbarH
    global EditorColorToolbar, EditorColorToolbarW, EditorColorToolbarH
    global EditorHwnd, EditorWinW, EditorWinH
    if !EditorToolbar
        return
    WinGetPos &ex, &ey, , , "ahk_id " EditorHwnd
    rows := [{hb: EditorToolbar, w: EditorToolbarW, h: EditorToolbarH}]
    if EditorColorToolbar
        rows.Push({hb: EditorColorToolbar, w: EditorColorToolbarW, h: EditorColorToolbarH})
    ToolbarPlaceUnder(rows, {l: ex, t: ey, r: ex + EditorWinW, b: ey + EditorWinH})
}

; 刷新工具栏选中态：选中的工具按钮高亮，选中的色块/粗细图标外框高亮
; 注意：不能在批量修改期间用 WM_SETREDRAW 暂停窗口重绘 —— 实测 WM_SETREDRAW=false 包裹
; 会阻断 Text 控件 Opt("Background...") 的背景色生效（按钮选中蓝 / 色块外框高亮均无法显示），
; 故这里直接逐个刷新，不做重绘抑制
EditorToolbarRefresh() {
    global EditorToolbar, EditorToolButtons, EditorColorSwatches, EditorSwatchFrames
    global EditorPenWidthFrames, EditorTool, EditorColorIdx, EditorPenWidthIdx
    global EDIT_COLORS
    if EditorToolbar && IsObject(EditorToolbar.HoverState) {
        hover := EditorToolbar.HoverState
        for name, ctrl in EditorToolButtons
            hover.Refresh(ctrl, name = EditorTool)
    }
    for i, sw in EditorColorSwatches
        SwatchRefresh(sw, EditorSwatchFrames[i], EDIT_COLORS[i], i = EditorColorIdx)
    for i, f in EditorPenWidthFrames
        RingRefresh(f, i = EditorPenWidthIdx)
}

; 工具栏按钮回调（工具切替由 ToolbarToolClick 统一分发，编辑阶段在此标注）
EditorSetColor(idx, *) {
    global EditorColorIdx
    EditorColorIdx := idx
    EditorToolbarRefresh()
}

EditorSetPenWidth(idx, *) {
    global EditorPenWidthIdx
    EditorPenWidthIdx := idx
    EditorToolbarRefresh()
}

EditorClear(*) {
    global EditorAnnotations
    ; 清除前先提交进行中的文本输入（随后一并被清空）
    if EditorTextSessionActive()
        EditorTextCommit()
    ; 标注缓存（马赛克格索引/平均色 Map）随对象一并回收，无需显式释放
    EditorAnnotations := []
    EditorBuildAnnotationLayer(EditorAnnotations)  ; 清空标注层（清除后画面立即干净，不残留旧标注）
    EditorRender()
}
