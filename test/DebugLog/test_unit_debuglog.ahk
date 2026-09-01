; ==================================================================
; 单元测试：DebugLog 模块 —— 禁用不写、启用写入格式正确
; 单跑：AutoHotkey64 test\test_unit_debuglog.ahk
; 聚合：AutoHotkey64 test\run_all_tests.ahk
; 说明：测试期间将 DEBUG_LOG_FILE 指向临时文件，结束恢复原值，不污染真实日志。
; ==================================================================
#Requires AutoHotkey v2.0
#SingleInstance Force
#ErrorStdOut
#Warn All, StdOut

#Include "..\lib\Yunit\Yunit.ahk"
#Include "..\lib\Yunit\Stdout.ahk"
#Include "..\lib\Yunit\JUnit.ahk"
#Include "..\..\src\Config\Config.ahk"
#Include "..\..\src\DebugLog\DebugLog.ahk"

class DebugLogUnitTest {
    Begin() {
        global DEBUG_LOG_ENABLED, DEBUG_LOG_FILE
        this._origEnabled := DEBUG_LOG_ENABLED
        this._origFile := DEBUG_LOG_FILE
        this._tmpLog := A_Temp "\_tmp_unit_debuglog.log"
        if FileExist(this._tmpLog)
            try FileDelete(this._tmpLog)
        if FileExist(this._tmpLog ".old")
            try FileDelete(this._tmpLog ".old")
    }
    End() {
        global DEBUG_LOG_ENABLED, DEBUG_LOG_FILE
        DEBUG_LOG_ENABLED := this._origEnabled
        DEBUG_LOG_FILE := this._origFile
        if FileExist(this._tmpLog)
            try FileDelete(this._tmpLog)
        if FileExist(this._tmpLog ".old")
            try FileDelete(this._tmpLog ".old")
    }

    test_禁用时不写入() {
        global DEBUG_LOG_ENABLED, DEBUG_LOG_FILE
        DEBUG_LOG_ENABLED := false
        DEBUG_LOG_FILE := this._tmpLog
        DebugLog("不应写入的内容")
        Yunit.Assert(!FileExist(this._tmpLog), "禁用状态下不应创建日志文件")
    }

    test_启用时写入消息与时间戳格式() {
        global DEBUG_LOG_ENABLED, DEBUG_LOG_FILE
        DEBUG_LOG_ENABLED := true
        DEBUG_LOG_FILE := this._tmpLog
        DebugLog("hello 单测")
        Yunit.Assert(FileExist(this._tmpLog), "启用状态下应创建日志文件")
        content := FileRead(this._tmpLog)
        Yunit.Assert(InStr(content, "hello 单测") > 0, "日志应包含消息内容，实际: [" content "]")
        Yunit.Assert(RegExMatch(content, "^\s*\[\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{3}\]") > 0, "日志应以 [yyyy-MM-dd HH:mm:ss.mmm] 开头，实际: [" content "]")
    }
}

; ---- 运行入口 ----
YunitJUnit.OutputFile := A_ScriptDir "\junit_unit_debuglog.xml"
tester := Yunit.Use(YunitStdOut, YunitJUnit)
tester.Test(DebugLogUnitTest)
YunitJUnit.Last.WriteXml()   ; ExitApp 不触发 __Delete，需显式落盘 XML
ExitApp YunitJUnit.Last.tests.fail ? 1 : 0
