; ==================================================================
; Updater —— GitHub Releases 自动更新（仅编译 exe 生效）
; 原理：异步请求 GitHub Releases API 获取最新版本号与下载地址，
;       用 VerCompare 与本地 APP_VERSION 比较；发现新版本经弹窗确认后，
;       下载新 exe 并校验 SHA256，再用 cmd 延迟替换同名 exe 并启动新实例。
; 入口：设置窗口「关于」页签「检查更新」按钮（见 Settings.ahk）
; 关键点：
;   - 仅 A_IsCompiled 时生效；源码运行直接跳过
;   - 网络请求用 MSXML2.ServerXMLHTTP 异步发起，定时器轮询 ReadyState
;   - 运行中的 exe 无法自我覆盖，必须退出后由 cmd 延时替换并重启
; ==================================================================

; 检查更新请求状态（全局，供定时器/回调跨调用访问）
UpdaterReqDone  := false     ; 请求是否已完成（防止重复处理）
UpdaterOnReady  := ""        ; 完成后的回调函数（存储后调用）
UpdaterReq      := ""        ; 当前请求对象
UpdaterPollTimer := 0        ; 轮询定时器句柄
UpdaterTimeoutTimer := 0     ; 超时看门狗定时器句柄

; ------------------------------------------------------------------
; 异步检查是否有新版本（核心入口）
; onResult(result)：请求完成后回调，result 为 Map：
;   latestVersion / needUpdate / latestTag / exeUrl / shaUrl
;   失败时含 error 字段。请求一律不阻塞；调用方不弹错误，仅记录。
; ------------------------------------------------------------------
CheckForUpdateAsync(onResult) {
    global APP_GITHUB_API_URL, APP_VERSION
    if !A_IsCompiled {
        ; 源码模式不支持自动替换，直接返回"与当前版本一致"
        onResult(NewUpdateResult("", APP_VERSION, false))
        return
    }
    UpdaterStartRequest(APP_GITHUB_API_URL, onResult)
}

; 构造统一的结果 Map
NewUpdateResult(latestVersion, currentVersion, needUpdate) {
    m := Map()
    m["latestVersion"] := latestVersion
    m["currentVersion"] := currentVersion
    m["needUpdate"] := needUpdate
    m["error"] := ""
    return m
}

; ------------------------------------------------------------------
; 发起一次 ServerXMLHTTP 异步请求，用定时器轮询 ReadyState
; （比直接绑定 onreadystatechange 事件更可控，规避 AHK v2 的 COM 事件陷阱）
; ------------------------------------------------------------------
UpdaterStartRequest(url, onResult) {
    global UpdaterReqDone, UpdaterOnReady, UpdaterReq
    global UpdaterPollTimer, UpdaterTimeoutTimer
    UpdaterReqDone := false
    UpdaterOnReady := onResult
    UpdaterReq := ""
    try {
        req := ComObject("MSXML2.ServerXMLHTTP")
        req.Open("GET", url, true)     ; true = 异步
        req.Send()
        UpdaterReq := req
        ; 轮询（100ms）+ 整体超时看门狗（15s）
        UpdaterPollTimer := SetTimer(UpdaterPoll, 100)
        UpdaterTimeoutTimer := SetTimer(UpdaterTimeout, -15000)
    } catch as err {
        UpdaterReqDone := true
        UpdaterOnReady := ""
        r := NewUpdateResult("", "", false)
        r["error"] := "发起请求失败：" err.Message
        onResult(r)
    }
}

; 轮询请求就绪状态（每 100ms 触发）
UpdaterPoll() {
    global UpdaterReqDone, UpdaterReq, UpdaterPollTimer
    if UpdaterReqDone
        return
    if !UpdaterReq
        return
    if UpdaterReq.ReadyState >= 4 {
        SetTimer(UpdaterPoll, 0)
        UpdaterPollTimer := 0
        UpdaterFinishRequest(UpdaterReq)
        UpdaterReq := ""
    }
}

; 请求超时看门狗
UpdaterTimeout() {
    global UpdaterReqDone, UpdaterOnReady, UpdaterPollTimer
    if UpdaterReqDone
        return
    SetTimer UpdaterPoll, 0
    UpdaterPollTimer := 0
    handleUpdaterTimeoutCallback(UpdaterOnReady)
    UpdaterReqDone := true
    UpdaterOnReady := ""
}

; 超时后回调调用（单独封装，避免在定时器回调里直接调用闭包/函数时的作用域歧义）
handleUpdaterTimeoutCallback(onResult) {
    if !IsSet(onResult) || !onResult
        return
    r := NewUpdateResult("", "", false)
    r["error"] := "请求超时"
    onResult(r)
}

; ------------------------------------------------------------------
; 处理请求完成：解析响应并按版本比较设置 needUpdate，最后调用回调
; ------------------------------------------------------------------
UpdaterFinishRequest(req) {
    global UpdaterReqDone, UpdaterOnReady, APP_VERSION
    if UpdaterReqDone
        return
    UpdaterReqDone := true
    onResult := UpdaterOnReady
    UpdaterOnReady := ""
    result := NewUpdateResult("", APP_VERSION, false)
    if (req.Status != 200) {
        result["error"] := "HTTP " req.Status
        if IsSet(onResult)
            onResult(result)
        return
    }
    ParseGithubRelease(req.ResponseText, &result)
    latest := result["latestVersion"]
    if latest != "" {
        ; VerCompare 返回正数表示远程较新（需要更新）
        result["needUpdate"] := VerCompare(latest, APP_VERSION) > 0
    } else {
        result["error"] := "无法解析最新版本"
    }
    if IsSet(onResult)
        onResult(result)
}

; ------------------------------------------------------------------
; 解析 GitHub Releases API JSON：提取 tag_name(去 v 前缀) 与首个 .exe 下载地址
; 结果写入 result(Map)：latestTag / latestVersion / exeUrl / shaUrl
; ------------------------------------------------------------------
ParseGithubRelease(json, &result) {
    if RegExMatch(json, '"tag_name"\s*:\s*"([^"]+)"', &m) {
        result["latestTag"] := m[1]
        ; 只去掉可能存在的 v 前缀，不能无条件截首字符：tag "0.4.0" 会被截成 ".4.0" 导致版本比较错乱
        ; （CI 目前只发 v* 标签，属隐患防御；口径与 .github\workflows\build.yml 的 `-replace '^v',''` 一致）
        result["latestVersion"] := RegExReplace(m[1], "(?i)^v", "")
    }
    pos := 1
    while RegExMatch(json, '"browser_download_url"\s*:\s*"([^"]+)"', &mu, pos) {
        url := mu[1]
        if InStr(url, ".exe") && !InStr(url, ".sha256") {
            result["exeUrl"] := url
            result["shaUrl"] := url ".sha256"
            break
        }
        pos := mu.Pos(1) + mu.Len(1)
    }
}

; ------------------------------------------------------------------
; 下载新 exe(+sha256) → SHA256 校验 → cmd 延迟替换并重启
; 返回 true 表示已进入替换流程；false 表示下载/校验失败
; ------------------------------------------------------------------
DownloadAndReplace(exeUrl, shaUrl) {
    global APP_VERSION
    SplitPath(A_AhkPath, , &exeDir)
    tmpDir := A_Temp "\zestcaps_upd_" A_TickCount
    try DirCreate(tmpDir)
    newExe := tmpDir "\zestcaps_new_v" APP_VERSION ".exe"
    newSha := tmpDir "\zestcaps_new_v" APP_VERSION ".exe.sha256"
    ; 看门狗：下载+校验全程 30s 超时保护
    SetTimer(UpdaterDlTimeout, -30000)
    try {
        TrayTip "正在下载更新...", "ZestCaps", 1
        Download(exeUrl, newExe)
        Download(shaUrl, newSha)
        ; SHA256 校验（若 sha256 文件存在且可读）
        remoteHash := ReadFirstHash(newSha)
        if remoteHash != "" {
            localHash := SHA256Hex(newExe)
            if StrLower(remoteHash) = StrLower(localHash) {
                TrayTip "下载完成，即将替换并重启。", "ZestCaps", 1
            } else {
                TrayTip "校验失败：下载文件与发布不一致，已中止更新。", "ZestCaps", 3
                try DirDelete(tmpDir, true)
                SetTimer(UpdaterDlTimeout, 0)   ; 失败退场前必须取消看门狗，否则 30s 后会被超时回调 ExitApp
                return false
            }
        } else {
            TrayTip "下载完成，即将替换并重启。", "ZestCaps", 1
        }
    } catch as err {
        TrayTip "下载失败：" err.Message, "ZestCaps", 3
        try DirDelete(tmpDir, true)
        SetTimer(UpdaterDlTimeout, 0)   ; 同上：失败退场前取消看门狗
        return false
    }
    SetTimer(UpdaterDlTimeout, 0)   ; 取消看门狗（已到最后一步）
    ; 隐藏托盘图标防止退场残留
    A_IconHidden := true
    self := A_AhkPath
    ; cmd 延迟替换：ping 延时约 2 秒等旧进程退出 → 用下载的新 exe 覆盖自身 → 启动新实例
    cmd := 'cmd /c ping -n 3 127.0.0.1 >nul & if exist "' newExe '" move /y "' newExe '" "' self '" & start "" "' self '"'
    try {
        Run(cmd, exeDir, "Hide")
    } catch as err {
        TrayTip "启动更新失败：" err.Message, "ZestCaps", 3
        try DirDelete(tmpDir, true)
        return false
    }
    ExitApp 0
}

; 下载/校验看门狗
UpdaterDlTimeout() {
    TrayTip "更新下载超时，已中止。", "ZestCaps", 3
    ExitApp
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
        DllCall("advapi32\CryptDestroyHash", "Ptr", hHash)
        DllCall("advapi32\CryptReleaseContext", "Ptr", hProv, "UInt", 0)
    }
}
; ==================================================================