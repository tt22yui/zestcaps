; ==================================================================
; 设置窗口 —— 集中编辑 config.ini 中的功能开关
; 入口：托盘菜单「设置...」（见 TrayMenu.ahk）
; 结构：Tab3 页签分组 —— 「通用」（启动相关）/「指示器」/「剪贴板」（粘贴）/「截图」（开关），
;       各功能模块开关归入各自页签，对应快捷键也跟随所在页签（文本框直接填写 AHK 原生格式），
;       新增模块只需加页签
; 保存后写回 config.ini 并重启脚本生效（与 Config.ahk 的读取约定一致）
; ==================================================================

; 保存设置并重启脚本（「保存并重启」按钮回调）
; editPasteKey/editShotKey：两个快捷键文本框（AHK 原生格式，如 ^v / F1）
SaveSettings(GuiObj, IndicatorOn, PasteOn, ScreenshotOn, StartupOn, SplashOn, editPasteKey, editShotKey) {
    global CONFIG_FILE
    ; 快捷键冲突校验（非法 / CapsLock / 两功能相同均在此拦截）
    err := ValidateHotkeyPair(editPasteKey.Value, editShotKey.Value, "纯文本粘贴", "区域截图")
    if err != "" {
        MsgBox err, "设置", "IconX"
        return
    }
    try {
        IniWrite (IndicatorOn ? 1 : 0), CONFIG_FILE, "Indicator", "IndicatorEnabled"
        IniWrite (PasteOn ? 1 : 0), CONFIG_FILE, "Features", "PastePlainEnabled"
        IniWrite (ScreenshotOn ? 1 : 0), CONFIG_FILE, "Features", "ScreenshotEnabled"
        IniWrite (StartupOn ? 1 : 0), CONFIG_FILE, "Features", "StartupEnabled"
        IniWrite (SplashOn ? 1 : 0), CONFIG_FILE, "Features", "SplashEnabled"
        ; 快捷键配置写回（重启后由 Hotkeys.ahk 读取并动态注册）
        IniWrite editPasteKey.Value, CONFIG_FILE, "Hotkeys", "PastePlain"
        IniWrite editShotKey.Value, CONFIG_FILE, "Hotkeys", "Screenshot"
        ; 同步开机启动快捷方式（config.ini 状态与系统启动项保持一致）
        SetStartup(StartupOn)
    } catch as err {
        MsgBox "保存设置失败：" err.Message, "设置", "IconX"
        return
    }
    ; 配置写回成功后重启脚本，使新配置全部生效
    ; 先销毁设置窗口再重启：Reload 需等旧实例完成 OnExit 清理才退出，
    ; 若窗口残留会显得"页面没关闭"，先关窗口可立即反馈
    GuiObj.Destroy()
    RestartScript()
}

; 重启脚本（设置保存 / 托盘「重启」共用）
; Reload 前先隐藏托盘图标：AHK 退出时不总是主动移除托盘图标，
; 残留的旧图标需鼠标悬停通知区域才被系统刷新清除（Windows 缓存行为），
; 提前隐藏可避免 Reload 后出现两个托盘图标的幻影图标
RestartScript() {
    DebugLog("重启: 调用 Reload（先隐藏托盘图标避免残留）")
    A_IconHidden := true
    Reload()
}

; 关闭设置窗口（关闭按钮 / Esc / 取消按钮共用）
CloseSettings(GuiObj) {
    GuiObj.Destroy()
}

; 打开设置窗口（托盘菜单调用；窗口已存在时仅前置显示）
OpenSettings() {
    global MENU_TITLE
    global HOTKEY_FORMAT_HINT
    global IndicatorEnabled, PastePlainEnabled, ScreenshotEnabled
    global StartupEnabled, SplashEnabled
    global PastePlainKey, ScreenshotKey

    ; 窗口已打开时前置显示，避免重复创建
    if WinExist("设置 - " MENU_TITLE) {
        WinActivate("设置 - " MENU_TITLE)
        return
    }

    settingsGui := Gui("+AlwaysOnTop", "设置 - " MENU_TITLE)
    settingsGui.OnEvent("Close", (*) => CloseSettings(settingsGui))
    settingsGui.OnEvent("Escape", (*) => CloseSettings(settingsGui))
    settingsGui.SetFont("s9", "Microsoft YaHei")

    ; 页签分组：通用（启动相关）/ 指示器 / 剪贴板（粘贴）/ 截图（开关）
    ; 各功能模块开关归入各自页签，对应快捷键跟随所在页签，新增模块只需加页签
    tabCtl := settingsGui.Add("Tab3", "x14 y12 w360 h240", ["通用", "指示器", "剪贴板", "截图"])

    ; ---- 通用页：启动相关设置 ----
    settingsGui.Add("GroupBox", "x28 y40 w332 h116", "启动选项")
    cbStartup := settingsGui.Add("CheckBox", "x44 y64 w306", "开机自动启动")
    cbStartup.Value := StartupEnabled
    cbSplash := settingsGui.Add("CheckBox", "x44 y88 w306", "启动闪屏动画")
    cbSplash.Value := SplashEnabled

    ; ---- 指示器页 ----
    tabCtl.UseTab(2)
    settingsGui.Add("GroupBox", "x28 y40 w332 h116", "功能开关")
    cbIndicator := settingsGui.Add("CheckBox", "x44 y64 w306", "输入状态指示器")
    cbIndicator.Value := IndicatorEnabled

    ; ---- 剪贴板页：纯文本粘贴（开关 + 跟随页签的快捷键文本框）----
    tabCtl.UseTab(3)
    settingsGui.Add("GroupBox", "x28 y40 w332 h116", "功能开关")
    cbPaste := settingsGui.Add("CheckBox", "x44 y64 w306", "纯文本粘贴")
    cbPaste.Value := PastePlainEnabled
    settingsGui.Add("Text", "x44 y96 w64 h20", "快捷键")
    editPasteKey := settingsGui.Add("Edit", "x110 y92 w208 h22", PastePlainKey)
    settingsGui.Add("Text", "x44 y164 w312 h20", HOTKEY_FORMAT_HINT)

    ; ---- 截图页：区域截图（开关 + 跟随页签的快捷键文本框）----
    tabCtl.UseTab(4)
    settingsGui.Add("GroupBox", "x28 y40 w332 h92", "截图开关")
    cbScreenshot := settingsGui.Add("CheckBox", "x44 y62 w306", "区域截图")
    cbScreenshot.Value := ScreenshotEnabled
    settingsGui.Add("Text", "x44 y94 w64 h20", "快捷键")
    editShotKey := settingsGui.Add("Edit", "x110 y90 w208 h22", ScreenshotKey)
    settingsGui.Add("Text", "x44 y140 w312 h20", HOTKEY_FORMAT_HINT)

    ; ---- 页签外：底部按钮 ----
    tabCtl.UseTab()    ; 回到页签外，底部按钮不受页签切换影响
    btnSave := settingsGui.Add("Button", "x210 y264 w116 h28", "保存并重启")
    btnSave.OnEvent("Click", (*) => SaveSettings(settingsGui, cbIndicator.Value, cbPaste.Value, cbScreenshot.Value, cbStartup.Value, cbSplash.Value, editPasteKey, editShotKey))
    btnCancel := settingsGui.Add("Button", "x326 y264 w56 h28", "取消")
    btnCancel.OnEvent("Click", (*) => CloseSettings(settingsGui))

    settingsGui.Show("w390 h300")
    ; 沉浸式深色标题栏（Win11）：对齐应用暗色品牌，让窗口标题栏与暗色图标/工具栏同源；
    ; DWM 属性(20=DWMWA_USE_IMMERSIVE_DARK_MODE)在 Win10 或显卡不支持时静默失效，try 兜底不弹错
    try DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", settingsGui.Hwnd, "UInt", 20, "Int*", true, "UInt", 4)
}
