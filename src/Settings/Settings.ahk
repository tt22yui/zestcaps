; ==================================================================
; 设置窗口 —— 集中编辑 config.ini 中的功能开关
; 入口：托盘菜单「设置...」（见 TrayMenu.ahk）
; 结构：Tab3 页签分组 —— 「通用」（启动相关）/「指示器」/「剪贴板」（粘贴）/「截图」（开关），
;       各功能模块开关归入各自页签，对应快捷键也跟随所在页签（文本框直接填写 AHK 原生格式），
;       新增模块只需加页签
; 保存后写回 config.ini 并重启脚本生效（与 Config.ahk 的读取约定一致）
; ==================================================================

; ==================================================================
; 每日清空时刻：两个「时/分」Edit + UpDown（0-23 / 0-59）组成的纯时间输入
; 用原生 AHK 控件，完全受 Tab3 页签与布局管理，不会像 Win32 裸控件那样
; 切页不跟随/错位；无日历、无日期，仅有上下微调 + 直接键入，杜绝非法时刻
; 越界输入由 UpDown 的 Range 自动钳制到合法区间
; ==================================================================

; 读取「时/分」两个 UpDown 编辑框，拼成 24 时制 "HH:mm"（补零）
ReadRBTime(hourEdit, minEdit) {
    return Format("{:02}:{:02}", Integer(hourEdit.Value), Integer(minEdit.Value))
}

; 保存设置并重启脚本（「保存并重启」按钮回调）
; editPasteKey/editShotKey：两个快捷键文本框（AHK 原生格式，如 ^v / F1）
; rbOn / editKeepDays / editTimeHour / editTimeMin：回收站页开关、保留天数、每日清空时刻（时/分两个 UpDown 编辑框）
SaveSettings(GuiObj, IndicatorOn, PasteOn, ScreenshotOn, StartupOn, SplashOn, editPasteKey, editShotKey, rbOn, editKeepDays, editTimeHour, editTimeMin) {
    global CONFIG_FILE
    ; 快捷键冲突校验（非法 / CapsLock / 两功能相同均在此拦截）
    err := ValidateHotkeyPair(editPasteKey.Value, editShotKey.Value, "纯文本粘贴", "区域截图")
    if err != "" {
        MsgBox err, "设置", "IconX"
        return
    }
    ; 回收站参数校验（清空时刻格式 / 保留天数合法性）
    err := ValidateRecycleBin(editKeepDays.Value, ReadRBTime(editTimeHour, editTimeMin))
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
        IniWrite (rbOn ? 1 : 0), CONFIG_FILE, "Features", "RecycleBinEnabled"
        ; 回收站参数配置写回（重启后由 Config.ahk 读取，RecycleBin.ahk 生效）
        IniWrite Integer(editKeepDays.Value), CONFIG_FILE, "RecycleBin", "KeepDays"
        IniWrite ReadRBTime(editTimeHour, editTimeMin), CONFIG_FILE, "RecycleBin", "Time"
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

; 校验「定时清空回收站」参数：每日清空时刻 HH:mm 格式 + 保留天数 ≥ 1；合法返回空串，非法返回错误信息
ValidateRecycleBin(keepDays, time) {
    if !RegExMatch(time, "^\d{1,2}:\d{2}$")
        return "清空时刻格式错误，请用 24 小时制 HH:mm（如 12:30）"
    try {
        if Integer(keepDays) < 1
            return "保留天数需至少为 1 天"
    } catch
        return "保留天数需为数字"
    return ""
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
    global RecycleBinEnabled, RBKeepDays, RBTime

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
    tabCtl := settingsGui.Add("Tab3", "x14 y12 w360 h240", ["通用", "指示器", "剪贴板", "截图", "回收站"])

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

    ; ---- 回收站页：定时清空回收站（开关 + 保留天数 + 每日清空时刻）----
    ; 布局对齐其他页签：标签左缘 x44、输入框统一起点 x110，两行按同网格排列
    tabCtl.UseTab(5)
    settingsGui.Add("GroupBox", "x28 y40 w332 h150", "定时清空回收站")
    rbCheck := settingsGui.Add("CheckBox", "x44 y62 w306", "每天自动清空回收站（保留近 N 天）")
    rbCheck.Value := RecycleBinEnabled
    ; 保留天数档位（下拉框选择），按配置当前值定位默认选中项（手动查找，兼容无 Array.IndexOf 的 AHK 版本）
    RB_KEEP_OPTIONS := ["7", "15", "30"]
    rbKeepIdx := 1
    for i, opt in RB_KEEP_OPTIONS
        if Format("{}", RBKeepDays) = opt
            rbKeepIdx := i
    settingsGui.Add("Text", "x44 y94 w64 h20", "保留天数")
    editKeepDays := settingsGui.Add("DropDownList", "x110 y90 w64 Choose" rbKeepIdx, RB_KEEP_OPTIONS)
    settingsGui.Add("Text", "x44 y126 w64 h20", "执行时刻")
    ; 纯时间输入：时/分两个 Edit + UpDown 微调（Range 0-23 / 0-59），越界自动钳制；
    ; 用原生 AHK 控件，天然受 Tab3 页签与布局管理，无日历、无日期、不串位
    editTimeHour := settingsGui.Add("Edit", "x110 y122 w40")
    uddTimeHour := settingsGui.Add("UpDown", "Range0-23")
    settingsGui.Add("Text", "x152 y126", ":")
    editTimeMin := settingsGui.Add("Edit", "x164 y122 w40")
    uddTimeMin := settingsGui.Add("UpDown", "Range0-59")
    ; 初始值由 RBTime 还原：先设 UpDown.Value（Range 会钳制非法值），再补齐两位显示
    uddTimeHour.Value := Integer(SubStr(RBTime, 1, 2))
    uddTimeMin.Value  := Integer(SubStr(RBTime, 4, 2))
    editTimeHour.Text := Format("{:02}", uddTimeHour.Value)
    editTimeMin.Text  := Format("{:02}", uddTimeMin.Value)
    settingsGui.Add("Text", "x44 y156 w312 h20", "上下微调或直接输入 24 时制")

    ; ---- 页签外：底部按钮 ----
    tabCtl.UseTab()    ; 回到页签外，底部按钮不受页签切换影响
    btnSave := settingsGui.Add("Button", "x210 y264 w116 h28", "保存并重启")
    btnSave.OnEvent("Click", (*) => SaveSettings(settingsGui, cbIndicator.Value, cbPaste.Value, cbScreenshot.Value, cbStartup.Value, cbSplash.Value, editPasteKey, editShotKey, rbCheck.Value, editKeepDays, editTimeHour, editTimeMin))
    btnCancel := settingsGui.Add("Button", "x326 y264 w56 h28", "取消")
    btnCancel.OnEvent("Click", (*) => CloseSettings(settingsGui))

    settingsGui.Show("w390 h300")
    ; 沉浸式深色标题栏（Win11）：对齐应用暗色品牌，让窗口标题栏与暗色图标/工具栏同源；
    ; DWM 属性(20=DWMWA_USE_IMMERSIVE_DARK_MODE)在 Win10 或显卡不支持时静默失效，try 兜底不弹错
    try DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", settingsGui.Hwnd, "UInt", 20, "Int*", true, "UInt", 4)
}
