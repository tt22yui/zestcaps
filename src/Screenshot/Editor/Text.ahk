; ==================================================================
; Editor 子模块：Text（由 Editor.ahk 机械拆分，仅搬运、逻辑不变）
; ==================================================================

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
