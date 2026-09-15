; ==================================================================
; 单元测试：Settings 模块 —— 时刻解析与回收站参数校验
; 覆盖：BuildClockTime（纯函数）、ValidateRecycleBin、IniReadInt（整数配置读取）
;
; 重点回归（本文件的 include 特意包含 Gdip）：
;   src\Common\Gdip_All_v2.ahk 曾自定义 IsNumber/IsInteger 并**覆盖 AHK 内置同名函数**
;   （只认数字类型、不认 "09" 这类数字字符串），曾导致两个真实故障：
;     1) 设置窗口点「保存并重启」总是报「清空时刻格式错误」（ReadRBTime 用 IsNumber 判断控件文本）；
;     2) ini 里的整数配置被静默替换成默认值（IniReadInt 同样用了 IsNumber）。
;   现库内已改用 Gdip_IsNumber/Gdip_IsInteger 前缀，不再覆盖内置；本测试在真实环境（含 Gdip）下
;   验证：① 内置 IsNumber 已恢复原语义；② 上述两处逻辑统一走 IsIntText 判定。
;
; 单跑：AutoHotkey64 test\Settings\test_unit_settings.ahk
; 聚合：AutoHotkey64 test\run_all_tests.ahk
; 判定：失败数 > 0 时退出码非 0；详细结果见 junit_unit_settings.xml 与 stdout
; ==================================================================
#Requires AutoHotkey v2.0
#SingleInstance Force
#ErrorStdOut
#Warn All, StdOut

#Include "..\lib\Yunit\Yunit.ahk"
#Include "..\lib\Yunit\Stdout.ahk"
#Include "..\lib\Yunit\JUnit.ahk"
#Include "..\..\src\Config\Config.ahk"
DEBUG_LOG_ENABLED := false     ; 屏蔽日志写入
#Include "..\..\src\DebugLog\DebugLog.ahk"
#Include "..\..\src\Startup\Startup.ahk"
#Include "..\..\src\DesktopShortcut\DesktopShortcut.ahk"
#Include "..\..\src\Hotkeys\Hotkeys.ahk"
#Include "..\..\src\Updater\Updater.ahk"
; 按 Main.ahk 的真实顺序补齐 Clipboard / Screenshot（Gdip 由 Screenshot 链式引入）：
; 一是让本测试运行在真实环境（含 Gdip 库），
; 二是避免 Hotkeys.ahk 里对 PastePlain/SelectRegionToCapture 的跨模块误报告警
#Include "..\..\src\Clipboard\Clipboard.ahk"
#Include "..\..\src\Screenshot\Screenshot.ahk"
#Include "..\..\src\Common\Gdip_All_v2.ahk"   ; 显式引入 Gdip（验证它不再覆盖内置 IsNumber/IsInteger）
#Include "..\..\src\Settings\Settings.ahk"

class SettingsUnitTest {
    test_Gdip不再覆盖内置数字判断() {
        ; 回归：Gdip 库改用 Gdip_ 前缀后，AHK 内置 IsNumber/IsInteger 应恢复原始语义
        Yunit.Assert(IsNumber(9), "内置 IsNumber 应接受数字类型")
        Yunit.Assert(IsNumber("09"), "内置 IsNumber 应接受数字字符串（不再被 Gdip 覆盖）")
        Yunit.Assert(IsIntText("09"), "IsIntText（正则实现）应接受数字字符串")
        Yunit.Assert(!IsIntText("０９"), "IsIntText 不接受全角数字（需 NormalizeDigits 先行归一化）")
    }

    test_时刻拼接() {
        Yunit.Assert(BuildClockTime("09", "00") = "09:00", "常规两位数字")
        Yunit.Assert(BuildClockTime("9", "5") = "09:05", "单位数应补零")
        Yunit.Assert(BuildClockTime("０９", "００") = "09:00", "全角数字应归一化")
        Yunit.Assert(BuildClockTime(" 9 ", " 0 ") = "09:00", "含空白应归一化")
        Yunit.Assert(BuildClockTime("", "") = "", "留空返回空串（交由校验报错并提示读到什么）")
        Yunit.Assert(BuildClockTime("abc", "1") = "", "非数字返回空串")
        Yunit.Assert(BuildClockTime("24", "00") = "24:00", "范围检查不在此函数（由 ValidateRecycleBin 负责）")
    }

    test_回收站参数校验() {
        Yunit.Assert(ValidateRecycleBin("30", "09:00") = "", "合法参数应通过")
        Yunit.Assert(ValidateRecycleBin("30", "23:59") = "", "边界值应通过")
        Yunit.Assert(ValidateRecycleBin("30", "9:05") = "", "1-2 位小时可接受（控件实际始终补零）")
        Yunit.Assert(ValidateRecycleBin("30", "24:00") != "", "小时超范围应被拦")
        Yunit.Assert(ValidateRecycleBin("30", "09:60") != "", "分钟超范围应被拦")
        Yunit.Assert(ValidateRecycleBin("30", "") != "", "空时刻应被拦")
        Yunit.Assert(ValidateRecycleBin("30", "abc") != "", "非数字时刻应被拦")
        Yunit.Assert(ValidateRecycleBin("abc", "09:00") != "", "非数字保留天数应被拦")
        Yunit.Assert(ValidateRecycleBin("0", "09:00") != "", "保留天数至少为 1")
    }

    test_整数配置读取() {
        ; 回归：IniReadInt 曾用 IsNumber 判断 ini 中的数字字符串 → 真实环境恒假 → 静默回退默认值
        f := A_Temp "\_tmp_unit_settings_ini.txt"
        if FileExist(f)
            try FileDelete(f)
        IniWrite "7", f, "RecycleBin", "KeepDays"
        IniWrite "abc", f, "RecycleBin", "Bad"
        Yunit.Assert(IniReadInt(f, "RecycleBin", "KeepDays", 30) = 7, "应读到 ini 里的 7（而不是回退默认 30）")
        Yunit.Assert(IniReadInt(f, "RecycleBin", "Bad", 30) = 30, "非数字应回退默认值")
        Yunit.Assert(IniReadInt(f, "RecycleBin", "Missing", 15) = 15, "缺失应回退默认值")
        if FileExist(f)
            try FileDelete(f)
    }
}

; ---- 运行入口（单跑或由 run_all_tests.ahk 调用）----
YunitJUnit.OutputFile := A_ScriptDir "\junit_unit_settings.xml"
tester := Yunit.Use(YunitStdOut, YunitJUnit)
tester.Test(SettingsUnitTest)
YunitJUnit.Last.WriteXml()   ; ExitApp 不触发 __Delete，需显式落盘 XML
ExitApp YunitJUnit.Last.tests.fail ? 1 : 0
