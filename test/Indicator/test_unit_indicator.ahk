; ==================================================================
; 单元测试：Indicator 纯逻辑 —— 标签/配色选择 + Map 淘汰（Visual.ahk）
; 单跑：AutoHotkey64 test\Indicator\test_unit_indicator.ahk
; 聚合：AutoHotkey64 test\run_all_tests.ahk
; ==================================================================
#Requires AutoHotkey v2.0
#SingleInstance Force
#ErrorStdOut
#Warn All, StdOut

#Include "..\lib\Yunit\Yunit.ahk"
#Include "..\lib\Yunit\Stdout.ahk"
#Include "..\lib\Yunit\JUnit.ahk"
#Include "..\..\src\Config\Config.ahk"
#Include "..\..\src\Indicator\Visual.ahk"

class IndicatorUnitTest {
    test_CapsLock优先于中英状态() {
        v := IndicatorVisual(true, true)
        Yunit.Assert(v.label = IND_TEXT_A, "CapsLock 开启应显示 A，实际 [" v.label "]")
        Yunit.Assert(v.bg = IND_BG_A, "CapsLock 开启应用 A 背景")
        Yunit.Assert(v.txt = IND_COLOR_A, "CapsLock 开启应用 A 文字色")
    }

    test_中文与英文配色() {
        cn := IndicatorVisual(false, true)
        Yunit.Assert(cn.label = IND_TEXT_CN && cn.bg = IND_BG_CN && cn.txt = IND_COLOR_CN, "中文应选中/配色")
        en := IndicatorVisual(false, false)
        Yunit.Assert(en.label = IND_TEXT_EN && en.bg = IND_BG_EN && en.txt = IND_COLOR_EN, "英文应选英/配色")
    }
}

YunitJUnit.OutputFile := A_ScriptDir "\junit_unit_indicator.xml"
tester := Yunit.Use(YunitStdOut, YunitJUnit)
tester.Test(IndicatorUnitTest)
YunitJUnit.Last.WriteXml()   ; ExitApp 不触发 __Delete，必须显式落盘
ExitApp YunitJUnit.Last.tests.fail ? 1 : 0
