; ==================================================================
; Editor 子模块：Render（由 Editor.ahk 机械拆分，仅搬运、逻辑不变）
; ==================================================================

; ------------------------------------------------------------------
; 渲染分层（性能优化：把"每帧全量重绘全部标注"降为"每帧只画 3 层缓存"）
;   EditorBgBase  基础层：原图缩放结果，只渲染一次（编辑窗尺寸固定，会话内不重建）
;   EditorBgBitmap 标注层：已提交标注聚合（透明），提交标注时增量绘制新标注；
;                清除/撤销时整层清空重建。拖动预览不再逐帧重画历史标注 → 标注多时帧率不再劣化
;   每帧 EditorRender 仅画 基础层 + 标注层 + 进行中标注（最多 3 次绘制）
; 边界指示由覆盖层边框窗口提供（Common\Overlay.ahk，与选区/钉屏一致），不画进渲染图
; ------------------------------------------------------------------
EditorBuildBase() {
    global EditorBgBase, EditorBaseBitmap, EditorImgW, EditorImgH, EditorWinW, EditorWinH
    if EditorBgBase {
        Gdip_DisposeImage(EditorBgBase)
        EditorBgBase := 0
    }
    EditorBgBase := Gdip_CreateBitmap(EditorWinW, EditorWinH)
    G := Gdip_GraphicsFromImage(EditorBgBase)
    Gdip_SetSmoothingMode(G, 4)
    Gdip_DrawImage(G, EditorBaseBitmap, 0, 0, EditorWinW, EditorWinH, 0, 0, EditorImgW, EditorImgH)
    Gdip_DeleteGraphics(G)
}

; 重建标注层（清空并重画指定标注集合；清除/撤销时调用）
EditorBuildAnnotationLayer(annotations) {
    global EditorBgBitmap, EditorWinW, EditorWinH, EditorScale
    if EditorBgBitmap {
        Gdip_DisposeImage(EditorBgBitmap)
        EditorBgBitmap := 0
    }
    EditorBgBitmap := Gdip_CreateBitmap(EditorWinW, EditorWinH)
    G := Gdip_GraphicsFromImage(EditorBgBitmap)
    Gdip_SetSmoothingMode(G, 4)
    for ann in annotations
        EditorDrawAnnotation(G, ann, EditorScale)
    Gdip_DeleteGraphics(G)
}

; 向标注层增量绘制单个标注（提交标注时调用，避免整层重画）
EditorAppendAnnotationToLayer(ann) {
    global EditorBgBitmap, EditorScale
    G := Gdip_GraphicsFromImage(EditorBgBitmap)
    Gdip_SetSmoothingMode(G, 4)
    EditorDrawAnnotation(G, ann, EditorScale)
    Gdip_DeleteGraphics(G)
}

EditorRender() {
    global EditorWorkBitmap, EditorBgBase, EditorBgBitmap, EditorWinW, EditorWinH, EditorHwnd
    global EditorPending, EditorScale

    ; 工作位图创建一次复用（避免每帧 CreateBitmap 分配/释放大块内存）；跨会话由 EditorCleanup 释放
    if !EditorWorkBitmap
        EditorWorkBitmap := Gdip_CreateBitmap(EditorWinW, EditorWinH)
    G := Gdip_GraphicsFromImage(EditorWorkBitmap)
    Gdip_SetSmoothingMode(G, 4)
    Gdip_GraphicsClear(G, "0xFF000000")
    ; 三层：基础层（原图缩放）→ 标注层（已提交标注）→ 进行中标注（拖动预览）
    Gdip_DrawImage(G, EditorBgBase, 0, 0, EditorWinW, EditorWinH)
    Gdip_DrawImage(G, EditorBgBitmap, 0, 0, EditorWinW, EditorWinH)
    if EditorPending
        EditorDrawAnnotation(G, EditorPending, EditorScale)
    Gdip_DeleteGraphics(G)

    ; 更新分层窗口
    hBitmap := Gdip_CreateHBITMAPFromBitmap(EditorWorkBitmap)
    hdc := CreateCompatibleDC()
    obm := SelectObject(hdc, hBitmap)
    UpdateLayeredWindow(EditorHwnd, hdc, , , EditorWinW, EditorWinH)
    SelectObject(hdc, obm)
    DeleteObject(hBitmap)
    DeleteDC(hdc)
}

; ------------------------------------------------------------------
; 按原图分辨率渲染最终图（复制/保存/钉屏用，含全部已提交标注）
; ------------------------------------------------------------------
EditorRenderFull() {
    global EditorBaseBitmap, EditorImgW, EditorImgH, EditorAnnotations
    pFull := Gdip_CreateBitmap(EditorImgW, EditorImgH)
    G := Gdip_GraphicsFromImage(pFull)
    Gdip_SetSmoothingMode(G, 4)
    Gdip_DrawImage(G, EditorBaseBitmap, 0, 0, EditorImgW, EditorImgH)
    for ann in EditorAnnotations
        EditorDrawAnnotation(G, ann, 1.0)
    Gdip_DeleteGraphics(G)
    return pFull
}

; ------------------------------------------------------------------
; 绘制单个标注到 graphics（s 为缩放系数：显示用 EditorScale，输出用 1.0）
; 线宽按标注创建时快照的档位（ann.penWidth），缩放后不小于 1px
; ------------------------------------------------------------------
EditorDrawAnnotation(G, ann, s) {
    w := Max(1, ann.penWidth * s)
    switch ann.type {
        case "arrow":
            pPen := Gdip_CreatePen(ann.color, w)
            EditorDrawArrow(G, pPen, ann.x1 * s, ann.y1 * s, ann.x2 * s, ann.y2 * s, w)
            Gdip_DeletePen(pPen)
        case "rect":
            pPen := Gdip_CreatePen(ann.color, w)
            Gdip_DrawRectangle(G, pPen, Min(ann.x1, ann.x2) * s, Min(ann.y1, ann.y2) * s, Abs(ann.x2 - ann.x1) * s, Abs(ann.y2 - ann.y1) * s)
            Gdip_DeletePen(pPen)
        case "ellipse":
            pPen := Gdip_CreatePen(ann.color, w)
            Gdip_DrawEllipse(G, pPen, Min(ann.x1, ann.x2) * s, Min(ann.y1, ann.y2) * s, Abs(ann.x2 - ann.x1) * s, Abs(ann.y2 - ann.y1) * s)
            Gdip_DeletePen(pPen)
        case "mosaic":
            EditorDrawMosaic(G, ann, s)
        case "text":
            EditorDrawText(G, ann, s)
        case "brush":
            EditorDrawBrush(G, ann, s)
    }
}

; ------------------------------------------------------------------
; 文本标注：Flameshot 式「半透明深色底块 + 彩色文字」，任何截图背景下都清晰可读
; 锚点 x1,y1 为底块左上角（图片空间）；字号 ann.fontSize 随粗细档位快照
; ------------------------------------------------------------------
EditorDrawText(G, ann, s) {
    global EDIT_TEXT_FONT, EDIT_TEXT_BG_ALPHA, EDIT_TEXT_PADDING
    if ann.text = ""
        return
    fontSize := Max(1, ann.fontSize * s)                    ; 当前 graphics 空间字号（显示=缩放，输出=原大）
    dims := EditorTextMeasure(G, ann.text, fontSize, EDIT_TEXT_FONT)   ; 量文本尺寸（Regular，与绘制同字体同度量）
    pad := EDIT_TEXT_PADDING * s
    bw := dims.w + 2 * pad
    bh := dims.h + 2 * pad
    xb := ann.x1 * s, yb := ann.y1 * s
    ; 半透明深色底块（黑 + EDIT_TEXT_BG_ALPHA 不透明度）
    pBrush := Gdip_BrushCreateSolid((EDIT_TEXT_BG_ALPHA << 24) | 0x000000)
    Gdip_FillRectangle(G, pBrush, xb, yb, bw, bh)
    Gdip_DeleteBrush(pBrush)
    ; 底块上画文字（左上角对齐，左留白）
    EditorTextDraw(G, ann.text, xb + pad, yb + pad, fontSize, ann.color, EDIT_TEXT_FONT)
}

; 测量文本在当前 graphics 空间的自然尺寸（像素宽/高），供底块自适应
; 直接 DllCall GdipMeasureString：库封装的 Gdip_MeasureString/Gdip_DrawString 的 &RectF
; 在 AHK v2 (>=2.0) 下不接受 Buffer 作 byref，故自造 RECTF Buffer 直调 GDI+
EditorTextMeasure(G, text, fontSize, fontFamily) {
    out := { w: 0, h: fontSize * 1.2 }   ; 兜底：失败时按字号粗估
    try {
        hFamily := Gdip_FontFamilyCreate(fontFamily)
        hFont := Gdip_FontCreate(hFamily, fontSize, 0)
        hFormat := Gdip_StringFormatCreate(0x1000)   ; StringFormatFlagsNoWrap：单行自然尺寸
        RC := Buffer(16)
        NumPut("float", 0, "float", 0, "float", 100000, "float", 100000, RC, 0)  ; 布局框 x,y,w,h
        outR := Buffer(16)
        chars := 0, lines := 0
        st := DllCall("gdiplus\GdipMeasureString"
                , "Ptr", G, "Str", text, "int", -1
                , "Ptr", hFont, "Ptr", RC, "Ptr", hFormat
                , "Ptr", outR, "UInt*", &chars, "UInt*", &lines)
        if (st = 0) {   ; Gdiplus::Ok
            w := NumGet(outR, 8, "float")
            h := NumGet(outR, 12, "float")
            if (w > 0 && h > 0)
                out := { w: w, h: h }
        }
        Gdip_DeleteStringFormat(hFormat)
        Gdip_DeleteFont(hFont)
        Gdip_DeleteFontFamily(hFamily)
    }
    return out
}

; 在指定位置绘制文本（左上对齐、NoWrap；直接 DllCall GdipDrawString，绕开库 RECTF byref 限制）
EditorTextDraw(G, text, x, y, fontSize, color, fontFamily) {
    try {
        hFamily := Gdip_FontFamilyCreate(fontFamily)
        hFont := Gdip_FontCreate(hFamily, fontSize, 0)
        hFormat := Gdip_StringFormatCreate(0x1000)   ; NoWrap
        RC := Buffer(16)
        NumPut("float", x, "float", y, "float", 100000, "float", 100000, RC, 0)
        pBrush := Gdip_BrushCreateSolid(color)
        DllCall("gdiplus\GdipDrawString"
                , "Ptr", G, "Str", text, "int", -1
                , "Ptr", hFont, "Ptr", RC, "Ptr", hFormat
                , "Ptr", pBrush)
        Gdip_DeleteBrush(pBrush)
        Gdip_DeleteStringFormat(hFormat)
        Gdip_DeleteFont(hFont)
        Gdip_DeleteFontFamily(hFamily)
    }
}

; 箭头：主线 + 两条箭头翼线（翼与主线约 30° 夹角）；首尾用圆形端点，
; 头部两条翼线与主线在头尖交融成圆头，尾部收成圆头，避免尖角
EditorDrawArrow(G, pPen, x1, y1, x2, y2, penW) {
    DllCall("gdiplus\GdipSetPenStartCap", "ptr", pPen, "int", 2)  ; LineCapRound 圆头
    DllCall("gdiplus\GdipSetPenEndCap", "ptr", pPen, "int", 2)
    Gdip_DrawLine(G, pPen, x1, y1, x2, y2)
    dx := x2 - x1, dy := y2 - y1
    len := Sqrt(dx * dx + dy * dy)
    if (len < 1)
        return
    ux := dx / len, uy := dy / len
    al := Max(12, penW * 3)  ; 翼长：与线宽相关，保证可见
    Gdip_DrawLine(G, pPen, x2, y2, x2 - ux * al + uy * al * 0.5, y2 - uy * al - ux * al * 0.5)
    Gdip_DrawLine(G, pPen, x2, y2, x2 - ux * al - uy * al * 0.5, y2 - uy * al + ux * al * 0.5)
    ; 头尖再叠一个同色实心圆：两条翼线与主线在头尖交融，视觉上进一步圆润
    argb := Buffer(4)
    DllCall("gdiplus\GdipGetPenColor", "ptr", pPen, "ptr", argb)
    c := NumGet(argb, 0, "uint")
    r := penW * 0.75                    ; 圆润半径（略大于半线宽，使其明显）
    pBrush := Gdip_BrushCreateSolid(c)
    Gdip_FillEllipse(G, pBrush, x2 - r, y2 - r, r * 2, r * 2)
    Gdip_DeleteBrush(pBrush)
}

; 画笔：圆角折线（逐点连线，线帽 Round + 线连接 Round，平滑无尖角）
; 点坐标为图片空间，按 s 缩放输出；单点/空点不发散（过小已由 LButtonUp 拦截）
; 注：逐段 Gdip_DrawLine（Gdip_DrawLines 封装在此 AHK 版本有兼容问题）
EditorDrawBrush(G, ann, s) {
    if !ann.points || ann.points.Length < 2
        return
    pPen := Gdip_CreatePen(ann.color, Max(1, ann.penWidth * s))
    DllCall("gdiplus\GdipSetPenStartCap", "ptr", pPen, "int", 2)  ; LineCapRound 圆头
    DllCall("gdiplus\GdipSetPenEndCap",   "ptr", pPen, "int", 2)  ; LineCapRound 圆头
    DllCall("gdiplus\GdipSetPenLineJoin", "ptr", pPen, "int", 2)  ; LineJoinRound 圆角连接
    prev := ann.points[1]
    loop ann.points.Length - 1 {
        cur := ann.points[A_Index + 1]
        Gdip_DrawLine(G, pPen, prev.x * s, prev.y * s, cur.x * s, cur.y * s)
        prev := cur
    }
    Gdip_DeletePen(pPen)
}

; 画笔抽稀采集：距上一采样点（显示空间距离）≥ 阈值才追加入点，
; 长笔画保持平滑的同时限制点总量，避免每帧重画 O(n) 时点数过大
EditorBrushAppendPoint(pend, x, y) {
    global EDIT_BRUSH_MIN_DIST, EditorScale
    if !pend.points
        return
    if !pend.points.Length {
        pend.points.Push({x: x, y: y})
        return
    }
    last := pend.points[-1]                       ; 数组负索引取末元素
    dx := (x - last.x) * EditorScale
    dy := (y - last.y) * EditorScale
    if (dx * dx + dy * dy >= EDIT_BRUSH_MIN_DIST * EDIT_BRUSH_MIN_DIST)
        pend.points.Push({x: x, y: y})
}

; 马赛克（笔触式）：沿自由轨迹涂抹经典像素化格子。
; ShareX Pixelate 同款画法：以图片原点为锚的固定全局格网（cell×cell），
; 笔头圆扫过的每个格子，取该格在原图上的平均色填一块硬边矩形即可，格内同色。
; 每格首次扫到算一次平均色并缓存（ann.cellColor[k]），此后固定不变——格网不随
; 轨迹移动、格子不因包围盒扩张而重算，抹到哪格哪格稳定变块，无脏乱无重影。
EditorDrawMosaic(G, ann, s) {
    global EditorBaseBitmap, EditorImgW, EditorImgH, EDIT_MOSAIC_CELL
    if !ann.points || ann.points.Length < 2
        return
    ; 先按笔触轨迹标记被扫过的格子（含平均色缓存），再统一绘制；笔头半径取创建时快照的档位
    EditorMosaicMarkTrail(ann, EditorBaseBitmap, EditorImgW, EditorImgH, EDIT_MOSAIC_CELL, ann.brushR)
    ; 逐格绘制已像素化的格子（显示坐标 = 格索引 × cell × s），硬边矩形
    Gdip_SetInterpolationMode(G, 5)   ; NearestNeighbor：格子硬边不被缩放柔化
    ; 复用同一个实心 brush，逐格用 GdipSetSolidFillColor 改色——避免每帧为每格
    ; Create/DeleteBrush（马赛克笔触拖动的性能热点）
    pBrush := Gdip_BrushCreateSolid(0xFF000000)
    for key in ann.cells {
        rowCol := StrSplit(key, ":")
        c := Integer(rowCol[1]), r := Integer(rowCol[2])
        gx := c * EDIT_MOSAIC_CELL, gy := r * EDIT_MOSAIC_CELL
        DllCall("gdiplus\GdipSetSolidFillColor", "Ptr", pBrush, "UInt", ann.cellColor[key])
        Gdip_FillRectangle(G, pBrush, gx * s, gy * s, EDIT_MOSAIC_CELL * s, EDIT_MOSAIC_CELL * s)
    }
    Gdip_DeleteBrush(pBrush)
}
; ------------------------------------------------------------------

; 沿笔触轨迹标记被笔头圆扫过的所有格子，并缓存每格平均色
; 关键：按「相邻采样点之间的线段」做胶囊覆盖（笔头半径 R 沿线段扫过），而非只圈孤立点圆。
; 这样手画再快、采样点再稀，两点之间的线段区间也会被像素化满，不断不掉、粗细一致。
EditorMosaicMarkTrail(ann, src, imgW, imgH, cell, R) {
    if ann.points.Length < 2
        return
    ; 增量：只处理自上次以来新增的线段（ann.markedSegs 记录已处理线段数）。
    ; 原实现每帧重扫整条轨迹的所有线段，长笔触时是 O(轨迹) 的重复热点。
    lo := (ann.markedSegs ? ann.markedSegs : 0) + 1
    hi := ann.points.Length - 1
    if (lo > hi)
        return
    j := lo
    while j <= hi {
        A := ann.points[j], B := ann.points[j + 1]
        EditorMosaicMarkSegment(ann, src, imgW, imgH, cell, R, A.x, A.y, B.x, B.y)
        j++
    }
    ann.markedSegs := hi
}

; 标记线段 A→B 两侧各 R 宽度（胶囊）覆盖的所有格子（格心到线段距离 ≤ R）；幂等累积
EditorMosaicMarkSegment(ann, src, imgW, imgH, cell, R, ax, ay, bx, by) {
    R2 := R * R
    c0 := Floor((Min(ax, bx) - R) / cell), c1 := Floor((Max(ax, bx) + R) / cell)
    r0 := Floor((Min(ay, by) - R) / cell), r1 := Floor((Max(ay, by) + R) / cell)
    r := r0
    while r <= r1 {
        c := c0
        while c <= c1 {
            gcx := c * cell + cell / 2, gcy := r * cell + cell / 2
            if EditorDistToSeg2(gcx, gcy, ax, ay, bx, by) <= R2 {
                key := c ":" r
                if !ann.cells.Has(key) {
                    ; 首次扫到：算该格平均色并缓存，此后固定不变
                    ann.cells[key] := true
                    ann.cellColor[key] := EditorCellAverage(src, c * cell, r * cell, cell, cell, imgW, imgH)
                }
            }
            c++
        }
        r++
    }
}

; 点 (px,py) 到线段 A→B 的最短距离平方（垂足在线段上则取垂距，否则取到最近端点的距离）
EditorDistToSeg2(px, py, ax, ay, bx, by) {
    vx := bx - ax, vy := by - ay
    wx := px - ax, wy := py - ay
    len2 := vx * vx + vy * vy
    t := 0
    if len2 {                       ; 退化线段视作点 A
        t := (wx * vx + wy * vy) / len2
        if t < 0
            t := 0
        else if t > 1
            t := 1
    }
    qx := ax + t * vx, qy := ay + t * vy
    dx := px - qx, dy := py - qy
    return dx * dx + dy * dy
}

; 求原图 [x,y,w,h] 区域的像素平均色（ARGB；区域越界自动裁剪到图内）
EditorCellAverage(src, x, y, w, h, imgW, imgH) {
    x := Max(0, x), y := Max(0, y)
    w := Min(w, imgW - x), h := Min(h, imgH - y)
    if (w <= 0 || h <= 0)
        return 0
    ; 锁失败必须立刻放弃本格：库内 BitmapData 为全 0 初始化，失败时不会被写入，
    ; Stride/Scan0 会保持 0，继续按 Scan0 读像素等于读空指针（崩溃），且不能对未锁成的位图 UnlockBits；
    ; 返回 0（全透明）→ 该格绘制不可见，等效于这一格没被马赛克到，属优雅降级
    if (Gdip_LockBits(src, x, y, w, h, &Stride, &Scan0, &BitmapData, 3, 0x26200a))
        return 0
    sumR := 0, sumG := 0, sumB := 0, cnt := 0
    py := 0
    loop h {
        row := Scan0 + py * Stride
        px := 0
        loop w {
            sumB += NumGet(row, px * 4, "UChar")
            sumG += NumGet(row, px * 4 + 1, "UChar")
            sumR += NumGet(row, px * 4 + 2, "UChar")
            cnt++
            px++
        }
        py++
    }
    Gdip_UnlockBits(src, &BitmapData)
    n := cnt ? cnt : 1
    avR := Round(sumR / n), avG := Round(sumG / n), avB := Round(sumB / n)
    return 0xFF000000 | (avR << 16) | (avG << 8) | avB
}
