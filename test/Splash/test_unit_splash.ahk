; ==================================================================
; 单元测试：Splash 淡入淡出透明度分段（_SplashAlpha 纯函数）
; 单跑：AutoHotkey64 test\Splash\test_unit_splash.ahk
; 聚合：AutoHotkey64 test\run_all_tests.ahk
; 说明：SplashEnabled 置 false 后加载 Splash.ahk，不创建闪屏窗口，仅取纯函数
; ==================================================================
#Requires AutoHotkey v2.0
#SingleInstance Force
#ErrorStdOut
#Warn All, StdOut

#Include "..\lib\Yunit\Yunit.ahk"
#Include "..\lib\Yunit\Stdout.ahk"
#Include "..\lib\Yunit\JUnit.ahk"
#Include "..\..\src\Config\Config.ahk"
SplashEnabled := false   ; 覆盖 Config 读取值：跳过闪屏窗口创建
#Include "..\..\src\Splash\Splash.ahk"

AlphaAt(elapsed) {
    a := 0
    _SplashAlpha(elapsed, &a)
    return a
}

class SplashUnitTest {
    test_起止透明度为0() {
        Yunit.Assert(AlphaAt(0) = 0, "起点应全透明，实际 " AlphaAt(0))
        Yunit.Assert(AlphaAt(SPLASH_DURATION_MS) = 0, "终点应全透明，实际 " AlphaAt(SPLASH_DURATION_MS))
    }

    test_中部为不透明() {
        Yunit.Assert(AlphaAt(SPLASH_FADE_MS) = 255, "淡入结束应为不透明，实际 " AlphaAt(SPLASH_FADE_MS))
        Yunit.Assert(AlphaAt(SPLASH_DURATION_MS // 2) = 255, "中段应为不透明，实际 " AlphaAt(SPLASH_DURATION_MS // 2))
    }

    test_淡出末端趋零且始终在0到255() {
        endAlpha := AlphaAt(SPLASH_DURATION_MS - SPLASH_FADE_MS // 2)
        Yunit.Assert(endAlpha > 0 && endAlpha < 255, "淡出半程应为中间透明度，实际 " endAlpha)
        for e in [-1000, 0, SPLASH_FADE_MS // 2, SPLASH_DURATION_MS // 2, SPLASH_DURATION_MS, SPLASH_DURATION_MS + 1000] {
            a := AlphaAt(e)
            Yunit.Assert(a >= 0 && a <= 255, "透明度须钳在 [0,255]（elapsed=" e " → " a "）")
        }
    }
}

YunitJUnit.OutputFile := A_ScriptDir "\junit_unit_splash.xml"
tester := Yunit.Use(YunitStdOut, YunitJUnit)
tester.Test(SplashUnitTest)
YunitJUnit.Last.WriteXml()   ; ExitApp 不触发 __Delete，必须显式落盘
ExitApp YunitJUnit.Last.tests.fail ? 1 : 0
