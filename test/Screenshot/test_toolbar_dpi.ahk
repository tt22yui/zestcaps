; 验证工具栏 DPI 缩放：ToolbarDpi() 换算 + SwatchCreate / PenWidthIconCreate / ToolbarHoverState.Add
; 控件尺寸在 125% 缩放下等比放大、100% 下保持原值（带看门狗，5 秒强制退出）
; 结果写入 %TEMP%\_tmp_toolbar_dpi.txt
#Requires AutoHotkey v2.0
#SingleInstance Force
#ErrorStdOut
#Warn All, StdOut

resultFile := A_Temp "\_tmp_toolbar_dpi.txt"
if FileExist(resultFile)
    try FileDelete(resultFile)

#Include "..\..\src\Config\Config.ahk"
#Include "..\..\src\Screenshot\Common\ToolbarUI.ahk"

; 看门狗：5 秒强制销毁所有窗口并退出（防止 GUI 残留/卡死）
SetTimer(Watchdog, -5000)
Watchdog() {
    global g1, g2, g3
    try g1.Destroy()
    try g2.Destroy()
    try g3.Destroy()
    try FileAppend "TIMEOUT 看门狗触发`n", A_Temp "\_tmp_toolbar_dpi.txt"
    ExitApp 0
}

failCount := 0
Check(cond, label) {
    global failCount
    if cond
        FileAppend "PASS " label "`n", A_Temp "\_tmp_toolbar_dpi.txt"
    else {
        FileAppend "FAIL " label "`n", A_Temp "\_tmp_toolbar_dpi.txt"
        failCount++
    }
}

DummyClick(*) {
    return
}

; ---- 实际 DPI 读取：窗口 Show 后 SetToolbarDpiScale 应返回真实缩放因子（本机 125% → 1.25）----
g1 := Gui("-Caption -DPIScale")
g1.Show("NA x0 y0 w100 h50")
realScale := SetToolbarDpiScale(g1.Hwnd)
Check(realScale > 0, "SetToolbarDpiScale 返回 " realScale)
Check(realScale = A_ScreenDPI / 96, "GetDpiForWindow 与系统 DPI 一致 (" realScale ")")

; ---- 125% 缩放（模拟高 DPI）：控件尺寸按 ToolbarDpi 等比放大 ----
ToolbarDpiScale := 1.25
g2 := Gui("-Caption -DPIScale")
s125 := ToolbarDpi(26)          ; 色块/图标外框尺寸
r125 := Max(2, ToolbarDpi(2))   ; 外框环宽（最小 2px）
i125 := s125 - 2 * r125         ; 内块尺寸（保证环两侧对称）
bw125 := ToolbarDpi(74)         ; 扁平按钮宽
bh125 := ToolbarDpi(26)         ; 扁平按钮高
lh125 := Max(1, ToolbarDpi(2))  ; 粗细线高（最小 1px）

pair := SwatchCreate(g2, 0xFF0000, DummyClick)
pair[1].GetPos(&fx1, &fy1, &fw1, &fh1)
pair[2].GetPos(&sx1, &sy1, &sw1, &sh1)
Check(fw1 = s125 && fh1 = s125, "色块外框 " s125 "x" s125 " (实际 " fw1 "x" fh1 ")")
Check(sw1 = i125 && sh1 = i125, "色块内块 " i125 "x" i125 " (实际 " sw1 "x" sh1 ")")

pen := PenWidthIconCreate(g2, 2, DummyClick)
pen[2].GetPos(&bx1, &by1, &bw1, &bh1)
pen[3].GetPos(&lx1, &ly1, &lw1, &lh1)
Check(bw1 = i125 && bh1 = i125, "粗细内块 " i125 "x" i125 " (实际 " bw1 "x" bh1 ")")
Check(lh1 = lh125, "粗细线高 " lh125 " (实际 " lh1 ")")

hs := ToolbarHoverState()
btn := hs.Add(g2, "测试", DummyClick)
btn.GetPos(&cx1, &cy1, &cw1, &ch1)
Check(cw1 = bw125 && ch1 = bh125, "扁平按钮 " bw125 "x" bh125 " (实际 " cw1 "x" ch1 ")")

; ---- 100% 缩放：尺寸保持原值（不破坏原有布局）----
ToolbarDpiScale := 1.0
g3 := Gui("-Caption -DPIScale")
pair3 := SwatchCreate(g3, 0xFF0000, DummyClick)
pair3[1].GetPos(&fx3, &fy3, &fw3, &fh3)
pair3[2].GetPos(&sx3, &sy3, &sw3, &sh3)
Check(fw3 = 26 && fh3 = 26, "100% 色块外框 26x26 (实际 " fw3 "x" fh3 ")")
Check(sw3 = 22 && sh3 = 22, "100% 色块内块 22x22 (实际 " sw3 "x" sh3 ")")
pen3 := PenWidthIconCreate(g3, 2, DummyClick)
pen3[3].GetPos(&lx3, &ly3, &lw3, &lh3)
Check(lh3 = 2, "100% 粗细线高 2 (实际 " lh3 ")")
hs3 := ToolbarHoverState()
btn3 := hs3.Add(g3, "测试", DummyClick)
btn3.GetPos(&cx3, &cy3, &cw3, &ch3)
Check(cw3 = 74 && ch3 = 26, "100% 扁平按钮 74x26 (实际 " cw3 "x" ch3 ")")

FileAppend "DONE failCount=" failCount "`n", resultFile
try g1.Destroy()
try g2.Destroy()
try g3.Destroy()
ExitApp failCount ? 1 : 0
