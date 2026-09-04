; ==================================================================
; 桌面快捷方式功能 —— 通过桌面上的快捷方式（ZestCaps.lnk）实现
; 状态以 config.ini 的 DesktopShortcutEnabled 为准：启动时自动补齐快捷方式，
; 设置界面保存时同步（见 Settings.ahk 的 SetDesktopShortcut 调用）
; 机制与开机启动（Startup.ahk）一致，仅目标目录不同（桌面 vs 启动文件夹）
; ==================================================================
global DesktopShortcutEnabled

; 桌面快捷方式路径（统一入口，避免多处拼写不一致）
DesktopShortcutPath() {
    return A_Desktop "\ZestCaps.lnk"
}

; 检查是否已创建桌面快捷方式（快捷方式是否存在）
IsDesktopShortcutCreated() {
    return FileExist(DesktopShortcutPath()) != ""
}

; 创建桌面快捷方式（已存在时跳过；失败记录日志但不中断脚本）
CreateDesktopShortcut() {
    if FileExist(DesktopShortcutPath())
        return
    try {
        FileCreateShortcut A_ScriptFullPath, DesktopShortcutPath(), A_ScriptDir
    } catch as err {
        DebugLog("桌面快捷方式: 创建快捷方式失败 - " err.Message)
    }
}

; 删除桌面快捷方式（不存在时跳过；失败记录日志但不中断脚本）
RemoveDesktopShortcut() {
    if !FileExist(DesktopShortcutPath())
        return
    try {
        FileDelete DesktopShortcutPath()
    } catch as err {
        DebugLog("桌面快捷方式: 删除快捷方式失败 - " err.Message)
    }
}

; 按设置状态同步桌面快捷方式（设置界面保存时调用；1=创建 0=删除）
SetDesktopShortcut(Enabled) {
    if Enabled
        CreateDesktopShortcut()
    else
        RemoveDesktopShortcut()
}

; 启动时自动补齐：配置要求创建桌面快捷方式但被删（如用户手删）时补建，保证状态一致
if DesktopShortcutEnabled && !IsDesktopShortcutCreated()
    CreateDesktopShortcut()