; ==================================================================
; 输入状态指示器 —— 鼠标旁显示 中/英/A
; ==================================================================

; 声明依赖 config.ahk 的全局配置（消除静态分析误报）
global IND_UPDATE_INTERVAL, IND_WIDTH, IND_HEIGHT, IND_OFFSET_X, IND_OFFSET_Y, IND_BRIEF_SHOW_DURATION
global IND_FONT_SIZE, IND_FONT_WEIGHT, IND_FONT_NAME
global IND_TEXT_CN, IND_COLOR_CN, IND_BG_CN
global IND_TEXT_EN, IND_COLOR_EN, IND_BG_EN
global IND_TEXT_A, IND_COLOR_A, IND_BG_A

; 纯逻辑（标签/配色选择 + Map 淘汰）抽到 Visual.ahk，便于无副作用单测
#Include "Visual.ahk"

; 全局设置：MouseGetPos 使用屏幕坐标（仅需设置一次）
CoordMode "Mouse", "Screen"

; 创建指示器 GUI
; 注意：基础样式【不加】WS_EX_LAYERED —— 分层窗在 DWM 下每次位移都逐帧合成，跟随会卡/拖影。
; 仅淡入淡出瞬间由 WinSetTransparent 临时上分层，完成后 Off 还原为普通窗（位移最平滑）。
; +E0x20(WS_EX_TRANSPARENT) 鼠标穿透  +E0x08000000(WS_EX_NOACTIVATE) 不抢焦点
; 加载期窗口调用可能失败：整体兜底为「停用指示器」而非中断启动（否则 OnError 吞异常后
; Main.ahk 后续的热键/托盘初始化被跳过，界面却毫无提示）
try {
    IndGUI := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x20 +E0x08000000 +Border")
    IndGUI.SetFont(IND_FONT_SIZE " " IND_FONT_WEIGHT, IND_FONT_NAME)
    IndGUI.MarginX := 0, IndGUI.MarginY := 0
    IndText := IndGUI.Add("Text", "cWhite x0 y0 w" IND_WIDTH " h" IND_HEIGHT " Center 0x200", IND_TEXT_CN)
    IndGUI.Show("w" IND_WIDTH " h" IND_HEIGHT " NoActivate")
    IndGUI.Hide()
} catch as indErr {
    IndicatorEnabled := false
    DebugLog("指示器: GUI 初始化失败，已停用指示器 - " indErr.Message)
}

; 短暂强制显示标记：为 true 时忽略光标类型，强制显示指示器
global indicatorBriefShow := false

; 启动定时器，让指示器跟随鼠标（仅功能开启时启动，避免禁用时空转）
; 时间分辨率是否有本进程的提升，供退出时配对 timeEndPeriod
global indicatorTimePeriodRaised := false

; 淡入淡出全局状态：必须在下方 if IndicatorEnabled 首次调用 _UpdateIndicator 之前初始化，
; 否则首次 StartIndicatorFade 启动的 _IndicatorFadeStep 定时器会读到未赋值的全局而抛错
global indAlpha := 0          ; 当前窗口透明度 0-255
global indFadeHide := false   ; 本次淡出完成后是否需要隐藏窗口

; 抓帧期抑制：滚动截图等持续抓屏场景置 true，强制隐藏指示器且不再显示，避免随光标被截进画面。
; 采用引用计数支持多阶段重叠（各阶段成对 on/off，互不误启用）；IndicatorCaptureSuppress 为派生状态
global IndicatorCaptureSuppressCount := 0
global IndicatorCaptureSuppress := false
; 抑制回调的 super-global 引用：由下方注册，供其它模块软调用（测试可不加载本模块）
global IndicatorCaptureSuppressFn := 0

; 按需抬高系统计时精度（P1-5 性能热点）：仅在指示器可见（跟随 IBeam 光标或短暂强制显示）时
; 抬到 1ms，保证 10ms 位置刷新顺滑；隐藏时立即还原——避免常驻抬高整机时钟中断频率的持续耗电。
IndicatorSetTimePeriod(on) {
    global indicatorTimePeriodRaised
    if (on && !indicatorTimePeriodRaised) {
        DllCall("winmm\timeBeginPeriod", "uint", 1)
        indicatorTimePeriodRaised := true
    } else if (!on && indicatorTimePeriodRaised) {
        try DllCall("winmm\timeEndPeriod", "uint", 1)
        indicatorTimePeriodRaised := false
    }
}

if IndicatorEnabled {
    SetTimer _UpdateIndicator, IND_UPDATE_INTERVAL
    _UpdateIndicator()
}

; 设置「抓帧期抑制」：滚动截图等抓屏场景调用，成对 on(true)/off(false)，可多阶段重叠。
; 抑制期间强制隐藏指示器并阻止显示，计数归零后按当前光标/状态重新判定；
; 经 super-global 回调供其它模块调用（见文件顶部声明）
IndicatorSetCaptureSuppress(on) {
    global IndicatorCaptureSuppress, IndicatorCaptureSuppressCount, indicatorBriefShow
    IndicatorCaptureSuppressCount := Max(0, IndicatorCaptureSuppressCount + (on ? 1 : -1))
    IndicatorCaptureSuppress := IndicatorCaptureSuppressCount > 0
    if IndicatorCaptureSuppress
        indicatorBriefShow := false
    _UpdateIndicator()
}
IndicatorCaptureSuppressFn := IndicatorSetCaptureSuppress

; 退出时配对释放时间分辨率提升（进程退出系统本会回收，但显式配对更规范：
; 不配对会在本进程整个生命周期内持续抬高系统计时精度，影响其他程序与笔记本耗电）
OnExit(Indicator_OnExit)
Indicator_OnExit(ExitReason, ExitCode) {
    global indicatorTimePeriodRaised
    if indicatorTimePeriodRaised {
        try DllCall("winmm\timeEndPeriod", "uint", 1)
        indicatorTimePeriodRaised := false
    }
}

; 定时器回调：更新指示器位置和内容（带缓存，避免无意义重绘）
_UpdateIndicator() {
    global IndicatorEnabled, IndicatorCaptureSuppress
    static prevLabel := "", prevBg := "", prevTxt := ""
    static prevX := 0, prevY := 0, prevVisible := false
    static prevHwnd := 0
    static imeFailStreak := 0   ; IME 检测连续失败计数（仅用于日志节流：只在失败起始拍记一条）
    static suppressHidden := false   ; 抓帧抑制是否已执行隐藏（避免每拍重复隐藏）

    ; 功能关闭时不再做 IME 检测，仅负责隐藏已显示的指示器
    if !IndicatorEnabled {
        if prevVisible {
            _IndicatorHideNow()
            prevVisible := false
        }
        return
    }

    ; 抓帧期（滚动截图等）：强制隐藏指示器，避免其随光标被截进画面；不做 IME 检测。
    ; 无条件隐藏（不只依赖 prevVisible）：淡出进行中或状态失配时也能立即消失
    if IndicatorCaptureSuppress {
        if !suppressHidden {
            _IndicatorHideNow()
            prevVisible := false
            suppressHidden := true
        }
        return
    }
    suppressHidden := false   ; 未抑制：允许下次抑制时重新执行隐藏

    activeHwnd := WinExist("A")
    activeKey := GetActiveProcKey()   ; 稳定跟踪键（进程名），与 IME_Switch 使用的键一致

    ; ---- 中/英判定 ----
    ; 优先级：真实转换检测 > 布局确定英文 > 跟踪状态（仅 TSF/WebView2 等经典读法不可信时兜底）
    conv := -1
    layout := "unknown"
    imcValid := false
    try {
        ; 三个 DllCall 检测在极端情况下可能抛运行时异常（imm32/user32 理论极低），
        ; 定时器回调内一旦抛出会弹错误框且反复触发。故整体兜底为「不确定」，
        ; 由下方分支按 layout/imcValid/SawChinese 的现有逻辑自然退化到跟踪状态。
        conv := DetectIMEByConversion(activeHwnd)
        layout := activeHwnd ? DetectIMEByLayout(activeHwnd) : "unknown"
        imcValid := activeHwnd ? DetectIMCValid(activeHwnd) : false
        imeFailStreak := 0
    } catch {
        ; 检测异常：连续失败只记失败起始拍的日志，避免每 10ms 周期刷屏
        imeFailStreak += 1
        if imeFailStreak = 1
            DebugLog("_UpdateIndicator: IME 检测异常(DllCall 抛错)，兜底为不确定状态(连续失败 #1)")
    }

    if (conv = 1) {
        ; 真实读到中文，锁定为中文并记录「该进程转换读法可信」（供后续 conv=0 时判断是否为真实英文）
        chinese := true
        SetIMESawChinese(activeKey, true)
    } else if (conv = 0 && imcValid) {
        ; 经典 Win32 窗口拥有 IMM 上下文：转换读法可信，0=确定英文
        chinese := false
    } else if (layout = false) {
        ; 非中文布局 → 确定英文（无论转换读法是否可信）
        chinese := false
    } else if GetIMESawChinese(activeKey) {
        ; 该进程曾真实读到过中文(WM_IME 有效，如 Trae/Electron)，此时 conv=0 是真实英文
        chinese := false
    } else {
        ; TSF-only 窗口(WebView2/Tauri)：经典读法恒错，用「上次切换」跟踪状态兜底
        chinese := GetIMEWindowState(activeKey)
    }

    SetIMEChinese(chinese)
    SetIMEWindowState(activeKey, chinese)
    IMETrimWindowStates(200)   ; 防止 Map 无限增长：超过上限时淘汰最早记录

    ; 1. 当前状态（纯函数选标签/配色，便于单测）
    vis := IndicatorVisual(GetKeyState("CapsLock", "T"), GetIMEChinese())
    label := vis.label, bg := vis.bg, txt := vis.txt

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
        if !prevVisible {
            ; 隐藏→显示：透明度先归零再显示并淡入，避免出现一闪而过的实心框
            SetIndicatorAlpha(0)
            MoveIndicator(mx, my)
            IndGUI.Show("NoActivate")
            StartIndicatorFade(true)
            prevX := mx
            prevY := my
            prevVisible := true
            IndicatorSetTimePeriod(true)   ; 可见期间才抬高计时精度（跟随更顺滑）
        } else if (mx != prevX || my != prevY) {
            ; 已显示：坐标有任何变化即移动（无死区、不缩放，纯位移最平滑）
            MoveIndicator(mx, my)
            prevX := mx
            prevY := my
        }
    } else {
        if prevVisible {
            StartIndicatorFade(false)   ; 触发淡出，完成后由淡出回调隐藏窗口
            prevVisible := false
            IndicatorSetTimePeriod(false)   ; 不再可见，还原计时精度省电
        }
    }
}

; ==================================================================
; 淡入淡出控制（分层窗口透明度动画）
; ==================================================================
; indAlpha / indFadeHide 两个全局状态在文件顶部（indicatorTimePeriodRaised 之后）初始化，
; 确保早于 if IndicatorEnabled 的首次 _UpdateIndicator 调用

; 设置窗口透明度：用 WinSetTransparent 自动管理 WS_EX_LAYERED（设数值即临时上分层，Off 还原普通窗）。
; 这样跟随阶段保持普通窗口位移最平滑，仅在淡入淡出瞬间才处于分层态。
SetIndicatorAlpha(alpha) {
    WinSetTransparent(alpha, IndGUI)
}

; 仅移动指示器窗口到(x,y)：用 SetWindowPos 纯位移，不缩放(NOSIZE)、不抢焦点(NOACTIVATE)、
; 不改层级(NOZORDER)。避免像 WinMove 那样按外框尺寸重设导致内容被裁剪/每次重排卡顿。
MoveIndicator(x, y) {
    static hwnd := 0
    if !hwnd
        hwnd := IndGUI.Hwnd
    ; flags = SWP_NOSIZE(0x1)|SWP_NOZORDER(0x4)|SWP_NOACTIVATE(0x10) = 0x15
    DllCall("user32\SetWindowPos", "ptr", hwnd, "ptr", 0, "int", x, "int", y, "int", 0, "int", 0, "uint", 0x15)
}

; 立即隐藏指示器（无淡出）：取消进行中的淡入淡出、归零透明度、隐藏窗口并还原为普通窗、还原计时精度。
; 供「功能关闭」「抓帧抑制」「淡出结束」等需要立即消失的场景复用（幂等）
_IndicatorHideNow() {
    global indAlpha
    SetTimer _IndicatorFadeStep, 0
    indAlpha := 0
    try IndGUI.Hide()
    try WinSetTransparent("Off", IndGUI)   ; 还原为普通窗，供下次平滑跟随
    IndicatorSetTimePeriod(false)
}

; 启动一次淡入(toShow=true)或淡出(toShow=false)
StartIndicatorFade(toShow) {
    global indFadeHide, IND_FADE_PERIOD
    indFadeHide := !toShow
    SetTimer _IndicatorFadeStep, IND_FADE_PERIOD
}

; 透明度步进：按周期推进 alpha，到达边界即停止（淡出结束时隐藏窗口）
_IndicatorFadeStep() {
    global indAlpha, indFadeHide
    global IND_FADE_IN_MS, IND_FADE_OUT_MS, IND_FADE_PERIOD
    if indFadeHide {
        step := Ceil(255 * IND_FADE_PERIOD / IND_FADE_OUT_MS)
        indAlpha -= step
        if indAlpha <= 0 {
            ; 淡出完成：复用统一的立即隐藏（归零透明度 + 隐藏 + 还原普通窗）
            _IndicatorHideNow()
        } else {
            SetIndicatorAlpha(indAlpha)
        }
    } else {
        step := Ceil(255 * IND_FADE_PERIOD / IND_FADE_IN_MS)
        indAlpha += step
        if indAlpha >= 255 {
            indAlpha := 255
            SetIndicatorAlpha(indAlpha)
            SetTimer _IndicatorFadeStep, 0
            WinSetTransparent("Off", IndGUI)   ; 淡入完成：还原为普通窗，位移不再走合成器
        } else {
            SetIndicatorAlpha(indAlpha)
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
