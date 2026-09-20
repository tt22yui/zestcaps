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
;      选区内部左键拖动整体平移、沿外侧边框/四角拖动改大小（钉屏合并手法，丝滑），
;      悬停边/角/内部时切换对应的方向光标给出可拖动提示；
;      工具栏动作即确认：点击标注工具（矩形/箭头/椭圆/马赛克）→ 自动选中第 1 色（红色）
;      并无缝进入编辑窗（无需再点颜色，工具与颜色状态同步显示），立即可标注；
;      保存/钉屏/复制 → 直接输出到剪贴板/文件/置顶，取消由 Esc / 右键承担
; ==================================================================

#Include "..\Common\Gdip_All_v2.ahk"
#Include "Common\Overlay.ahk"    ; 覆盖层共享组件（全屏挖洞蒙版 + 4 条边框），选区/编辑器/钉屏三阶段复用
#Include "Common\ToolbarUI.ahk"  ; 工具栏通用组件（色块/扁平按钮/悬停），Editor 与选区工具栏共用
#Include "Editor.ahk"
#Include "Scroll\ScrollCapture.ahk"  ; 滚动截图（手动滚动 + 自动抓帧拼接），依赖 Editor/Pin 的 Esc 分发
#Include "Selection\WindowFind.ahk"
#Include "Selection\Select.ahk"

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
GdipToken := Gdip_Startup()
if !GdipToken {
    ; GDI+ 不可用时只停用截图功能，不弹模态框、更不退出脚本：
    ; CapsLock 切换/指示器等核心功能与截图无关，不应被一起带走
    ; （闪屏同样是 GDI+ 依赖，已按「优雅跳过」处理，此处保持一致）
    ScreenshotEnabled := false
    DebugLog("截图: GDI+ 初始化失败，已自动停用截图功能（其余功能正常）")
}
; 退出时不注册 OnExit 清理、也不调用 Gdip_Shutdown：GDI+ 在最后一次 shutdown 时才释放全部全局对象，
; 截图会话累积的位图/画布对象会使这一步挂起约 2 秒，阻塞 Reload 时旧实例退出
; （新实例被 #SingleInstance 等待，造成"重启慢"）。进程退出时系统自动回收 GDI+ 资源。

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
        ; 窗口可能在 WinExist 与 WinGetPos 之间消失（AHK v2 对已销毁窗口抛 TargetError）。
        ; 本函数由悬停/拖动定时器与消息回调复用，异常会顺着定时器线程中断整个截图会话（蒙版残留），
        ; 故统一兜底为「窗口已失效」，回落自由矩形
        try WinGetPos &x, &y, &w, &h, "ahk_id " this.win_id
        catch {
            this.win_id := 0
            return false
        }
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
        ; scroll 动作例外：滚动截图自行管理抓帧与覆盖层，进入独立流程（见下方 case "scroll"）
        pBitmap := 0
        if (action != "save" && action != "scroll") {
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
                ; Gdip 库约定：0=成功、负值=失败（见 Gdip_All_v2.ahk 的 Gdip_SaveBitmapToFile），
                ; 故必须显式比较 = 0，直接当布尔用会把成功判成失败
                if (pBitmap && Gdip_SaveBitmapToFile(pBitmap, filename) = 0) {
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
            case "scroll":
                ; 滚动截图：拆掉选区内透明拦截层与动作工具栏（用户需透过区域操作目标窗口滚动），
                ; 保留蒙版/边框作区域指示；RunScrollCapture 阻塞直到用户 Esc/右键结束并返回长图；
                ; 完成后销毁覆盖层，交给标注编辑窗（独立路径：覆盖层新建，不走继承）
                ovs := ScreenshotSelOverlays
                ScreenshotSelOverlays := 0
                scrollBmp := 0
                try {
                    _DestroyOverlays(0, 0, ovs.selGui, ovs.toolbar, false)
                    scrollBmp := RunScrollCapture(region)
                } finally {
                    MaskOverlayDestroy(ovs.mask)
                    BorderStripsDestroy(ovs.borders)
                }
                if !scrollBmp {
                    DebugLog("Screenshot: 滚动截图取消/失败")
                    return
                }
                try {
                    result := ShowEditor(scrollBmp, region, 0, "", 0, 0)
                } catch as e {
                    Gdip_DisposeImage(scrollBmp)
                    throw
                }
                DebugLog("Screenshot: 滚动截图编辑结束 -> " result)
            default:  ; "editor"：打开标注编辑窗（接管 pBitmap 生命周期，编辑结束时自动释放）
                ; initialTool/initialColor：点击标注工具时自动选中的预选工具与第 1 色（红色），
                ; 编辑器打开时同步该状态，立即可标注；点击窗口路径（未选工具）为空/0 → 编辑器无工具进入，
                ; 左键拖动可移动图片，点击工具栏工具后自动选中第 1 色直接绘制；
                ; 蒙版/边框就地升级给编辑器（洞切换到编辑窗、边框跟随编辑窗），不销毁重建；
                ; 选区工具栏由编辑器接管（row1 跨阶段持久，进编辑只补行2）；编辑器环境（编辑窗首帧）
                ; 就绪后由 leftoverCleanup 销毁遗留的拦截层（keepToolbar 保留工具栏），消除整屏明暗跳变
                ovs := ScreenshotSelOverlays
                inherited := ovs ? {mask: ovs.mask, borders: ovs.borders} : 0
                try {
                    result := ShowEditor(pBitmap, region, FinishSelectionOverlays.Bind(true, true, true), initialTool, initialColor, inherited)
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
