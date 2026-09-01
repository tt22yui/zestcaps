; ==================================================================
; 单元测试：Config 模块 —— 常量存在性、取值合理性、派生逻辑
; 单跑：AutoHotkey64 test\test_unit_config.ahk
; 聚合：AutoHotkey64 test\run_all_tests.ahk
; 判定：失败数 > 0 时退出码非 0；详细结果见 junit_unit_config.xml 与 stdout
; ==================================================================
#Requires AutoHotkey v2.0
#SingleInstance Force
#ErrorStdOut
#Warn All, StdOut

#Include "..\lib\Yunit\Yunit.ahk"
#Include "..\lib\Yunit\Stdout.ahk"
#Include "..\lib\Yunit\JUnit.ahk"
#Include "..\..\src\Config\Config.ahk"

class ConfigUnitTest {
    test_版本号格式() {
        Yunit.Assert(APP_VERSION != "", "APP_VERSION 不应为空")
        Yunit.Assert(RegExMatch(APP_VERSION, "^\d+(\.\d+)+$") > 0, "APP_VERSION 应为 x.y 格式，实际: [" APP_VERSION "]")
    }

    test_CapsLock参数合理() {
        Yunit.Assert(CAPS_SHORT_PRESS > 0 && CAPS_SHORT_PRESS < CAPS_RELEASE_TIMEOUT, "短按阈值应在 (0, 释放超时) 之间，实际: " CAPS_SHORT_PRESS)
        Yunit.Assert(CAPS_COOLDOWN_MS > 0, "冷却时间应 > 0")
        Yunit.Assert(CAPS_WATCHDOG_INTERVAL_MS > 0, "看门狗周期应 > 0")
    }

    test_闪屏派生时长计算() {
        Yunit.Assert(SPLASH_FADE_MS = Max(50, Ceil(SPLASH_DURATION_MS / 8)), "SPLASH_FADE_MS 派生错误: " SPLASH_FADE_MS)
        Yunit.Assert(SPLASH_SEG_MS = Ceil(SPLASH_CYCLE_MS / 4), "SPLASH_SEG_MS 派生错误: " SPLASH_SEG_MS)
    }

    test_截图参数合理() {
        Yunit.Assert(MIN_SEL_SIZE > 0, "MIN_SEL_SIZE 应 > 0")
        Yunit.Assert(SCREENSHOT_TIMEOUT_MS >= 1000, "截图超时应 >= 1000ms")
        Yunit.Assert(EDIT_LINE_WIDTHS.Length > 0, "线宽档位数组不应为空")
    }

    test_功能开关为0或1() {
        Yunit.Assert(IndicatorEnabled = 0 || IndicatorEnabled = 1, "IndicatorEnabled 应为 0/1")
        Yunit.Assert(PastePlainEnabled = 0 || PastePlainEnabled = 1, "PastePlainEnabled 应为 0/1")
        Yunit.Assert(StartupEnabled = 0 || StartupEnabled = 1, "StartupEnabled 应为 0/1")
    }
}

; ---- 运行入口（单跑或由 run_all_tests.ahk 调用）----
YunitJUnit.OutputFile := A_ScriptDir "\junit_unit_config.xml"
tester := Yunit.Use(YunitStdOut, YunitJUnit)
tester.Test(ConfigUnitTest)
YunitJUnit.Last.WriteXml()   ; ExitApp 不触发 __Delete，需显式落盘 XML
ExitApp YunitJUnit.Last.tests.fail ? 1 : 0
