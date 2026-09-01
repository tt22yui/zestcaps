; ==================================================================
; 快捷键配置模块 —— 除 CapsLock 固定热键外，其余热键均可自定义
; 配置存 config.ini 的 [Hotkeys] 段（AHK 原生热键串，如 ^v / F1 / ^+f）
; 设置窗口「快捷键」文本框直接填写 AHK 原生格式 → 写回 ini → 重启生效（见 Settings.ahk）
; 当前可配置热键：
;   PastePlainKey —— 纯文本粘贴（默认 ^+v = Ctrl+Shift+V）
;   ScreenshotKey —— 区域截图（默认 F1）
; ==================================================================

; ----- 默认热键（内置兜底：ini 缺失/非法时回退） -----
PASTE_PLAIN_KEY_DEFAULT := "^+v"  ; 纯文本粘贴默认：Ctrl+Shift+V
SCREENSHOT_KEY_DEFAULT := "F1"    ; 区域截图默认：F1
HOTKEY_RESERVED        := "CapsLock"   ; 固定热键，禁止配置为其他功能（保护 Main.ahk 的 CapsLock::）

; ----- 从 config.ini 读取当前热键（无配置项时用默认值） -----
PastePlainKey := IniRead(CONFIG_FILE, "Hotkeys", "PastePlain", PASTE_PLAIN_KEY_DEFAULT)
ScreenshotKey := IniRead(CONFIG_FILE, "Hotkeys", "Screenshot", SCREENSHOT_KEY_DEFAULT)
; 启动校验：非法热键回退默认，避免注册时报错
if !IsValidHotkey(PastePlainKey)
    PastePlainKey := PASTE_PLAIN_KEY_DEFAULT
if !IsValidHotkey(ScreenshotKey)
    ScreenshotKey := SCREENSHOT_KEY_DEFAULT

; ==================================================================
; 动态注册所有可配置热键（Main.ahk 底部调用；CapsLock 固定热键不在此）
; Options 显式传 "On"：AHK v2 中若热键此前被禁用（Off），仅替换回调会保持禁用，
; 传 ON 才能保证注册后处于启用状态（官方文档：include the word ON in Options）
; 注册失败（如被系统/其他程序占用）仅记日志，不中断启动
; ==================================================================
RegisterCustomHotkeys() {
    ; AHK v2 约定：Hotkey 回调必须能接收热键名参数，0 参数函数（如 PastePlain/SelectRegionToCapture）
    ; 需用变参闭包 `(*) => 函数()` 包裹，否则抛 "Invalid callback function" 导致注册静默失败
    try Hotkey(PastePlainKey, (*) => PastePlain(), "On")
    catch as err
        DebugLog("快捷键注册失败: " PastePlainKey " → " err.Message)
    try Hotkey(ScreenshotKey, (*) => SelectRegionToCapture(), "On")
    catch as err
        DebugLog("快捷键注册失败: " ScreenshotKey " → " err.Message)
}

; ==================================================================
; 校验热键串是否可被 Hotkey 接受（纯语法检查，无副作用）
; AHK v2 无「卸载热键」功能，注册法校验会残留/覆盖真实热键，故改为：
; 拆出修饰符前缀后的键名，用 GetKeyName 确认是可识别按键（垃圾名返回空串）
; 显式排除固定键 CapsLock（避免误配置覆盖 CapsLock:: 的行为）
; ==================================================================
IsValidHotkey(key) {
    if key = ""
        return false
    if key = HOTKEY_RESERVED
        return false
    ; 去修饰前缀（含 < > 左右侧修饰，如 <^v / >!a / <^>! = AltGr），取键名
    rest := RegExReplace(key, "^[\~\$\*]*(?:[<>]?[\^\!\+\#])*")
    if rest = ""
        return false
    ; < > 仅作修饰前缀有意义，单独不是可识别按键（GetKeyName("<") 非空，需显式排除）
    if rest = "<" || rest = ">"
        return false
    return GetKeyName(rest) != ""
}

; ==================================================================
; 校验一对可配置热键是否合法且互不冲突（设置页保存前调用）
; 参数：keyA/keyB 两个 AHK 热键串；labelA/labelB 功能名（用于冲突提示）
; 返回：空串=通过；否则返回错误提示文案（非空即不通过）
; ==================================================================
ValidateHotkeyPair(keyA, keyB, labelA, labelB) {
    if !IsValidHotkey(keyA) || !IsValidHotkey(keyB)
        return "存在无效的快捷键，请检查输入。"
    if keyA = HOTKEY_RESERVED || keyB = HOTKEY_RESERVED
        return HOTKEY_RESERVED " 为固定热键，不能自定义。"
    if keyA = keyB
        return labelA " 与 " labelB " 不能使用相同的快捷键。"
    return ""
}
