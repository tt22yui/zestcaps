; ==================================================================
; Screenshot 选区子模块：WindowFind（由 Screenshot.ahk 机械拆分，仅搬运、逻辑不变）
; ==================================================================

; 获取鼠标下的窗口区域（跳过蒙版/边框/拦截层；桌面则返回整个显示器）
GetWindowRegionFromMouse(region) {
    global ScreenshotMaskHwnds, ScreenshotSelHwnd, ScreenshotBorderHwnds
    MouseGetPos &mx, &my, &overWin, , 2
    ; 蒙版/边框/拦截层置顶会挡住鼠标检测，命中它们时改为取 z-order 下层的真实窗口
    if (overWin = ScreenshotSelHwnd) {
        overWin := GetWindowBelowPoint(mx, my, _BuildOverlaySkipSet())
    } else {
        for h in ScreenshotMaskHwnds {
            if (overWin = h) {
                overWin := GetWindowBelowPoint(mx, my, _BuildOverlaySkipSet())
                break
            }
        }
        if overWin {
            for h in ScreenshotBorderHwnds {
                if (overWin = h) {
                    overWin := GetWindowBelowPoint(mx, my, _BuildOverlaySkipSet())
                    break
                }
            }
        }
    }
    if overWin {
        ; overWin 来自刚枚举的窗口，仍可能在枚举与查询之间消失（AHK v2 抛 TargetError，
        ; 而本函数跑在 10ms 悬停定时器里）→ 兜底按「非桌面」处理，不中断截图会话
        cls := ""
        try cls := WinGetClass("ahk_id " overWin)
        if (cls = "WorkerW" || cls = "Progman")
            overWin := 0  ; 桌面
    }
    if overWin {
        region.SetWinID(overWin)
    } else {
        idx := MonitorIndexAt(mx, my)
        MonitorGet(idx, &ml, &mt, &mr, &mb)
        region.SetRegionByPos(ml, mt, mr, mb)
    }
}

; 构造本次截图覆盖层（蒙版 + 边框 4 条 + 拦截层）的 hwnd 跳过集合
_BuildOverlaySkipSet() {
    global ScreenshotMaskHwnds, ScreenshotSelHwnd, ScreenshotBorderHwnds
    skip := Map()
    for h in ScreenshotMaskHwnds
        skip[h] := true
    for h in ScreenshotBorderHwnds
        skip[h] := true
    skip[ScreenshotSelHwnd] := true
    return skip
}

; 屏幕坐标下最顶层的真实窗口（跳过蒙版/边框/拦截层，按 z-order 从上往下找矩形包含该点的可见顶层窗口）
; 说明：GetWindow 的 GW_HWNDNEXT 只遍历同类型窗口，置顶链末尾返回 NULL 无法进入普通窗口，
;       因此改用 EnumWindows 枚举全部顶层窗口（按 z-order 从上到下回调），命中即返回。
GetWindowBelowPoint(mx, my, skipSet) {
    r := Buffer(16)
    found := 0
    ; 闭包回调：命中第一个（z-order 最上）矩形包含该点且非跳过的可见窗口后停止枚举
    EnumWinFn(h) {
        if skipSet.Has(h)
            return true
        if !DllCall("IsWindowVisible", "Ptr", h)
            return true
        if !DllCall("GetWindowRect", "Ptr", h, "Ptr", r.Ptr)
            return true
        l := NumGet(r, 0, "Int"), t := NumGet(r, 4, "Int")
        rt := NumGet(r, 8, "Int"), b := NumGet(r, 12, "Int")
        if (mx >= l && mx < rt && my >= t && my < b) {
            found := h
            return false  ; 停止枚举
        }
        return true
    }
    cb := CallbackCreate(EnumWinFn)
    DllCall("EnumWindows", "Ptr", cb, "Ptr", 0)
    CallbackFree(cb)
    return found
}
