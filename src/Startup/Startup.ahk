; ==================================================================
; 开机启动功能 —— 通过开始菜单启动文件夹中的快捷方式实现
; 状态以 config.ini 的 StartupEnabled 为准：启动时自动补齐快捷方式，
; 设置界面保存时同步（见 Settings.ahk 的 SetStartup 调用）
; ==================================================================
global StartupEnabled

; 开机启动快捷方式路径（统一入口，避免多处拼写不一致）
StartupShortcutPath() {
    return A_Startup "\ZestCaps.lnk"
}

; 检查是否已设置开机启动（快捷方式是否存在）
IsStartupEnabled() {
    return FileExist(StartupShortcutPath()) != ""
}

; 创建开机启动快捷方式（已存在时跳过；失败记录日志但不中断脚本）
CreateStartupShortcut() {
    if FileExist(StartupShortcutPath())
        return
    try {
        FileCreateShortcut A_ScriptFullPath, StartupShortcutPath(), A_ScriptDir
    } catch as err {
        DebugLog("开机启动: 创建快捷方式失败 - " err.Message)
    }
}

; 删除开机启动快捷方式（不存在时跳过；失败记录日志但不中断脚本）
RemoveStartupShortcut() {
    if !FileExist(StartupShortcutPath())
        return
    try {
        FileDelete StartupShortcutPath()
    } catch as err {
        DebugLog("开机启动: 删除快捷方式失败 - " err.Message)
    }
}

; 按设置状态同步开机启动（设置界面保存时调用；1=开启 0=关闭）
SetStartup(Enabled) {
    if Enabled
        CreateStartupShortcut()
    else
        RemoveStartupShortcut()
}

; 启动时自动补齐：配置要求开机启动但快捷方式被删（如用户手删）时补建，保证状态一致
if StartupEnabled && !IsStartupEnabled()
    CreateStartupShortcut()
