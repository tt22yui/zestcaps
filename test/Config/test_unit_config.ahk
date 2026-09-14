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
; Config.ahk 创建 config.ini 的兜底分支会调用 DebugLog；不加载 DebugLog.ahk 的话
; 该名字会被静态分析当成「从未赋值的全局变量」并告警（跨模块误报，正式运行经 Main.ahk 加载无此问题）
DEBUG_LOG_ENABLED := false
#Include "..\..\src\DebugLog\DebugLog.ahk"

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

    test_数字文本归一化() {
        ; 中文输入法下很容易把全角数字打进设置窗口：全角既不是数字类型、正则 \d 也不匹配，
        ; 不归一化会误报「清空时刻格式错误」（用户实测反馈）
        Yunit.Assert(!IsIntText("０９"), "前提：全角数字不是合法整数文本（误报根源之一）")
        Yunit.Assert(NormalizeDigits("０９：００") = "09:00", "全角数字与全角冒号应转半角")
        Yunit.Assert(NormalizeDigits("０９") = "09", "全角数字应转半角")
        Yunit.Assert(NormalizeDigits(" 9 ") = "9", "应去首尾空白")
        Yunit.Assert(NormalizeDigits("12:00") = "12:00", "半角内容应原样返回")
        Yunit.Assert(NormalizeDigits("") = "", "空串仍为空串")
        Yunit.Assert(NormalizeDigits("abc") = "abc", "非数字内容原样返回")
    }

    test_整数文本判定() {
        ; ⚠️ 不能用内置 IsNumber 判断字符串：Gdip 库同名函数会覆盖它（见 test_unit_settings.ahk）
        Yunit.Assert(IsIntText("09"), "数字字符串应判为整数文本")
        Yunit.Assert(IsIntText(" 30 "), "含空白应判为整数文本")
        Yunit.Assert(IsIntText("-1"), "负号应被接受")
        Yunit.Assert(!IsIntText(""), "空串不是整数文本")
        Yunit.Assert(!IsIntText("abc"), "非数字不是整数文本")
        Yunit.Assert(!IsIntText("1.5"), "小数不是整数文本")
        Yunit.Assert(!IsIntText("０９"), "全角数字不是整数文本（需先归一化）")
    }

    test_时刻规范化() {
        Yunit.Assert(NormalizeClockTime("9:05", "12:00") = "09:05", "未补零应补零")
        Yunit.Assert(NormalizeClockTime("０９：００", "12:00") = "09:00", "全角应归一化后再解析")
        Yunit.Assert(NormalizeClockTime("23:59", "12:00") = "23:59", "范围内应保留")
        Yunit.Assert(NormalizeClockTime("24:00", "12:00") = "12:00", "超范围应回退默认")
        Yunit.Assert(NormalizeClockTime("99:99", "12:00") = "12:00", "非法应回退默认")
        Yunit.Assert(NormalizeClockTime("abc", "12:00") = "12:00", "非数字应回退默认")
        Yunit.Assert(NormalizeClockTime("", "12:00") = "12:00", "空值应回退默认")
    }
}

; ---- 运行入口（单跑或由 run_all_tests.ahk 调用）----
YunitJUnit.OutputFile := A_ScriptDir "\junit_unit_config.xml"
tester := Yunit.Use(YunitStdOut, YunitJUnit)
tester.Test(ConfigUnitTest)
YunitJUnit.Last.WriteXml()   ; ExitApp 不触发 __Delete，需显式落盘 XML
ExitApp YunitJUnit.Last.tests.fail ? 1 : 0
