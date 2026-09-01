; ==================================================================
; CapsLock 键行为实现 —— 短按切换输入法 / 长按切换大小写
; 热键定义（CapsLock::）在主程序 Main.ahk 中
; ==================================================================

; 防重入标志（全局）：CapsLock 处理（含 KeyWait 等待期）未结束时忽略新的按下；
; capsBusySince 记录 capsBusy 置位时刻（A_TickCount），供看门狗判断是否超时卡死
global capsBusy := false
global capsBusySince := 0

; 处理 CapsLock 热键：按按压时间分发到不同功能
HandleCapsLock() {
    global capsBusy, capsBusySince
    ; 快速连按会在 KeyWait 等待期间触发新的热键线程（AHK 允许 KeyWait 重入），
    ; 多个并发线程会各自发送 Ctrl+Space，可能造成重复切换，或在发送中途被打断而遗留
    ; Ctrl 按下状态（表现为 Ctrl 卡住）。故增加此标志，同一时刻只允许一个处理流程。
    if capsBusy {
        DebugLog("CapsLock: 上次处理未完成，忽略本次按下")
        return
    }
    capsBusy := true
    capsBusySince := A_TickCount
    try {
        ; 快速连按冷却：距上次同热键触发不足 CAPS_COOLDOWN_MS 毫秒则忽略
        ; 防止连按时 IME 状态震荡（偶数次切换 = 回到原位）
        if (A_PriorHotkey = "CapsLock" && A_TimeSincePriorHotkey < CAPS_COOLDOWN_MS) {
            DebugLog("CapsLock: 冷却中，忽略 (" A_TimeSincePriorHotkey "ms < " CAPS_COOLDOWN_MS "ms)")
            return
        }
        ; 检测按键按压时间：
        ; - 短按(0.3秒内释放)：切换输入法
        ; - 长按(超过0.3秒)：切换大小写状态
        DebugLog("CapsLock: 按下，等待释放判定...")
        if KeyWait("CapsLock", "T" CAPS_SHORT_PRESS) {
            DebugLog("CapsLock: 短按 -> IME_Switch")
            IME_Switch()    ; 短按：调用输入法切换函数
        }
        else {
            DebugLog("CapsLock: 长按 -> CAPS_Switch")
            CAPS_Switch()   ; 长按：调用大小写切换函数
        }
    } finally {
        capsBusy := false
        capsBusySince := 0
    }
}

; ==================================================================
; 看门狗：capsBusy 超时自愈（防假死）
; 原理：HandleCapsLock 正常最长约 1.3s 内结束（短按判定 0.3s + 释放等待上限 1s），
;       若处理线程因外部原因挂起（如 SendInput/DllCall 异常卡住）走不到 finally，
;       capsBusy 会永久置位导致 CapsLock 功能失效（软假死）。本定时器周期检测，
;       超过 CAPS_BUSY_TIMEOUT_MS 未释放则强制复位，并释放可能残留的修饰键。
; ==================================================================
SetTimer WatchdogCapsBusy, CAPS_WATCHDOG_INTERVAL_MS

WatchdogCapsBusy() {
    global capsBusy, capsBusySince, CAPS_BUSY_TIMEOUT_MS
    if !capsBusy || !capsBusySince
        return
    elapsed := A_TickCount - capsBusySince
    if elapsed > CAPS_BUSY_TIMEOUT_MS {
        DebugLog("Watchdog: capsBusy 超时(" elapsed "ms > " CAPS_BUSY_TIMEOUT_MS "ms)，强制复位并释放修饰键")
        capsBusy := false
        capsBusySince := 0
        ForceReleaseModifiers()
    }
}

; 切换 CapsLock 大小写状态
CAPS_Switch() {
    ; 等待CapsLock按键释放，加超时防止假死（最多等 CAPS_RELEASE_TIMEOUT 秒）
    if KeyWait("CapsLock", "T" CAPS_RELEASE_TIMEOUT) {
        DebugLog("CAPS_Switch: CapsLock 已释放")
    } else {
        DebugLog("CAPS_Switch: KeyWait 超时(" CAPS_RELEASE_TIMEOUT "s)，CapsLock 可能未释放！")
    }

    ; 检查当前CapsLock状态并切换
    if GetKeyState("CapsLock", "T") {
        SetCapsLockState false
        DebugLog("CAPS_Switch: 关闭 CapsLock")
    }
    else {
        SetCapsLockState true
        DebugLog("CAPS_Switch: 开启 CapsLock")
    }
    ShowInputIndicator()
}

; 切换中英文输入法
IME_Switch() {
    global IME_WindowStates, IME_isChinese
    if GetKeyState("CapsLock", "T") {
        ; CapsLock 开启时短按：只关掉 CapsLock，不切输入法
        SetCapsLockState false
        ShowInputIndicator()
        return
    }
    ; 记录本次切换窗口的稳定跟踪键（进程名），供 _UpdateIndicator 读取同一键
    activeKey := GetActiveProcKey()

    ; CapsLock 关闭时短按：切换中英文输入法
    ; 先确保 Ctrl 是释放状态，避免累积导致卡键
    DebugLog("IME_Switch: 前置释放 Ctrl")
    ; 发送期间用 Critical 禁止被其他热键/定时器打断，
    ; 防止 ^{Space} 发送到一半被打断，留下没有对应 Ctrl up 的 Ctrl down（表现为 Ctrl 卡住）
    Critical
    try {
        SendInput "{Ctrl up}"
        DebugLog("IME_Switch: 发送 ^{Space}")
        SendInput "^{Space}"
        ; 发送后再次确保 Ctrl 已释放
        Sleep 10
        SendInput "{Ctrl up}"
    } finally {
        Critical "Off"
    }
    DebugLog("IME_Switch: 后置释放 Ctrl，完成")
    ; 记录本次切换：翻转该窗口自己的跟踪状态
    ; 关键：全新窗口(无历史记录)一律从 false(英文) 起算，绝不继承全局/上一窗口状态，
    ; 否则会把前面窗口的 中/英 带过来且在 TSF 窗口切反（Tauri 场景）。
    cur := IME_WindowStates.Has(activeKey) ? IME_WindowStates[activeKey] : false
    newState := !cur
    IME_isChinese := newState
    IME_WindowStates[activeKey] := newState
    ; 非阻塞延迟刷新指示器，等待 IME 完成切换
    SetTimer ShowInputIndicator, -100
}

; 强制释放全部修饰键并关闭 CapsLock（看门狗 / OnExit 共用）
ForceReleaseModifiers() {
    SendInput "{Ctrl up}{Alt up}{Shift up}{LWin up}{RWin up}"
    SetCapsLockState false
}

; 脚本退出时强制释放所有修饰键，防止按键卡死（通过 OnExit 注册）
ReleaseAllModifiers(ExitReason, ExitCode) {
    DebugLog("OnExit: 释放所有修饰键 (reason=" ExitReason ", code=" ExitCode ")")
    ; 记录当前修饰键状态，方便问题分析
    ctrlState := GetKeyState("Ctrl")
    altState := GetKeyState("Alt")
    shiftState := GetKeyState("Shift")
    lwinState := GetKeyState("LWin")
    rwinState := GetKeyState("RWin")
    DebugLog("OnExit: 退出前修饰键状态 Ctrl=" ctrlState " Alt=" altState " Shift=" shiftState " LWin=" lwinState " RWin=" rwinState)
    ; 强制释放所有修饰键
    ForceReleaseModifiers()
    Sleep 50
    DebugLog("OnExit: 修饰键释放完成")
}
