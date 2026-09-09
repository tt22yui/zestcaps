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
global ToolbarPhase := ""       ; 工具栏当前阶段（"selection" 选区 / "editor" 编辑），决定按钮点击行为
global ScreenToolbarResult := ""  ; 选区阶段动作结果通道（"editor"/save/pin/copy），替代对选区局部 state 的引用
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
global EditorCircleCursor := 0  ; 画笔/马赛克专用小圆圈光标（CreateCursor 动态生成，无外部 .cur；会话结束 DestroyCursor 释放）
global EditorTextEditGui := 0   ; 文本标注输入覆盖窗 Gui（原生 Edit，支持中文 IME/光标/粘贴）
global EditorTextEditBox := 0   ; 输入覆盖窗 Edit 控件
global EditorTextPending := 0   ; 进行中的文本标注对象（图片空间锚点/色/字号；提交时填 text）
global EditorTextCommitting := false  ; 提交/结束进行中防重入：WM_KILLFOCUS 在销毁窗口时触发，据此拦截二次提交

; ------------------------------------------------------------------
; 标注数据结构：type + 图片空间坐标（x1,y1 起点 / x2,y2 终点）
;  - arrow/rect/ellipse: color + penWidth（绘制时按各自线宽）
;  - mosaic: 无 color/penWidth（采样原图）
; ------------------------------------------------------------------
class EditorAnnotation {
    type := ""
    x1 := 0, y1 := 0, x2 := 0, y2 := 0
    color := 0
    penWidth := 0  ; 线宽（图片空间像素，创建时快照当前档位）；arrow/rect/ellipse/brush 用
    brushR := 0    ; 马赛克笔头半径（图片空间像素，创建时按当前粗细档位快照）；仅 type="mosaic" 用
    points := []  ; 画笔折线点（每项 {x,y}，图片空间坐标）；仅 type="brush"/"mosaic" 使用
    text := ""    ; 文本内容；仅 type="text" 使用（x1,y1 为文本底块左上角锚点）
    fontSize := 0 ; 字号（图片空间像素，创建时按当前粗细档位快照）；仅 type="text" 使用
    cells := Map()      ; 马赛克已像素化格集（key="row:col"，值固定）；仅 type="mosaic" 使用
    cellColor := Map()  ; 每格平均色缓存（key="row:col" → ARGB，首次扫过算一次后固定）
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
    global EditorTool, EditorColorIdx, EditorPenWidthIdx, EditorResult
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
    OnMessage(0x20, EditorSetCursor)   ; WM_SETCURSOR：画笔/马赛克用圆环光标

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

        ; 悬浮工具栏：选区已 promote（row1 持久）则补行2并锚到编辑窗，过渡无跳动；
        ; 否则（快速截图无选区工具栏）全量构建两行
        if EditorToolbar
            EditorPromoteSelectionToolbar()
        else
            EditorCreateToolbar()
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
            OnMessage(0x20, EditorSetCursor, 0)
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
    for key in ann.cells {
        rowCol := StrSplit(key, ":")
        c := Integer(rowCol[1]), r := Integer(rowCol[2])
        gx := c * EDIT_MOSAIC_CELL, gy := r * EDIT_MOSAIC_CELL
        pBrush := Gdip_BrushCreateSolid(ann.cellColor[key])
        Gdip_FillRectangle(G, pBrush, gx * s, gy * s, EDIT_MOSAIC_CELL * s, EDIT_MOSAIC_CELL * s)
        Gdip_DeleteBrush(pBrush)
    }
}
; ------------------------------------------------------------------

; 沿笔触轨迹标记被笔头圆扫过的所有格子，并缓存每格平均色
; 关键：按「相邻采样点之间的线段」做胶囊覆盖（笔头半径 R 沿线段扫过），而非只圈孤立点圆。
; 这样手画再快、采样点再稀，两点之间的线段区间也会被像素化满，不断不掉、粗细一致。
EditorMosaicMarkTrail(ann, src, imgW, imgH, cell, R) {
    if ann.points.Length < 2
        return
    loop ann.points.Length - 1 {
        A := ann.points[A_Index], B := ann.points[A_Index + 1]
        EditorMosaicMarkSegment(ann, src, imgW, imgH, cell, R, A.x, A.y, B.x, B.y)
    }
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
    Gdip_LockBits(src, x, y, w, h, &Stride, &Scan0, &BitmapData, 3, 0x26200a)
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

; 释放标注的缓存资源（Mosaic 无独立 bitmap，仅索引/平均色 Map，可复用同一对象退出即弃）
EditorReleaseAnnotationCache(ann) {
}

; ------------------------------------------------------------------
; 鼠标事件（lParam 低16位=客户区X，高16位=客户区Y，符号扩展 → 图片空间坐标）
; ------------------------------------------------------------------
EditorLButtonDown(wParam, lParam, msg, hwnd) {
    global EditorHwnd, EditorPending, EditorTool, EditorColorIdx, EditorPenWidthIdx, EditorScale
    global EditorDragging, EditorDragWinX, EditorDragWinY, EditorDragMouseX, EditorDragMouseY
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
            EditorRepositionToolbar()
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
    ; 画笔/马赛克：追记末点；单点（仅点击无拖动）不提交
    tooSmall := (EditorPending.type = "brush" || EditorPending.type = "mosaic") && EditorPending.points.Length < 2
    ; 忽略过小区域（防误触）：丢弃时释放其缓存，避免泄漏
    if !tooSmall && (Abs(EditorPending.x2 - EditorPending.x1) > 2 || Abs(EditorPending.y2 - EditorPending.y1) > 2) {
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
; 光标：画笔/马赛克工具用小圆圈（WM_SETCURSOR 拦截，按当前工具切换）
; 其他工具走默认（箭头）；未选工具拖动也走默认，避免编辑区拖动时光标怪异
; ------------------------------------------------------------------
EditorSetCursor(wParam, lParam, msg, hwnd) {
    global EditorTool
    if (hwnd != EditorHwnd)
        return
    if (EditorTool = "brush" || EditorTool = "mosaic")
        return EditorApplyCircleCursor()   ; true=已处理（用小圆圈）；false=交系统默认
    return false  ; 交给系统默认
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

; ------------------------------------------------------------------
; 文本标注输入会话：点击 → 就地弹原生 Edit 覆盖窗（支持中文 IME/光标/粘贴）
;   → 输入 → Enter 提交 / Esc·点击外部·切工具 时提交或取消
; 提交将文本渲染为「半透明底块 + 彩色文字」标注并入标注层
; ------------------------------------------------------------------
EditorTextSessionActive() {
    global EditorTextEditGui
    return IsObject(EditorTextEditGui)
}

; 在图片空间坐标 (ix,iy) 处开启文本输入会话（先防御清理遗留会话）
EditorTextStartAt(ix, iy) {
    global EditorTextPending, EditorColorIdx, EditorPenWidthIdx
    global EDIT_COLORS, EDIT_TEXT_FONT_SIZE
    EditorTextEnd()   ; 防御：清理可能残留的会话
    EditorTextPending := EditorAnnotation()
    EditorTextPending.type := "text"
    EditorTextPending.color := EDIT_COLORS[EditorColorIdx]
    EditorTextPending.fontSize := EDIT_TEXT_FONT_SIZE[EditorPenWidthIdx]  ; 字号随粗细档位快照
    EditorTextPending.x1 := ix
    EditorTextPending.y1 := iy
    EditorTextCreateOverlay()
}

; 创建原生 Edit 输入覆盖窗（压在编辑窗上方，前景色=选中色、字号随档位、深色底预览）
; 尺寸校准：Edit 字体以 pt 计且随系统 DPI 缩放，与预估的显示px 不一致会「框比字小」，
; 故建窗后按控件字体的实际行高(GetTextMetrics)精确设定覆盖窗高度，杜绝文字被裁剪。
EditorTextCreateOverlay() {
    global EditorTextEditGui, EditorTextEditBox, EditorTextPending
    global EditorHwnd, EditorScale
    global EDIT_TEXT_FONT, EDIT_TEXT_BG, EDIT_TEXT_PADDING
    if IsObject(EditorTextEditGui)
        return
    fontSize := EditorTextPending.fontSize * EditorScale          ; 显示空间字号（px）
    colorStr := Format("c{:06X}", EditorTextPending.color & 0xFFFFFF)
    ; 编辑窗屏幕位置 + 锚点显示坐标 → 覆盖窗左上角
    WinGetPos &wx, &wy, , , "ahk_id " EditorHwnd
    sx := Round(EditorTextPending.x1 * EditorScale) + wx
    sy := Round(EditorTextPending.y1 * EditorScale) + wy
    pad := Round(EDIT_TEXT_PADDING * EditorScale)
    initW := Max(140, Round(fontSize * 8) + pad * 2)              ; 单行初始宽度：约 8 倍字号 + padding
    eg := Gui("-Caption +AlwaysOnTop -DPIScale ToolWindow")
    eg.MarginX := 0, eg.MarginY := 0
    eg.BackColor := EDIT_TEXT_BG
    box := eg.Add("Edit", "Background" EDIT_TEXT_BG " " colorStr) ; 单行输入（Enter 提交）
    ; Edit 字号需精确等于 fontSize（像素）才能与最终渲染一致：SetFont 用「点(pt)」，pt→px 随系统 DPI
    ; 缩放，故按 DPI 反算 pt = px * 72 / DPI（不动则 100% 屏用 *0.75，高 DPI 下输入框字号偏大→大小不符）
    box.SetFont("s" Max(1, Round(fontSize * 72 / A_ScreenDPI)), EDIT_TEXT_FONT)
    EditorTextEditBox := box
    EditorTextEditGui := eg
    boxH_tmp := Max(Round(fontSize * 1.6) + 8, 40)
    eg.Show("NA Hide x" sx " y" sy " w" initW " h" boxH_tmp)  ; 强制创建控件（隐藏），此后 box.Hwnd 有效
    ; 精确度量该字体实际像素行高（pt 随 DPI 缩放，用 GetTextMetrics 取值），量不到则按字号估算兜底
    lineH := EditorTextMeasureLineHeight(box.Hwnd)
    if (lineH <= 0)
        lineH := Round(fontSize * 1.6)
    boxH := lineH + Max(6, pad * 2)                               ; 高度 = 行高 + 上下留白
    box.Move(0, 0, initW, boxH)
    eg.Move(sx, sy, initW, boxH)
    eg.Show("NA")
    OnMessage(0x100, EditorTextKey)          ; WM_KEYDOWN：捕捉 Enter 提交
    OnMessage(0x0008, EditorTextKillFocus)   ; WM_KILLFOCUS：点击其他处（编辑窗/工具栏/外部窗口）→ 直接提交确认
    box.Focus()
}

; 测量控件字体的实际像素行高（tmHeight + tmExternalLeading）；失败返回 0 由调用方兜底
EditorTextMeasureLineHeight(ctrlHwnd) {
    lineH := 0
    try {
        hFont := SendMessage(0x0031, 0, 0, , "ahk_id " ctrlHwnd)  ; WM_GETFONT：取控件当前字体
        if hFont {
            hdc := DllCall("GetDC", "Ptr", ctrlHwnd, "Ptr")
            if hdc {
                hOld := DllCall("SelectObject", "Ptr", hdc, "Ptr", hFont, "Ptr")
                m := Buffer(64)
                if DllCall("GetTextMetricsW", "Ptr", hdc, "Ptr", m) {
                    tmHeight := NumGet(m, 0, "Int")    ; tmHeight
                    tmExtLead := NumGet(m, 16, "Int")  ; tmExternalLeading
                    lineH := tmHeight + tmExtLead
                }
                DllCall("SelectObject", "Ptr", hdc, "Ptr", hOld, "Ptr")
                DllCall("ReleaseDC", "Ptr", ctrlHwnd, "Ptr", hdc)
            }
        }
    }
    return lineH
}

; WM_KILLFOCUS：输入框失焦（点编辑窗/工具栏/任意外部窗口）＝ 点击其他地方 → 直接提交确认退出输入
; 延迟一拍提交，避免窗口消息处理中同步销毁本控件窗口引发问题；提交语义见 EditorTextCommit
EditorTextKillFocus(wParam, lParam, msg, hwnd) {
    global EditorTextEditBox, EditorTextCommitting
    if EditorTextCommitting
        return 0
    if IsObject(EditorTextEditBox) && (hwnd = EditorTextEditBox.Hwnd)
        SetTimer EditorTextCommit, -10
    return 0
}

; WM_KEYDOWN 分发：仅当焦点在输入覆盖窗 Edit 时，Enter 触发提交（OnEvent(KeyDown) 在分层场景注册报错，改走消息钩子）
EditorTextKey(wParam, lParam, msg, hwnd) {
    global EditorTextEditBox
    if (wParam = 0x0D) {   ; VK_RETURN
        hFocus := DllCall("GetFocus", "Ptr")
        if (IsObject(EditorTextEditBox) && hFocus = EditorTextEditBox.Hwnd) {
            EditorTextCommit()
            return 1   ; 消费 Enter，避免系统默认行为
        }
    }
    return ""
}

; 提交当前文本输入：非空 → 生成 text 标注并入标注层渲染；空文本则取消
EditorTextCommit() {
    global EditorTextEditGui, EditorTextEditBox, EditorTextPending
    global EditorAnnotations
    if !IsObject(EditorTextEditGui)
        return
    text := ""
    try text := EditorTextEditBox.Text
    pend := EditorTextPending
    EditorTextEnd()   ; 先销毁覆盖窗/注销消息（含清空 pending）
    if text = "" || !IsObject(pend)
        return
    pend.text := text
    EditorAnnotations.Push(pend)
    EditorAppendAnnotationToLayer(pend)
    EditorRender()
}

; 取消当前文本输入（丢弃，不产生标注）
EditorTextCancel() {
    EditorTextEnd()
}

; 结束文本输入会话：销毁覆盖窗、注销消息、清空 pending（幂等）
EditorTextEnd() {
    global EditorTextEditGui, EditorTextEditBox, EditorTextPending, EditorTextCommitting
    EditorTextCommitting := true   ; 销毁窗口会触发 WM_KILLFOCUS，置位拦截避免二次提交
    if IsObject(EditorTextEditGui) {
        try EditorTextEditGui.Destroy()
        OnMessage(0x100, EditorTextKey, 0)
        OnMessage(0x0008, EditorTextKillFocus, 0)
    }
    EditorTextEditGui := 0
    EditorTextEditBox := 0
    EditorTextPending := 0
    EditorTextCommitting := false
    EditorRefreshCursor()   ; 覆盖窗销毁后可能残留 I 形/旧光标，主动恢复到当前工具光标，防「鼠标偶发消失」
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
    global EditorToolButtons, EditorToolLabels
    global ToolbarHoverActive
    global EDIT_TB_BG, EDIT_TB_SEP
    if EditorToolbar
        return EditorToolbar
    ; 防御性重置（正常流程中清理函数已清空，这里兜底防重复调用时累积）
    EditorToolButtons := Map()
    EditorToolLabels := Map()
    ; 深色主题面板，微软雅黑字体（按钮统一 24 高：文字按钮/色块/分隔线对齐）
    EditorToolbar := Gui("-Caption +AlwaysOnTop -DPIScale ToolWindow")
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
    ; 纯图标改版：几何绘图类用 Segoe UI Symbol 字形（▭矩形 →箭头 ◯椭圆 ▦马赛克 ✎画笔）
    tools := [["▭", "rect", "矩形"], ["→", "arrow", "箭头"], ["◯", "ellipse", "椭圆"], ["T", "text", "文本"], ["▦", "mosaic", "马赛克"], ["✎", "brush", "画笔"]]
    for t in tools {
        c := tb.HoverState.AddIcon(tb, t[1], "Segoe UI Symbol", ToolbarToolClick.Bind(t[2]), t[3])
        EditorToolButtons[t[2]] := c
        EditorToolLabels[t[2]] := t[1]
    }

    ; 分隔线 + 输出按钮：保存 / 钉屏 / 复制（复制最右），点击行为由 ToolbarPhase 分流
    ; 纯图标改版：系统动作类统一用 Segoe MDL2 Assets（⤓→E74E保存 图钉→E840钉屏 ⧉→E8C8复制），
    ToolbarSeparator(tb)
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
    EditorColorToolbar := Gui("-Caption +AlwaysOnTop -DPIScale ToolWindow")
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
    ; 回滚到动画起点：row1 回原位；row2 紧贴 row1 下缘、先全透明（从贴合处向下展开）
    EditorToolbar.Move(sx, sy)
    r2StartY := fy + EditorToolbarH
    EditorColorToolbar.Move(fx, r2StartY)
    try WinSetTransparent 0, "ahk_id " EditorColorToolbar.Hwnd
    ; 显示两行（row1 本就可见，Show 无副作用；row2 首次 Show）
    EditorToolbar.Show("NA")
    EditorColorToolbar.Show("NA")
    _ToolbarTransitionRun({r1: EditorToolbar, r2: EditorColorToolbar
        , sx: sx, sy: sy, fx: fx, fy: fy
        , w1: EditorToolbarW, h1: EditorToolbarH, w2: EditorColorToolbarW, h2: EditorColorToolbarH
        , r2x: fx, r2sy: r2StartY, r2ey: cy, dur: 160})
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
    global EditorCircleCursor
    EditorTextEnd()   ; 防御：若存在未结束的文本输入会话，销毁覆盖窗并注销消息
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
    if EditorCircleCursor {   ; 释放动态光标（CreateCursor 句柄）
        DllCall("DestroyCursor", "Ptr", EditorCircleCursor)
        EditorCircleCursor := 0
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
