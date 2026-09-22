; ==================================================================
; 单元测试：IME 纯逻辑 —— 中文布局判定（IsChineseLayout）
; 单跑：AutoHotkey64 test\Indicator\test_unit_ime.ahk
; 聚合：AutoHotkey64 test\run_all_tests.ahk
; ==================================================================
#Requires AutoHotkey v2.0
#SingleInstance Force
#ErrorStdOut
#Warn All, StdOut

#Include "..\lib\Yunit\Yunit.ahk"
#Include "..\lib\Yunit\Stdout.ahk"
#Include "..\lib\Yunit\JUnit.ahk"
#Include "..\..\src\Indicator\IME.ahk"

class IMEUnitTest {
    test_中文布局判定为真() {
        Yunit.Assert(IsChineseLayout(0x0804), "zh-CN(0x0804) 应判为中文")
        Yunit.Assert(IsChineseLayout(0x0404), "zh-TW(0x0404) 应判为中文")
        Yunit.Assert(IsChineseLayout(0x0C04), "zh-HK(0x0C04) 应判为中文")
        Yunit.Assert(IsChineseLayout(0x1004), "zh-SG(0x1004) 应判为中文")
    }

    test_非中文布局判定为假() {
        Yunit.Assert(!IsChineseLayout(0x0409), "en-US(0x0409) 非中文")
        Yunit.Assert(!IsChineseLayout(0x0411), "ja-JP(0x0411) 非中文")
        Yunit.Assert(!IsChineseLayout(0x0412), "ko-KR(0x0412) 非中文")
        Yunit.Assert(!IsChineseLayout(0), "0 非中文")
    }

    test_跟踪Map超限淘汰最早记录() {
        global IME_WindowStates, IME_SawChinese
        IME_WindowStates := Map()
        IME_SawChinese := Map()
        loop 5 {
            IME_WindowStates["p" A_Index] := true
            if (A_Index = 1)
                IME_SawChinese["p1"] := true   ; 仅 p1 有锁存，验证同步裁剪
        }
        IMETrimWindowStates(3)
        Yunit.Assert(IME_WindowStates.Count = 4, "每调用一次只淘汰一条（5→4），实际 " IME_WindowStates.Count)
        while (IME_WindowStates.Count > 3)
            IMETrimWindowStates(3)
        Yunit.Assert(!IME_WindowStates.Has("p1") && !IME_WindowStates.Has("p2"), "最早插入的 p1/p2 应被淘汰")
        Yunit.Assert(IME_WindowStates.Has("p5"), "最新的 p5 应保留")
        Yunit.Assert(!IME_SawChinese.Has("p1"), "SawChinese 应同步裁剪 p1")
    }
}

YunitJUnit.OutputFile := A_ScriptDir "\junit_unit_ime.xml"
tester := Yunit.Use(YunitStdOut, YunitJUnit)
tester.Test(IMEUnitTest)
YunitJUnit.Last.WriteXml()   ; ExitApp 不触发 __Delete，必须显式落盘
ExitApp YunitJUnit.Last.tests.fail ? 1 : 0
