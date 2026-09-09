; Updater 模块加载检查：按真实依赖（Config → DebugLog → Updater）加载，
; 验证 Updater.ahk 可被无 Error/Warning 地编译加载，并跑通纯逻辑函数。
; 运行后检查 stderr 输出 Error/Warning 且退出码 0 即判定通过。
#Requires AutoHotkey v2.0
#SingleInstance Force
#ErrorStdOut
#Warn All, StdOut
doneFile := A_Temp "\_tmp_updater_load_done.txt"
if FileExist(doneFile)
    try FileDelete(doneFile)
; 按 Main.ahk 真实顺序加载 Updater 依赖链
#Include "..\..\src\Config\Config.ahk"
#Include "..\..\src\DebugLog\DebugLog.ahk"
#Include "..\..\src\Updater\Updater.ahk"

; ---- 纯逻辑验证（不触发网络） ----
try {
    ; 1) JSON 解析
    sample := '{"tag_name":"v0.4.0","assets":[{"name":"zestcaps_v0.4.0.exe","browser_download_url":"https://github.com/x/y/releases/download/v0.4.0/zestcaps_v0.4.0.exe"},{"name":"x.sha256","browser_download_url":"https://github.com/x/y/releases/download/v0.4.0/x.exe.sha256"}]}'
    res := Map()
    ParseGithubRelease(sample, &res)
    if res["latestVersion"] != "0.4.0"
        throw Error("tag 解析失败: " res["latestVersion"])
    if res["exeUrl"] != "https://github.com/x/y/releases/download/v0.4.0/zestcaps_v0.4.0.exe"
        throw Error("exeUrl 解析失败")
    if res["shaUrl"] != "https://github.com/x/y/releases/download/v0.4.0/zestcaps_v0.4.0.exe.sha256"
        throw Error("shaUrl 解析失败")
    ; 2) 版本比较：0.4.0(远程) > 0.3.2(本地) → 需更新
    if VerCompare(res["latestVersion"], APP_VERSION) <= 0
        throw Error("版本比较判定错误")
    ; 3) ReadFirstHash 读取发布 sha256 首行
    probe := A_Temp "\_tmp_updater_sha_test.txt"
    try FileAppend "abcdef1234567890abcdef1234567890  probe.txt`n", probe, "UTF-8-RAW"
    h := ReadFirstHash(probe)
    if h != "abcdef1234567890abcdef1234567890"
        throw Error("ReadFirstHash 失败: " h)
    try FileDelete(probe)
    ; 4) SHA256Hex 本地计算非空
    if SHA256Hex(A_ScriptFullPath) = ""
        throw Error("SHA256Hex 计算失败")
    FileAppend "UPDATER_LOAD_OK`n", doneFile
} catch as e {
    FileAppend "UPDATER_LOAD_FAIL: " e.Message " @" e.Line "`n", doneFile
    ExitApp 1
}
ExitApp 0