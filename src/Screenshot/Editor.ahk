; ==================================================================
; 截图标注编辑窗
; 截图确认后自动打开：编辑窗外围 4 条半透明蒙版变暗聚焦（编辑区域露出），
; 未选工具时左键拖动可移动截图区域；选择工具后绘制矩形/箭头/椭圆/马赛克标注，
; 支持清除，以及复制到剪贴板 / 保存 PNG / 钉屏置顶
;
; 依赖：Gdip 库（src\Common\Gdip_All_v2.ahk，由 Screenshot.ahk 先行引入）
; 入口：ShowEditor(pBitmap) —— 接管 pBitmap 生命周期，编辑窗关闭时释放
;
; 坐标约定：标注坐标一律存「图片空间」（原图像素坐标），渲染时按缩放系数换算，
;           保证输出（复制/保存/钉屏）为原图分辨率
; ==================================================================

#Include "Pin.ahk"

; ------------------------------------------------------------------
; 编辑窗全局状态（模块内维护；常量在 Config.ahk 中定义）
; ------------------------------------------------------------------
global EditorBaseBitmap := 0    ; 原图（调用方传入，本模块负责释放）
global EditorImgW := 0, EditorImgH := 0  ; 原图尺寸
global EditorScale := 1.0       ; 显示缩放系数（等比缩小，不放大）
global EditorWinW := 0, EditorWinH := 0  ; 编辑窗尺寸
global EditorGui := 0           ; 编辑窗 Gui 对象
global EditorHwnd := 0          ; 编辑窗 hwnd
global EditorAnnotations := []  ; 已提交标注数组
global EditorPending := 0       ; 进行中标注（拖动时实时预览，未提交）
global EditorTool := ""        ; 当前工具（arrow/rect/ellipse/mosaic；空=无工具，左键拖动可移动编辑窗）
global EditorColorIdx := 1      ; 当前颜色索引（EDIT_COLORS；所有工具共享，切工具时保持）
global EditorPenWidthIdx := 2   ; 当前线宽档位索引（EDIT_LINE_WIDTHS，默认中档；不持久化）
global EditorToolbar := 0       ; 工具栏（第一行：工具/清除/输出按钮）Gui 对象（挂 HoverState 属性：扁平按钮悬停状态）
global EditorToolbarW := 0, EditorToolbarH := 0  ; 工具栏尺寸缓存（创建时获取一次，拖动定位时复用，避免每帧 WinGetPos）
global EditorColorToolbar := 0  ; 颜色工具栏（第二行：颜色行 + 粗细档位，始终显示，与选区颜色行同结构）
global EditorColorToolbarW := 0, EditorColorToolbarH := 0  ; 颜色工具栏尺寸缓存
global EditorToolButtons := Map()  ; 工具名 → 按钮控件（刷新选中态）
global EditorToolLabels := Map()   ; 工具名 → 基础标签（如 "箭头"）
global EditorColorSwatches := []   ; 颜色索引 → 色块内块控件（刷新选中态）
global EditorSwatchFrames := []    ; 颜色索引 → 色块外框控件（选中时外框高亮）
global EditorPenWidthFrames := []  ; 粗细图标索引 → 外框控件（刷新选中态）
global EditorWorkBitmap := 0    ; 显示用工作 bitmap（渲染缓存，创建一次复用，重绘前 Clear）
global EditorBgBase := 0        ; 基础层缓存（原图缩放结果，只渲染一次；编辑窗尺寸固定，会话内不重建）
global EditorBgBitmap := 0      ; 标注层缓存（已提交标注聚合，透明；提交时增量绘制，清除/重建时全量重画）
global EditorResult := ""       ; 编辑结果（copy/save/pin/cancel），主循环轮询
global EditorMaskOv := 0        ; 覆盖层蒙版（Common\Overlay.ahk 共享组件：全屏挖洞，就地从选区接管或新建）
global EditorBorders := []      ; 覆盖层边框窗口数组（Common\Overlay.ahk 共享组件：4 条天蓝框，就地从选区接管或新建）
global EditorDragging := false  ; 未选工具时左键拖动编辑窗（移动截图区域位置）
global EditorDragWinX := 0, EditorDragWinY := 0  ; 拖动起点时的编辑窗位置
global EditorDragMouseX := 0, EditorDragMouseY := 0  ; 拖动起点时的鼠标屏幕坐标
global EditorDragTargetX := 0, EditorDragTargetY := 0  ; 拖动目标位置（消息回调仅记录，定时器统一应用）
global EditorDragAppliedX := 0, EditorDragAppliedY := 0  ; 已应用位置（定时器应用后记录，用于去重）

; ------------------------------------------------------------------
; 标注数据结构：type + 图片空间坐标（x1,y1 起点 / x2,y2 终点）
;  - arrow/rect/ellipse: color + penWidth（绘制时按各自线宽）
;  - mosaic: 无 color/penWidth（采样原图）
; ------------------------------------------------------------------
class EditorAnnotation {
    type := ""
    x1 := 0, y1 := 0, x2 := 0, y2 := 0
    color := 0
    penWidth := 0  ; 线宽（图片空间像素，创建时快照当前档位）
    mosaic := 0  ; 马赛克压缩小图缓存（GDI+ bitmap，重绘复用，避免反复采样原图）
    mosaicRw := 0, mosaicRh := 0  ; 缓存对应的裁剪后区域尺寸（图片空间）；区域变化时重建缓存
}

; ------------------------------------------------------------------
; 打开标注编辑窗（阻塞直到编辑结束）
; pBitmap：截图原图（GDI+ bitmap），本函数负责释放
; region：原选区（RegionSetting），用于把编辑窗定位在选区原位；可省略（独立调用时居中显示）
; leftoverCleanup：可选回调，编辑器环境（编辑窗首帧 + 覆盖层就绪）就绪后调用；
;                 截图流程用于销毁遗留的选区拦截层/工具栏（蒙版/边框已就地接管，不销毁）
; initialTool：可选，编辑器初始标注工具（arrow/rect/ellipse/mosaic），由选区工具栏预选；
;              点击窗口路径（未选工具）为空 → 编辑器无工具，左键拖动可移动编辑窗
; initialColor：可选，编辑器初始颜色索引（EDIT_COLORS 索引），由选区工具栏自动选中第 1 色；
;               0 或省略则用第 1 色
; inherited：可选，截图阶段遗留覆盖层 {mask, borders}（Common\Overlay.ahk 组件），
;            就地升级复用（蒙版洞切换到编辑窗、边框跟随编辑窗）；缺省则新建，界面一致
; 返回值："copy" | "save:<路径>" | "pin" | "cancel"
; ------------------------------------------------------------------
ShowEditor(pBitmap, region := 0, leftoverCleanup := 0, initialTool := "", initialColor := 0, inherited := 0) {
    global EditorBaseBitmap, EditorImgW, EditorImgH, EditorScale, EditorWinW, EditorWinH
    global EditorBgBitmap
    global EditorGui, EditorHwnd, EditorAnnotations, EditorPending
    global EditorTool, EditorColorIdx, EditorResult
    global EditorMaskOv, EditorBorders
    global EDIT_SCREEN_MARGIN, EDIT_LINE_WIDTH_DEFAULT

    ; 初始化状态
    EditorBaseBitmap := pBitmap
    Gdip_GetImageDimensions(pBitmap, &EditorImgW, &EditorImgH)
    EditorAnnotations := []
    EditorPending := 0
    EditorTool := initialTool ? initialTool : ""  ; 初始工具（选区工具栏预选）；点击窗口路径为空则无工具，左键拖动可移动编辑窗
    EditorColorIdx := initialColor ? initialColor : 1  ; 初始颜色（初始工具用选区传入色/第 1 色）；未选用第 1 色
    EditorPenWidthIdx := EDIT_LINE_WIDTH_DEFAULT  ; 每次会话重置为默认中档（不持久化）

    ; 等比缩放适配屏幕（只缩小不放大），边界以鼠标所在显示器工作区为准
    MouseGetPos &mx, &my
    MonitorGetWorkArea(MonitorIndexAt(mx, my), &wl, &wt, &wr, &wb)
    availW := wr - wl - 2 * EDIT_SCREEN_MARGIN
    availH := wb - wt - 2 * EDIT_SCREEN_MARGIN
    EditorScale := Min(1.0, availW / EditorImgW, availH / EditorImgH)
    EditorWinW := Round(EditorImgW * EditorScale)
    EditorWinH := Round(EditorImgH * EditorScale)
    ; 定位：优先在原选区位置（编辑窗中心对齐选区中心，图片原地显示不"移动"）；
    ; 无选区信息（独立调用）时居中于鼠标所在显示器
    if region && region.GetRegionRect(&rl, &rt, &rw, &rh) {
        ex := rl + rw // 2 - EditorWinW // 2
        ey := rt + rh // 2 - EditorWinH // 2
    } else {
        ex := wl + (wr - wl - EditorWinW) // 2
        ey := wt + (wb - wt - EditorWinH) // 2
    }
    ; 钳制在鼠标所在显示器工作区内（选区贴边时编辑窗也不超出屏幕）
    ex := Min(Max(ex, wl), wr - EditorWinW)
    ey := Min(Max(ey, wt), wb - EditorWinH)

    ; 预渲染分层缓存：基础层（原图缩放结果只算一次）+ 标注层（已提交标注聚合，初始为空）
    ; 拖动标注预览只画 3 层，不再每帧重画历史标注
    EditorBuildBase()
    EditorBuildAnnotationLayer(EditorAnnotations)

    ; 覆盖层（蒙版 + 边框）：优先接管截图阶段遗留（就地升级，三阶段同一套视觉资产），
    ; 否则新建（独立调用场景）。蒙版挖洞到编辑窗、边框围绕编辑窗，与编辑窗同一帧生效
    EditorMaskOv := (inherited && inherited.mask) ? inherited.mask : MaskOverlayCreate()
    EditorBorders := (inherited && inherited.borders) ? inherited.borders : BorderStripsCreate()

    ; 创建编辑窗（分层窗口：内容由 GDI+ 全量渲染）
    EditorGui := Gui("-Caption +AlwaysOnTop -DPIScale +E0x80000")
    EditorGui.MarginX := 0
    EditorGui.MarginY := 0
    EditorHwnd := EditorGui.Hwnd

    ; 鼠标事件：左键按下/移动/松开（绘制），右键（取消进行中标注）
    OnMessage(0x201, EditorLButtonDown)
    OnMessage(0x200, EditorMouseMove)
    OnMessage(0x202, EditorLButtonUp)
    OnMessage(0x204, EditorRButtonDown)

    try {
        ; 首帧渲染：先对隐藏窗口 UpdateLayeredWindow 再 Show，窗口一出现即为完整图像，避免空白矩形闪烁
        EditorRender()
        MaskOverlayHole(EditorMaskOv, ex, ey, EditorWinW, EditorWinH)
        BorderStripsMove(EditorBorders, ex, ey, EditorWinW, EditorWinH)
        EditorGui.Show("NA x" ex " y" ey " w" EditorWinW " h" EditorWinH)

        ; 编辑器环境（编辑窗首帧 + 覆盖层就绪）已就绪：销毁截图阶段遗留的选区拦截层/工具栏
        ; （蒙版/边框已就地接管复用，不销毁），消除「蒙版销毁 → 编辑窗出现」之间的整屏明暗跳变
        if leftoverCleanup
            leftoverCleanup()

        ; 悬浮工具栏：置于编辑窗正下方
        EditorCreateToolbar(ex + EditorWinW // 2, ey + EditorWinH + 8)
        EditorToolbarRefresh()

        ; 等待用户操作（按钮回调 / Esc 设置 EditorResult）
        EditorResult := ""
        EscRegister()   ; Esc 统一分发：编辑优先（取消编辑），钉屏共存时按需切换
        try {
            while EditorResult = "" {
                ; 编辑窗被意外销毁（异常中断等）时按取消退出，避免工具栏残留
                if !WinExist("ahk_id " EditorHwnd) {
                    EditorResult := "cancel"
                    break
                }
                Sleep 20
            }
        } finally {
            EscUnregister()   ; 若无其他钉屏会话（EscNeed 归零）则注销热键
            OnMessage(0x201, EditorLButtonDown, 0)
            OnMessage(0x200, EditorMouseMove, 0)
            OnMessage(0x202, EditorLButtonUp, 0)
            OnMessage(0x204, EditorRButtonDown, 0)
        }

        ; 处理结果：按原图分辨率渲染最终图，再执行输出
        result := EditorResult
        pFull := 0
        switch EditorResult {
            case "copy":
                pFull := EditorRenderFull()
                Gdip_SetBitmapToClipboard(pFull)
            case "pin":
                ; 就地钉屏：编辑窗画面原地保留，仅关闭工具栏/蒙版并切换钉屏交互（无感，零跳变）
                EditorPinInPlace()
                return "pin"
            default:
                ; 保存：EditorSave 已弹出系统对话框并记录 "save:<路径>"（取消时仍处于编辑态，不会走到这里）
                if SubStr(EditorResult, 1, 5) = "save:" {
                    pFull := EditorRenderFull()
                    filename := SubStr(EditorResult, 6)
                    if Gdip_SaveBitmapToFile(pFull, filename)
                        result := "save:" filename
                    else {
                        result := "save_fail"
                        TrayTip "截图保存失败", "无法写入文件，请检查磁盘空间或目标目录权限。", "IconX"
                    }
                }
        }
        if pFull
            Gdip_DisposeImage(pFull)
        EditorCleanup()
        return result
    } catch as e {
        EditorCleanup()  ; 初始化/主流程异常：兜底释放编辑器资源（含接管的覆盖层），避免残留卡屏
        throw
    }
}

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
    }
}

; 箭头：主线 + 两条箭头翼线（翼与主线约 30° 夹角）
EditorDrawArrow(G, pPen, x1, y1, x2, y2, penW) {
    Gdip_DrawLine(G, pPen, x1, y1, x2, y2)
    dx := x2 - x1, dy := y2 - y1
    len := Sqrt(dx * dx + dy * dy)
    if (len < 1)
        return
    ux := dx / len, uy := dy / len
    al := Max(12, penW * 3)  ; 翼长：与线宽相关，保证可见
    Gdip_DrawLine(G, pPen, x2, y2, x2 - ux * al + uy * al * 0.5, y2 - uy * al - ux * al * 0.5)
    Gdip_DrawLine(G, pPen, x2, y2, x2 - ux * al - uy * al * 0.5, y2 - uy * al + ux * al * 0.5)
}

; 马赛克：源区域先压缩（双线性平均），再按最近邻放大回目标区域 → 像素块效果
; 压缩小图缓存到 ann.mosaic：首次渲染生成，此后重绘直接复用，避免反复采样原图
EditorDrawMosaic(G, ann, s) {
    global EditorBaseBitmap, EditorImgW, EditorImgH, EDIT_MOSAIC_CELL
    ; 图片空间区域（裁剪到图内）
    x1 := Max(0, Min(ann.x1, ann.x2))
    y1 := Max(0, Min(ann.y1, ann.y2))
    x2 := Min(EditorImgW, Max(ann.x1, ann.x2))
    y2 := Min(EditorImgH, Max(ann.y1, ann.y2))
    rw := x2 - x1, rh := y2 - y1
    if (rw < 2 || rh < 2)
        return
    ; 缓存区域变化（拖动预览时区域不断变大）→ 先释放再重建，保证内容跟随鼠标
    if (ann.mosaic && (ann.mosaicRw != rw || ann.mosaicRh != rh)) {
        Gdip_DisposeImage(ann.mosaic)
        ann.mosaic := 0
    }
    if !ann.mosaic {
        k := EDIT_MOSAIC_CELL
        smallW := Max(1, Round(rw / k))
        smallH := Max(1, Round(rh / k))
        ; 1) 压缩：源区域 → 小图（双线性平均），仅此一次采样原图
        ann.mosaic := Gdip_CreateBitmap(smallW, smallH)
        G2 := Gdip_GraphicsFromImage(ann.mosaic)
        Gdip_SetInterpolationMode(G2, 3)  ; Bilinear
        Gdip_DrawImage(G2, EditorBaseBitmap, 0, 0, smallW, smallH, x1, y1, rw, rh)
        Gdip_DeleteGraphics(G2)
        ann.mosaicRw := rw, ann.mosaicRh := rh
    }
    ; 2) 放大：缓存小图 → 目标区域（最近邻 → 像素块）
    Gdip_GetImageDimensions(ann.mosaic, &mw, &mh)
    Gdip_SetInterpolationMode(G, 5)   ; NearestNeighbor
    Gdip_DrawImage(G, ann.mosaic, x1 * s, y1 * s, rw * s, rh * s, 0, 0, mw, mh)
    Gdip_SetInterpolationMode(G, 6)   ; 恢复高质双线性
}

; 释放标注的缓存资源（马赛克小图；幂等）
EditorReleaseAnnotationCache(ann) {
    if ann.mosaic {
        Gdip_DisposeImage(ann.mosaic)
        ann.mosaic := 0
    }
}

; ------------------------------------------------------------------
; 鼠标事件（lParam 低16位=客户区X，高16位=客户区Y，符号扩展 → 图片空间坐标）
; ------------------------------------------------------------------
EditorLButtonDown(wParam, lParam, msg, hwnd) {
    global EditorHwnd, EditorPending, EditorTool, EditorColorIdx, EditorPenWidthIdx, EditorScale
    global EditorDragging, EditorDragWinX, EditorDragWinY, EditorDragMouseX, EditorDragMouseY
    global EditorToolbar, EditorColorToolbar
    global EDIT_COLORS, EDIT_LINE_WIDTHS
    if (hwnd != EditorHwnd)
        return
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
    EditorPending := EditorAnnotation()
    EditorPending.type := EditorTool
    EditorPending.color := EDIT_COLORS[EditorColorIdx]
    EditorPending.penWidth := EDIT_LINE_WIDTHS[EditorPenWidthIdx]  ; 快照当前线宽档位（标注各自固定粗细）
    EditorPending.x1 := (lParam << 48 >> 48) / EditorScale
    EditorPending.y1 := (lParam << 32 >> 48) / EditorScale
    EditorPending.x2 := EditorPending.x1
    EditorPending.y2 := EditorPending.y1
    DllCall("SetCapture", "Ptr", hwnd)
}

EditorMouseMove(wParam, lParam, msg, hwnd) {
    global EditorHwnd, EditorPending, EditorScale
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
    MoveWindowFast(EditorHwnd, EditorDragTargetX, EditorDragTargetY, EditorWinW, EditorWinH)
    MaskOverlayHole(EditorMaskOv, EditorDragTargetX, EditorDragTargetY, EditorWinW, EditorWinH)
    BorderStripsMove(EditorBorders, EditorDragTargetX, EditorDragTargetY, EditorWinW, EditorWinH)
    EditorDragAppliedX := EditorDragTargetX
    EditorDragAppliedY := EditorDragTargetY
}

; 拖动刷新定时器（10ms 合并一次，把高频鼠标消息的移动请求聚合成稳定的窗口移动）
EditorDragTick() {
    global EditorDragging
    if !EditorDragging
        return
    EditorApplyDrag()
}

EditorLButtonUp(wParam, lParam, msg, hwnd) {
    global EditorHwnd, EditorPending, EditorAnnotations, EditorScale
    global EditorDragging, EditorToolbar, EditorColorToolbar, EditorWinW, EditorWinH
    if (hwnd != EditorHwnd)
        return
    DllCall("ReleaseCapture")
    if EditorDragging {
        EditorDragging := false
        SetTimer EditorDragTick, 0  ; 停掉合并定时器
        EditorApplyDrag()  ; 应用最后一帧位置，避免松开瞬间的滞后
        ; 恢复两行工具栏并贴附到编辑窗新位置（蒙版/边框已在拖动中跟随，无需恢复）
        if EditorToolbar {
            EditorRepositionToolbar(EditorDragAppliedX + EditorWinW // 2, EditorDragAppliedY + EditorWinH + 8)
            EditorToolbar.Show("NA")
        }
        if EditorColorToolbar
            EditorColorToolbar.Show("NA")
        return
    }
    if !EditorPending
        return
    EditorPending.x2 := (lParam << 48 >> 48) / EditorScale
    EditorPending.y2 := (lParam << 32 >> 48) / EditorScale
    ; 忽略过小区域（防误触）：丢弃时释放其缓存，避免泄漏
    if (Abs(EditorPending.x2 - EditorPending.x1) > 2 || Abs(EditorPending.y2 - EditorPending.y1) > 2) {
        EditorAnnotations.Push(EditorPending)
        EditorAppendAnnotationToLayer(EditorPending)  ; 增量烘焙到标注层（只画新标注，避免整层重绘）
    } else {
        EditorReleaseAnnotationCache(EditorPending)
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
        EditorReleaseAnnotationCache(EditorPending)  ; 取消进行中标注，释放其缓存
        EditorPending := 0
        DllCall("ReleaseCapture")
        EditorRender()
    }
}

; ------------------------------------------------------------------
; 悬浮工具栏（置于编辑窗下方）
; ------------------------------------------------------------------
EditorCreateToolbar(centerX, y) {
    global EditorToolbar, EditorToolbarW, EditorToolbarH
    global EditorColorToolbar, EditorColorToolbarW, EditorColorToolbarH
    global EditorToolButtons, EditorToolLabels, EditorColorSwatches, EditorSwatchFrames
    global EditorPenWidthFrames
    global ToolbarHoverActive, ToolbarHoverAux
    global EditorHwnd
    global EDIT_COLORS, EDIT_TB_BG, EDIT_TB_SEP, EDIT_TB_BTN_BG, EDIT_TB_BTN_TEXT, EDIT_TB_RING
    global EDIT_LINE_WIDTHS, EDIT_LINE_WIDTH_DISPLAY
    ; DPI 缩放：字体 s11 由 AHK 按 DPI 自动放大，控件尺寸需手动等比放大（ToolbarDpi）。
    ; 工具栏与编辑窗同显示器（置于其正下方），直接复用编辑窗 DPI（编辑窗已 Show，DPI 有效）
    SetToolbarDpiScale(EditorHwnd)
    ; 防御性重置（正常流程中清理函数已清空，这里兜底防重复调用时累积）
    EditorToolButtons := Map()
    EditorToolLabels := Map()
    EditorColorSwatches := []
    EditorSwatchFrames := []
    EditorPenWidthFrames := []

    ; ---- 第一行：工具按钮 + 输出（保存/钉屏/复制），与选区工具栏第一行同结构 ----
    ; 深色主题面板，微软雅黑字体（按钮统一 26 高：文字按钮/色块/分隔线对齐）
    EditorToolbar := Gui("-Caption +AlwaysOnTop -DPIScale ToolWindow")
    EditorToolbar.MarginX := ToolbarDpi(8)
    EditorToolbar.MarginY := ToolbarDpi(6)
    EditorToolbar.BackColor := EDIT_TB_BG
    EditorToolbar.SetFont("s11", "Microsoft YaHei")
    tb := EditorToolbar
    ; 通用扁平按钮悬停状态（选区工具栏与编辑窗工具栏共用同一套窗口级鼠标处理）
    tb.HoverState := ToolbarHoverState()
    ToolbarHoverActive := tb.HoverState
    tb.HoverState.selFn := EditorIsSelectedTool.Bind(EditorToolButtons)  ; 仅工具按钮参与选中态

    ; 工具按钮区（PixPin 风格：矩形 / 箭头 / 椭圆 / 马赛克，选中态由 EditorToolbarRefresh 刷新）
    ; 标签带 Unicode 图标前缀，一眼识别工具用途（▭矩形 →箭头 ◯椭圆 ▦马赛克）
    ; 注意：必须用 .Bind() 在绑定瞬间捕获循环值 —— AHK v2 闭包读不到 for 循环变量
    ;       （闭包看到的是循环外未赋值的空值），直接闭包引用会在点击时访问空变量报错
    tools := [["▭ 矩形", "rect"], ["→ 箭头", "arrow"], ["◯ 椭圆", "ellipse"], ["▦ 马赛克", "mosaic"]]
    for t in tools {
        c := tb.HoverState.Add(tb, t[1], EditorSetTool.Bind(t[2]))
        EditorToolButtons[t[2]] := c
        EditorToolLabels[t[2]] := t[1]
    }

    ; 分隔线 + 输出按钮：保存 / 钉屏 / 复制（复制最右：复制后关闭编辑器，退出由 Esc 承担）
    ; 图标统一为符号字体字符（与工具按钮同风格，避免 emoji 彩色混排）：⤓保存 ⤒钉屏 ⧉复制
    ToolbarSeparator(tb)
    tb.HoverState.Add(tb, "⤓ 保存", EditorSave)
    tb.HoverState.Add(tb, "⤒ 钉屏", EditorPin)
    tb.HoverState.Add(tb, "⧉ 复制", EditorCopy)

    ; 先 AutoSize 拿到实际尺寸（缓存，拖动定位时复用，避免每帧 WinGetPos），
    ; 再缓存按钮客户区坐标（布局定稿后悬停命中测试用）
    tb.Show("NA AutoSize")
    WinGetPos &tx, &ty, &tw, &th, "ahk_id " EditorToolbar.Hwnd
    EditorToolbarW := tw, EditorToolbarH := th
    tb.HoverState.CacheRects()

    ; ---- 第二行：颜色行（"颜色"标签 + 色块 + 粗细档位 + 清除，与选区颜色行同结构，清除并入此行）----
    EditorColorToolbar := Gui("-Caption +AlwaysOnTop -DPIScale ToolWindow")
    EditorColorToolbar.MarginX := ToolbarDpi(8)
    EditorColorToolbar.MarginY := ToolbarDpi(6)
    EditorColorToolbar.BackColor := EDIT_TB_BG
    EditorColorToolbar.SetFont("s11", "Microsoft YaHei")
    ctb := EditorColorToolbar
    ; "颜色"标签带 ● 图标前缀（色块入口），宽度加宽容纳图标+文字（实测 53px，留居中边距）
    ctb.Add("Text", "x+m w" ToolbarDpi(62) " h" ToolbarDpi(26) " Center 0x200 Background" EDIT_TB_BTN_BG " c" EDIT_TB_BTN_TEXT, "● 颜色")
    ToolbarSeparator(ctb)
    for i, color in EDIT_COLORS {
        pair := SwatchCreate(ctb, color, EditorSetColor.Bind(i))
        EditorSwatchFrames.Push(pair[1])
        EditorColorSwatches.Push(pair[2])
    }
    ; 三档粗细图标（细/中/粗）：结构与色块一致（外框 30×30 + 内块 26×26 盖中心形成 2px 环），
    ; 内块中央 ● 圆点表示线宽档位（字号 8/11/15 对应细/中/粗）；选中态外框白环（同色块），点击切换线宽档位
    for i, w in EDIT_LINE_WIDTHS {
        pair := PenWidthIconCreate(ctb, EDIT_LINE_WIDTH_DISPLAY[i], EditorSetPenWidth.Bind(i))
        EditorPenWidthFrames.Push(pair[1])
    }
    ; 分隔线 + 清除（ToolbarSeparator 前导留白含 y0，打断色块内块 yp+2 的 y 继承，保证按钮顶端对齐）
    ToolbarSeparator(ctb)
    ctb.HoverState := ToolbarHoverState()  ; 清除按钮走同一套悬停样式（独立实例，经 ToolbarHoverAux 分发）
    ctb.HoverState.Add(ctb, "✕ 清除", EditorClear)
    ToolbarHoverAux := ctb.HoverState
    ctb.Show("NA AutoSize")
    WinGetPos &ctx, &cty, &ctw, &cth, "ahk_id " EditorColorToolbar.Hwnd
    EditorColorToolbarW := ctw, EditorColorToolbarH := cth
    ctb.HoverState.CacheRects()

    ; 两行整体定位：置于编辑窗正下方居中
    EditorRepositionToolbar(centerX, y)
    ; 两行工具栏淡入出现（约 130ms），避免编辑窗就绪后工具栏"硬出现"
    ToolbarFadeIn(EditorToolbar.Hwnd)
    ToolbarFadeIn(EditorColorToolbar.Hwnd)
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
; 两行整体定位（工具行 + 颜色行，与选区两行工具栏同一手法）；下方放不下则整体移到编辑窗上方
; 尺寸已缓存（EditorToolbarW/H、EditorColorToolbarW/H），边界复用蒙版覆盖范围（全屏并集），避免每帧 WinGetPos/MonitorGetWorkArea 的开销
EditorRepositionToolbar(centerX, y) {
    global EditorToolbar, EditorToolbarW, EditorToolbarH
    global EditorColorToolbar, EditorColorToolbarW, EditorColorToolbarH
    global EditorMaskOv
    if !EditorToolbar
        return
    tw := EditorToolbarW, th := EditorToolbarH
    ctw := EditorColorToolbarW, cth := EditorColorToolbarH
    ml := EditorMaskOv.mx, mt := EditorMaskOv.my
    mr := ml + EditorMaskOv.mw, mb := mt + EditorMaskOv.mh
    ; 颜色行固定显示，两行整体计入高度
    totalH := th + cth + 2
    cx := Min(Max(centerX, ml + tw // 2), mr - tw // 2)
    cy := y
    if (cy + totalH > mb)
        cy := Max(y - totalH - 8, mt)  ; 下方放不下则整体移到编辑窗上方
    py := Max(cy, mt)
    EditorToolbar.Move(cx - tw // 2, py, tw, th)
    if IsObject(EditorToolbar.HoverState)
        EditorToolbar.HoverState.SetWindowPos(cx - tw // 2, py, tw, th)  ; 同步悬停命中测试的窗口坐标缓存
    if EditorColorToolbar {
        ccx := Min(Max(centerX, ml + ctw // 2), mr - ctw // 2)
        cpx := ccx - ctw // 2
        cpy := Max(py + th + 2, mt)
        EditorColorToolbar.Move(cpx, cpy, ctw, cth)
        if IsObject(EditorColorToolbar.HoverState)
            EditorColorToolbar.HoverState.SetWindowPos(cpx, cpy, ctw, cth)  ; 同步悬停命中测试的窗口坐标缓存
    }
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

; ------------------------------------------------------------------
; 工具栏按钮回调
; ------------------------------------------------------------------
EditorSetTool(tool, *) {
    global EditorTool
    ; 切工具仅切换工具类型，颜色与线宽为所有工具共享，保持不变
    EditorTool := tool
    EditorToolbarRefresh()
}

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
    for ann in EditorAnnotations
        EditorReleaseAnnotationCache(ann)  ; 逐个释放马赛克缓存
    EditorAnnotations := []
    EditorBuildAnnotationLayer(EditorAnnotations)  ; 清空标注层（清除后画面立即干净，不残留旧标注）
    EditorRender()
}

EditorCopy(*) {
    global EditorResult
    EditorResult := "copy"
}

; 保存对话框弹出前临时隐藏全屏置顶覆盖层（蒙版/边框/工具栏）并降低编辑窗置顶，
; 避免系统保存对话框被置顶蒙版遮挡/拦截点击；对话框关闭后由 EditorRestoreOverlaysForDialog 恢复
; 注意：用 Gui.Hide/Show 而非 WinHide/WinShow —— WinHide 每窗口同步等待约 109ms（实测），
;       7 个窗口累计 ~766ms 造成保存明显卡顿；Gui.Hide 为 0ms 非阻塞
EditorHideOverlaysForDialog() {
    global EditorMaskOv, EditorBorders, EditorToolbar, EditorColorToolbar, EditorHwnd
    if IsObject(EditorMaskOv) && EditorMaskOv.hwnd
        EditorMaskOv.gui.Hide()
    if IsObject(EditorBorders)
        for b in EditorBorders
            b.Hide()
    if IsObject(EditorToolbar) && EditorToolbar.Hwnd
        EditorToolbar.Hide()
    if IsObject(EditorColorToolbar) && EditorColorToolbar.Hwnd
        EditorColorToolbar.Hide()
    WinSetAlwaysOnTop(0, "ahk_id " EditorHwnd)
}

; 恢复编辑窗置顶并重新显示覆盖层（与 EditorHideOverlaysForDialog 配对使用）
EditorRestoreOverlaysForDialog() {
    global EditorMaskOv, EditorBorders, EditorToolbar, EditorColorToolbar, EditorHwnd
    WinSetAlwaysOnTop(1, "ahk_id " EditorHwnd)
    if IsObject(EditorMaskOv) && EditorMaskOv.hwnd
        EditorMaskOv.gui.Show("NA")
    if IsObject(EditorBorders)
        for b in EditorBorders
            b.Show("NA")
    if IsObject(EditorToolbar) && EditorToolbar.Hwnd
        EditorToolbar.Show("NA")
    if IsObject(EditorColorToolbar) && EditorColorToolbar.Hwnd
        EditorColorToolbar.Show("NA")
}

EditorSave(*) {
    global EditorResult
    ; 弹系统保存对话框前临时隐藏置顶覆盖层，避免对话框被蒙版遮挡/拦截点击
    EditorHideOverlaysForDialog()
    saved := false
    filename := ""
    try {
        filename := SelectSaveFilename()  ; 系统对话框默认定位，不做位置控制
        if filename != "" {
            saved := true
            EditorHideWindowForSave()  ; 保存成功：立即隐藏编辑窗，屏幕恢复干净，渲染/写文件后台不可见
        }
    } finally {
        ; 仅取消保存时恢复覆盖层（保持编辑状态继续编辑）；
        ; 保存成功时覆盖层保持隐藏，避免「恢复→随即销毁」的闪回与停留
        if !saved
            EditorRestoreOverlaysForDialog()
    }
    if filename != ""
        EditorResult := "save:" filename
}

; 保存成功时隐藏编辑窗（覆盖层已在 EditorHideOverlaysForDialog 隐藏）：
; 使保存后屏幕立即恢复干净，原图渲染与文件写入在不可见状态下完成，与选区保存同样利落
EditorHideWindowForSave() {
    global EditorGui
    if EditorGui
        EditorGui.Hide()
}

EditorPin(*) {
    global EditorResult
    EditorResult := "pin"
}

EditorEscClose(*) {
    global EditorResult
    EditorResult := "cancel"
}

; ------------------------------------------------------------------
; 关闭编辑窗的悬浮工具栏与相关回调，保留编辑窗本身（蒙版/边框由 EditorOverlayCleanup 处理）
; 幂等，可安全重复调用
; ------------------------------------------------------------------
EditorCloseOverlays() {
    global EditorToolbar, EditorColorToolbar
    global EditorToolButtons, EditorToolLabels, EditorColorSwatches, EditorSwatchFrames
    global ToolbarHoverActive, ToolbarHoverAux
    global EditorDragging
    SetTimer EditorDragTick, 0
    if EditorToolbar {
        ; 工具栏销毁后悬停分发不再转发到其状态实例（防止 ToolbarHoverActive 悬空引用）
        if IsObject(EditorToolbar.HoverState) && ToolbarHoverActive = EditorToolbar.HoverState
            ToolbarHoverActive := 0
        try EditorToolbar.HoverState.ClearTransient()  ; 先取消渐变/清理暂存，避免 Map 残存控件引用
        try EditorToolbar.Destroy()
        catch
            WinClose("ahk_id " EditorToolbar.Hwnd)  ; Destroy 失败时强制关闭窗口
        EditorToolbar := 0
    }
    if EditorColorToolbar {
        if IsObject(EditorColorToolbar.HoverState) && ToolbarHoverAux = EditorColorToolbar.HoverState
            ToolbarHoverAux := 0
        try EditorColorToolbar.HoverState.ClearTransient()
        try EditorColorToolbar.Destroy()
        catch
            WinClose("ahk_id " EditorColorToolbar.Hwnd)
        EditorColorToolbar := 0
    }
    EditorToolButtons := Map()
    EditorToolLabels := Map()
    EditorColorSwatches := []
    EditorSwatchFrames := []
    EditorDragging := false
}

; ------------------------------------------------------------------
; 销毁编辑器持有的覆盖层（蒙版 + 边框），幂等
; 就地钉屏时蒙版单独销毁、边框转移给钉屏会话，本函数不参与
; ------------------------------------------------------------------
EditorOverlayCleanup() {
    global EditorMaskOv, EditorBorders
    MaskOverlayDestroy(EditorMaskOv)
    BorderStripsDestroy(EditorBorders)
    EditorMaskOv := 0
    EditorBorders := []
}

; ------------------------------------------------------------------
; 清理编辑窗资源（幂等，可安全重复调用）
; ------------------------------------------------------------------
EditorCleanup() {
    global EditorGui, EditorHwnd, EditorWorkBitmap, EditorBaseBitmap
    global EditorPending, EditorResult, EditorAnnotations, EditorBgBitmap, EditorBgBase
    EditorCloseOverlays()
    EditorOverlayCleanup()
    if EditorGui {
        try EditorGui.Destroy()
        EditorGui := 0
        EditorHwnd := 0
    }
    if EditorWorkBitmap {
        Gdip_DisposeImage(EditorWorkBitmap)
        EditorWorkBitmap := 0
    }
    ; 释放标注缓存（马赛克小图）与分层缓存（基础层/标注层），再释放原图
    for ann in EditorAnnotations
        EditorReleaseAnnotationCache(ann)
    EditorAnnotations := []
    if EditorPending {
        EditorReleaseAnnotationCache(EditorPending)
        EditorPending := 0
    }
    if EditorBgBitmap {
        Gdip_DisposeImage(EditorBgBitmap)
        EditorBgBitmap := 0
    }
    if EditorBgBase {
        Gdip_DisposeImage(EditorBgBase)
        EditorBgBase := 0
    }
    if EditorBaseBitmap {
        Gdip_DisposeImage(EditorBaseBitmap)
        EditorBaseBitmap := 0
    }
    EditorResult := ""
}

; ------------------------------------------------------------------
; 就地钉屏：编辑窗画面原地保留，仅关闭工具栏并切换钉屏交互（无感，零跳变）；
; 蒙版销毁（钉屏不需要暗区），边框转移给钉屏会话（拖动跟随、关闭释放）
; 不阻塞等待窗口关闭——清理挂到 Close 事件，编辑线程立即返回，
; F1 热键恢复空闲，支持连续截/钉多张图（多钉屏：每次调用独立转移资源，互不干扰）
; ------------------------------------------------------------------
EditorPinInPlace() {
    global EditorGui, EditorHwnd, EditorWorkBitmap, EditorBgBitmap, EditorBaseBitmap, EditorBgBase
    global EditorAnnotations, EditorPending, EditorMaskOv, EditorBorders
    global EditorWinW, EditorWinH, EditorImgW, EditorImgH

    ; 缩放源：原图分辨率合成图（原图 + 全部标注），钉屏缩放时按它等比重绘（保证标注随缩放保留）
    resSource := EditorRenderFull()

    ; 转移本次编辑窗资源到局部（全局清 0，防止下一编辑会话覆盖全局后误释放）
    localGui := EditorGui
    localHwnd := EditorHwnd
    workBmp := EditorWorkBitmap
    bgBmp := EditorBgBitmap
    bgBaseBmp := EditorBgBase
    baseBmp := EditorBaseBitmap
    anns := EditorAnnotations
    pend := EditorPending
    borders := EditorBorders  ; 覆盖层边框转移给钉屏会话（拖动跟随、关闭释放）
    winW := EditorWinW, winH := EditorWinH  ; 窗口尺寸随会话移交（缩放/拖动时边框跟随定位用）
    imgW := EditorImgW, imgH := EditorImgH
    EditorGui := 0
    EditorHwnd := 0
    EditorWorkBitmap := 0
    EditorBgBitmap := 0
    EditorBgBase := 0
    EditorBaseBitmap := 0
    EditorAnnotations := []
    EditorPending := 0
    EditorBorders := []

    ; 关闭工具栏，销毁蒙版（绘制消息钩子已在主循环 finally 中移除），编辑窗画面 + 边框保留
    EditorCloseOverlays()
    MaskOverlayDestroy(EditorMaskOv)
    EditorMaskOv := 0

    ; 原图已并入缩放源（resSource 含全部内容），就地释放，不再随会话保留
    Gdip_DisposeImage(baseBmp)

    ; 在画面右下角叠加缩放手柄并刷新分层窗口（画面本身原地保留，无感切换）
    handle := PinHandleSize(localHwnd)
    PinDrawGripOnto(workBmp, handle)
    _PinUpdateLayer(localHwnd, workBmp)

    ; 注册为钉屏会话（消息钩子常驻按 hwnd 分发，Esc 需求 +1），边框随会话移交
    PinRegister(localHwnd, localGui, borders, winW, winH, resSource, workBmp, imgW, imgH, handle)

    ; 不阻塞等待窗口关闭：清理挂到窗口 Close 事件（右键 / Esc → WinClose → WM_CLOSE 触发），
    ; 本函数立即返回，编辑线程随之结束，F1 热键恢复空闲，可继续截/钉下一张图（多张钉屏）
    localGui.OnEvent("Close", (*) => PinCleanupSession(localHwnd, bgBmp, bgBaseBmp, anns, pend))
}

; 钉屏会话关闭清理（Close 事件回调）：注销会话并释放全部资源（含覆盖层边框）；
; 每步独立 try 保护：单项失败不阻断其余资源释放（避免异常被全局错误钩子吞掉后静默泄漏）；
; 返回 0 允许 Gui 默认关闭流程继续（窗口销毁）
PinCleanupSession(hwnd, bgBmp, bgBaseBmp, anns, pend) {
    global PinSessions
    s := PinSessions.Get(hwnd, 0)
    if s {
        BorderStripsDestroy(s.borders)  ; 释放钉屏会话持有的覆盖层边框
        try Gdip_DisposeImage(s.work)   ; 释放显示工作位图（编辑窗转移画面）
        try Gdip_DisposeImage(s.src)    ; 释放缩放源合成图（原图 + 标注）
        try PinRemove(hwnd)
    }
    for ann in anns
        try EditorReleaseAnnotationCache(ann)
    if pend
        try EditorReleaseAnnotationCache(pend)
    try Gdip_DisposeImage(bgBmp)
    try Gdip_DisposeImage(bgBaseBmp)
    return 0
}
