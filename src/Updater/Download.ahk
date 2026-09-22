; ==================================================================
; Updater 子模块：下载新 exe(+sha256) → SHA256 校验 → cmd 延迟替换并重启
; （含下载看门狗与 SHA256 计算；由 Updater.ahk #Include，纯搬运、零逻辑变更）
; ==================================================================

; ------------------------------------------------------------------
; 下载新 exe(+sha256) → SHA256 校验 → cmd 延迟替换并重启（全程异步，不阻塞脚本线程）
; onStatus：可选，界面状态回调（形如 msg => ...），用于把进度/失败原因回写界面；
;           不给则只有 TrayTip
; onDone：可选，结束回调 onDone(ok)；成功路径会 ExitApp 重启，通常只有失败才会触发
; 说明：改用异步 ServerXMLHTTP + 定时器轮询（与「检查更新」同一套路），
;       使 30s 看门狗定时器能在下载/网络卡住时真正触发——原实现用内置 Download()
;       同步阻塞，卡住时整个脚本线程停住，看门狗根本无从触发（形同虚设）。
; ------------------------------------------------------------------
DownloadAndReplace(exeUrl, shaUrl, onStatus := 0, onDone := 0) {
    global APP_VERSION, UpdaterDlOnStatus, UpdaterDlOnDone, UpdaterDlActive
    global UpdaterDlTmpDir, UpdaterDlNewExe, UpdaterDlNewSha, UpdaterDlShaUrl
    if UpdaterDlActive
        return  ; 防重入：已有下载进行中
    DebugLog("更新: 开始下载更新包 " exeUrl)
    tmpDir := A_Temp "\zestcaps_upd_" A_TickCount
    try DirCreate(tmpDir)
    UpdaterDlTmpDir := tmpDir
    UpdaterDlNewExe := tmpDir "\zestcaps_new_v" APP_VERSION ".exe"
    UpdaterDlNewSha := tmpDir "\zestcaps_new_v" APP_VERSION ".exe.sha256"
    UpdaterDlShaUrl := shaUrl
    UpdaterDlOnStatus := onStatus
    UpdaterDlOnDone := onDone
    UpdaterDlActive := true
    ; 看门狗：下载 + 校验全程 30s（异步下载期间脚本线程空闲，定时器可正常触发）
    SetTimer(UpdaterDlTimeout, -30000)
    UpdaterReportStatus(onStatus, "正在下载更新…", 1)
    _UpdaterDlStart(exeUrl, UpdaterDlNewExe)
}

; 发起单个文件的异步下载；完成后由 UpdaterDlPoll 写入文件并衔接下一步（exe → sha → 校验替换）
_UpdaterDlStart(url, targetFile) {
    global APP_VERSION, UpdaterDlReq, UpdaterDlFile, UpdaterDlPollTimer
    UpdaterDlFile := targetFile
    try {
        req := ComObject("MSXML2.ServerXMLHTTP")
        req.Open("GET", url, true)     ; true = 异步
        ; GitHub 对缺少 User-Agent 的请求会 403；显式带上（与检查请求一致）
        req.setRequestHeader("User-Agent", "ZestCaps/" APP_VERSION)
        ; 显式超时（解析/连接/发送/接收，毫秒）：从源头约束单次请求，与看门狗双保险
        req.setTimeouts(10000, 10000, 10000, 20000)
        req.Send()
        UpdaterDlReq := req
        UpdaterDlPollTimer := SetTimer(UpdaterDlPoll, 100)
    } catch as err {
        _UpdaterDlFail("更新失败：发起下载失败（" err.Message "）")
    }
}

; 轮询下载请求就绪状态（每 100ms）：就绪后把响应体写入文件，再继续下一个文件
UpdaterDlPoll() {
    global UpdaterDlReq, UpdaterDlFile, UpdaterDlPollTimer
    global UpdaterDlNewExe, UpdaterDlNewSha, UpdaterDlShaUrl
    if !UpdaterDlReq
        return
    if UpdaterDlReq.ReadyState < 4
        return
    req := UpdaterDlReq
    SetTimer(UpdaterDlPoll, 0)
    UpdaterDlPollTimer := 0
    UpdaterDlReq := ""
    status := 0
    try status := req.Status
    catch
        status := 0
    if (status != 200) {
        ; exe 下载失败 → 整次失败；sha256 失败（含 404/网络错误）→ 视为发布未附带，跳过校验继续
        if (UpdaterDlFile = UpdaterDlNewExe) {
            _UpdaterDlFail("更新失败：下载新版本文件失败（HTTP " status "）")
        } else {
            DebugLog("更新: sha256 下载失败（HTTP " status "），跳过校验继续")
            _UpdaterDlFinalize()
        }
        return
    }
    try {
        ; 二进制写盘：ADODB.Stream 直接接收 XMLHTTP 的 ResponseBody（SafeArray）
        s := ComObject("ADODB.Stream")
        s.Type := 1                      ; adTypeBinary
        s.Open()
        s.Write(req.ResponseBody)
        s.SaveToFile(UpdaterDlFile, 2)   ; adSaveCreateOverWrite
        s.Close()
    } catch as err {
        _UpdaterDlFail("更新失败：写入下载文件失败（" err.Message "）")
        return
    }
    ; 依次下载：exe 完成 → 下载 sha256；sha256 完成 → 校验 + 替换
    if (UpdaterDlFile = UpdaterDlNewExe)
        _UpdaterDlStart(UpdaterDlShaUrl, UpdaterDlNewSha)
    else
        _UpdaterDlFinalize()
}

; 两个文件下载完成：校验 SHA256（若发布附带）→ 用 cmd 延迟替换并重启
_UpdaterDlFinalize() {
    global UpdaterDlNewExe, UpdaterDlNewSha, UpdaterDlOnStatus, UpdaterDlOnDone, UpdaterDlActive
    SetTimer(UpdaterDlTimeout, 0)   ; 下载完成，取消看门狗
    ; SHA256 校验（若 sha256 文件存在且可读）
    remoteHash := ReadFirstHash(UpdaterDlNewSha)
    if remoteHash != "" {
        localHash := SHA256Hex(UpdaterDlNewExe)
        if (StrLower(remoteHash) != StrLower(localHash)) {
            DebugLog("更新: SHA256 校验失败（远端 " remoteHash " / 本地 " localHash "）")
            _UpdaterDlFail("更新失败：下载文件与发布校验值不一致，已中止（可稍后重试）")
            return
        }
        DebugLog("更新: 下载完成且 SHA256 校验通过")
    } else {
        DebugLog("更新: 未取得 sha256（发布可能未附带），跳过校验")
    }
    UpdaterReportStatus(UpdaterDlOnStatus, "下载完成，即将替换并重启…", 1)
    ; 隐藏托盘图标防止退场残留
    A_IconHidden := true
    self := A_AhkPath    ; 实测：编译版下 A_AhkPath 即自身 exe 路径（见 test 报告）
    SplitPath(self, , &exeDir)
    ; cmd 延迟替换：ping 延时约 2 秒等旧进程退出 → 用下载的新 exe 覆盖自身 → 启动新实例
    cmd := 'cmd /c ping -n 3 127.0.0.1 >nul & if exist "' UpdaterDlNewExe '" move /y "' UpdaterDlNewExe '" "' self '" & start "" "' self '"'
    DebugLog("更新: 执行替换并重启 -> " cmd)
    try Run(cmd, exeDir, "Hide")
    catch as err {
        _UpdaterDlFail("更新失败：无法启动替换进程（" err.Message "）")
        return
    }
    UpdaterDlActive := false
    UpdaterDlOnStatus := 0
    UpdaterDlOnDone := 0
    ExitApp 0
}

; 下载/校验失败或超时：停定时器、清临时目录、回报界面与结束回调
; 不再 ExitApp——失败可被用户感知并稍后重试（原实现只能退出应用）
_UpdaterDlFail(msg) {
    global UpdaterDlOnStatus, UpdaterDlOnDone, UpdaterDlActive
    global UpdaterDlReq, UpdaterDlPollTimer, UpdaterDlTmpDir
    SetTimer(UpdaterDlTimeout, 0)
    SetTimer(UpdaterDlPoll, 0)
    UpdaterDlPollTimer := 0
    UpdaterDlReq := ""
    UpdaterDlActive := false
    DebugLog("更新: " msg)
    _UpdaterDlCleanupTmp()
    cb := UpdaterDlOnDone
    UpdaterReportStatus(UpdaterDlOnStatus, msg, 3)
    UpdaterDlOnStatus := 0
    UpdaterDlOnDone := 0
    if IsObject(cb)
        cb.Call(false)
}

; 清理本次下载的临时目录（幂等）
_UpdaterDlCleanupTmp() {
    global UpdaterDlTmpDir
    if (UpdaterDlTmpDir != "") {
        try DirDelete(UpdaterDlTmpDir, true)
        UpdaterDlTmpDir := ""
    }
}

; 回报更新阶段状态：优先回写界面（onStatus 回调），同时保留 TrayTip 便于托盘场景
UpdaterReportStatus(onStatus, msg, icon := 1) {
    if IsObject(onStatus)
        try onStatus.Call(msg)
    TrayTip msg, "ZestCaps", icon
}

; 下载/校验看门狗（30s）
; 现在下载是异步的：定时器可在下载/网络卡住时真正触发，中止下载并让用户重试（不再只能 ExitApp）
UpdaterDlTimeout() {
    global UpdaterDlActive, UpdaterDlReq, UpdaterDlPollTimer
    if !UpdaterDlActive
        return
    SetTimer(UpdaterDlPoll, 0)
    UpdaterDlPollTimer := 0
    UpdaterDlReq := ""   ; 释放请求对象，停止后续回调
    _UpdaterDlFail("更新超时已中止：网络较慢或下载被拦截，请稍后重试。")
}

; ------------------------------------------------------------------
; 读取发布附带的 sha256 文件首行哈希（格式 "hash  filename"）
; 空文件 / 空行返回 ""（原实现直接取 StrSplit 结果第 1 项，空文件会抛 Invalid index，
; 被下载失败分支吞成「下载失败」提示，误导排查）；
; 首个字段按任意空白切分，兼容多空格与 TAB 分隔（原实现按单个空格切分会把文件名并进哈希）
; ------------------------------------------------------------------
ReadFirstHash(shaFile) {
    if !FileExist(shaFile)
        return ""
    raw := FileRead(shaFile, "UTF-8-RAW")
    if (Trim(raw, " `t`r`n") = "")
        return ""
    firstLine := Trim(StrSplit(StrReplace(raw, "`r`n", "`n"), "`n")[1], " `t`r`n")
    if RegExMatch(firstLine, "^\s*(\S+)", &m)
        return m[1]
    return ""
}

; ------------------------------------------------------------------
; 计算文件 SHA256 十六进制串（Cryptography API）
; ------------------------------------------------------------------
SHA256Hex(file) {
    static CALG_SHA256 := 0x800C, HP_HASHVAL := 2
    data := FileRead(file, "RAW")
    hProv := 0, hHash := 0
    try {
        if !DllCall("advapi32\CryptAcquireContext", "Ptr*", &hProv, "Ptr", 0, "Ptr", 0, "UInt", 0x18, "UInt", 0xF0000000)
            return ""
        if !DllCall("advapi32\CryptCreateHash", "Ptr", hProv, "UInt", CALG_SHA256, "UInt", 0, "UInt", 0, "Ptr*", &hHash)
            return ""
        if !DllCall("advapi32\CryptHashData", "Ptr", hHash, "Ptr", data, "UInt", data.Size, "UInt", 0)
            return ""
        cb := 0
        DllCall("advapi32\CryptGetHashParam", "Ptr", hHash, "UInt", HP_HASHVAL, "Ptr", 0, "UInt*", &cb, "UInt", 0)
        buf := Buffer(cb)
        DllCall("advapi32\CryptGetHashParam", "Ptr", hHash, "UInt", HP_HASHVAL, "Ptr", buf, "UInt*", &cb, "UInt", 0)
        hex := ""
        loop cb
            hex .= Format("{:02x}", NumGet(buf, A_Index - 1, "UChar"))
        return hex
    } finally {
        ; 仅释放「已成功创建」的句柄：CryptAcquireContext 失败时 hProv=0、CryptCreateHash
        ; 失败时 hHash=0，对 0 句柄调用 Destroy/Release 属无效操作（须判空后再调）
        if hHash
            DllCall("advapi32\CryptDestroyHash", "Ptr", hHash)
        if hProv
            DllCall("advapi32\CryptReleaseContext", "Ptr", hProv, "UInt", 0)
    }
}
; ==================================================================
