; ==================================================================
; 输入状态指示器 —— 鼠标旁显示 中/英/A
; ==================================================================

; 声明依赖 config.ahk 的全局配置（消除静态分析误报）
global IND_UPDATE_INTERVAL, IND_WIDTH, IND_HEIGHT, IND_OFFSET_X, IND_OFFSET_Y, IND_BRIEF_SHOW_DURATION
global IND_FONT_SIZE, IND_FONT_WEIGHT, IND_FONT_NAME
global IND_TEXT_CN, IND_COLOR_CN, IND_BG_CN
global IND_TEXT_EN, IND_COLOR_EN, IND_BG_EN
global IND_TEXT_A, IND_COLOR_A, IND_BG_A

; 全局设置：MouseGetPos 使用屏幕坐标（仅需设置一次）
CoordMode "Mouse", "Screen"

; 创建指示器 GUI
IndGUI := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x20 +E0x08000000 +Border")
IndGUI.SetFont(IND_FONT_SIZE " " IND_FONT_WEIGHT, IND_FONT_NAME)
IndGUI.MarginX := 0, IndGUI.MarginY := 0
IndText := IndGUI.Add("Text", "cWhite x0 y0 w" IND_WIDTH " h" IND_HEIGHT " Center 0x200", IND_TEXT_CN)
IndGUI.Show("w" IND_WIDTH " h" IND_HEIGHT " NoActivate")
IndGUI.Hide()

; 短暂强制显示标记：为 true 时忽略光标类型，强制显示指示器
global indicatorBriefShow := false

; 启动定时器，让指示器跟随鼠标（仅功能开启时启动，避免禁用时空转）
if IndicatorEnabled {
    SetTimer _UpdateIndicator, IND_UPDATE_INTERVAL
    _UpdateIndicator()
}

; 定时器回调：更新指示器位置和内容（带缓存，避免无意义重绘）
_UpdateIndicator() {
    global IndicatorEnabled, IME_isChinese, IME_WindowStates
    global IME_SawChinese
    static prevLabel := "", prevBg := "", prevTxt := ""
    static prevX := 0, prevY := 0, prevVisible := false
    static prevHwnd := 0

    ; 功能关闭时不再做 IME 检测，仅负责隐藏已显示的指示器
    if !IndicatorEnabled {
        if prevVisible {
            IndGUI.Hide()
            prevVisible := false
        }
        return
    }

    activeHwnd := WinExist("A")
    activeKey := GetActiveProcKey()   ; 稳定跟踪键（进程名），与 IME_Switch 使用的键一致

    ; ---- 中/英判定 ----
    ; 优先级：真实转换检测 > 布局确定英文 > 跟踪状态（仅 TSF/WebView2 等经典读法不可信时兜底）
    conv := DetectIMEByConversion(activeHwnd)
    layout := activeHwnd ? DetectIMEByLayout(activeHwnd) : "unknown"
    imcValid := activeHwnd ? DetectIMCValid(activeHwnd) : false

    if (conv = 1) {
        ; 真实读到中文，锁定为中文并记录「该进程转换读法可信」（供后续 conv=0 时判断是否为真实英文）
        chinese := true
        IME_SawChinese[activeKey] := true
    } else if (conv = 0 && imcValid) {
        ; 经典 Win32 窗口拥有 IMM 上下文：转换读法可信，0=确定英文
        chinese := false
    } else if (layout = false) {
        ; 非中文布局 → 确定英文（无论转换读法是否可信）
        chinese := false
    } else if IME_SawChinese.Has(activeKey) && IME_SawChinese[activeKey] {
        ; 该进程曾真实读到过中文(WM_IME 有效，如 Trae/Electron)，此时 conv=0 是真实英文
        chinese := false
    } else {
        ; TSF-only 窗口(WebView2/Tauri)：经典读法恒错，用「上次切换」跟踪状态兜底
        chinese := IME_WindowStates.Has(activeKey) ? IME_WindowStates[activeKey] : false
    }

    IME_isChinese := chinese
    IME_WindowStates[activeKey] := chinese
    ; 防止 Map 无限增长：超过 200 条时删除最早记录的进程（跟踪状态与锁存同步裁剪）
    if IME_WindowStates.Count > 200 {
        enum := IME_WindowStates.__Enum()
        enum(&oldest)
        IME_WindowStates.Delete(oldest)
        IME_SawChinese.Delete(oldest)
    }

    ; 1. 当前状态
    if GetKeyState("CapsLock", "T") {
        label := IND_TEXT_A, bg := IND_BG_A, txt := IND_COLOR_A
    } else if IME_isChinese {
        label := IND_TEXT_CN, bg := IND_BG_CN, txt := IND_COLOR_CN
    } else {
        label := IND_TEXT_EN, bg := IND_BG_EN, txt := IND_COLOR_EN
    }

    ; 2. GUI 样式只有变化时才重绘
    if (label != prevLabel) {
        IndText.Text := label
        prevLabel := label
    }
    if (bg != prevBg) {
        IndGUI.BackColor := bg
        prevBg := bg
    }
    if (txt != prevTxt) {
        IndText.Opt(txt)
        prevTxt := txt
    }

    ; 3. IBeam 光标时持续显示，或短暂强制显示期间也显示
    if (A_Cursor = "IBeam" || indicatorBriefShow) {
        MouseGetPos &mx, &my
        mx += IND_OFFSET_X
        my += IND_OFFSET_Y
        ; 移动超过 2px 或从隐藏→显示时才重新定位
        if !prevVisible || Abs(mx - prevX) >= 2 || Abs(my - prevY) >= 2 {
            IndGUI.Show("x" mx " y" my " w" IND_WIDTH " h" IND_HEIGHT " NoActivate")
            prevX := mx
            prevY := my
        }
        prevVisible := true
    } else {
        if prevVisible {
            IndGUI.Hide()
            prevVisible := false
        }
    }
}

; 状态变化时立即刷新指示器（并短暂强制显示，时间可配置）
ShowInputIndicator() {
    global IndicatorEnabled, indicatorBriefShow, IND_BRIEF_SHOW_DURATION
    if !IndicatorEnabled
        return
    indicatorBriefShow := true
    SetTimer _HideBriefIndicator, -IND_BRIEF_SHOW_DURATION
    _UpdateIndicator()
}

_HideBriefIndicator() {
    global indicatorBriefShow
    indicatorBriefShow := false
}
