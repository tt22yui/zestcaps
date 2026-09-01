; ==================================================================
; 定时清空回收站 —— 每天固定时刻清空回收站中「删除时间超过 N 天」的项
; 清空策略「保留近期 N 天」：只物理删除 $R 数据项与对应 $I 元文件，
;   近 N 天内删除的文件（在回收站内可找回）保留不动。
; 状态/参数存 config.ini：
;   [Features]   RecycleBinEnabled  1=开 0=关
;   [RecycleBin] KeepDays 保留天数；Time 每日执行时刻(HH:mm)
; 实现依赖 Config.ahk（RecycleBinEnabled/RBKeepDays/RBTime）
;  与 DebugLog.ahk（DebugLog）
; ==================================================================

; 引用 Config.ahk 中定义的全局（顶层声明，避免单文件加载时报 UseUnsetGlobal；
; Main 按顺序加载时由 Config 生效值覆盖，此处不赋值所以不会破坏配置）
global RecycleBinEnabled, RBKeepDays, RBTime

; ----- 每日定时：一次性动态定时器，精确挂到下次执行时刻，触发后自动重新排程下一天 -----
; 平时脚本不轮询，仅在接近执行时刻前被唤醒一次，负载趋近于零
InitRecycleBinTimer() {
    global RecycleBinEnabled
    if !RecycleBinEnabled
        return
    ScheduleNextRecycle()
}

; 计算距下次「每日执行时刻」的毫秒数并注册一次性定时器
ScheduleNextRecycle() {
    global RBTime
    ; 构造今天的执行时刻（YYYYMMDDHHMMSS），若已过则推到明天
    target := FormatTime(, "yyyyMMdd") StrReplace(RBTime, ":") "00"
    if target <= A_Now
        target := DateAdd(target, 1, "Days")
    secs := DateDiff(target, A_Now, "Seconds")     ; 距执行还有多少秒
    SetTimer(RecycleBinFire, Max(secs * 1000, 1000))
}

; 定时器回调：先取消本次一次性定时，再清理，最后排下一轮
RecycleBinFire() {
    global RecycleBinEnabled
    SetTimer(RecycleBinFire, 0)                    ; 取消一次性定时（防止周期重复触发）
    if RecycleBinEnabled
        RecycleBinCleanup()
    if RecycleBinEnabled
        ScheduleNextRecycle()                      ; 重新排程下一天
}

; ----- 清空回收站中超过保留天数的项，返回本次删除项数 -----
; 实现：Shell.Application 枚举回收站 → 取每项物理 $R 路径构造 $I 元文件路径 →
;     以 $I 元文件修改时间作为删除时间，与「N 天前」阈值比对 → 超期则物理删除 $R 与 $I
RecycleBinCleanup() {
    global RBKeepDays
    if RBKeepDays <= 0
        return 0
    try {
        shell := ComObject("Shell.Application")
        recycle := shell.Namespace(10)       ; 10 = 回收站（sftphFOLDERID_RecycleBin）
        cut := DateAdd(A_Now, -RBKeepDays, "Days")   ; 本地时间阈值
        nDeleted := 0
        for item in recycle.Items() {
            rPath := item.Path
            splitP := StrSplit(rPath, "\")
            if splitP.Length < 2
                continue
            base := splitP[splitP.Length]
            if !RegExMatch(base, "^\$R")     ; 跳过非 $R 隐藏项（理论不会出现）
                continue
            dir := SubStr(rPath, 1, StrLen(rPath) - StrLen(base))
            iPath := dir StrReplace(base, "$R", "$I")   ; 对应 $I 元文件
            delTime := FileGetTime(iPath, "M")   ; 删除时间存于 $I 元文件修改时间（本地）
            if delTime = "" || delTime >= cut
                continue                       ; 缺 $I 或仍在保留期内 → 跳过
            if SafeRecycleDelete(rPath, iPath)
                nDeleted++
        }
        DebugLog("回收站: 保留近 " RBKeepDays " 天，本次清理删除 " nDeleted " 项")
        return nDeleted
    } catch as err {
        DebugLog("回收站: 清理出错 - " err.Message)
        return 0
    }
}

; 物理删除回收站中的 $R 数据项及其 $I 元文件
; 经 SHFileOperationW（Shell 标准通道）静默永久删除，比直接 FileDelete 更符合系统惯例，
; 且文件夹项由 Shell 递归处理，无需区分文件/文件夹
SafeRecycleDelete(RPath, IPath) {
    paths := []
    if FileExist(RPath)
        paths.Push(RPath)
    if FileExist(IPath)
        paths.Push(IPath)
    if paths.Length = 0
        return false
    return ShRecycleDelete(paths)
}

; 调用 SHFileOperationW 静默永久删除给定物理路径列表
; pFrom 为双 null 结尾的多路径列表（FO_DELETE | SILENT | NOCONFIRMATION | NOERRORUI）
ShRecycleDelete(paths) {
    try {
        p := ""
        for path in paths
            p .= path Chr(0)
        pFrom := Buffer((StrLen(p) + 1) * 2)   ; 内容 + 结尾 null → 双 null 结束
        StrPut(p, pFrom, "UTF-16")
        ; 按架构填充 SHFILEOPSTRUCTW：wFunc/pFrom/fFlags 偏移在 x86 与 x64 下不同
        fop := Buffer(64, 0)
        if A_PtrSize = 8 {                     ; x64：hwnd(8) wFunc(8) pFrom(16) pTo(24) fFlags(32)
            NumPut("UInt", 0x0003, fop, 8)     ; wFunc = FO_DELETE
            NumPut("Ptr", pFrom.Ptr, fop, 16)
            NumPut("UInt", 0x0004 | 0x0010 | 0x0040, fop, 32)   ; SILENT|NOCONFIRMATION|NOERRORUI
        } else {                               ; x86：hwnd(4) wFunc(4) pFrom(8) pTo(12) fFlags(16)
            NumPut("UInt", 0x0003, fop, 4)
            NumPut("Ptr", pFrom.Ptr, fop, 8)
            NumPut("UInt", 0x0004 | 0x0010 | 0x0040, fop, 16)
        }
        return DllCall("shell32\SHFileOperationW", "Ptr", fop, "UInt") = 0
    } catch as err {
        DebugLog("回收站: SHFileOperationW 调用失败 - " err.Message)
        return false
    }
}

; 启动时按配置初始化定时
InitRecycleBinTimer()
