; ==================================================================
; Editor 子模块：Input（由 Editor.ahk 机械拆分，仅搬运、逻辑不变）
; ==================================================================

; ------------------------------------------------------------------
; 鼠标事件（lParam 低16位=客户区X，高16位=客户区Y，符号扩展 → 图片空间坐标）
; ------------------------------------------------------------------
EditorLButtonDown(wParam, lParam, msg, hwnd) {
    global EditorHwnd, EditorPending, EditorTool, EditorColorIdx, EditorPenWidthIdx, EditorScale
    global EditorDragging, EditorDragWinX, EditorDragWinY, EditorDragMouseX, EditorDragMouseY
    ; 拖动目标/已应用位置同样是模块级全局：漏声明会被当成本函数的局部变量，
    ; 起点坐标写不到全局（同时触发 #Warn LocalSameAsGlobal）
    global EditorDragTargetX, EditorDragTargetY, EditorDragAppliedX, EditorDragAppliedY
    global EditorToolbar, EditorColorToolbar
    global EDIT_COLORS, EDIT_LINE_WIDTHS, EDIT_MOSAIC_BRUSH_R
    if (hwnd != EditorHwnd)
        return
    ; 文本输入会话期间点击编辑窗 = 本次点击仅提交文本并退出编辑模式
    ; （不再继续由本次点击新建文本框；要再添加一段文字需另行点击一次）
    if EditorTextSessionActive() {
        EditorTextCommit()
        return
    }
    ; 未选工具：左键拖动编辑窗（移动截图区域位置）
    ; 消息回调只记录起点与目标，实际移动由 EditorDragTick 定时器合并应用（避免高频消息同步移动导致掉帧）
    if (EditorTool = "") {
        EditorDragging := true
        WinGetPos &wx, &wy, , , "ahk_id " EditorHwnd
        MouseGetPos &mx, &my
        EditorDragWinX := wx, EditorDragWinY := wy
        EditorDragMouseX := mx, EditorDragMouseY := my
        EditorDragTargetX := wx, EditorDragTargetY := wy
        EditorDragAppliedX := wx, EditorDragAppliedY := wy
        if EditorToolbar
            EditorToolbar.Hide()  ; 拖动期间隐藏两行工具栏，只留编辑窗 + 覆盖层跟随
        if EditorColorToolbar
            EditorColorToolbar.Hide()
        DllCall("SetCapture", "Ptr", hwnd)
        SetTimer EditorDragTick, 10
        return
    }
    ; 文本工具：点击处就地开启原生 Edit 输入会话（不进入通用 pending 绘制流程）
    if (EditorTool = "text") {
        EditorTextStartAt((lParam << 48 >> 48) / EditorScale, (lParam << 32 >> 48) / EditorScale)
        return
    }
    EditorPending := EditorAnnotation()
    EditorPending.type := EditorTool
    EditorPending.color := EDIT_COLORS[EditorColorIdx]
    EditorPending.penWidth := EDIT_LINE_WIDTHS[EditorPenWidthIdx]  ; 快照当前线宽档位（标注各自固定粗细）
    EditorPending.x1 := (lParam << 48 >> 48) / EditorScale
    EditorPending.y1 := (lParam << 32 >> 48) / EditorScale
    EditorPending.x2 := EditorPending.x1
    EditorPending.y2 := EditorPending.y1
    if (EditorTool = "brush" || EditorTool = "mosaic") {   ; 画笔/马赛克：多点笔触，初始化点集，首点入数组
        EditorPending.points := []
        EditorBrushAppendPoint(EditorPending, EditorPending.x1, EditorPending.y1)
    }
    if (EditorTool = "mosaic")   ; 马赛克笔头半径随当前粗细档位（细/中/粗 → 10/15/22）
        EditorPending.brushR := EDIT_MOSAIC_BRUSH_R[EditorPenWidthIdx]
    DllCall("SetCapture", "Ptr", hwnd)
}

EditorMouseMove(wParam, lParam, msg, hwnd) {
    global EditorHwnd, EditorPending, EditorScale, EditorTool
    global EditorDragging, EditorDragWinX, EditorDragWinY, EditorDragMouseX, EditorDragMouseY
    global EditorDragTargetX, EditorDragTargetY
    global EditorWinW, EditorWinH
    if (hwnd != EditorHwnd)
        return
    ; 未选工具拖动：仅记录目标位置（轻量），实际移动由定时器统一应用
    if EditorDragging {
        MouseGetPos &mx, &my
        EditorDragTargetX := EditorDragWinX + mx - EditorDragMouseX
        EditorDragTargetY := EditorDragWinY + my - EditorDragMouseY
        return
    }
    if !EditorPending
        return
    EditorPending.x2 := (lParam << 48 >> 48) / EditorScale
    EditorPending.y2 := (lParam << 32 >> 48) / EditorScale
    if (EditorTool = "brush" || EditorTool = "mosaic")  ; 画笔/马赛克：追加当前点（按抽稀阈值决定是否记录）
        EditorBrushAppendPoint(EditorPending, EditorPending.x2, EditorPending.y2)
    EditorRender()
}

; ------------------------------------------------------------------
; 拖动合并应用：编辑窗 + 覆盖层（蒙版挖洞 + 4 条边框）统一跟随（与选区微调/钉屏同一手法）
; 位置未变化时直接跳过（去重，避免高频消息触发冗余窗口移动）
; ------------------------------------------------------------------
EditorApplyDrag() {
    global EditorDragTargetX, EditorDragTargetY, EditorDragAppliedX, EditorDragAppliedY
    global EditorHwnd, EditorMaskOv, EditorBorders, EditorWinW, EditorWinH
    if (EditorDragTargetX = EditorDragAppliedX && EditorDragTargetY = EditorDragAppliedY)
        return
    ; 覆盖层/编辑窗可能在拖动途中被销毁（如保存框流程把覆盖层藏起来后又销毁）：
    ; 该函数由 10ms 定时器调用，异常会每拍被全局兜底记录（日志刷屏）且定时器不会自停；
    ; 这里吞掉异常并照常记录「已应用」，让本帧失败不重试（位置变化后下一帧自然再试）
    try {
        MoveWindowFast(EditorHwnd, EditorDragTargetX, EditorDragTargetY, EditorWinW, EditorWinH)
        MaskOverlayHole(EditorMaskOv, EditorDragTargetX, EditorDragTargetY, EditorWinW, EditorWinH)
        BorderStripsMove(EditorBorders, EditorDragTargetX, EditorDragTargetY, EditorWinW, EditorWinH)
    }
    EditorDragAppliedX := EditorDragTargetX
    EditorDragAppliedY := EditorDragTargetY
}

; 拖动刷新定时器（10ms 合并一次，把高频鼠标消息的移动请求聚合成稳定的窗口移动）
EditorDragTick() {
    global EditorDragging
    if !EditorDragging
        return
    ; 自愈：左键已物理弹起却仍标记拖动中（WM_LBUTTONUP 丢失，如被其他程序抢走或系统卡顿）——
    ; 否则编辑窗会一直黏着鼠标跟随、10ms 定时器持续空转，且拖动期间隐藏的工具栏永不恢复；
    ; 走与正常松开一致的收尾（释放捕获 + 恢复两行工具栏）
    if !GetKeyState("LButton", "P") {
        EditorFinishDrag()
        return
    }
    EditorApplyDrag()
}

; 结束编辑窗拖动（正常松开与自愈路径共用）：停合并定时器、释放鼠标捕获、
; 应用末帧位置，并恢复拖动期间隐藏的两行工具栏
EditorFinishDrag() {
    global EditorDragging, EditorToolbar, EditorColorToolbar
    EditorDragging := false
    SetTimer EditorDragTick, 0
    DllCall("ReleaseCapture")
    EditorApplyDrag()  ; 应用最后一帧位置，避免松开瞬间的滞后
    ; 恢复两行工具栏并贴附到编辑窗新位置（蒙版/边框已在拖动中跟随，无需恢复）
    if EditorToolbar {
        EditorRepositionToolbar()
        EditorToolbar.Show("NA")
    }
    if EditorColorToolbar
        EditorColorToolbar.Show("NA")
}

EditorLButtonUp(wParam, lParam, msg, hwnd) {
    global EditorHwnd, EditorPending, EditorAnnotations, EditorScale
    global EditorDragging, EditorWinW, EditorWinH
    if (hwnd != EditorHwnd)
        return
    if EditorDragging {
        EditorFinishDrag()
        return
    }
    DllCall("ReleaseCapture")
    if !EditorPending
        return
    EditorPending.x2 := (lParam << 48 >> 48) / EditorScale
    EditorPending.y2 := (lParam << 32 >> 48) / EditorScale
    ; 画笔/马赛克：追记末点（无条件，不走抽稀）——移动期只按抽稀阈值采样，
    ; 末点不补则松开前的最后一段不绘制，快速甩笔时缺口可达数十像素
    if (EditorPending.type = "brush" || EditorPending.type = "mosaic") {
        if EditorPending.points && EditorPending.points.Length
            EditorPending.points.Push({x: EditorPending.x2, y: EditorPending.y2})
    }
    ; 画笔/马赛克：单点（仅点击无拖动）不提交
    tooSmall := (EditorPending.type = "brush" || EditorPending.type = "mosaic") && EditorPending.points.Length < 2
    ; 忽略过小区域（防误触）：丢弃时释放其缓存，避免泄漏
    if !tooSmall && (Abs(EditorPending.x2 - EditorPending.x1) > 2 || Abs(EditorPending.y2 - EditorPending.y1) > 2) {
        EditorAnnotations.Push(EditorPending)
        EditorAppendAnnotationToLayer(EditorPending)  ; 增量烘焙到标注层（只画新标注，避免整层重绘）
    }
    EditorPending := 0
    EditorRender()
}

; 右键：取消进行中的标注（不提交）
EditorRButtonDown(wParam, lParam, msg, hwnd) {
    global EditorHwnd, EditorPending
    if (hwnd != EditorHwnd)
        return
    if EditorPending {
        EditorPending := 0   ; 取消进行中标注（马赛克缓存是普通 Map，随对象一并回收，无需显式释放）
        DllCall("ReleaseCapture")
        EditorRender()
    }
}

; ------------------------------------------------------------------
; 光标：画笔/马赛克工具用小圆圈（WM_SETCURSOR 拦截，按当前工具切换）
; 其他工具走默认（箭头）；未选工具拖动也走默认，避免编辑区拖动时光标怪异
; ------------------------------------------------------------------
EditorSetCursor(wParam, lParam, msg, hwnd) {
    global EditorTool
    if (hwnd != EditorHwnd)
        return
    if (EditorTool = "brush" || EditorTool = "mosaic") {
        ; 小圆圈光标已设置：返回 true 接管本消息；生成失败则落到下方裸 return 交系统默认
        if EditorApplyCircleCursor()
            return true
    }
    ; 其它工具默认箭头 / 光标生成失败：裸 return。切勿写 return false——AHK v2 中返回整数
    ; （含 0/false）会被当作消息应答并终止 WM_SETCURSOR 默认处理，导致编辑窗默认光标无法恢复
    ; （与 Select.ahk:558 记录的同款陷阱一致）
}

; 应用小圆圈光标（画笔/马赛克）；返回 true 表示已设置，false 表示生成失败走默认
EditorApplyCircleCursor() {
    global EditorCircleCursor
    if !EditorCircleCursor
        EditorCircleCursor := EditorCreateCircleCursor()
    if EditorCircleCursor {
        DllCall("SetCursor", "Ptr", EditorCircleCursor)
        return true
    }
    return false
}

; 动态生成画笔/马赛克用「小圆圈」光标：32×32 ARGB 真透明光标（白描边 + 黑圆环，深浅背景都可见）
; 用 GDI+ 绘制位图 → Gdip_CreateHBITMAPFromBitmap → CreateIconIndirect(fIcon=FALSE) 生成：
; 32 位 alpha 原生支持真透明 + 抗锯齿，只有圆环本体出现、四周与中心全透明、清晰不糊，
; 彻底规避 CreateCursor 单色位平面导致的「大方块/残留/糊」问题。热点居中(16,16)，对准笔触中心。
EditorCreateCircleCursor() {
    ; 绘制 32×32 ARGB 圆环（底全透明，白外圈 + 黑内圈）
    bmp := Gdip_CreateBitmap(32, 32)
    G := Gdip_GraphicsFromImage(bmp)
    Gdip_SetSmoothingMode(G, 4)          ; AntiAlias：圆环边缘平滑
    Gdip_GraphicsClear(G, 0x00FFFFFF)    ; 全透明底
    p1 := Gdip_CreatePen(0xFFFFFFFF, 4)  ; 白描边（外圈，保证黑环在深色背景上可见）
    Gdip_DrawEllipse(G, p1, 4, 4, 24, 24)
    p2 := Gdip_CreatePen(0xFF000000, 2)  ; 黑圆环（内圈，主体）
    Gdip_DrawEllipse(G, p2, 6, 6, 20, 20)
    Gdip_DeletePen(p1)
    Gdip_DeletePen(p2)
    Gdip_DeleteGraphics(G)
    hbmp := Gdip_CreateHBITMAPFromBitmap(bmp, 0xFF000000)
    Gdip_DisposeImage(bmp)

    ; hbmMask：CreateIconIndirect 要求有效单色 mask 句柄（不能 NULL）。
    ; 32×32 全 1（AND 全置位）→ 不透出底板，透明完全交由 hbmColor 的 alpha 决定
    mBuf := Buffer(32 * 4, 0xFF)   ; 单色位图位域：每像素 1 bit，32 位 → 每行 4 字节，全 0xFF=全 1
    mmask := DllCall("CreateBitmap", "Int", 32, "Int", 32, "UInt", 1, "UInt", 1, "Ptr", mBuf, "Ptr")
    if !hbmp || !mmask {   ; 任一位图创建失败即放弃，避免无效资源进 ICONINFO
        if hbmp
            DllCall("DeleteObject", "Ptr", hbmp)
        if mmask
            DllCall("DeleteObject", "Ptr", mmask)
        return 0
    }

    ; 组装 ICONINFO 生成光标（fIcon=FALSE → 光标）；热点居中(16,16)
    maskOff := (3 * 4 + (A_PtrSize - 1)) // A_PtrSize * A_PtrSize   ; 前 3 个 DWORD 后按指针对齐
    colorOff := maskOff + A_PtrSize
    ii := Buffer(colorOff + A_PtrSize, 0)
    NumPut("UInt", 0, ii, 0)            ; fIcon = 0 → 光标
    NumPut("UInt", 16, ii, 4)           ; xHotspot
    NumPut("UInt", 16, ii, 8)           ; yHotspot
    NumPut("Ptr", mmask, ii, maskOff)   ; hbmMask（全 1 单色，不透底）
    NumPut("Ptr", hbmp, ii, colorOff)   ; hbmColor（32 位 alpha 圆环）
    hcur := DllCall("CreateIconIndirect", "Ptr", ii, "Ptr")
    DllCall("DeleteObject", "Ptr", mmask)  ; 位图已由光标持有，随即释放
    DllCall("DeleteObject", "Ptr", hbmp)
    return hcur
}

; 刷新当前工具对应光标：画笔/马赛克用小圆圈，其余用标准箭头
; （文本输入框等临时窗口销毁后系统可能不自动复位光标，需主动重设）
EditorRefreshCursor() {
    global EditorTool
    if (EditorTool = "brush" || EditorTool = "mosaic")
        EditorApplyCircleCursor()
    else
        DllCall("SetCursor", "Ptr", DllCall("LoadCursor", "Ptr", 0, "Ptr", 32512))  ; IDC_ARROW=32512 标准箭头
}
