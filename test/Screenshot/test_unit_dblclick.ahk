; ==================================================================
; 单元测试：截图选区双击判定 —— _IsSelectionDoubleClick / _ResetSelectionDoubleClick
; 覆盖：连续按下的双击判定语义、跨会话复位（回归：static 状态跨会话保留会把
;       上一次截图结束时的按下当成新会话的双击 → 首次单击平移被误判为「双击→直接复制」）
; 单跑：AutoHotkey64 test\Screenshot\test_unit_dblclick.ahk
; 聚合：AutoHotkey64 test\run_all_tests.ahk
; 判定：失败数 > 0 时退出码非 0；详细结果见 junit_unit_dblclick.xml 与 stdout
; 说明：本测试只调用纯判定函数，不创建任何窗口（无需看门狗）；
;       include 链与 Main.ahk 一致（Config → DebugLog → Screenshot），并屏蔽日志写入
; ==================================================================
#Requires AutoHotkey v2.0
#SingleInstance Force
#ErrorStdOut
#Warn All, StdOut

#Include "..\lib\Yunit\Yunit.ahk"
#Include "..\lib\Yunit\Stdout.ahk"
#Include "..\lib\Yunit\JUnit.ahk"
#Include "..\..\src\Config\Config.ahk"
DEBUG_LOG_ENABLED := false     ; 屏蔽日志写入，避免污染正式日志
#Include "..\..\src\DebugLog\DebugLog.ahk"
#Include "..\..\src\Screenshot\Screenshot.ahk"

class DblClickUnitTest {
    test_首按不判双击_次按判双击() {
        _ResetSelectionDoubleClick()
        Yunit.Assert(_IsSelectionDoubleClick(100, 100) = false, "首按必须返回 false")
        Yunit.Assert(_IsSelectionDoubleClick(100, 100) = true, "紧随其后的同一位置按下应判为双击")
    }

    test_复位后不继承上一会话() {
        ; 回归：上一次截图会话末尾的按下会被 static 记住（时间 + 坐标），
        ; 新会话进入微调时若不复位，首次单击平移会被误判为双击
        _ResetSelectionDoubleClick()
        Yunit.Assert(_IsSelectionDoubleClick(300, 300) = false, "首按返回 false 并记录状态")
        _ResetSelectionDoubleClick()   ; 模拟新会话开始（SelectRegion 进入微调前调用）
        Yunit.Assert(_IsSelectionDoubleClick(300, 300) = false, "复位后同点按下不得判为双击")
        Yunit.Assert(_IsSelectionDoubleClick(300, 300) = true, "复位后连续两次按下才判双击")
    }

    test_超出双击时间不判双击() {
        _ResetSelectionDoubleClick()
        _IsSelectionDoubleClick(500, 500)
        Sleep DllCall("GetDoubleClickTime") + 120   ; 超过系统双击时间（默认 500ms）
        Yunit.Assert(_IsSelectionDoubleClick(500, 500) = false, "超时不应判为双击")
    }

    test_超出位移容差不判双击() {
        _ResetSelectionDoubleClick()
        _IsSelectionDoubleClick(500, 500)
        ; 位移远大于 SM_CXDOUBLECLK（默认 4px）→ 即使紧跟也不判双击
        Yunit.Assert(_IsSelectionDoubleClick(700, 500) = false, "超距不应判为双击")
    }

    test_容差内小位移仍判双击() {
        _ResetSelectionDoubleClick()
        _IsSelectionDoubleClick(500, 500)
        ; 1px 抖动在系统双击容差内 → 仍应判为双击（宽容抖动）
        Yunit.Assert(_IsSelectionDoubleClick(501, 500) = true, "容差内小位移应仍判为双击")
    }
}

; ---- 运行入口（单跑或由 run_all_tests.ahk 调用）----
YunitJUnit.OutputFile := A_ScriptDir "\junit_unit_dblclick.xml"
tester := Yunit.Use(YunitStdOut, YunitJUnit)
tester.Test(DblClickUnitTest)
YunitJUnit.Last.WriteXml()   ; ExitApp 不触发 __Delete，需显式落盘 XML
ExitApp YunitJUnit.Last.tests.fail ? 1 : 0
