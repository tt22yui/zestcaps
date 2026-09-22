; ==================================================================
; Settings 子模块：设置窗口构建
; 由 Settings.ahk #Include。OpenSettings 负责窗口/页签骨架与底部按钮，
; 各页签控件由 _SettingsBuild<页签> 构建器加入，控件引用收集到 c（供保存按钮回调）。
; ==================================================================

; 打开设置窗口（托盘菜单调用；窗口已存在时仅前置显示）
OpenSettings() {
    global MENU_TITLE
    global APP_VERSION

    ; 窗口已打开时前置显示，避免重复创建
    if WinExist("设置 - " MENU_TITLE) {
        WinActivate("设置 - " MENU_TITLE)
        return
    }

    settingsGui := Gui("+AlwaysOnTop", "设置 - " MENU_TITLE)
    settingsGui.OnEvent("Close", (*) => CloseSettings(settingsGui))
    settingsGui.OnEvent("Escape", (*) => CloseSettings(settingsGui))
    settingsGui.SetFont("s9", "Microsoft YaHei")

    ; 页签分组：通用（启动相关）/ 指示器 / 剪贴板（粘贴）/ 截图（开关）/ 回收站 / 关于
    ; 各功能模块开关归入各自页签，对应快捷键跟随所在页签，新增模块只需加页签
    tabCtl := settingsGui.Add("Tab3", "x14 y12 w360 h240", ["通用", "指示器", "剪贴板", "截图", "回收站", "关于"])

    c := {}   ; 控件引用集合：各页签构建器写入，底部「保存并重启」按钮回调读取
    _SettingsBuildGeneral(settingsGui, tabCtl, c)
    _SettingsBuildIndicator(settingsGui, tabCtl, c)
    _SettingsBuildClipboard(settingsGui, tabCtl, c)
    _SettingsBuildScreenshot(settingsGui, tabCtl, c)
    _SettingsBuildRecycleBin(settingsGui, tabCtl, c)
    _SettingsBuildAbout(settingsGui, tabCtl, c)

    ; ---- 页签外：底部按钮 ----
    tabCtl.UseTab()    ; 回到页签外，底部按钮不受页签切换影响
    btnSave := settingsGui.Add("Button", "x210 y264 w116 h28", "保存并重启")
    btnSave.OnEvent("Click", (*) => SaveSettings(settingsGui, c.cbIndicator.Value, c.cbPaste.Value, c.cbScreenshot.Value, c.cbStartup.Value, c.cbSplash.Value, c.cbDesktopShortcut.Value, c.cbAutoUpdate.Value, c.editPasteKey, c.editShotKey, c.rbCheck.Value, c.editKeepDays, c.editTimeHour, c.editTimeMin, c.cbAutoReset.Value, c.editResetSecs))
    btnCancel := settingsGui.Add("Button", "x326 y264 w56 h28", "取消")
    btnCancel.OnEvent("Click", (*) => CloseSettings(settingsGui))

    settingsGui.Show("w390 h300")
    ; 沉浸式深色标题栏（Win11）：对齐应用暗色品牌，让窗口标题栏与暗色图标/工具栏同源；
    ; DWM 属性(20=DWMWA_USE_IMMERSIVE_DARK_MODE)在 Win10 或显卡不支持时静默失效，try 兜底不弹错
    try DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", settingsGui.Hwnd, "UInt", 20, "Int*", true, "UInt", 4)
}

; ---- 通用页：启动相关设置 ----
_SettingsBuildGeneral(gui, tabCtl, c) {
    global StartupEnabled, SplashEnabled, DesktopShortcutEnabled
    tabCtl.UseTab(1)
    gui.Add("GroupBox", "x28 y40 w332 h140", "启动选项")
    c.cbStartup := gui.Add("CheckBox", "x44 y64 w306", "开机自动启动")
    c.cbStartup.Value := StartupEnabled
    c.cbSplash := gui.Add("CheckBox", "x44 y88 w306", "启动闪屏动画")
    c.cbSplash.Value := SplashEnabled
    c.cbDesktopShortcut := gui.Add("CheckBox", "x44 y112 w306", "创建桌面快捷方式")
    c.cbDesktopShortcut.Value := DesktopShortcutEnabled
}

; ---- 指示器页 ----
_SettingsBuildIndicator(gui, tabCtl, c) {
    global IndicatorEnabled, AutoResetEnglishEnabled, AutoResetIdleSeconds
    global AUTO_RESET_MIN_SECONDS, AUTO_RESET_MAX_SECONDS
    tabCtl.UseTab(2)
    gui.Add("GroupBox", "x28 y40 w332 h150", "功能开关")
    c.cbIndicator := gui.Add("CheckBox", "x44 y64 w306", "输入状态指示器")
    c.cbIndicator.Value := IndicatorEnabled
    ; 空闲自动复位到英文：依赖指示器提供中/英状态，指示器关闭时联动禁用
    c.cbAutoReset := gui.Add("CheckBox", "x44 y92 w306", "自动复位到英文")
    c.cbAutoReset.Value := AutoResetEnglishEnabled
    gui.Add("Text", "x44 y124 w64 h20", "空闲秒数")
    c.editResetSecs := gui.Add("Edit", "x110 y120 w48")
    c.uddResetSecs := gui.Add("UpDown", "Range" AUTO_RESET_MIN_SECONDS "-" AUTO_RESET_MAX_SECONDS)
    c.uddResetSecs.Value := AutoResetIdleSeconds
    c.editResetSecs.Text := Format("{}", c.uddResetSecs.Value)
    c.cbAutoReset.Enabled := IndicatorEnabled
    c.editResetSecs.Enabled := IndicatorEnabled
    c.uddResetSecs.Enabled := IndicatorEnabled
    c.cbIndicator.OnEvent("Click", (*) => _ToggleAutoResetEnabled(c.cbIndicator.Value, c.cbAutoReset, c.editResetSecs, c.uddResetSecs))
}

; ---- 剪贴板页：纯文本粘贴（开关 + 跟随页签的快捷键文本框）----
_SettingsBuildClipboard(gui, tabCtl, c) {
    global PastePlainEnabled, PastePlainKey, HOTKEY_FORMAT_HINT
    tabCtl.UseTab(3)
    gui.Add("GroupBox", "x28 y40 w332 h116", "功能开关")
    c.cbPaste := gui.Add("CheckBox", "x44 y64 w306", "纯文本粘贴")
    c.cbPaste.Value := PastePlainEnabled
    gui.Add("Text", "x44 y96 w64 h20", "快捷键")
    c.editPasteKey := gui.Add("Edit", "x110 y92 w208 h22", PastePlainKey)
    gui.Add("Text", "x44 y164 w312 h20", HOTKEY_FORMAT_HINT)
}

; ---- 截图页：区域截图（开关 + 跟随页签的快捷键文本框）----
_SettingsBuildScreenshot(gui, tabCtl, c) {
    global ScreenshotEnabled, ScreenshotKey, HOTKEY_FORMAT_HINT
    tabCtl.UseTab(4)
    gui.Add("GroupBox", "x28 y40 w332 h92", "截图开关")
    c.cbScreenshot := gui.Add("CheckBox", "x44 y62 w306", "区域截图")
    c.cbScreenshot.Value := ScreenshotEnabled
    gui.Add("Text", "x44 y94 w64 h20", "快捷键")
    c.editShotKey := gui.Add("Edit", "x110 y90 w208 h22", ScreenshotKey)
    gui.Add("Text", "x44 y140 w312 h20", HOTKEY_FORMAT_HINT)
}

; ---- 回收站页：定时清空回收站（开关 + 保留天数 + 每日清空时刻）----
; 布局对齐其他页签：标签左缘 x44、输入框统一起点 x110，两行按同网格排列
_SettingsBuildRecycleBin(gui, tabCtl, c) {
    global RecycleBinEnabled, RBKeepDays, RBTime
    tabCtl.UseTab(5)
    gui.Add("GroupBox", "x28 y40 w332 h150", "定时清空回收站")
    c.rbCheck := gui.Add("CheckBox", "x44 y62 w306", "自动清理回收站")
    c.rbCheck.Value := RecycleBinEnabled
    ; 保留天数：可编辑下拉框（7/15/30 常用档位可点选，也允许直接键入任意 ≥1 的值）
    ; 初值用 .Text 回显 config 当前值（含非档位值）——旧实现用 DropDownList 固定档位，
    ; 当前值不在档位时默认落到第一档，保存时把用户的保留天数静默改掉
    RB_KEEP_OPTIONS := ["7", "15", "30"]
    gui.Add("Text", "x44 y94 w64 h20", "保留天数")
    c.editKeepDays := gui.Add("ComboBox", "x110 y90 w64", RB_KEEP_OPTIONS)
    c.editKeepDays.Text := Format("{}", RBKeepDays)
    gui.Add("Text", "x44 y126 w64 h20", "执行时刻")
    ; 纯时间输入：时/分两个 Edit + UpDown 微调（Range 0-23 / 0-59），越界自动钳制；
    ; 用原生 AHK 控件，天然受 Tab3 页签与布局管理，无日历、无日期、不串位
    c.editTimeHour := gui.Add("Edit", "x110 y122 w40")
    c.uddTimeHour := gui.Add("UpDown", "Range0-23")
    gui.Add("Text", "x152 y126", ":")
    c.editTimeMin := gui.Add("Edit", "x164 y122 w40")
    c.uddTimeMin := gui.Add("UpDown", "Range0-59")
    ; 初始值由 RBTime 还原：先设 UpDown.Value（Range 会钳制非法值），再补齐两位显示
    c.uddTimeHour.Value := Integer(SubStr(RBTime, 1, 2))
    c.uddTimeMin.Value  := Integer(SubStr(RBTime, 4, 2))
    c.editTimeHour.Text := Format("{:02}", c.uddTimeHour.Value)
    c.editTimeMin.Text  := Format("{:02}", c.uddTimeMin.Value)
}

; ---- 关于页：版本信息 + 自动更新（精简文字，沿用 x28/x44 对齐网格）----
_SettingsBuildAbout(gui, tabCtl, c) {
    global APP_VERSION, AutoUpdateEnabled
    tabCtl.UseTab(6)
    ; 版本信息分组（一行精简）
    gui.Add("GroupBox", "x28 y40 w332 h64", "版本信息")
    gui.Add("Text", "x44 y62 w44 h20", "版本")
    gui.Add("Text", "x88 y62 w240 h20", "v" APP_VERSION "（AutoHotkey v2 · MIT）")
    ; 自动更新分组：开关 + 下载/检查按钮（点击即反馈：不确定进度条脉冲 + 状态文本，不依赖 TrayTip）
    gui.Add("GroupBox", "x28 y128 w332 h116", "自动更新")
    c.cbAutoUpdate := gui.Add("CheckBox", "x44 y146 w220 h22", "启动时自动检查更新")
    c.cbAutoUpdate.Value := AutoUpdateEnabled
    if !A_IsCompiled
        c.cbAutoUpdate.Enabled := false              ; 源码运行不支持自动更新，禁用避免误导
    ; 按钮宽度按最长的「下载并更新 vX.Y.Z」留足，避免中文标签被截断
    c.btnUpdate := gui.Add("Button", "x44 y176 w150 h26", "检查更新")
    gui.Add("Text", "x202 y182 w150 h18", "自动从 GitHub 更新")
    c.updProg := gui.Add("Progress", "x44 y208 w300 h8", 0)
    c.updProg.Visible := false                       ; 默认隐藏，点击后才显示脉冲
    c.updStatus := gui.Add("Text", "x44 y222 w300 h20", (A_IsCompiled ? "点击「检查更新」查看 GitHub 是否发布新版本" : "自动更新仅编译版可用（源码运行不检查网络）"))
    c.btnUpdate.OnEvent("Click", (*) => HandleUpdateClick(c.btnUpdate, c.updProg, c.updStatus))
    ; 已有待下载更新时（例如启动检查刚发现新版本）直接显示下载入口，不用再点一次检查
    RefreshUpdateButton(c.btnUpdate)
    if A_IsCompiled && HasPendingUpdate()
        c.updStatus.Text := "发现新版本 v" PendingUpdateField("version") "，点按钮即可下载"
}

; 指示器开关联动：关闭指示器时禁用「空闲自动复位到英文」相关控件（中/英状态检测不再运行）
_ToggleAutoResetEnabled(On, cbAutoReset, editResetSecs, uddResetSecs) {
    cbAutoReset.Enabled := On
    editResetSecs.Enabled := On
    uddResetSecs.Enabled := On
}
