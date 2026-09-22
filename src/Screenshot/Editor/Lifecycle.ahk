; ==================================================================
; Editor 子模块：Lifecycle（由 Editor.ahk 机械拆分，仅搬运、逻辑不变）
; ==================================================================

; ------------------------------------------------------------------
; 编辑窗最小化 / 还原：同步覆盖层（边框 / 工具栏 / 蒙版）可见性
; 编辑器虽无标题栏，仍可从任务栏最小化；覆盖层都是独立顶层窗口(+AlwaysOnTop)，
; 不跟随宿主最小化，不处理就会在桌面上残留边框与工具栏（与钉屏同一根因，见 Pin.ahk 的 PinSizeChanged）。
; 直接复用保存框那套隐藏/恢复流程（覆盖层集合完全一致，且恢复只依赖缓存坐标，不查询分层窗口位置）。
; WM_SIZE 的 wParam：1=SIZE_MINIMIZED，0=SIZE_RESTORED，2=SIZE_MAXIMIZED；
; 注册时机见 ShowEditor（覆盖层就绪后注册，避免初始化期间提前显现）
; ------------------------------------------------------------------
EditorSizeChanged(wParam, lParam, msg, hwnd) {
    global EditorHwnd
    if (hwnd != EditorHwnd)
        return
    if (wParam = 1)
        EditorHideOverlaysForDialog()
    else
        EditorRestoreOverlaysForDialog()
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
    global EditorToolButtons, EditorColorSwatches, EditorSwatchFrames
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
    ; 标注集合与分层缓存（基础层/标注层）随后释放，最后释放原图；
    ; 标注缓存是普通 Map（马赛克格索引/平均色），随对象一并回收，无需显式释放
    EditorAnnotations := []
    EditorPending := 0
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
    global EditorCircleCursor, EditorResult

    ; 防御：文本输入会话若仍活跃（正常点击工具栏会先触发 KILLFOCUS 提交），
    ; 必须先提交再合成钉屏图，否则这段文字不进画面、Edit 覆盖窗可能残留在钉屏上
    if EditorTextSessionActive()
        EditorTextCommit()

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

    ; 就地钉屏不经过 EditorCleanup，这里补做两件只属于「编辑会话」的收尾：
    ;   1) 圆圈光标句柄只在 EditorCleanup 中释放，本路径必须自己释放，否则每次就地钉屏泄漏一个 USER 句柄；
    ;      先切回系统箭头再销毁，避免销毁正在生效的光标（否则指针可能瞬间异常）
    ;   2) EditorResult 复位，避免上一会话的结果残留到下一次编辑
    if EditorCircleCursor {
        DllCall("SetCursor", "Ptr", DllCall("LoadCursor", "Ptr", 0, "Ptr", 32512))  ; IDC_ARROW 标准箭头
        DllCall("DestroyCursor", "Ptr", EditorCircleCursor)
        EditorCircleCursor := 0
    }
    EditorResult := ""
}

; 钉屏会话关闭清理（Close 事件回调）：注销会话并释放全部资源（含覆盖层边框）；
; 每步独立 try 保护：单项失败不阻断其余资源释放（避免异常被全局错误钩子吞掉后静默泄漏）；
; 返回 0 允许 Gui 默认关闭流程继续（窗口销毁）
PinCleanupSession(hwnd, bgBmp, bgBaseBmp, anns, pend) {
    s := PinGetSession(hwnd)
    if s {
        BorderStripsDestroy(s.borders)  ; 释放钉屏会话持有的覆盖层边框
        try Gdip_DisposeImage(s.work)   ; 释放显示工作位图（编辑窗转移画面）
        try Gdip_DisposeImage(s.src)    ; 释放缩放源合成图（原图 + 标注）
        try PinRemove(hwnd)
    }
    ; anns/pend（标注集合）无需显式释放：马赛克缓存是普通 Map，随对象一并回收
    try Gdip_DisposeImage(bgBmp)
    try Gdip_DisposeImage(bgBaseBmp)
    return 0
}
