; ==================================================================
; 自动复位到英文（空闲复位）
; 开启且「输入状态指示器」也开启时：键盘空闲超过 AutoResetIdleSeconds 秒后，
; 自动关闭 CapsLock（大写→小写）、把中文输入法切回英文，并闪一下指示器反馈。
; 依赖：Config.ahk（AutoResetEnglishEnabled / AutoResetIdleSeconds / AUTO_RESET_POLL_MS）
;       Indicator.ahk（中/英状态 IME_isChinese、ShowInputIndicator）
;       InputSwitch\CapsLock.ahk（ResetIMEToEnglish）
; 空闲判定用 A_TimeIdleKeyboard（仅计键盘输入），需安装键盘钩子才能准确反映键盘空闲。
; ==================================================================

; 声明依赖的全局配置（消除静态分析误报）
global AutoResetEnglishEnabled, IndicatorEnabled, AutoResetIdleSeconds, AUTO_RESET_POLL_MS
global autoResetArmed := true   ; 是否处于「本段空闲尚未复位」的可复位 epoch

; 指示器关闭时中/英状态检测不运行（IME_isChinese 不更新），故此时本功能不启用
if (AutoResetEnglishEnabled && IndicatorEnabled) {
    InstallKeybdHook   ; A_TimeIdleKeyboard 依赖键盘钩子，否则退化为「任意输入空闲」
    SetTimer AutoResetEnglishTick, AUTO_RESET_POLL_MS
    DebugLog("自动复位: 已启用，空闲阈值 " AutoResetIdleSeconds " 秒")
}

; 空闲检测周期回调：按 epoch 决定是否复位（同一段空闲只复位一次）
AutoResetEnglishTick() {
    global AutoResetEnglishEnabled, IndicatorEnabled, AutoResetIdleSeconds
    global autoResetArmed
    if !(AutoResetEnglishEnabled && IndicatorEnabled)
        return
    ; 任意修饰键 / CapsLock 物理按下时跳过本拍，避免干扰进行中的组合键操作
    if (GetKeyState("Ctrl")
        || GetKeyState("Alt")
        || GetKeyState("Shift")
        || GetKeyState("LWin")
        || GetKeyState("RWin")
        || GetKeyState("CapsLock"))
        return
    ; 未达阈值：检测到键盘输入，重新武装本 epoch，等待下次空闲
    if (A_TimeIdleKeyboard < AutoResetIdleSeconds * 1000) {
        autoResetArmed := true
        return
    }
    if !autoResetArmed
        return  ; 本段空闲已复位过，不再重复
    changed := false
    if GetKeyState("CapsLock", "T") {
        SetCapsLockState false
        DebugLog("自动复位: 大写 -> 小写")
        changed := true
    }
    if ResetIMEToEnglish()
        changed := true
    autoResetArmed := false
    if changed
        ShowInputIndicator()  ; 闪一下 中/英/A 徽标反馈
}
