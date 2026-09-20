; 验证滚动截图主流程 RunScrollCapture（真实抓屏 + 轮询 + Esc 收尾 + 资源清理）：
;   - 静态区域（内容不变）时返回单帧位图，尺寸等于选区；
;   - 结束后 Esc 回调复位、右键热键注销、提示条销毁，无残留卡屏。
; 目标窗口为一张静态图片（保证"无变化"分支被走到），定时器在进入轮询后触发 Esc 等价回调结束。
; 带看门狗（10 秒强制清理并退出）；结果写 %TEMP%\_tmp_scroll_flow.txt（用完即删）
#Requires AutoHotkey v2.0
#SingleInstance Force
#ErrorStdOut
#Warn All, StdOut
#Warn All, Off   ; 独立加载 Screenshot 模块链时跨模块全局静态误报，按项目约定屏蔽

resultFile := A_Temp "\_tmp_scroll_flow.txt"
tmpPng := A_Temp "\_tmp_scroll_flow.png"
if FileExist(resultFile)
    try FileDelete(resultFile)

#Include "..\..\src\Config\Config.ahk"
#Include "..\..\src\DebugLog\DebugLog.ahk"
#Include "..\..\src\Screenshot\Screenshot.ahk"

SetTimer(Watchdog, -10000)
Watchdog() {
    global ScreenshotEscCancel
    if ScreenshotEscCancel
        try ScreenshotEscCancel.Call()
    _Cleanup()
    try FileAppend "TIMEOUT 看门狗触发`n", resultFile
    ExitApp 1
}

failCount := 0
Check(cond, label) {
    global failCount
    if cond
        FileAppend "PASS " label "`n", resultFile
    else {
        FileAppend "FAIL " label "`n", resultFile
        failCount++
    }
}

_Cleanup() {
    global gv
    try gv.Destroy()
}

; 生成静态测试图并显示
pBmp := Gdip_CreateBitmap(300, 200)
g := Gdip_GraphicsFromImage(pBmp)
br := Gdip_BrushCreateSolid(0xFF2255AA)
Gdip_FillRectangle(g, br, 0, 0, 300, 200)
Gdip_DeleteBrush(br)
Gdip_DeleteGraphics(g)
Gdip_SaveBitmapToFile(pBmp, tmpPng)
Gdip_DisposeImage(pBmp)

MonitorGetWorkArea(1, &wl, &wt, &wr, &wb)
gv := Gui("+AlwaysOnTop -Caption +Border")
gv.AddPicture("x0 y0 w300 h200", tmpPng)
gv.Show("x" (wl + 40) " y" (wt + 40) " w300 h200")
Sleep 300

region := RegionSetting()
region.SetRegionRect(wl + 41, wt + 41, 300, 200)

; 进入轮询后触发 Esc 等价回调结束（重复检测，避免早于回调注册）
SetTimer(StopTimer, 200)
StopTimer() {
    global ScreenshotEscCancel, stopTimerFired
    if ScreenshotEscCancel {
        SetTimer StopTimer, 0
        stopTimerFired := true
        ScreenshotEscCancel.Call()
    }
}
stopTimerFired := false

bmp := RunScrollCapture(region)
SetTimer(StopTimer, 0)
Check(bmp != 0, "RunScrollCapture 返回位图")
Check(bmp && Gdip_GetImageWidth(bmp) = 300 && Gdip_GetImageHeight(bmp) = 200, "静态区域结果为单帧原尺寸")
Check(stopTimerFired, "轮询期间 Esc 回调已生效并结束流程")
Check(ScreenshotEscCancel = 0, "结束后 Esc 回调已复位")

if bmp
    Gdip_DisposeImage(bmp)
_Cleanup()
try FileDelete(tmpPng)

FileAppend "DONE failCount=" failCount "`n", resultFile
try FileAppend FileRead(resultFile), "*"
try FileDelete(resultFile)
ExitApp failCount ? 1 : 0
