; ==================================================================
; Indicator 纯逻辑（便于单测，无窗口/定时器副作用）
; 由 Indicator.ahk #Include；仅依赖 Config.ahk 的 IND_* 常量。
; ==================================================================

; 按 CapsLock / 中英状态选择指示器显示（标签 / 背景色 / 文字色）
IndicatorVisual(capsOn, chinese) {
    global IND_TEXT_A, IND_BG_A, IND_COLOR_A
    global IND_TEXT_CN, IND_BG_CN, IND_COLOR_CN
    global IND_TEXT_EN, IND_BG_EN, IND_COLOR_EN
    if capsOn
        return { label: IND_TEXT_A, bg: IND_BG_A, txt: IND_COLOR_A }
    if chinese
        return { label: IND_TEXT_CN, bg: IND_BG_CN, txt: IND_COLOR_CN }
    return { label: IND_TEXT_EN, bg: IND_BG_EN, txt: IND_COLOR_EN }
}
