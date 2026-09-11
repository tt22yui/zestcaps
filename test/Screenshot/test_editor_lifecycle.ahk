; ==================================================================
; GUI 回归：编辑窗完整生命周期（打开 → 工具栏动作 → 资源清理 / 就地钉屏交接）
;
; 为什么需要（重构护栏）：ShowEditor 是超长函数、Editor.ahk 持有 100+ 全局，
; 任何拆分/改名都必须保证「会话开→交互→收尾」的状态与资源完全对称。本测试把这条链路跑通：
;   1) 打开阶段：编辑窗 + 覆盖层（蒙版 + 4 条边框）+ 两行工具栏就绪；尺寸/缩放/位图正确；
;      边框**确实可见**（回归：Gui.Move 不会显示隐藏窗口，只 Move 不 Show 会整场不可见）
;   2) 复制路径收尾：ShowEditor 返回 "copy" 后窗口销毁；4 个位图、标注集合、两行工具栏、
;      蒙版、边框、圆圈光标全部释放；EditorResult/EditorPending/EditorHwnd 等全局复位；Esc 需求归零；
;      剪贴板确实写入了位图
;   3) 就地钉屏交接：返回 "pin" 后编辑窗原地转为钉屏会话（PinSessions 注册、边框保留且可见）、
;      蒙版与工具栏销毁、圆圈光标句柄释放（回归：此前就地钉屏漏释放，每次泄漏一个 USER 句柄）；
;      关闭钉屏后会话与边框一并清理
;
; 驱动方式：ShowEditor 内部阻塞轮询 EditorResult，故用一次性定时器在会话运行期间调用**真实回调**
;   （ToolbarToolClick / ToolbarOutputClick，等价于用户点工具栏按钮），不使用任何鼠标模拟。
;
; 注意：测试会在屏幕上短暂显示编辑窗/蒙版/工具栏（约 1~2 秒），并临时占用 Esc 热键；
;       带看门狗（20 秒强制清理并退出，超时按失败计）；结果写入 %TEMP%\_tmp_editor_lifecycle.txt（用完即删）。
; ==================================================================
#Requires AutoHotkey v2.0
#SingleInstance Force
#ErrorStdOut
#Warn All, StdOut

resultFile := A_Temp "\_tmp_editor_lifecycle.txt"
if FileExist(resultFile)
    try FileDelete(resultFile)

#Include "..\..\src\Config\Config.ahk"
DEBUG_LOG_ENABLED := false     ; 屏蔽日志写入，避免污染正式日志
#Include "..\..\src\DebugLog\DebugLog.ahk"
#Include "..\..\src\Screenshot\Screenshot.ahk"   ; 链式引入 Gdip / Overlay / ToolbarUI / Editor / Pin

; 未捕获异常不能让默认错误框挂住测试（会连带挂住 GUI 测试套件）：写结果 + 清理 + 非零退出
OnError(TestOnError)
TestOnError(Thrown, Mode) {
    global resultFile
    try FileAppend "ERROR: " (Thrown is Error ? Thrown.Message " @" Thrown.Line : String(Thrown)) "`n", resultFile
    try PinEscClose()
    ExitApp 2
    return 1
}

; 看门狗：20 秒强制清理并退出（超时视为失败，非零退出）
SetTimer(Watchdog, -20000)
Watchdog() {
    global resultFile, EditorGui
    try PinEscClose()
    if IsObject(EditorGui)
        try EditorGui.Destroy()
    try FileAppend "TIMEOUT 看门狗触发`n", resultFile
    ExitApp 1
}

failCount := 0
Check(cond, label) {
    global failCount, resultFile
    if cond
        FileAppend "PASS " label "`n", resultFile
    else {
        FileAppend "FAIL " label "`n", resultFile
        failCount++
    }
}

; 构造测试原图（纯色，便于断言尺寸）
MakeTestBitmap(w, h, color) {
    pBmp := Gdip_CreateBitmap(w, h)
    G := Gdip_GraphicsFromImage(pBmp)
    pBrush := Gdip_BrushCreateSolid(color)
    Gdip_FillRectangle(G, pBrush, 0, 0, w, h)
    Gdip_DeleteBrush(pBrush)
    Gdip_DeleteGraphics(G)
    return pBmp
}
Visible(hwnd) => DllCall("IsWindowVisible", "Ptr", hwnd) ? 1 : 0

; ==================================================================
; 阶段 1：打开 → 复制路径 → 收尾
; ==================================================================
Rec1 := {}
Drive1() {
    global Rec1
    global EditorGui, EditorHwnd, EditorToolbar, EditorColorToolbar, EditorBorders, EditorMaskOv
    global EditorWorkBitmap, EditorBgBitmap, EditorBgBase, EditorBaseBitmap
    global EditorWinW, EditorWinH, EditorImgW, EditorImgH, EditorScale, EditorTool, ToolbarPhase
    Rec1.hwnd := EditorHwnd
    Rec1.guiAlive := IsObject(EditorGui) && WinExist("ahk_id " EditorHwnd) ? true : false
    Rec1.winVisible := DllCall("IsWindowVisible", "Ptr", EditorHwnd) ? 1 : 0
    Rec1.hasToolbar := IsObject(EditorToolbar) && EditorToolbar.Hwnd ? true : false
    Rec1.toolbarVisible := IsObject(EditorToolbar) ? (DllCall("IsWindowVisible", "Ptr", EditorToolbar.Hwnd) ? 1 : 0) : -1
    Rec1.hasColorToolbar := IsObject(EditorColorToolbar) ? true : false
    Rec1.phase := ToolbarPhase
    Rec1.borderCount := EditorBorders.Length
    Rec1.bordersVisible := 0
    for b in EditorBorders
        Rec1.bordersVisible += DllCall("IsWindowVisible", "Ptr", b.Hwnd) ? 1 : 0
    Rec1.maskAlive := IsObject(EditorMaskOv) && EditorMaskOv.hwnd ? true : false
    Rec1.maskVisible := IsObject(EditorMaskOv) && EditorMaskOv.hwnd ? (DllCall("IsWindowVisible", "Ptr", EditorMaskOv.hwnd) ? 1 : 0) : -1
    Rec1.work := EditorWorkBitmap ? 1 : 0
    Rec1.bg := EditorBgBitmap ? 1 : 0
    Rec1.bgBase := EditorBgBase ? 1 : 0
    Rec1.baseBmp := EditorBaseBitmap ? 1 : 0   ; 字段名不用 base：那是 AHK 对象的原型属性，赋值会报 Expected an Object
    Rec1.winW := EditorWinW, Rec1.winH := EditorWinH
    Rec1.imgW := EditorImgW, Rec1.imgH := EditorImgH
    Rec1.scale := EditorScale
    ; 真实工具栏回调：先切工具（验证分发），再触发复制（主循环退出）
    ToolbarToolClick("rect")
    Rec1.toolAfterClick := EditorTool
    ToolbarOutputClick("copy")
}

savedClip := ClipboardAll()            ; 备份用户剪贴板（复制动作会整体替换剪贴板）
A_Clipboard := "zestcaps-gui-test"     ; 置为纯文本，确保后续「有位图格式」的断言不是旧内容造成的假通过
Check(!DllCall("IsClipboardFormatAvailable", "uint", 2) && !DllCall("IsClipboardFormatAvailable", "uint", 8) && !DllCall("IsClipboardFormatAvailable", "uint", 17),
    "前置条件：置文本后剪贴板不含位图格式")

src1 := MakeTestBitmap(320, 200, "0xFF3366CC")
SetTimer(Drive1, -400)
Ret1 := ShowEditor(src1)

Check(Ret1 = "copy", "ShowEditor 返回 copy（实际 [" Ret1 "]）")
Check(Rec1.guiAlive && Rec1.winVisible = 1, "会话期间编辑窗存在且可见")
Check(Rec1.hasToolbar && Rec1.toolbarVisible = 1, "会话期间工具栏存在且可见")
Check(Rec1.hasColorToolbar, "会话期间颜色行已建")
Check(Rec1.phase = "editor", "工具栏阶段为 editor（实际 [" Rec1.phase "]）")
Check(Rec1.borderCount = 4 && Rec1.bordersVisible = 4, "会话期间 4 条边框全部可见（实际 " Rec1.bordersVisible "/" Rec1.borderCount "）")
Check(Rec1.maskAlive && Rec1.maskVisible = 1, "会话期间蒙版存在且可见")
Check(Rec1.work && Rec1.bg && Rec1.bgBase && Rec1.baseBmp, "会话期间工作位图/标注层/基础层/原图就绪")
Check(Rec1.imgW = 320 && Rec1.imgH = 200, "图片尺寸 320x200（实际 " Rec1.imgW "x" Rec1.imgH "）")
Check(Rec1.winW = 320 && Rec1.winH = 200, "窗口尺寸=图片尺寸（未缩放，实际 " Rec1.winW "x" Rec1.winH "）")
Check(Rec1.scale = 1.0, "缩放系数 1.0（实际 " Rec1.scale "）")
Check(Rec1.toolAfterClick = "rect", "工具点击写入 EditorTool（实际 [" Rec1.toolAfterClick "]）")

; ---- 收尾断言（资源与全局必须完全复位）----
Check(!WinExist("ahk_id " Rec1.hwnd), "返回后编辑窗已销毁")
Check(EditorGui = 0 && EditorHwnd = 0, "编辑器 GUI / HWND 全局已复位")
Check(EditorWorkBitmap = 0 && EditorBgBitmap = 0 && EditorBgBase = 0 && EditorBaseBitmap = 0, "4 个位图全局已释放置零")
Check(EditorAnnotations.Length = 0 && !EditorPending, "标注集合与进行中标注已清空")
Check(EditorMaskOv = 0 && EditorBorders.Length = 0, "蒙版与边框已释放")
Check(EditorToolbar = 0 && EditorColorToolbar = 0, "两行工具栏已销毁")
Check(EditorCircleCursor = 0, "圆圈光标句柄为 0")
Check(EditorResult = "", "EditorResult 已复位")
Check(EscNeed = 0, "Esc 热键需求计数归零")
Check(DllCall("IsClipboardFormatAvailable", "uint", 2) || DllCall("IsClipboardFormatAvailable", "uint", 8) || DllCall("IsClipboardFormatAvailable", "uint", 17),
    "复制动作已把位图写入剪贴板（CF_BITMAP/CF_DIB/CF_DIBV5）")

A_Clipboard := savedClip              ; 还原用户剪贴板

; ==================================================================
; 阶段 2：打开 → 切画笔（创建圆圈光标）→ 就地钉屏 → 交接与清理
; ==================================================================
Rec2 := {}
Drive2() {
    global Rec2
    global EditorHwnd, EditorCircleCursor, EditorTool
    Rec2.hwnd := EditorHwnd
    ToolbarToolClick("brush")            ; 真实回调：切画笔并应用圆环光标
    Rec2.tool := EditorTool
    Rec2.cursorAfterBrush := EditorCircleCursor ? 1 : 0
    ToolbarOutputClick("pin")            ; 真实回调：钉屏 → 主循环退出
}

src2 := MakeTestBitmap(240, 160, "0xFF22AA66")
SetTimer(Drive2, -400)
Ret2 := ShowEditor(src2)

Check(Ret2 = "pin", "ShowEditor 返回 pin（实际 [" Ret2 "]）")
Check(Rec2.tool = "brush", "工具已切到 brush（实际 [" Rec2.tool "]）")
Check(Rec2.cursorAfterBrush = 1, "切画笔后已创建圆圈光标句柄")
Check(IsObject(PinSessions) && PinSessions.Has(Rec2.hwnd), "就地钉屏已注册钉屏会话")
Check(WinExist("ahk_id " Rec2.hwnd), "钉屏窗口仍在（画面原地保留）")
Check(EditorCircleCursor = 0, "就地钉屏已释放圆圈光标句柄（回归）")
Check(EditorMaskOv = 0 && EditorToolbar = 0 && EditorColorToolbar = 0, "蒙版与两行工具栏已销毁")
Check(EditorResult = "", "就地钉屏后 EditorResult 已复位")

pin := PinSessions.Get(Rec2.hwnd, 0)
Check(IsObject(pin) && pin.borders.Length = 4, "钉屏会话持有 4 条边框")
borderHwnd := 0
visAfterPin := 0
if IsObject(pin) {
    borderHwnd := pin.borders[1].Hwnd
    ; 循环变量刻意不叫 b：脚本顶层赋值会成为全局，与库内各处 `for b in ...` 的局部同名并触发告警
    for bd in pin.borders
        visAfterPin += DllCall("IsWindowVisible", "Ptr", bd.Hwnd) ? 1 : 0
}
Check(visAfterPin = 4, "交接后 4 条边框仍全部可见（实际 " visAfterPin "/4）")

; ---- 关闭钉屏：会话与边框一并清理 ----
WinClose("ahk_id " Rec2.hwnd)
Sleep 400
Check(!PinSessions.Has(Rec2.hwnd), "关闭后钉屏会话注销")
if borderHwnd
    Check(!WinExist("ahk_id " borderHwnd), "关闭后边框窗口已销毁")
Check(EscNeed = 0, "关闭后 Esc 热键需求归零")

; ==================================================================
; 汇总
; ==================================================================
FileAppend "DONE failCount=" failCount "`n", resultFile
try FileAppend FileRead(resultFile), "*"   ; 回显到 stdout（重定向/CI 可见）
try FileDelete(resultFile)
ExitApp failCount ? 1 : 0
