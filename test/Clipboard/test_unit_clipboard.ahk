; ==================================================================
; 单元测试：Clipboard 模块 —— 纯文本清洗
; 覆盖纯函数：PlainTextClean（PastePlain.ahk）
; 单跑：AutoHotkey64 test\Clipboard\test_unit_clipboard.ahk
; 聚合：AutoHotkey64 test\run_all_tests.ahk
; 判定：失败数 > 0 时退出码非 0；详细结果见 junit_unit_clipboard.xml 与 stdout
; ==================================================================
#Requires AutoHotkey v2.0
#SingleInstance Force
#ErrorStdOut
#Warn All, StdOut
; 追加 #Warn All, Off：单测只 include Clipboard 链，未 include DebugLog，
; PastePlain 内引用的函数名会被误报 UseUnsetLocal（跨模块误报，正式运行不含此问题）
#Warn All, Off

#Include "..\lib\Yunit\Yunit.ahk"
#Include "..\lib\Yunit\Stdout.ahk"
#Include "..\lib\Yunit\JUnit.ahk"
#Include "..\..\src\Clipboard\Clipboard.ahk"

class ClipboardUnitTest {
    test_去首尾空白() {
        Yunit.Assert(PlainTextClean("  hello  ") = "hello", "首尾空格应被去除")
        Yunit.Assert(PlainTextClean("`thello`t") = "hello", "首尾制表符应被去除")
        Yunit.Assert(PlainTextClean("`r`n  hi  `r`n") = "hi", "首尾换行应被去除")
        Yunit.Assert(PlainTextClean(" `t`r`n hello `n`r`t ") = "hello", "混合空白应被去除")
    }

    test_保留内部空白() {
        Yunit.Assert(PlainTextClean("  a b  ") = "a b", "内部空格应保留")
        Yunit.Assert(PlainTextClean("a`r`nb") = "a`r`nb", "内部换行应保留")
        Yunit.Assert(PlainTextClean("`ta`tb`t") = "a`tb", "内部制表符应保留")
    }

    test_边界输入() {
        Yunit.Assert(PlainTextClean("") = "", "空串应仍为空串")
        Yunit.Assert(PlainTextClean("   ") = "", "全空格应被清成空串")
        Yunit.Assert(PlainTextClean("`t`r`n ") = "", "全空白应被清成空串")
        Yunit.Assert(PlainTextClean("x") = "x", "单字符应原样返回")
    }

    test_不改变非字符串内容语义() {
        ; 清洗只做首尾裁剪：数字/符号/中文内容不得被改写
        Yunit.Assert(PlainTextClean("  中文 测试 ") = "中文 测试", "中文与内部空格应保留")
        Yunit.Assert(PlainTextClean(" 123 ") = "123", "数字串应保留")
        Yunit.Assert(PlainTextClean(" a=b;c ") = "a=b;c", "符号应保留")
    }
}

; ---- 运行入口（单跑或由 run_all_tests.ahk 调用）----
YunitJUnit.OutputFile := A_ScriptDir "\junit_unit_clipboard.xml"
tester := Yunit.Use(YunitStdOut, YunitJUnit)
tester.Test(ClipboardUnitTest)
YunitJUnit.Last.WriteXml()   ; ExitApp 不触发 __Delete，需显式落盘 XML
ExitApp YunitJUnit.Last.tests.fail ? 1 : 0
