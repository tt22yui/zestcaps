; ==================================================================
; 纯文本粘贴（默认 Ctrl+Shift+V，热键可配置）—— 归属「剪贴板」模块
; 热键由 Hotkeys.ahk 动态注册（可配置，见 src\Hotkeys\Hotkeys.ahk）
; ==================================================================

; 粘贴为纯文本并去除格式和首尾空白
PastePlain() {
    global PastePlainEnabled
    ; 记录进入时的修饰键状态，方便排查双重点击冲突
    ctrlPhys := GetKeyState("Ctrl", "P")
    shiftPhys := GetKeyState("Shift", "P")
    DebugLog("PastePlain: 热键触发 CtrlPhys=" ctrlPhys " ShiftPhys=" shiftPhys " enabled=" PastePlainEnabled)
    if !PastePlainEnabled {
        DebugLog("PastePlain: 功能关闭，透传 ^v")
        Send "^v"
        DebugLog("PastePlain: 透传 ^v 完成")
        return
    }
    ; 检查剪贴板是否为空或未定义
    if !IsSet(A_Clipboard) || (A_Clipboard == "") {
        return
    }

    ; 去除剪贴板文本的首尾空白字符
    A_Clipboard := Trim(A_Clipboard, " `t`r`n")

    ; 执行粘贴操作
    DebugLog("PastePlain: 纯文本粘贴，发送 ^v")
    Send "^v"
    DebugLog("PastePlain: ^v 完成")
}
