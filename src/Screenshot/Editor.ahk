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
#Include "Editor\Render.ahk"
#Include "Editor\Input.ahk"
#Include "Editor\Text.ahk"
#Include "Editor\Toolbar.ahk"
#Include "Editor\Output.ahk"
#Include "Editor\Lifecycle.ahk"

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
global EditorScrollButton := 0  ; 选区工具栏「滚动截图」按钮控件（仅选区阶段存在；进入编辑阶段仅隐藏、保留槽位，见 EditorHideScrollButton）
global EditorColorToolbar := 0  ; 颜色工具栏（第二行：颜色行 + 粗细档位，始终显示，与选区颜色行同结构）
global EditorColorToolbarW := 0, EditorColorToolbarH := 0  ; 颜色工具栏尺寸缓存
global ToolbarPhase := ""       ; 工具栏当前阶段（"selection" 选区 / "editor" 编辑），决定按钮点击行为
global ScreenToolbarResult := ""  ; 选区阶段动作结果通道（"editor"/save/pin/copy），替代对选区局部 state 的引用
global EditorToolButtons := Map()  ; 工具名 → 按钮控件（刷新选中态）
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
    markedSegs := 0     ; 马赛克已处理到的轨迹线段数（增量标记用，避免每帧重扫整条轨迹）
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

    try {
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
        ; 覆盖层就绪后才注册 WM_SIZE 同步（编辑器可从任务栏最小化，见 EditorSizeChanged）；
        ; 提前注册会被初始化期间的 WM_SIZE 触发，导致覆盖层在定位完成前提前显现
        OnMessage(0x0005, EditorSizeChanged)

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
            OnMessage(0x0005, EditorSizeChanged, 0)   ; 与注册对称注销（编辑器会话结束）
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
                    ; Gdip 库约定：0=成功、负值=失败（见 Gdip_All_v2.ahk 的 Gdip_SaveBitmapToFile）
                    if (Gdip_SaveBitmapToFile(pFull, filename) = 0)
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
