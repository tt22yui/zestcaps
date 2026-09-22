; 验证工具栏 DPI 缩放：ToolbarDpi() 换算 + SwatchCreate / PenWidthIconCreate / ToolbarHoverState.Add
; 控件尺寸在 125% 缩放下等比放大、100% 下保持原值（带看门狗，超时按失败非零退出）
; 注意：组件基准尺寸为 24（0.3.x 起由 26 缩小到 24），PenWidthIconCreate 返回 [外框, 内块]
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

; 看门狗：15 秒强制销毁所有窗口并退出（防止 GUI 残留/卡死）；超时按失败计
SetTimer(Watchdog, -15000)
Watchdog() {
    global g1, g2, g3
    try g1.Destroy()
    try g2.Destroy()
    try g3.Destroy()
    try FileAppend "TIMEOUT 看门狗触发`n", A_Temp "\_tmp_toolbar_dpi.txt"
    ExitApp 1
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
s125 := ToolbarDpi(24)          ; 色块/图标外框尺寸（基准 24）
r125 := Max(2, ToolbarDpi(2))   ; 外框环宽（最小 2px）
i125 := s125 - 2 * r125         ; 内块尺寸（保证环两侧对称）
bw125 := ToolbarDpi(74)         ; 扁平按钮宽
bh125 := ToolbarDpi(24)         ; 扁平按钮高（基准 24）

pair := SwatchCreate(g2, 0xFF0000, DummyClick)
pair[1].GetPos(&fx1, &fy1, &fw1, &fh1)
pair[2].GetPos(&sx1, &sy1, &sw1, &sh1)
Check(fw1 = s125 && fh1 = s125, "色块外框 " s125 "x" s125 " (实际 " fw1 "x" fh1 ")")
Check(sw1 = i125 && sh1 = i125, "色块内块 " i125 "x" i125 " (实际 " sw1 "x" sh1 ")")

pen := PenWidthIconCreate(g2, 11, DummyClick)
pen[1].GetPos(&pfx, &pfy, &pfw, &pfh)
pen[2].GetPos(&bx1, &by1, &bw1, &bh1)
Check(pfw = s125 && pfh = s125, "粗细外框 " s125 "x" s125 " (实际 " pfw "x" pfh ")")
Check(bw1 = i125 && bh1 = i125, "粗细内块 " i125 "x" i125 " (实际 " bw1 "x" bh1 ")")

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
Check(fw3 = 24 && fh3 = 24, "100% 色块外框 24x24 (实际 " fw3 "x" fh3 ")")
Check(sw3 = 20 && sh3 = 20, "100% 色块内块 20x20 (实际 " sw3 "x" sh3 ")")
pen3 := PenWidthIconCreate(g3, 11, DummyClick)
pen3[2].GetPos(&px3, &py3, &pw3, &ph3)
Check(pw3 = 20 && ph3 = 20, "100% 粗细内块 20x20 (实际 " pw3 "x" ph3 ")")
hs3 := ToolbarHoverState()
btn3 := hs3.Add(g3, "测试", DummyClick)
btn3.GetPos(&cx3, &cy3, &cw3, &ch3)
Check(cw3 = 74 && ch3 = 24, "100% 扁平按钮 74x24 (实际 " cw3 "x" ch3 ")")

FileAppend "DONE failCount=" failCount "`n", resultFile
try g1.Destroy()
try g2.Destroy()
try g3.Destroy()
ExitApp failCount ? 1 : 0
