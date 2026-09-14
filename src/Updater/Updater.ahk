; ==================================================================
; Updater —— GitHub Releases 自动更新（仅编译 exe 生效）
; 原理：异步请求 GitHub Releases API 获取最新版本号与下载地址，
;       用 VerCompare 与本地 APP_VERSION 比较；发现新版本后登记为"待下载"，
;       由设置窗口「下载并更新 vX.Y.Z」按钮或启动弹窗确认后下载新 exe 并校验 SHA256，
;       再用 cmd 延迟替换同名 exe 并启动新实例。
; 入口：设置窗口「关于」页签「检查更新」按钮（见 Settings.ahk）；
;       启动时自动检查（编译版 + 设置开关开启时生效，见 InitStartupUpdateCheck）
; 关键点：
;   - 仅 A_IsCompiled 时生效；源码运行直接跳过
;   - 网络请求用 MSXML2.ServerXMLHTTP 异步发起，定时器轮询 ReadyState
;   - 运行中的 exe 无法自我覆盖，必须退出后由 cmd 延时替换并重启
;   - 全程写 DebugLog（更新不生效时的排查依据），下载阶段的状态/失败原因经 onStatus 回报界面
; ==================================================================

; 检查更新请求状态（全局，供定时器/回调跨调用访问）
UpdaterReqDone  := false     ; 请求是否已完成（防止重复处理）
UpdaterOnReady  := ""        ; 完成后的回调函数（存储后调用）
UpdaterReq      := ""        ; 当前请求对象
UpdaterPollTimer := 0        ; 轮询定时器句柄
UpdaterTimeoutTimer := 0     ; 超时看门狗定时器句柄
UpdaterDlOnStatus := 0       ; 下载阶段界面状态回调（供超时看门狗也能回报，见 DownloadAndReplace）
; 已发现、待下载的更新（Map：version / exeUrl / shaUrl）；为空表示当前没有可下载的新版本
; 用途：启动检查发现新版本后即写入，设置窗口据此就地提供「下载并更新 vX.Y.Z」按钮，
;       避免"只能靠一个模态弹窗下载"（弹窗被关掉或显示失败就没有任何下载入口）
PendingUpdate := ""

; ------------------------------------------------------------------
; 记录待下载的更新信息（version / exeUrl / shaUrl）
; ------------------------------------------------------------------
SetPendingUpdate(version, exeUrl, shaUrl) {
    global PendingUpdate
    PendingUpdate := Map("version", version, "exeUrl", exeUrl, "shaUrl", shaUrl)
}

; 清除待下载状态（无更新可下载时调用）
ClearPendingUpdate() {
    global PendingUpdate
    PendingUpdate := ""
}

; 是否有待下载的更新
HasPendingUpdate() {
    global PendingUpdate
    return PendingUpdate is Map
}

; 取待下载更新的字段（version / exeUrl / shaUrl）；无待下载更新或字段缺失时返回 ""
; 注：Map[key] 对**缺失键会抛 "Item has no value."**（探针实测，并非返回空串），故必须用 Get 兜底
PendingUpdateField(key) {
    global PendingUpdate
    return (PendingUpdate is Map) ? PendingUpdate.Get(key, "") : ""
}

; 读取检查结果 Map 的字段；exeUrl / shaUrl 仅在发布附带 exe 资源时才存在，
; 直接写 result["exeUrl"] 取缺失键会抛 "Item has no value."，再被全局错误处理器静默吞掉
; （表现为"有新版本却毫无反应"）——故统一走本函数兜底
UpdateResultField(result, key) {
    return result.Has(key) ? result[key] : ""
}

; 更新按钮该显示的文字（纯函数，便于单测）
; 注：不含 A_IsCompiled 判断——源码模式由界面层决定是否按此显示
UpdateButtonLabel() {
    return HasPendingUpdate() ? "下载并更新 v" PendingUpdateField("version") : "检查更新"
}

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

; ------------------------------------------------------------------
; 启动时自动检查更新（仅编译版 + 「设置 → 关于」开关开启时生效）
; 由 Main.ahk 在脚本加载完成后调用 InitStartupUpdateCheck()：
;   - 延迟 1.5 秒触发，避开启动流程（检查本身异步，不阻塞、不卡启动）
;   - 静默检查：失败/已最新都不打扰用户；发现新版本才弹窗询问是否立即更新
;   - 关闭方式：设置 → 关于 → 取消「启动时自动检查更新」
; ------------------------------------------------------------------
InitStartupUpdateCheck() {
    global AutoUpdateEnabled
    if !A_IsCompiled {
        return                                  ; 源码运行不支持自动替换（与手动检查一致）
    }
    if !AutoUpdateEnabled {
        DebugLog("更新: 启动自动检查已关闭（设置 → 关于）")
        return
    }
    SetTimer(StartupUpdateCheck, -1500)
}

StartupUpdateCheck() {
    global APP_VERSION
    DebugLog("更新: 启动自动检查开始（当前 v" APP_VERSION "）")
    CheckForUpdateAsync(StartupUpdateCheckDone)
}

; 启动检查结果：失败静默（不打扰启动），有新版才弹窗询问
StartupUpdateCheckDone(result) {
    global APP_VERSION
    if result["error"] != "" {
        DebugLog("更新: 启动检查失败（静默忽略）- " result["error"])
        return
    }
    if !result["needUpdate"] {
        DebugLog("更新: 已是最新版本 v" APP_VERSION)
        return
    }
    newVer := result["latestVersion"]
    exeUrl := UpdateResultField(result, "exeUrl")
    if exeUrl = "" {
        DebugLog("更新: 发现 v" newVer "，但该发布未附带 exe 下载地址")
        return
    }
    shaUrl := UpdateResultField(result, "shaUrl")
    ; 先登记待下载状态：即使下面的弹窗被关掉或显示失败，设置窗口里仍有「下载并更新」按钮可用
    SetPendingUpdate(newVer, exeUrl, shaUrl)
    DebugLog("更新: 发现新版本 v" newVer "，弹窗询问是否立即更新")
    answer := ""
    ; ⚠️ 选项串必须是 AHK 认得的写法：MsgBox 遇到非法选项会抛 "Invalid option."，而
    ;    GlobalError.ahk 的 OnError 处理器 return 1 会把异常吞掉（只写日志、不弹错误框），
    ;    表现为「提示有新版本之后毫无反应」。曾把图标选项误写成 IconQuestion（正确为 Icon?）
    ;    导致更新弹窗长期静默失效。外面再套一层 try：万一弹窗构造失败也只是少个提示，
    ;    流程不中断——待下载状态已登记，用户仍可在设置窗口点「下载并更新」。
    try {
        answer := MsgBox("发现新版本 v" newVer "（当前 v" APP_VERSION "）`n`n是否立即下载并更新？更新完成后程序会自动重启。`n`n（也可稍后在「设置 → 关于」里手动更新，该页可关闭启动检查）", "ZestCaps 更新", "YesNo Icon?")
    } catch as err {
        DebugLog("更新: 启动更新弹窗显示失败（" err.Message "），改由设置窗口提供下载按钮")
        return
    }
    DebugLog("更新: 启动更新弹窗选择=" (answer = "" ? "(空)" : answer))
    if answer = "Yes"
        DownloadAndReplace(exeUrl, shaUrl)
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
    global UpdaterPollTimer, UpdaterTimeoutTimer, APP_VERSION
    UpdaterReqDone := false
    UpdaterOnReady := onResult
    UpdaterReq := ""
    DebugLog("更新: 发起检查请求 " url)
    try {
        req := ComObject("MSXML2.ServerXMLHTTP")
        req.Open("GET", url, true)     ; true = 异步
        ; 显式带 User-Agent：GitHub REST API 对缺少 UA 的请求会直接 403
        req.setRequestHeader("User-Agent", "ZestCaps/" APP_VERSION)
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
        DebugLog("更新: 发起请求失败 - " err.Message)
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
    DebugLog("更新: 检查请求超时（15s）")
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
        DebugLog("更新: 检查失败 HTTP " req.Status)
        if IsSet(onResult)
            onResult(result)
        return
    }
    ParseGithubRelease(req.ResponseText, &result)
    latest := result["latestVersion"]
    if latest != "" {
        ; VerCompare 返回正数表示远程较新（需要更新）
        result["needUpdate"] := VerCompare(latest, APP_VERSION) > 0
        DebugLog("更新: 最新 v" latest " / 当前 v" APP_VERSION " → needUpdate=" (result["needUpdate"] ? 1 : 0))
    } else {
        result["error"] := "无法解析最新版本"
        DebugLog("更新: 响应中未解析出 tag_name")
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
; onStatus：可选，界面状态回调（形如 msg => ...）；给了就把进度/失败原因回写界面，
;           不给则只有 TrayTip（此前一律只有 TrayTip，失败时界面停在"正在下载"，用户以为没反应）
; 返回 true 表示已进入替换流程；false 表示下载/校验失败
; ------------------------------------------------------------------
DownloadAndReplace(exeUrl, shaUrl, onStatus := 0) {
    global APP_VERSION, UpdaterDlOnStatus
    DebugLog("更新: 开始下载更新包 " exeUrl)
    SplitPath(A_AhkPath, , &exeDir)
    tmpDir := A_Temp "\zestcaps_upd_" A_TickCount
    try DirCreate(tmpDir)
    newExe := tmpDir "\zestcaps_new_v" APP_VERSION ".exe"
    newSha := tmpDir "\zestcaps_new_v" APP_VERSION ".exe.sha256"
    UpdaterDlOnStatus := onStatus   ; 供超时看门狗回报
    ; 看门狗：下载+校验全程 30s 超时保护
    SetTimer(UpdaterDlTimeout, -30000)
    try {
        UpdaterReportStatus(onStatus, "正在下载更新…", 1)
        Download(exeUrl, newExe)
        Download(shaUrl, newSha)
        ; SHA256 校验（若 sha256 文件存在且可读）
        remoteHash := ReadFirstHash(newSha)
        if remoteHash != "" {
            localHash := SHA256Hex(newExe)
            if StrLower(remoteHash) = StrLower(localHash) {
                DebugLog("更新: 下载完成且 SHA256 校验通过")
                UpdaterReportStatus(onStatus, "下载完成，即将替换并重启…", 1)
            } else {
                DebugLog("更新: SHA256 校验失败（远端 " remoteHash " / 本地 " localHash "）")
                UpdaterReportStatus(onStatus, "更新失败：下载文件与发布校验值不一致，已中止（可稍后重试）", 3)
                try DirDelete(tmpDir, true)
                SetTimer(UpdaterDlTimeout, 0)   ; 失败退场前必须取消看门狗，否则 30s 后会被超时回调 ExitApp
                UpdaterDlOnStatus := 0
                return false
            }
        } else {
            DebugLog("更新: 未取得 sha256（发布可能未附带），跳过校验")
            UpdaterReportStatus(onStatus, "下载完成，即将替换并重启…", 1)
        }
    } catch as err {
        DebugLog("更新: 下载失败 - " err.Message)
        UpdaterReportStatus(onStatus, "更新失败：下载出错（" err.Message "）", 3)
        try DirDelete(tmpDir, true)
        SetTimer(UpdaterDlTimeout, 0)   ; 同上：失败退场前取消看门狗
        UpdaterDlOnStatus := 0
        return false
    }
    SetTimer(UpdaterDlTimeout, 0)   ; 取消看门狗（已到最后一步）
    ; 隐藏托盘图标防止退场残留
    A_IconHidden := true
    self := A_AhkPath    ; 实测：编译版下 A_AhkPath 即自身 exe 路径（见 test 报告）
    ; cmd 延迟替换：ping 延时约 2 秒等旧进程退出 → 用下载的新 exe 覆盖自身 → 启动新实例
    cmd := 'cmd /c ping -n 3 127.0.0.1 >nul & if exist "' newExe '" move /y "' newExe '" "' self '" & start "" "' self '"'
    DebugLog("更新: 执行替换并重启 -> " cmd)
    try {
        Run(cmd, exeDir, "Hide")
    } catch as err {
        DebugLog("更新: 启动替换命令失败 - " err.Message)
        UpdaterReportStatus(onStatus, "更新失败：无法启动替换进程（" err.Message "）", 3)
        try DirDelete(tmpDir, true)
        UpdaterDlOnStatus := 0
        return false
    }
    UpdaterDlOnStatus := 0
    ExitApp 0
}

; 回报更新阶段状态：优先回写界面（onStatus 回调），同时保留 TrayTip 便于托盘场景
UpdaterReportStatus(onStatus, msg, icon := 1) {
    if IsObject(onStatus)
        try onStatus.Call(msg)
    TrayTip msg, "ZestCaps", icon
}

; 下载/校验看门狗
; 说明：Download 是同步阻塞调用，卡住时整个脚本线程都停着，只能退出应用让用户重开
UpdaterDlTimeout() {
    global UpdaterDlOnStatus
    DebugLog("更新: 下载/校验超时（30s），退出应用以便下次启动重试")
    UpdaterReportStatus(UpdaterDlOnStatus, "更新超时已中止：网络较慢或下载被拦截，请稍后重试。", 3)
    Sleep 1200          ; 给界面/气泡一点时间再退出
    UpdaterDlOnStatus := 0
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