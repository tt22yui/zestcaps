#Requires AutoHotkey v2.0
#SingleInstance Force
#ErrorStdOut
#Warn All, Off
; ==================================================================
; 常驻输入状态探针 —— 捕获「鼠标全死」卡死瞬间的前台/顶窗状态
; 定位 ZestCaps 是否与「点击全部失效、键盘可用」卡死相关的一次性诊断工具
; 触发写盘（两种方式）：
;   1) 手动：按 Ctrl+Alt+Shift+Z（卡死时键盘仍可用，最可靠）
;   2) 自动：光标处出现「铺满屏幕的透明/置顶型遮罩窗口」且连续多拍命中
; 产物：tmp\probe_input.log（内存滚动缓冲回放 + 触发时刻全量快照）
; 说明：headless、无窗口；所有异常 try/catch 落盘，不弹任何框
; 用完后删除本文件与产物，不留存
; ==================================================================

; 配置常量
TICK_MS        := 200          ; 采样周期（毫秒）
BUFFER_N       := 120          ; 内存滚动缓冲条数（≈24 秒，触发时回放）
SUSPECT_STREAK := 3            ; 连续命中可疑遮罩达该次数才自动触发
ATTACH_MS      := 2000         ; 自动触发后继续跟踪的时长（毫秒，落满 2 秒附着帧）
LOG_FILE       := A_ScriptDir "\probe_input.log"
HEART_FILE     := A_ScriptDir "\probe_heartbeat.tmp"
LOG_MAX_BYTES  := 5 * 1024 * 1024

; 扩展窗口样式位
WS_EX_TRANSPARENT := 0x00000020
WS_EX_TOOLWINDOW  := 0x00000080
WS_EX_LAYERED     := 0x00080000

; 全局状态
global Buf := []                      ; 滚动缓冲
global suspectStreak := 0             ; 连续可疑计数
global attachReason := ""             ; 自动触发原因（附着期结束后落盘）

; ------------------------------------------------------------------
; 基础工具函数
; ------------------------------------------------------------------

; 当前时间戳（含毫秒）
NowStamp() {
    return FormatTime(, "yyyy-MM-dd HH:mm:ss") "." Format("{:03}", Mod(A_TickCount, 1000))
}

; 读取光标坐标（失败返回 false，坐标为 -1,-1）
CurPos(&x, &y) {
    pt := Buffer(8)
    if DllCall("GetCursorPos", "Ptr", pt) {
        x := NumGet(pt, 0, "Int"), y := NumGet(pt, 4, "Int")
        return true
    }
    x := -1, y := -1
    return false
}

; 窗口扩展样式位
WinExStyle(hwnd) {
    return DllCall("GetWindowLongPtr", "Ptr", hwnd, "Int", -20, "Ptr")
}

; 窗口所在进程名（取不到返回空）
WinProcName(hwnd) {
    pid := 0
    DllCall("GetWindowThreadProcessId", "Ptr", hwnd, "UInt*", &pid)
    if !pid
        return ""
    try return ProcessGetName(pid)
    return ""
}

; 窗口是否可见
WinVisible(hwnd) {
    return hwnd ? !!DllCall("IsWindowVisible", "Ptr", hwnd) : false
}

; 窗口矩形（失败返回 false）
WinRectOf(hwnd, &l, &t, &r, &b) {
    rc := Buffer(16)
    if DllCall("GetWindowRect", "Ptr", hwnd, "Ptr", rc) {
        l := NumGet(rc, 0, "Int"), t := NumGet(rc, 4, "Int")
        r := NumGet(rc, 8, "Int"), b := NumGet(rc, 12, "Int")
        return true
    }
    return false
}

; 全部显示器虚拟边界
VirtualBounds(&vx, &vy, &vw, &vh) {
    vx := DllCall("GetSystemMetrics", "Int", 76)   ; SM_XVIRTUALSCREEN
    vy := DllCall("GetSystemMetrics", "Int", 77)   ; SM_YVIRTUALSCREEN
    vw := DllCall("GetSystemMetrics", "Int", 78)   ; SM_CXVIRTUALSCREEN
    vh := DllCall("GetSystemMetrics", "Int", 79)   ; SM_CYVIRTUALSCREEN
}

; 用 SendMessageTimeout 安全取窗口标题（WM_GETTEXT 可因目标挂起而阻塞，
; 这里带 300ms 超时 + ABORTIFHUNG，绝不让探针自身的定时器被污染卡死）
WinTitleOf(hwnd) {
    static WM_GETTEXT := 0x000D, SMTO_ABORTIFHUNG := 0x0002
    if !hwnd
        return ""
    MAX := 512
    buf := Buffer((MAX + 1) * 2)
    res := 0                                    ; 必须先初始化，未赋值的局部变量作 OutRef 会抛错
    n := DllCall("SendMessageTimeoutW", "Ptr", hwnd, "UInt", WM_GETTEXT, "Ptr", MAX, "Ptr", buf
                , "UInt", SMTO_ABORTIFHUNG, "UInt", 300, "UInt*", &res, "Ptr")
    if !n
        return ""
    return StrGet(buf, "UTF-16")
}

; 简洁描述一个窗口（标题/类/进程/可见性/矩形），用于日志
DescribeWin(hwnd) {
    if !hwnd
        return "(无)"
    title := WinTitleOf(hwnd)                    ; 非阻塞取标题
    if title = ""
        title := "〈无标题〉"
    cls := "?"
    try cls := WinGetClass("ahk_id " hwnd)
    proc := WinProcName(hwnd)
    vis := WinVisible(hwnd) ? "可见" : "不可见"
    rc := ""
    if WinRectOf(hwnd, &l, &t, &r, &b)
        rc := " rect=(" l "," t ")-(" r "," b ") size=" (r - l) "x" (b - t)
    return Format("hwnd={:#x} title=[{}] class=[{}] proc=[{}] {}{}", hwnd, title, cls, proc, vis, rc)
}

; ------------------------------------------------------------------
; 可疑判定：铺满屏幕的「透明/分层遮罩型」窗口 —— 卡死的头号嫌疑
; 逻辑：非桌面 + WS_EX_LAYERED/TRANSPARENT + 覆盖虚拟屏面积 > 55% + 光标落在其内
; 普通全屏应用（游戏/视频）是非分层普通窗口，不会误判
; ------------------------------------------------------------------
IsSuspectOverlay(hwnd, cx, cy) {
    if !hwnd
        return false
    ex := WinExStyle(hwnd)
    if !(ex & (WS_EX_LAYERED | WS_EX_TRANSPARENT))
        return false
    VirtualBounds(&vx, &vy, &vw, &vh)
    if (vw * vh) <= 0
        return false
    if !WinRectOf(hwnd, &l, &t, &r, &b)
        return false
    ; 光标必须落在窗口矩形内（含负坐标显示器）
    if (cx < l || cx >= r || cy < t || cy >= b)
        return false
    cover := ((r - l) * (b - t)) / (vw * vh)
    if (cover < 0.55)
        return false
    cls := ""                               ; 先初始化，取不到时保底
    try cls := WinGetClass("ahk_id " hwnd)
    if cls = "" || InStr(cls, "Progman") || InStr(cls, "WorkerW")
        return false
    return true
}

; 采集一帧完整快照文本
BuildSnap(fReason) {
    CurPos(&cx, &cy)
    ts := NowStamp()
    fg := DllCall("GetForegroundWindow", "Ptr")
    cu := DllCall("WindowFromPoint", "Int", cx, "Int", cy, "Ptr")
    s := "· " ts " 原因=" fReason " 光标=(" cx "," cy ")"
    s .= "`n   前台: " DescribeWin(fg)
    s .= "`n   光标下: " DescribeWin(cu)
    ; 可疑遮罩详情
    for hw in [cu, fg] {
        if IsSuspectOverlay(hw, cx, cy)
            s .= "`n   <<可疑遮罩>> " DescribeWin(hw) " exstyle=0x" Format("{:X}", WinExStyle(hw))
    }
    return s
}

; 把滚动缓冲写盘（带触发标记 + 当前实时快照）
FlushLog(reason) {
    global Buf, LOG_FILE, LOG_MAX_BYTES
    ; 触发帧的实时快照（不入缓冲）
    cur := BuildSnap("flush@" reason)
    ; 超限清理
    try {
        if FileExist(LOG_FILE) && FileGetSize(LOG_FILE) > LOG_MAX_BYTES
            FileDelete(LOG_FILE)
    }
    body := ""
    for line in Buf
        body .= line "`n"
    out := NowStamp() " ===== FLUSH 原因=[" reason "] 前台=" Format("{:#x}", DllCall("GetForegroundWindow", "Ptr")) " =====" "`n"
    out .= cur "`n"
    out .= "---- 以下为触发前滚动缓冲回放（最旧→最新） ----`n" body
    out .= "===== END " NowStamp() " =====`n"
    try FileAppend out, LOG_FILE
}

; 自动触发：进入附着期，ATTACH_MS 后落盘（附着期帧会进缓冲，届时自然回放）
BeginAttach(reason) {
    global attachReason, ATTACH_MS
    attachReason := reason
    SetTimer AttachFlush, -ATTACH_MS
}

AttachFlush() {
    global attachReason
    FlushLog(attachReason)
}

; ------------------------------------------------------------------
; 每拍采样
; ------------------------------------------------------------------
SteadyTick() {
    global Buf, suspectStreak
    try {
        snap := BuildSnap("tick")
        Buf.Push(snap)
        while Buf.Length > BUFFER_N
            Buf.RemoveAt(1)
        ; 自动触发判定：光标下出现全屏透明遮罩连续多拍
        CurPos(&cx, &cy)
        cu := DllCall("WindowFromPoint", "Int", cx, "Int", cy, "Ptr")
        if IsSuspectOverlay(cu, cx, cy) {
            suspectStreak += 1
            if suspectStreak = SUSPECT_STREAK
                BeginAttach("auto 光标下出现全屏透明/分层遮罩")
        } else {
            suspectStreak := 0
        }
    } catch as e {
        ; 单拍异常不致命：写独立错误文件并继续采样，避免探针自身死掉
        try FileAppend NowStamp() " SteadyTick 异常: " e.Message " @" e.Line "`n", A_ScriptDir "\probe_error.log"
    }
}

; 心跳：确认探针自身存活（文件内容最新时间即最近一次运行）
Heartbeat() {
    global HEART_FILE
    try {
        if FileExist(HEART_FILE)         ; FileDelete 对不存在的文件会抛错，先判断
            FileDelete(HEART_FILE)
        FileAppend NowStamp() " alive`n", HEART_FILE
    } catch as e {
        ; 任一步失败都落盘，绝不静默
        try FileAppend NowStamp() " Heartbeat 异常: " e.Message " @" e.Line "`n", A_ScriptDir "\probe_error.log"
    }
}

; 退出时兜底落盘一轮
FlushOnExit(ExitReason, ExitCode) {
    FlushLog("exit:" ExitReason)
}

; 手动触发热键：Ctrl+Alt+Shift+Z（卡死时键盘可用，最可靠）
^!+z::FlushLog("manual-hotkey")

; ------------------------------------------------------------------
; 启动
; ------------------------------------------------------------------
OnExit(FlushOnExit)
try FileDelete(HEART_FILE)
; 启动标记：确认到达定时器循环
try FileAppend "start " NowStamp() "`n", A_ScriptDir "\probe_start.tmp"
SetTimer Heartbeat, 5000                ; 心跳
SetTimer SteadyTick, TICK_MS            ; 采样（首次 +200ms，确保先进入消息循环）