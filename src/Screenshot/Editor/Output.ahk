; ==================================================================
; Editor 子模块：Output（由 Editor.ahk 机械拆分，仅搬运、逻辑不变）
; ==================================================================

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
    global EditorResult, EscNeed
    ; 弹系统保存对话框前临时隐藏置顶覆盖层，避免对话框被蒙版遮挡/拦截点击
    EditorHideOverlaysForDialog()
    ; 保存框期间临时关闭 Esc 热键：否则在对话框里按 Esc 取消保存时，Esc 会被统一分发
    ; 当成「取消编辑」而提前结束整个编辑会话（对齐选区保存框的处理）。
    ; 这里直接 Off 而不走 EscUnregister：EscNeed 是编辑/钉屏共享的引用计数，
    ; 多张钉屏共存时计数不归零，靠 EscUnregister 关不掉热键
    Hotkey "Esc", "Off"
    saved := false
    filename := ""
    try {
        filename := SelectSaveFilename()  ; 系统对话框默认定位，不做位置控制
        if filename != "" {
            saved := true
            EditorHideWindowForSave()  ; 保存成功：立即隐藏编辑窗，屏幕恢复干净，渲染/写文件后台不可见
        }
    } finally {
        ; 按引用计数恢复 Esc（本次只是临时关闭，不改变计数）
        if (EscNeed > 0)
            Hotkey "Esc", EditorEscDispatch, "On"
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
