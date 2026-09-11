; ==================================================================
; 单元测试：RecycleBin 模块 —— 清理判定纯函数
; 覆盖：RecycleBinShouldDelete（保留期比较 + 异常输入的安全兜底）
; 单跑：AutoHotkey64 test\RecycleBin\test_unit_recyclebin.ahk
; 聚合：AutoHotkey64 test\run_all_tests.ahk
; 判定：失败数 > 0 时退出码非 0；详细结果见 junit_unit_recyclebin.xml 与 stdout
; 说明：本模块是唯一会「永久删除用户文件」的模块，故单测重点覆盖"拿不准一律保留"的安全边界：
;       keepDays<=0、时间戳缺失/格式非法、恰好等于阈值，都必须判为不清理。
;       测试只调用纯函数，不接触真实回收站（不会删任何文件）。
; ==================================================================
#Requires AutoHotkey v2.0
#SingleInstance Force
#ErrorStdOut
#Warn All, StdOut

#Include "..\lib\Yunit\Yunit.ahk"
#Include "..\lib\Yunit\Stdout.ahk"
#Include "..\lib\Yunit\JUnit.ahk"

; RecycleBin.ahk 顶层会读这三个全局（InitRecycleBinTimer）并声明它们；
; 先给最小占位值，保证 RecycleBinEnabled=false（不注册定时器）且无 UseUnsetGlobal 告警
RecycleBinEnabled := false
RBKeepDays := 30
RBTime := "12:00"
; RecycleBinCleanup 会调用 DebugLog：不加载 DebugLog.ahk 会被静态分析当成
; 「从未赋值的全局变量」并告警（跨模块误报）；此处关日志并给出最小占位全局
DEBUG_LOG_ENABLED := false
DEBUG_LOG_FILE := ""
DEBUG_LOG_MAX_SIZE_KB := 800
#Include "..\..\src\DebugLog\DebugLog.ahk"
#Include "..\..\src\RecycleBin\RecycleBin.ahk"

class RecycleBinUnitTest {
    ; -------- 绝对时间戳（不依赖当前时钟，判定结果确定）--------
    test_超过保留期应清理() {
        ; now=2026-09-10 12:00:00，保留 30 天 → 阈值 2026-08-11 12:00:00
        now := "20260910120000"
        Yunit.Assert(RecycleBinShouldDelete("20260801120000", 30, now), "31 天前应清理")
        Yunit.Assert(RecycleBinShouldDelete("20260701120000", 30, now), "更早的项应清理")
        Yunit.Assert(RecycleBinShouldDelete("20260811115959", 30, now), "阈值前 1 秒应清理")
    }

    test_保留期内不清理() {
        now := "20260910120000"
        Yunit.Assert(!RecycleBinShouldDelete("20260909120000", 30, now), "1 天前不应清理")
        Yunit.Assert(!RecycleBinShouldDelete("20260811120001", 30, now), "阈值后 1 秒不应清理")
        Yunit.Assert(!RecycleBinShouldDelete("20260910120000", 30, now), "刚删除的项不应清理")
    }

    test_恰好等于阈值不清理() {
        ; 边界：删除时间正好等于「now - keepDays」（同一天同一时刻）→ 保留
        now := "20260910120000"
        cut := DateAdd(now, -30, "Days")
        Yunit.Assert(cut = "20260811120000", "阈值计算应为 20260811120000，实际: [" cut "]")
        Yunit.Assert(!RecycleBinShouldDelete(cut, 30, now), "恰好等于阈值应保留")
    }

    ; -------- 安全兜底（拿不准一律保留）--------
    test_保留天数非正数不清理() {
        now := "20260910120000"
        for days in [0, -1, -30]
            Yunit.Assert(!RecycleBinShouldDelete("20000101000000", days, now), "keepDays=" days " 不应清理任何项")
    }

    test_时间戳缺失或非法不清理() {
        now := "20260910120000"
        ; 缺失（$I 读不到）、空串、长度不对、含非数字、ISO 格式等一律保留
        for bad in ["", "   ", "20260801", "2026080112000", "202608011200001", "2026-08-01 12:00:00", "abcdefghijklmn", "2026080112000a"] {
            Yunit.Assert(!RecycleBinShouldDelete(bad, 30, now), "非法时间戳 [" bad "] 不应触发删除")
        }
    }

    ; -------- 与真实时钟一致的相对用例（覆盖 DateAdd/A_Now 路径）--------
    test_相对当前时间判定() {
        now := A_Now
        Yunit.Assert(RecycleBinShouldDelete(DateAdd(now, -31, "Days"), 30, now), "31 天前应清理")
        Yunit.Assert(!RecycleBinShouldDelete(DateAdd(now, -1, "Days"), 30, now), "1 天前不应清理")
        Yunit.Assert(!RecycleBinShouldDelete(DateAdd(now, -30, "Days"), 30, now), "恰好 30 天应保留")
        ; 保留 7 天档位（设置页可选 7/15/30）
        Yunit.Assert(RecycleBinShouldDelete(DateAdd(now, -8, "Days"), 7, now), "保留 7 天时 8 天前应清理")
        Yunit.Assert(!RecycleBinShouldDelete(DateAdd(now, -7, "Days"), 7, now), "保留 7 天时 7 天前应保留")
    }
}

; ---- 运行入口（单跑或由 run_all_tests.ahk 调用）----
YunitJUnit.OutputFile := A_ScriptDir "\junit_unit_recyclebin.xml"
tester := Yunit.Use(YunitStdOut, YunitJUnit)
tester.Test(RecycleBinUnitTest)
YunitJUnit.Last.WriteXml()   ; ExitApp 不触发 __Delete，需显式落盘 XML
ExitApp YunitJUnit.Last.tests.fail ? 1 : 0
