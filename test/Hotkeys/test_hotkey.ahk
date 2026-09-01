; ==================================================================
; 快捷键自定义功能 —— 关键技术可行性测试（历史存档）
; 本脚本诞生于「点按录制」方案开发期，用于验证 InputHook 录制与 Hotkey 注册行为；
; 录制方案已于后续版本移除（改为设置窗口文本框直接填写 AHK 原生格式），
; 本脚本保留作复盘记录，不再对应正式模块功能
; 验证点：
;   1. Hotkey() 的 Action 支持「字符串函数名」与「函数对象」两种形式
;   2. 非法键名注册时是否抛错（作为保存时校验手段）
;   3. try 块内裸函数名作回调参数（复现 v2 已知陷阱，约束正式代码写法）
;   4. GetKeyName 从 vk/sc 取键名（录制方案下构建快捷键字符串）
;   5. InputHook 实测：KeyOpt N 触发 OnKeyDown、Stop 触发 OnEnd、修饰键状态读取
; 运行方式：& "$env:ProgramFiles\AutoHotkey\v2\AutoHotkey64.exe" test\test_hotkey.ahk
; 结果写入 %TEMP%\_tmp_hotkey_test.txt
; ==================================================================
#Requires AutoHotkey v2.0
#SingleInstance Force
#ErrorStdOut
#Warn All, Off

rf := A_Temp "\_tmp_hotkey_test.txt"
if FileExist(rf)
    try FileDelete(rf)

; 看门狗：8 秒强制退出，防止 Send 模拟按键卡住
SetTimer(() => ExitApp(), 8000)

; 退出时强制释放修饰键，防止 {Ctrl down} 残留卡键
OnExit((*) => (SendEvent "{Ctrl up}{Shift up}{Alt up}", true))

Log(msg) {
    FileAppend msg "`n", rf
}

; 测试回调（供 Hotkey 注册使用）
TestHandlerA(*) {
    global _hitsA
    _hitsA += 1
}

; ---- 1. 字符串形式的 Action（实测不支持，正式代码须用函数对象）----
_hitsA := 0
try {
    Hotkey "^+9", "TestHandlerA", "On"
    Log "WARN: 字符串 Action 居然注册成功（与预期不符）"
    Hotkey "^+9", "Off"
} catch as e {
    Log "INFO: 字符串 Action 注册被拒（确认 v2 不支持，须用函数对象）: " e.Message
}

; ---- 2. 函数对象形式的 Action（顶层取引用，避开 try 内裸函数名陷阱）----
fnA := TestHandlerA
try {
    Hotkey "^+8", fnA, "On"
    Log "PASS: 函数对象 Action 注册成功 ^+8"
    Hotkey "^+8", "Off"
} catch as e {
    Log "FAIL: 函数对象 Action 注册失败: " e.Message
}

; ---- 3. 非法键名注册应抛错 ----
try {
    Hotkey "zzzz", fnA, "On"
    Log "FAIL: 非法键名 zzzz 未抛错"
    Hotkey "zzzz", "Off"
} catch as e {
    Log "PASS: 非法键名 zzzz 抛错: " e.Message
}

; ---- 4. try 块内裸函数名作回调参数（v2 陷阱复现）----
try {
    Hotkey "^+7", TestHandlerA, "On"
    Log "INFO: try 内裸函数名可用（未复现陷阱）"
    Hotkey "^+7", "Off"
} catch as e {
    Log "INFO: try 内裸函数名抛错（确认陷阱，正式代码应避开）: " e.Message
}

; ---- 5. GetKeyName 从 vk/sc 取键名 ----
nameZ := GetKeyName(Format("vk{:02X}sc{:03X}", 0x5A, 0x2C))    ; Z 键
nameF1 := GetKeyName("vk70")                                  ; F1 = vk 0x70
Log "INFO: GetKeyName(vk5Asc02C)=" nameZ "  GetKeyName(vk70)=" nameF1
if nameZ = "z" || nameZ = "Z"
    Log "PASS: Z 键名映射正常"
else
    Log "WARN: Z 键名映射异常: " nameZ

; ---- 6. 修饰键 VK 判定逻辑 ----
IsModifierVK(vk) {
    return (vk = 0x10 || vk = 0x11 || vk = 0x12 || vk = 0xA0 || vk = 0xA1
        || vk = 0xA2 || vk = 0xA3 || vk = 0xA4 || vk = 0xA5 || vk = 0x5B || vk = 0x5C)
}
Log (IsModifierVK(0x11) ? "PASS: 0x11(Ctrl) 判定为修饰键" : "FAIL: 0x11 未判定为修饰键")
Log (IsModifierVK(0x5A) ? "FAIL: 0x5A(Z) 误判为修饰键" : "PASS: 0x5A(Z) 判定为非修饰键")

; ---- 7. InputHook 实测：模拟按下 Ctrl+Shift+F9，验证 OnKeyDown 与组合键构建 ----
InstallKeybdHook()    ; 安装键盘钩子，确保 GetKeyState 状态可靠

global capturedCombo := "NONE"
ih := InputHook("V", "{Esc}")
ih.KeyOpt("{All}", "N")    ; 通知选项：所有键触发 OnKeyDown
ih.OnKeyDown := (hook, vk, sc) => CaptureTest(hook, vk, sc)
ih.OnEnd := (*) => Log("INFO: OnEnd 触发, EndReason=" ih.EndReason ", EndKey=" ih.EndKey)
ih.Start()

; 组合键构建（与正式模块同逻辑）：Ctrl ^ + Shift + + Alt ! + Win #
; 注意：使用逻辑状态（GetKeyState 默认模式），实测物理状态(P)不反映注入/瞬态按键
BuildCombo(vk, sc) {
    mods := ""
    mods .= GetKeyState("Ctrl") ? "^" : ""
    mods .= GetKeyState("Shift") ? "+" : ""
    mods .= GetKeyState("Alt") ? "!" : ""
    mods .= GetKeyState("LWin") || GetKeyState("RWin") ? "#" : ""
    name := GetKeyName(Format("vk{:02X}sc{:03X}", vk, sc))
    if name = ""
        name := Format("vk{:02X}", vk)
    return mods . name
}

CaptureTest(hook, vk, sc) {
    global capturedCombo
    ; 记录每次按键（含修饰键）与修饰键状态读取，排查状态检测
    Log("INFO: KeyDown vk=" Format("0x{:02X}", vk) " sc=" Format("0x{:03X}", sc) "  CtrlP=" GetKeyState("Ctrl", "P") " CtrlL=" GetKeyState("Ctrl") " ShiftP=" GetKeyState("Shift", "P") " ShiftL=" GetKeyState("Shift"))
    if IsModifierVK(vk)
        return    ; 修饰键自身跳过，等主键
    capturedCombo := BuildCombo(vk, sc)
    hook.Stop()   ; 捕获到主键后停止
}

; 模拟按键：Ctrl 按下 → Shift 按下 → F9 → 释放（F9 在任何窗口都无副作用）
SendEvent "{Ctrl down}"
Sleep 30
SendEvent "{Shift down}"
Sleep 30
SendEvent "{F9}"
Sleep 50
SendEvent "{Shift up}"
Sleep 30
SendEvent "{Ctrl up}"
Sleep 150

Log "INFO: 录制捕获组合=" capturedCombo
if capturedCombo = "^+F9" || capturedCombo = "+^F9"
    Log "PASS: InputHook 捕获并构建组合键成功: " capturedCombo
else
    Log "WARN: 捕获组合键异常: " capturedCombo

; ---- 8. 已有热键的关闭/恢复/回调替换（恢复现场与保留键开关依赖此行为）----
CapsLock::DummyCapHandler()    ; 定义一个热键，模拟保留键 CapsLock
DummyCapHandler(*) {
    return
}
try {
    Hotkey "CapsLock", "Off"
    Hotkey "CapsLock", "On"
    Log "PASS: 已有热键 CapsLock 关闭/恢复成功"
} catch as e {
    Log "FAIL: 已有热键 CapsLock 开关失败: " e.Message
}
try {
    Hotkey "^+8", fnA, "On"    ; 重新注册已 Off 的键，替换回调
    Hotkey "^+8", "Off"
    Log "PASS: 重新注册已有热键成功（替换回调不抛错）"
} catch as e {
    Log "FAIL: 重新注册已有热键失败: " e.Message
}

; ---- 9. 零参数函数直接作 Hotkey 回调：v2 触发时会传入热键名参数，需确认是否报错 ----
global _hitsZero := 0
ZeroParamFn() {
    global _hitsZero
    _hitsZero += 1
}
try {
    Hotkey "^+6", ZeroParamFn, "On"
    Log "INFO: 零参数函数注册成功，模拟触发验证..."
    SendEvent "^+6"
    Sleep 150
    Log "INFO: 零参数回调触发次数 _hitsZero=" _hitsZero
    Hotkey "^+6", "Off"
} catch as e {
    Log "INFO: 零参数函数注册异常: " e.Message
}

; ---- 10. 闭包包装回调（(*)=>Fn()）作 Hotkey 回调：应正常触发 ----
global _hitsClosure := 0
ClosureFn() {
    global _hitsClosure
    _hitsClosure += 1
}
try {
    Hotkey "^+5", (*) => ClosureFn(), "On"
    Log "INFO: 闭包包装回调注册成功，模拟触发验证..."
    SendEvent "^+5"
    Sleep 150
    Log "INFO: 闭包回调触发次数 _hitsClosure=" _hitsClosure
    Hotkey "^+5", "Off"
} catch as e {
    Log "INFO: 闭包回调注册异常: " e.Message
}

ExitApp 0
