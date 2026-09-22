; 设置窗口 GUI 回归测试：
;   - Settings.ahk 能正常加载、OpenSettings 能创建窗口
;   - 「关于」页更新按钮：默认「检查更新」；登记待下载更新后必须**就地变成「下载并更新 vX.Y.Z」**
;     （回归：旧实现只弹 Yes/No 模态框，弹窗被关掉/显示失败后界面上再无任何下载入口；
;      根因是选项串误写 IconQuestion 使 MsgBox 抛 Invalid option. 并被全局处理器静默吞掉）
; 带看门狗（15 秒强制关闭窗口并退出），结果写入 %TEMP%\_tmp_settings_gui.txt
#Requires AutoHotkey v2.0
#SingleInstance Force
#ErrorStdOut
#Warn All, StdOut

resultFile := A_Temp "\_tmp_settings_gui.txt"
if FileExist(resultFile)
    try FileDelete(resultFile)

; 按 Main.ahk 的真实加载顺序引入（含 Gdip 链），避免独立加载时的跨模块静态告警
; （DebugLog / PastePlain / SelectRegionToCapture / SetStartup / SetDesktopShortcut 等）
#Include "..\..\src\Config\Config.ahk"
DEBUG_LOG_ENABLED := false                 ; 屏蔽日志写入
#Include "..\..\src\DebugLog\DebugLog.ahk"
#Include "..\..\src\Startup\Startup.ahk"
#Include "..\..\src\DesktopShortcut\DesktopShortcut.ahk"
#Include "..\..\src\Hotkeys\Hotkeys.ahk"   ; Settings 的「快捷键」页依赖（校验）
#Include "..\..\src\Updater\Updater.ahk"   ; 更新按钮依赖待下载状态与按钮文字
#Include "..\..\src\Clipboard\Clipboard.ahk"
#Include "..\..\src\Screenshot\Screenshot.ahk"
#Include "..\..\src\Common\Gdip_All_v2.ahk"
#Include "..\..\src\Settings\Settings.ahk"

; 看门狗：15 秒强制关闭窗口并退出（防止窗口残留/卡死打扰用户）
SetTimer Watchdog, -15000
Watchdog() {
    global resultFile
    try {
        if WinExist("设置 - " MENU_TITLE)
            WinClose("设置 - " MENU_TITLE)
        FileAppend "TIMEOUT 看门狗触发`n", resultFile
    }
    ExitApp 1   ; 超时按失败计（非零退出，聚合器/CI 可见）
}

failCount := 0
Check(cond, label) {
    global failCount, resultFile
    if cond
        FileAppend "PASS " label "`n", resultFile
    else {
        FileAppend "FAIL " label "`n", resultFile
        failCount++
    }
}

; 在窗口内按控件文字查找控件（返回 GuiControl 对象；找不到返回 ""）
FindCtrlByText(winHwnd, text) {
    for h in WinGetControlsHwnd("ahk_id " winHwnd) {
        ctrl := ""
        try ctrl := GuiCtrlFromHwnd(h)
        if !IsObject(ctrl)
            continue
        t := ""
        try t := ctrl.Text
        if t = text
            return ctrl
    }
    return ""
}

OpenSettings()
winHwnd := WinExist("设置 - " MENU_TITLE)
Check(winHwnd != 0, "设置窗口已创建")

; ---- 默认态：无待下载更新时按钮为「检查更新」----
; 注意：本文件顶层变量都是脚本级全局（与 src 内所有模块同处一个作用域），
; 命名必须避开 src 里的局部变量名（如 btn），否则触发 #Warn 的 LocalSameAsGlobal 告警
updBtnCtrl := FindCtrlByText(winHwnd, "检查更新")
Check(IsObject(updBtnCtrl), "「关于」页存在「检查更新」按钮")

if IsObject(updBtnCtrl) {
    ; ---- 发现新版本 → 按钮就地变下载入口（本次修复的核心行为）----
    SetPendingUpdate("9.9.9", "https://example.invalid/zestcaps_v9.9.9.exe", "")
    Check(HasPendingUpdate(), "登记待下载更新后 HasPendingUpdate 为真")
    RefreshUpdateButton(updBtnCtrl)
    Check(updBtnCtrl.Text = "下载并更新 v9.9.9", "按钮应就地变为「下载并更新 v9.9.9」(实际 [" updBtnCtrl.Text "])")

    ; ---- 清除待下载状态 → 回到「检查更新」----
    ClearPendingUpdate()
    RefreshUpdateButton(updBtnCtrl)
    Check(updBtnCtrl.Text = "检查更新", "清除待下载状态后按钮应回到「检查更新」(实际 [" updBtnCtrl.Text "])")
}

; 清理：关闭窗口，避免残留
if WinExist("设置 - " MENU_TITLE)
    WinClose("设置 - " MENU_TITLE)
Sleep 100

FileAppend "DONE failCount=" failCount "`n", resultFile
ExitApp failCount ? 1 : 0
