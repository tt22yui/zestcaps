; ==================================================================
; 单元测试：滚动截图拼接算法 —— ScrollStitchFrame / ScrollImagesIdentical
; 覆盖：首帧克隆、纯垂直位移拼接、连续多帧、固定底栏自动剔除、画面一致性判定
; 说明：用合成位图（内容由 (x,y) 决定，纹理丰富）验证，不创建任何窗口（无需看门狗）；
;       include 链与 Main.ahk 一致（Config → DebugLog → Screenshot，后者已含 Gdip 与滚动模块），
;       并屏蔽日志写入。单跑：AutoHotkey64 test\Screenshot\test_unit_scroll.ahk
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

; ------------------------------------------------------------------
; 测试辅助（合成位图工具）
; ------------------------------------------------------------------

; 生成虚拟长页面：每像素颜色由 (x, y) 决定
ScrollTestPage(pageW, pageH) {
    p := Gdip_CreateBitmap(pageW, pageH)
    stride := 0, scan0 := 0, bd := 0
    Gdip_LockBits(p, 0, 0, pageW, pageH, &stride, &scan0, &bd, 3, 0x26200A)
    py := 0
    while (py < pageH) {
        px := 0
        while (px < pageW) {
            cr := (px * 7 + py * 13) & 0xFF
            cg := (px * 3 + py * 5 + 17) & 0xFF
            cb := (px + py * 2 + 31) & 0xFF
            Gdip_SetLockBitPixel(0xFF000000 | (cr << 16) | (cg << 8) | cb, scan0, px, py, stride)
            px++
        }
        py++
    }
    Gdip_UnlockBits(p, &bd)
    return p
}

; 从虚拟页面裁一帧：内容 page[pageY .. pageY + frameH - footH)，底部补固定底栏
ScrollTestFrame(page, pageW, pageY, frameH, footH) {
    contentH := frameH - footH
    p := Gdip_CreateBitmap(pageW, frameH)
    g := Gdip_GraphicsFromImage(p)
    Gdip_SetCompositingMode(g, 1)
    Gdip_SetInterpolationMode(g, 5)
    Gdip_DrawImage(g, page, 0, 0, pageW, contentH, 0, pageY, pageW, contentH)
    if (footH > 0) {
        br := Gdip_BrushCreateSolid(0xFF3A3A3A)
        Gdip_FillRectangle(g, br, 0, contentH, pageW, footH)
        Gdip_DeleteBrush(br)
    }
    Gdip_DeleteGraphics(g)
    return p
}

; 期望结果：page[0 .. contentRows) + 固定底栏
ScrollTestExpected(page, pageW, contentRows, footH) {
    p := Gdip_CreateBitmap(pageW, contentRows + footH)
    g := Gdip_GraphicsFromImage(p)
    Gdip_SetCompositingMode(g, 1)
    Gdip_SetInterpolationMode(g, 5)
    Gdip_DrawImage(g, page, 0, 0, pageW, contentRows, 0, 0, pageW, contentRows)
    if (footH > 0) {
        br := Gdip_BrushCreateSolid(0xFF3A3A3A)
        Gdip_FillRectangle(g, br, 0, contentRows, pageW, footH)
        Gdip_DeleteBrush(br)
    }
    Gdip_DeleteGraphics(g)
    return p
}

ScrollTestDispose(bitmaps) {
    for bmp in bitmaps
        if bmp
            Gdip_DisposeImage(bmp)
}

; ------------------------------------------------------------------
; 测试用例
; ------------------------------------------------------------------
class ScrollUnitTest {
    test_首帧返回克隆() {
        page := ScrollTestPage(80, 200)
        f := ScrollTestFrame(page, 80, 0, 100, 0)
        best := {count: 0, index: 0, ignoreBottom: 0}
        ScrollStitchReset(best)
        r := ScrollStitchFrame(0, f, true, best, &status)
        Yunit.Assert(status = 0, "首帧状态应为成功")
        Yunit.Assert(ScrollImagesIdentical(r, f), "首帧应返回内容一致的克隆")
        ScrollTestDispose([page, f, r])
    }

    test_纯位移两帧拼接() {
        page := ScrollTestPage(80, 400)
        fA := ScrollTestFrame(page, 80, 0, 150, 0)
        fB := ScrollTestFrame(page, 80, 60, 150, 0)
        expectedBmp := ScrollTestExpected(page, 80, 210, 0)
        best := {count: 0, index: 0, ignoreBottom: 0}
        ScrollStitchReset(best)
        r1 := ScrollStitchFrame(0, fA, true, best, &status)
        r2 := ScrollStitchFrame(r1, fB, true, best, &status)
        Yunit.Assert(status = 0, "两帧拼接状态应为成功")
        Yunit.Assert(ScrollImagesIdentical(r2, expectedBmp), "两帧应按垂直位移拼成长图")
        ScrollTestDispose([page, fA, fB, expectedBmp, r1, r2])
    }

    test_连续三帧拼接() {
        page := ScrollTestPage(80, 600)
        fA := ScrollTestFrame(page, 80, 0, 150, 0)
        fB := ScrollTestFrame(page, 80, 60, 150, 0)
        fC := ScrollTestFrame(page, 80, 120, 150, 0)
        expectedBmp := ScrollTestExpected(page, 80, 270, 0)
        best := {count: 0, index: 0, ignoreBottom: 0}
        ScrollStitchReset(best)
        r1 := ScrollStitchFrame(0, fA, true, best, &status)
        r2 := ScrollStitchFrame(r1, fB, true, best, &status)
        Gdip_DisposeImage(r1)
        r3 := ScrollStitchFrame(r2, fC, true, best, &status)
        Gdip_DisposeImage(r2)
        Yunit.Assert(status = 0, "三帧拼接状态应为成功")
        Yunit.Assert(ScrollImagesIdentical(r3, expectedBmp), "三帧应按累积位移拼成长图")
        ScrollTestDispose([page, fA, fB, fC, expectedBmp, r3])
    }

    test_固定底栏自动剔除() {
        ; 底栏 80px > 基线忽略区（max(50, 高/10)=50），验证自动识别固定底栏并剔除
        page := ScrollTestPage(80, 600)
        footH := 80
        fA := ScrollTestFrame(page, 80, 0, 300, footH)
        fB := ScrollTestFrame(page, 80, 100, 300, footH)
        contentRows := (300 - footH) + 100   ; 220 + 100 = 320
        expectedBmp := ScrollTestExpected(page, 80, contentRows, footH)
        best := {count: 0, index: 0, ignoreBottom: 0}
        ScrollStitchReset(best)
        r1 := ScrollStitchFrame(0, fA, true, best, &status)
        r2 := ScrollStitchFrame(r1, fB, true, best, &status)
        Yunit.Assert(status = 0, "固定底栏拼接状态应为成功")
        Yunit.Assert(ScrollImagesIdentical(r2, expectedBmp), "固定底栏应被自动剔除，内容正确拼接")
        ScrollTestDispose([page, fA, fB, expectedBmp, r1, r2])
    }

    test_固定底栏高度超过三分之一仍可剔除() {
        ; 回归：底栏 150px = 帧高 400 的 37.5% > 旧上限 curH//3(133)，
        ; 旧实现检测不到 → rectBottom 落进底栏 → 匹配永远失败、长图不再增长
        page := ScrollTestPage(80, 800)
        footH := 150
        fA := ScrollTestFrame(page, 80, 0, 400, footH)
        fB := ScrollTestFrame(page, 80, 50, 400, footH)
        contentRows := (400 - footH) + 50   ; 250 + 50 = 300
        expectedBmp := ScrollTestExpected(page, 80, contentRows, footH)
        best := {count: 0, index: 0, ignoreBottom: 0}
        ScrollStitchReset(best)
        r1 := ScrollStitchFrame(0, fA, true, best, &status)
        r2 := ScrollStitchFrame(r1, fB, true, best, &status)
        Yunit.Assert(status = 0, "高底栏拼接状态应为成功")
        Yunit.Assert(ScrollImagesIdentical(r2, expectedBmp), "底栏超过帧高 1/3 时仍应被剔除并正确拼接")
        ScrollTestDispose([page, fA, fB, expectedBmp, r1, r2])
    }

    test_画面一致性判定() {
        page := ScrollTestPage(80, 300)
        fA := ScrollTestFrame(page, 80, 0, 100, 0)
        fB := ScrollTestFrame(page, 80, 0, 100, 0)
        fC := ScrollTestFrame(page, 80, 40, 100, 0)
        Yunit.Assert(ScrollImagesIdentical(fA, fB), "同帧应判定为一致")
        Yunit.Assert(!ScrollImagesIdentical(fA, fC), "位移帧应判定为不一致")
        ScrollTestDispose([page, fA, fB, fC])
    }
}

; ---- 运行入口（单跑或由 run_all_tests.ahk 调用）----
YunitJUnit.OutputFile := A_ScriptDir "\junit_unit_scroll.xml"
tester := Yunit.Use(YunitStdOut, YunitJUnit)
tester.Test(ScrollUnitTest)
YunitJUnit.Last.WriteXml()   ; ExitApp 不触发 __Delete，需显式落盘 XML
ExitApp YunitJUnit.Last.tests.fail ? 1 : 0
