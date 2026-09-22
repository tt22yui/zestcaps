; ==================================================================
; Settings 子模块：保存与校验
; 由 Settings.ahk #Include。含 SaveSettings 与参数校验、时刻/秒数解析。
; ==================================================================

; ==================================================================
; 每日清空时刻：两个「时/分」Edit + UpDown（0-23 / 0-59）组成的纯时间输入
; 用原生 AHK 控件，完全受 Tab3 页签与布局管理，不会像 Win32 裸控件那样
; 切页不跟随/错位；无日历、无日期，仅有上下微调 + 直接键入，杜绝非法时刻
; 越界输入由 UpDown 的 Range 自动钳制到合法区间
; ==================================================================

; 由「时」「分」两栏文本拼 24 时制 "HH:mm"（补零）；非法返回空串（纯函数，便于单测）
; ⚠️ 判断「是不是数字」统一用 IsIntText（正则，只认可选负号的十进制整数）：
;    不要用内置 IsNumber()——它接受 "1.5"/"1e3" 等写法；且历史上 Gdip 库同名覆盖过内置版本
;    （现已改名 Gdip_IsNumber 修复），曾导致「保存设置总是报清空时刻格式错误」。
; 归一化（去空白 + 全角转半角）先行：中文输入法下很容易把 ０９ 这种全角数字打进框里
BuildClockTime(hourText, minuteText) {
    h := NormalizeDigits(hourText)
    mi := NormalizeDigits(minuteText)
    if !IsIntText(h) || !IsIntText(mi)
        return ""
    return Format("{:02}:{:02}", Integer(h), Integer(mi))
}

; 读取「时/分」两个 Edit（UpDown 伴生框）并拼成时刻；非法时写日志（原始内容）便于排查
ReadRBTime(hourEdit, minEdit) {
    built := BuildClockTime(hourEdit.Value, minEdit.Value)
    if built = ""
        DebugLog("设置: 时刻控件值非法 hour=[" hourEdit.Value "] min=[" minEdit.Value "]")
    return built
}

; 保存设置并重启脚本（「保存并重启」按钮回调）
; editPasteKey/editShotKey：两个快捷键文本框（AHK 原生格式，如 ^v / F1）
; rbOn / editKeepDays / editTimeHour / editTimeMin：回收站页开关、保留天数、每日清空时刻（时/分两个 UpDown 编辑框）
; autoResetOn / editResetSecs：指示器页「空闲自动复位到英文」开关与空闲秒数
SaveSettings(GuiObj, IndicatorOn, PasteOn, ScreenshotOn, StartupOn, SplashOn, DesktopShortcutOn, AutoUpdateOn, editPasteKey, editShotKey, rbOn, editKeepDays, editTimeHour, editTimeMin, autoResetOn, editResetSecs) {
    global CONFIG_FILE
    ; 快捷键冲突校验（非法 / CapsLock / 两功能相同均在此拦截）
    err := ValidateHotkeyPair(editPasteKey.Value, editShotKey.Value, "纯文本粘贴", "区域截图")
    if err != "" {
        MsgBox err, "设置", "IconX"
        return
    }
    ; 回收站参数校验（清空时刻格式与范围 / 保留天数合法性）+ 自动复位空闲秒数校验
    ; 包 try：保留天数与时刻来自可自由键入的控件，非数字时整数转换会抛异常；
    ; 不包的话异常会被全局兜底吞掉，用户点「保存并重启」将毫无反应也无提示
    try {
        err := ValidateRecycleBin(editKeepDays.Text, ReadRBTime(editTimeHour, editTimeMin))
        if err = ""
            err := ValidateAutoResetSeconds(editResetSecs.Text)
    } catch as e {
        err := "保留天数 / 执行时刻需填写有效数字（" e.Message "）"
    }
    if err != "" {
        MsgBox err, "设置", "IconX"
        return
    }
    try {
        IniWrite (IndicatorOn ? 1 : 0), CONFIG_FILE, "Indicator", "IndicatorEnabled"
        IniWrite (PasteOn ? 1 : 0), CONFIG_FILE, "Features", "PastePlainEnabled"
        IniWrite (ScreenshotOn ? 1 : 0), CONFIG_FILE, "Features", "ScreenshotEnabled"
        IniWrite (StartupOn ? 1 : 0), CONFIG_FILE, "Features", "StartupEnabled"
        IniWrite (DesktopShortcutOn ? 1 : 0), CONFIG_FILE, "Features", "DesktopShortcutEnabled"
        IniWrite (SplashOn ? 1 : 0), CONFIG_FILE, "Features", "SplashEnabled"
        IniWrite (rbOn ? 1 : 0), CONFIG_FILE, "Features", "RecycleBinEnabled"
        IniWrite (AutoUpdateOn ? 1 : 0), CONFIG_FILE, "Features", "AutoUpdateEnabled"
        IniWrite (autoResetOn ? 1 : 0), CONFIG_FILE, "Features", "AutoResetEnglishEnabled"
        ; 回收站参数配置写回（重启后由 Config.ahk 读取，RecycleBin.ahk 生效）
        IniWrite Integer(editKeepDays.Text), CONFIG_FILE, "RecycleBin", "KeepDays"
        IniWrite ReadRBTime(editTimeHour, editTimeMin), CONFIG_FILE, "RecycleBin", "Time"
        ; 自动复位空闲秒数写回（重启后由 Config.ahk 读取并夹取到合法区间）
        IniWrite Integer(NormalizeDigits(editResetSecs.Text)), CONFIG_FILE, "AutoReset", "IdleSeconds"
        ; 快捷键配置写回（重启后由 Hotkeys.ahk 读取并动态注册）
        IniWrite editPasteKey.Value, CONFIG_FILE, "Hotkeys", "PastePlain"
        IniWrite editShotKey.Value, CONFIG_FILE, "Hotkeys", "Screenshot"
        ; 同步开机启动快捷方式（config.ini 状态与系统启动项保持一致）
        SetStartup(StartupOn)
        ; 同步桌面快捷方式（config.ini 状态与桌面快捷方式保持一致）
        SetDesktopShortcut(DesktopShortcutOn)
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

; 校验「定时清空回收站」参数：每日清空时刻 HH:mm（含 0-23 / 0-59 范围校验）+ 保留天数 ≥ 1
; 合法返回空串，非法返回错误信息
ValidateRecycleBin(keepDays, time) {
    if !RegExMatch(time, "^(\d{1,2}):(\d{2})$", &m)
        ; 报错带上实际读到的内容：便于用户/排查者一眼看出是空、全角数字还是别的字符
        return "清空时刻格式错误：当前读到 [" time "]，请用 24 小时制 HH:mm（如 12:30）`n「时」「分」两栏请填半角数字（0-23 与 0-59），勿留空"
    ; 仅校验格式无法拦截 99:99，超出范围会排出错误的定时（RecycleBin.ahk 按字符串拼接执行时刻）
    if (Integer(m[1]) > 23 || Integer(m[2]) > 59)
        return "清空时刻超出范围，请填写 00:00 - 23:59"
    ; 同样用 IsIntText 而非内置 IsNumber（统一只认十进制整数写法，避免 "1.5" 等被误收）
    if !IsIntText(keepDays)
        return "保留天数需为数字"
    if Integer(keepDays) < 1
        return "保留天数需至少为 1 天"
    return ""
}

; 校验「空闲自动复位到英文」的空闲秒数：整数且在 [AUTO_RESET_MIN_SECONDS, AUTO_RESET_MAX_SECONDS] 内
; 合法返回空串；先归一化（去空白 + 全角转半角）再用 IsIntText 判定，处理中文输入法全角数字
ValidateAutoResetSeconds(text) {
    global AUTO_RESET_MIN_SECONDS, AUTO_RESET_MAX_SECONDS
    v := NormalizeDigits(text)
    if !IsIntText(v)
        return "空闲秒数需为整数（" AUTO_RESET_MIN_SECONDS "-" AUTO_RESET_MAX_SECONDS "）"
    if (Integer(v) < AUTO_RESET_MIN_SECONDS || Integer(v) > AUTO_RESET_MAX_SECONDS)
        return "空闲秒数需在 " AUTO_RESET_MIN_SECONDS " - " AUTO_RESET_MAX_SECONDS " 秒之间"
    return ""
}
