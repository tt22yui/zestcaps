; 验证「滚动截图」入口在选区工具栏的接入与编辑阶段移除：
;   - 选区建 row1 时附加滚动截图按钮（EditorScrollButton 非 0）
;   - ToolbarScrollClick 写结果通道 "scroll"
;   - EditorHideScrollButton 仅隐藏按钮并**保留槽位**：工具栏宽度不变、输出按钮不左移，
;     并把该按钮从悬停命中/提示列表移除（避免空白槽位误触发悬停/tooltip）
;   - _DestroyOverlays 销毁 row1 时同步清按钮引用
;
; 按 Main.ahk 真实加载顺序加载（Config → DebugLog → Screenshot 链式 Include）。
; 带看门狗（15 秒强制清理并退出）；结果写 %TEMP%\_tmp_scroll_toolbar.txt（用完即删）
#Requires AutoHotkey v2.0
#SingleInstance Force
#ErrorStdOut
#Warn All, StdOut
#Warn All, Off   ; 独立加载 Screenshot 模块链时跨模块全局静态误报，按项目约定屏蔽

resultFile := A_Temp "\_tmp_scroll_toolbar.txt"
if FileExist(resultFile)
    try FileDelete(resultFile)

#Include "..\..\src\Config\Config.ahk"
#Include "..\..\src\DebugLog\DebugLog.ahk"
#Include "..\..\src\Screenshot\Screenshot.ahk"

SetTimer(Watchdog, -15000)
Watchdog() {
    _Cleanup()
    try FileAppend "TIMEOUT 看门狗触发`n", A_Temp "\_tmp_scroll_toolbar.txt"
    ExitApp 1   ; 超时按失败计（非零退出，聚合器/CI 可见）
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
    global EditorToolbar, EditorColorToolbar, ToolbarHoverActive, EditorScrollButton
    if IsObject(EditorToolbar) && IsObject(EditorToolbar.HoverState)
        try EditorToolbar.HoverState.ClearTransient()
    if IsObject(EditorToolbar)
        try EditorToolbar.Destroy()
    if IsObject(EditorColorToolbar) && IsObject(EditorColorToolbar.HoverState)
        try EditorColorToolbar.HoverState.ClearTransient()
    if IsObject(EditorColorToolbar)
        try EditorColorToolbar.Destroy()
    EditorToolbar := 0
    EditorColorToolbar := 0
    ToolbarHoverActive := 0
    EditorScrollButton := 0
}

global EditorTool, EditorColorIdx, ToolbarPhase, ScreenToolbarResult
EditorTool := ""
EditorColorIdx := 1
ToolbarPhase := "selection"
ScreenToolbarResult := ""

; ---- 选区建 row1：应附加滚动截图按钮 ----
t1 := ScreenToolbarCreateRow1(0)
Check(IsObject(t1) && t1 = EditorToolbar, "选区建 row1 成功")
Check(IsObject(EditorScrollButton), "选区 row1 含滚动截图按钮")
hs := t1.HoverState
nBtns0 := hs.btns.Length
Check(nBtns0 = 10, "row1 按钮数=10（6 工具 + 滚动截图 + 保存/钉屏/复制），实际 " nBtns0)
; 通过 tooltip 文本定位「保存」按钮（不再有 EditorScrollAfterCtrls 可查）
saveCtrl := 0
for c, tip in hs.tips
    if (tip = "保存")
        saveCtrl := c
Check(IsObject(saveCtrl), "找到「保存」按钮")
saveCtrl.GetPos(&saveX0, )
w0 := EditorToolbarW

; ---- 点击滚动截图按钮：写结果通道 ----
ToolbarScrollClick()
Check(ScreenToolbarResult = "scroll", "点击滚动截图写 Result=scroll")

; ---- 编辑阶段隐藏：仅隐藏、保留槽位（宽度不变、输出按钮不左移、退出悬停命中/提示）----
EditorHideScrollButton()
Check(EditorScrollButton = 0, "隐藏后清空按钮引用")
Check(EditorToolbarW = w0, "隐藏后工具栏宽度不变（保留槽位，避免重新居中）(" w0 " → " EditorToolbarW ")")
Check(hs.btns.Length = nBtns0 - 1, "滚动按钮已从悬停命中列表移除（" nBtns0 " → " hs.btns.Length "）")
hasScrollTip := false
for c, tip in hs.tips
    if (tip = "滚动截图")
        hasScrollTip := true
Check(!hasScrollTip, "滚动截图按钮已从悬停提示列表移除（空白槽位不再误弹 tooltip）")
saveCtrl.GetPos(&saveX1, )
Check(saveX1 = saveX0, "输出按钮位置不变（不左移）(" saveX0 " → " saveX1 ")")

; ---- 销毁 row1：按钮引用随之清空（幂等兜底）----
ScreenToolbarResult := ""
_DestroyOverlays(0, 0, 0, t1, false)
Check(EditorToolbar = 0, "销毁后清空 EditorToolbar 引用")

; ---- 重建：按钮应再次出现（新会话选区路径）----
t2 := ScreenToolbarCreateRow1(0)
Check(IsObject(EditorScrollButton), "重建 row1 后滚动截图按钮再次出现")
Check(EditorToolbarW > 0, "重建后宽度有效")
_DestroyOverlays(0, 0, 0, t2, false)
Check(EditorScrollButton = 0, "销毁重建的 row1 后按钮引用清空")

FileAppend "DONE failCount=" failCount "`n", resultFile
try FileAppend FileRead(resultFile), "*"
try FileDelete(resultFile)
ExitApp failCount ? 1 : 0
