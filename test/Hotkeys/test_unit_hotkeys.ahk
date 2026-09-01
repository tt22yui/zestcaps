; ==================================================================
; 单元测试：Hotkeys 模块 —— 快捷键校验 / 冲突校验
; 覆盖纯函数：IsValidHotkey、ValidateHotkeyPair
; 单跑：AutoHotkey64 test\Hotkeys\test_unit_hotkeys.ahk
; 聚合：AutoHotkey64 test\run_all_tests.ahk
; 判定：失败数 > 0 时退出码非 0；详细结果见 junit_unit_hotkeys.xml 与 stdout
; ==================================================================
#Requires AutoHotkey v2.0
#SingleInstance Force
#ErrorStdOut
#Warn All, StdOut
; 追加 #Warn All, Off：单测进程未 include Clipboard/Screenshot/DebugLog，
; RegisterCustomHotkeys 引用的函数名被误报 UseUnsetLocal（跨模块误报，正式模块未屏蔽）
#Warn All, Off

#Include "..\lib\Yunit\Yunit.ahk"
#Include "..\lib\Yunit\Stdout.ahk"
#Include "..\lib\Yunit\JUnit.ahk"
#Include "..\..\src\Config\Config.ahk"
#Include "..\..\src\Hotkeys\Hotkeys.ahk"

class HotkeysUnitTest {
    test_当前配置热键有效() {
        Yunit.Assert(PastePlainKey != "" && ScreenshotKey != "", "当前热键不应为空")
        Yunit.Assert(IsValidHotkey(PastePlainKey), "PastePlainKey 应合法，实际: [" PastePlainKey "]")
        Yunit.Assert(IsValidHotkey(ScreenshotKey), "ScreenshotKey 应合法，实际: [" ScreenshotKey "]")
        Yunit.Assert(PastePlainKey != ScreenshotKey, "两功能热键不应相同")
    }

    test_IsValidHotkey合法键() {
        ; ^CapsLock 带修饰键，与裸 CapsLock 固定热键不冲突，属合法；
        ; < > 为左右侧修饰前缀（如 <^v 左Ctrl、>!a 右Alt、<^>! 即 AltGr），亦属合法
        for k in ["^v", "^+v", "F1", "F2", "^+F9", "!^+k", "~^v", "Space", "Enter", "#a", "vk56", "^CapsLock", "<^v", ">!a", "<^>!m"]
            Yunit.Assert(IsValidHotkey(k), "应为合法热键: [" k "]")
    }

    test_IsValidHotkey非法键() {
        ; 仅裸 CapsLock 被拒（保护固定热键）；带修饰的 ^CapsLock 合法；
        ; < > 必须位于修饰符之前（^<v 位置非法），单独 < / > 也不是可识别键
        for k in ["", "zzzz", "^zzzz", "^+", "CapsLock", "abc", "^<v", "<", ">"]
            Yunit.Assert(!IsValidHotkey(k), "应判为非法热键: [" k "]")
    }

    test_ValidateHotkeyPair通过() {
        Yunit.Assert(ValidateHotkeyPair("^v", "F1", "A", "B") = "", "合法且不冲突应通过")
    }

    test_ValidateHotkeyPair冲突() {
        Yunit.Assert(ValidateHotkeyPair("^v", "^v", "A", "B") != "", "相同热键应冲突")
        Yunit.Assert(ValidateHotkeyPair("CapsLock", "F1", "A", "B") != "", "CapsLock 应被拒绝")
        Yunit.Assert(ValidateHotkeyPair("F1", "CapsLock", "A", "B") != "", "CapsLock 应被拒绝")
        Yunit.Assert(ValidateHotkeyPair("zzzz", "F1", "A", "B") != "", "非法热键应被拒绝")
        Yunit.Assert(ValidateHotkeyPair("^v", "zzzz", "A", "B") != "", "非法热键应被拒绝")
    }
}

; ---- 运行入口（单跑或由 run_all_tests.ahk 调用）----
YunitJUnit.OutputFile := A_ScriptDir "\junit_unit_hotkeys.xml"
tester := Yunit.Use(YunitStdOut, YunitJUnit)
tester.Test(HotkeysUnitTest)
YunitJUnit.Last.WriteXml()   ; ExitApp 不触发 __Delete，需显式落盘 XML
ExitApp YunitJUnit.Last.tests.fail ? 1 : 0
