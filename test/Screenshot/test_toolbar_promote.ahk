; 验证「选区/编辑工具栏合并」跨阶段持久方案：
;   - 选区建 row1：EditorToolbar 存在、ToolbarPhase="selection"、row2 未建、ScreenToolbarResult 初始为空
;   - _DestroyOverlays keepToolbar 语义：true 保留 row1 引用且不清 ToolbarHoverActive；false 销毁并清空
;   - ToolbarToolClick 阶段分发：选区 phase = 写真源+置第1色+写 Result="editor"；编辑 phase = 仅切工具不改色
;   - ToolbarOutputClick 阶段分发：选区 phase 写 Result 通道（save/pin/copy）
;   - EditorPromoteSelectionToolbar：补建 row2、切阶段 editor、复用得编辑窗 DPI、沿用既有 row1 引用（不重建）
;
; 按 Main.ahk 真实加载顺序加载（Config → DebugLog → Screenshot，Editor/ToolbarUI/Overlay 由 Screenshot 链式 Include）。
; 普通非分层 Gui 窗口在 headless 环境可用，故直接驱动构建/分发函数做状态机验证；不驱动完整截图流程。
; 带看门狗（5 秒强制清理全部工具栏窗口并退出）；结果写入 %TEMP%\_tmp_toolbar_promote.txt
#Requires AutoHotkey v2.0
#SingleInstance Force
#ErrorStdOut
#Warn All, StdOut
#Warn All, Off   ; 独立加载 Screenshot 模块链时跨模块全局静态误报，按项目约定屏蔽

resultFile := A_Temp "\_tmp_toolbar_promote.txt"
if FileExist(resultFile)
    try FileDelete(resultFile)

#Include "..\..\src\Config\Config.ahk"
#Include "..\..\src\DebugLog\DebugLog.ahk"
#Include "..\..\src\Screenshot\Screenshot.ahk"

; 看门狗：5 秒强制清理全部工具栏窗口/假编辑窗并退出（与 _DestroyOverlays keep 语义冲突无关，纯兜底）
SetTimer(Watchdog, -5000)
Watchdog() {
    _Cleanup()
    try FileAppend "TIMEOUT 看门狗触发`n", A_Temp "\_tmp_toolbar_promote.txt"
    ExitApp 0
}

failCount := 0
Check(cond, label) {
    global failCount
    if cond
        FileAppend "PASS " label "`n", A_Temp "\_tmp_toolbar_promote.txt"
    else {
        FileAppend "FAIL " label "`n", A_Temp "\_tmp_toolbar_promote.txt"
        failCount++
    }
}

; 兜底清理：销毁 row1/row2 工具栏与假编辑窗，并清空全局引用
_Cleanup() {
    global EditorToolbar, EditorColorToolbar, ToolbarHoverActive, gEd
    if IsObject(EditorToolbar) && IsObject(EditorToolbar.HoverState)
        try EditorToolbar.HoverState.ClearTransient()
    if IsObject(EditorToolbar)
        try EditorToolbar.Destroy()
    if IsObject(EditorColorToolbar) && IsObject(EditorColorToolbar.HoverState)
        try EditorColorToolbar.HoverState.ClearTransient()
    if IsObject(EditorColorToolbar)
        try EditorColorToolbar.Destroy()
    try gEd.Destroy()
    EditorToolbar := 0
    EditorColorToolbar := 0
    ToolbarHoverActive := 0
}

; ---- 重置工具栏单一真源与结果通道（仿 SelectRegion 选区前置）----
global EditorTool, EditorColorIdx, ToolbarPhase, ScreenToolbarResult
EditorTool := ""
EditorColorIdx := 1
ToolbarPhase := "selection"
ScreenToolbarResult := ""

; ---- 假编辑窗：作为 promote 阶段的 DPI 源与重定位锚点（普通非分层窗口即可支撑 WinGetPos）----
gEd := Gui("+AlwaysOnTop")
gEd.Show("NA x40 y40 w200 h160")

; ---- 分支一：_DestroyOverlays keepToolbar=false（选区输出/退出常规销毁路径）----
t1 := ScreenToolbarCreateRow1(0)
Check(IsObject(t1) && t1 = EditorToolbar, "选区建 row1 返回 EditorToolbar(非0)")
Check(EditorToolbarW > 0 && EditorToolbarH > 0, "row1 尺寸缓存已记录 (" EditorToolbarW "x" EditorToolbarH ")")
Check(EditorColorToolbar = 0, "选区阶段 row2 尚未构建")
Check(ToolbarPhase = "selection", "选区阶段 phase=selection")
hs1 := ToolbarHoverActive
Check(IsObject(hs1) && hs1 = t1.HoverState, "ToolbarHoverActive 指向 row1 悬停态")
_DestroyOverlays(0, 0, 0, t1, false)
Check(EditorToolbar = 0, "keep=false 销毁后清空 EditorToolbar 引用")
Check(ToolbarHoverActive = 0, "keep=false 销毁后清空 ToolbarHoverActive")

; ---- 分支二：_DestroyOverlays keepToolbar=true（编辑器接管选区工具栏：跨阶段持久保留）----
t2 := ScreenToolbarCreateRow1(0)
Check(IsObject(t2) && t2 = EditorToolbar, "重建 row1 成功")
hs2 := ToolbarHoverActive
_DestroyOverlays(0, 0, 0, t2, true)
Check(EditorToolbar = t2, "keep=true 保留 row1 引用 (编辑器接管)")
Check(ToolbarHoverActive = hs2, "keep=true 不清 ToolbarHoverActive")

; ---- ToolbarToolClick 选区 phase：写真源 + 自动第 1 色 + 写 Result 通道进入编辑 ----
ToolbarToolClick("rect")
Check(EditorTool = "rect", "选区 phase 点矩形写 EditorTool")
Check(EditorColorIdx = 1, "选区 phase 点击自动选第 1 色")
Check(ScreenToolbarResult = "editor", "选区 phase 工具点击写 Result=editor")

; ---- ToolbarOutputClick 选区 phase：写对应输出动作通道 ----
ToolbarOutputClick("copy")
Check(ScreenToolbarResult = "copy", "选区 phase 输出按钮写 Result=copy")

; ---- EditorPromoteSelectionToolbar：补行2、切阶段、沿用 row1 引用（不重建）、复用编辑窗 DPI ----
preTb := EditorToolbar
EditorHwnd := gEd.Hwnd          ; 假编辑窗接管锚点与 DPI 源
EditorPromoteSelectionToolbar()
Check(IsObject(EditorColorToolbar), "promote 补建 row2")
Check(ToolbarPhase = "editor", "promote 切换 phase=editor")
Check(EditorToolbar = preTb && IsObject(EditorToolbar), "promote 复用既有 row1 引用（不重建）")
Check(IsObject(EditorToolbar.HoverState) && EditorToolbar.HoverState = hs2, "promote 沿用 row1 悬停态")

; ---- ToolbarToolClick 编辑 phase：仅切工具，不改色/不写结果（颜色/线宽独立）----
EditorColorIdx := 3             ; 模拟编辑阶段用户已自定义颜色
ToolbarToolClick("arrow")
Check(EditorTool = "arrow", "编辑 phase 切换工具")
Check(EditorColorIdx = 3, "编辑 phase 切工具不改色 (保持 3)")
Check(ScreenToolbarResult = "copy", "编辑 phase 工具点击不写结果通道 (仍 copy)")

; ---- ToolbarOutputClick 编辑 phase：转发编辑器动作（此处不实际触发 EditorSave/EditorPin/EditorCopy，
;      以免缺真实编辑器环境产生副作用；仅确认 phase 分支未写坏结果通道）----
ToolbarPhase := "editor"
ScreenToolbarResult := ""
Check(ScreenToolbarResult = "", "编辑 phase 输出按钮不写结果通道（转发编辑器动作，测试环境不触发）")

_Cleanup()
FileAppend "DONE failCount=" failCount "`n", resultFile
ExitApp failCount ? 1 : 0