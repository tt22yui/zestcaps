; ==================================================================
; 通用快捷方式维护 —— 开机启动（Startup）/ 桌面快捷方式（DesktopShortcut）共用
; 两者机制完全一致（FileCreateShortcut 指向 A_ScriptFullPath、工作目录 A_ScriptDir），
; 仅目标目录不同。抽到本模块避免逐行重复（P1-4）；失败只写日志，不中断脚本。
; 依赖：DebugLog.ahk（由 Main.ahk 先行引入）
; ==================================================================

; 快捷方式是否存在
ShortcutExists(path) {
    return FileExist(path) != ""
}

; 创建快捷方式（已存在则跳过；失败写日志不中断）
ShortcutCreateIfMissing(path, tag) {
    if FileExist(path)
        return
    try {
        FileCreateShortcut A_ScriptFullPath, path, A_ScriptDir
    } catch as err {
        DebugLog(tag ": 创建快捷方式失败 - " err.Message)
    }
}

; 删除快捷方式（不存在则跳过；失败写日志不中断）
ShortcutRemoveIfExists(path, tag) {
    if !FileExist(path)
        return
    try {
        FileDelete path
    } catch as err {
        DebugLog(tag ": 删除快捷方式失败 - " err.Message)
    }
}
