#Requires AutoHotkey v2.0
#SingleInstance Force
#ErrorStdOut
#Warn All, Off
; 设置模块加载测试：验证 Settings.ahk 加载无错误、关键函数可调用
#Include "..\..\src\Config\Config.ahk"
#Include "..\..\src\Settings\Settings.ahk"

testFile := A_Temp "\_tmp_settings_load_test.txt"
try FileDelete(testFile)

; 验证关键函数均已定义（OpenSettings / SaveSettings / CloseSettings）
try {
    ok := IsSet(OpenSettings) && IsSet(SaveSettings) && IsSet(CloseSettings)
    FileAppend (ok ? "OK: Settings 模块加载成功，函数齐全`n" : "FAIL: 函数缺失`n"), testFile
} catch as err {
    FileAppend "FAIL: " err.Message " @" err.Line "`n", testFile
}

; 验证 Tab3 页签切换语法（复现 OpenSettings 的页签构建，不 Show 窗口）
; 回归目标：曾用 settingsGui.Add("Tab3", "UseTab:2") 抛 Invalid option
try {
    g := Gui()
    tabCtl := g.Add("Tab3", "x14 y12 w350 h220", ["通用", "指示器", "剪贴板", "截图"])
    g.Add("CheckBox", "x44 y58", "通用页控件")
    tabCtl.UseTab(2)
    g.Add("CheckBox", "x44 y58", "指示器页控件")
    tabCtl.UseTab(3)
    g.Add("CheckBox", "x44 y58", "剪贴板页控件")
    tabCtl.UseTab(4)
    g.Add("CheckBox", "x44 y40", "截图页控件")
    tabCtl.UseTab()
    g.Add("Button", "x198 y242", "页签外按钮")
    g.Destroy()
    FileAppend "OK: Tab3 页签构建 + UseTab 切换语法正常`n", testFile
} catch as err {
    FileAppend "FAIL: Tab3 页签构建异常 - " err.Message " @" err.Line "`n", testFile
}

; 验证 A_IconHidden 内置变量可用（重启前隐藏托盘图标，避免 Reload 后幽灵图标残留）
try {
    A_IconHidden := true
    ok := A_IconHidden
    A_IconHidden := false
    FileAppend (ok ? "OK: A_IconHidden 可用`n" : "FAIL: A_IconHidden 赋值无效`n"), testFile
} catch as err {
    FileAppend "FAIL: A_IconHidden 异常 - " err.Message " @" err.Line "`n", testFile
}

ExitApp()
