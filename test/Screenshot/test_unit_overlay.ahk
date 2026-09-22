; ==================================================================
; 单元测试：Overlay —— 蒙版挖洞几何（MaskHoleBands 纯函数）
; 覆盖「全屏减矩形」4 条补集矩形：上/下/左/右带 + 贴边与负坐标边界
; 单跑：AutoHotkey64 test\Screenshot\test_unit_overlay.ahk
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
#Include "..\..\src\Screenshot\Common\Overlay.ahk"

class OverlayUnitTest {
    test_挖洞四带几何() {
        ; 全屏 1920x1080，窗口在 (0,0)，洞 (100,100,200,150)
        b := MaskHoleBands(100, 100, 200, 150, 0, 0, 1920, 1080)
        Yunit.Assert(b.Length = 4, "应有 4 条补集矩形，实际 " b.Length)
        Yunit.Assert(b[1][1] = 0 && b[1][2] = 0 && b[1][3] = 1920 && b[1][4] = 100, "上带应为 0,0,1920,100")
        Yunit.Assert(b[2][1] = 0 && b[2][2] = 250 && b[2][3] = 1920 && b[2][4] = 1080, "下带应为 0,250,1920,1080")
        Yunit.Assert(b[3][1] = 0 && b[3][2] = 100 && b[3][3] = 100 && b[3][4] = 250, "左带应为 0,100,100,250")
        Yunit.Assert(b[4][1] = 300 && b[4][2] = 100 && b[4][3] = 1920 && b[4][4] = 250, "右带应为 300,100,1920,250")
    }

    test_洞贴顶时不产生负高度上带() {
        b := MaskHoleBands(50, 0, 100, 50, 0, 0, 800, 600)
        Yunit.Assert(b[1][4] = 0, "洞贴顶 → 上带高度应钳到 0（非负），实际 " b[1][4])
        Yunit.Assert(b[3][3] = 50, "左带右缘应等于 rx=50，实际 " b[3][3])
    }

    test_多显示器负坐标窗口() {
        ; 窗口起点 (-800,0)，洞在窗口内 (100,100,200,150)
        b := MaskHoleBands(-700, 100, 200, 150, -800, 0, 800, 600)
        Yunit.Assert(b[3][3] = 100, "左带右缘 = rx = 100，实际 " b[3][3])
        Yunit.Assert(b[4][1] = 300, "右带左缘 = rx + w = 300，实际 " b[4][1])
    }
}

YunitJUnit.OutputFile := A_ScriptDir "\junit_unit_overlay.xml"
tester := Yunit.Use(YunitStdOut, YunitJUnit)
tester.Test(OverlayUnitTest)
YunitJUnit.Last.WriteXml()   ; ExitApp 不触发 __Delete，必须显式落盘
ExitApp YunitJUnit.Last.tests.fail ? 1 : 0
