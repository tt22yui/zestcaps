; ==================================================================
; 输入法状态检测
; ==================================================================

; 当前活动窗口的输入法中/英模式（由 _UpdateIndicator 实时检测更新）
IME_isChinese := false
; 各窗口上次检测到的状态（检测失败时的兜底）
IME_WindowStates := Map()
; 各窗口「转换读法曾真实读到中文」锁存：为 true 表示该窗口 WM_IME 有效（如 Trae/Electron），
; 此时 conv=0 是真实英文；为 false(且无 IMM 上下文)表示 TSF-only 窗口(WebView2/Tauri)，须用跟踪状态。
IME_SawChinese := Map()

; 对新窗口做最佳推测：布局不是中文 → 肯定是英文
; 布局是中文（微信输入法等）→ 无法确定，返回当前值
DetectIMEByLayout(hwnd) {
    threadId := DllCall("user32\GetWindowThreadProcessId", "ptr", hwnd, "ptr", 0, "uint")
    hkl := DllCall("user32\GetKeyboardLayout", "uint", threadId, "ptr")
    langId := hkl & 0xFFFF
    ; 0x0804=zh-CN  0x0404=zh-TW  0x0C04=zh-HK  0x1004=zh-SG
    if (langId != 0x0804 && langId != 0x0404 && langId != 0x0C04 && langId != 0x1004)
        return false    ; 非中文布局 → 英文
    return "unknown"    ; 中文布局 → 不确定
}

; 顶层窗口是否持有有效 IMM 输入上下文（ImmGetContext 非空）
; TSF-only 应用(WebView2/Tauri)通常为 0 —— 这类窗口经典 IMM 读法(Wm_IME_CONTROL/ImmGetConversionStatus)拿不到真实转换模式，
; 检测时必须走「跟踪状态」分支；经典 Win32 窗口则返回 true，继续信任转换读法。
DetectIMCValid(hwnd) {
    if !hwnd
        return false
    hIMC := DllCall("imm32\ImmGetContext", "ptr", hwnd, "ptr")
    if hIMC
        DllCall("imm32\ImmReleaseContext", "ptr", hwnd, "ptr", hIMC)
    return hIMC ? true : false
}

; 当前活动窗口的稳定跟踪键：用进程名而非窗口 hwnd。
; WebView2/Tauri 等场景下，切换线程与指示器定时器的 WinExist("A") 会取到不同 hwnd，
; 若按键按 hwnd 存、定时器按 hwnd 读就会错位导致跟踪状态读不到；进程名在两者间始终一致。
; 注：函数名须与局部变量 activeKey 等区分（AHK 标识符大小写不敏感，撞名会被当未赋值变量）。
GetActiveProcKey() {
    try return WinGetProcessName("A")
    return ""
}

; 通过 WM_IME_CONTROL 消息查询 IME 中/英模式（微信输入法等 TSF IME 支持）
; 返回 1=中文  0=英文  -1=无法获取（无 IME 窗口或超时）
DetectIMEByConversion(hwnd) {
    if !hwnd
        return -1
    hImcWnd := DllCall("imm32\ImmGetDefaultIMEWnd", "ptr", hwnd, "ptr")
    if !hImcWnd
        return -1
    ; WM_IME_CONTROL=0x0283  IMC_GETCONVERSIONMODE=0x0005
    ; SMTO_ABORTIFHUNG=2：目标窗口卡死时立即返回；超时 100ms 防止脚本冻结
    out := 0
    success := DllCall("user32\SendMessageTimeout", "ptr", hImcWnd, "uint", 0x0283, "ptr", 0x0005, "ptr", 0, "uint", 2, "uint", 100, "ptr*", &out, "ptr")
    if !success
        return -1
    return out & 0x01
}
