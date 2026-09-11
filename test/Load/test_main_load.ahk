#Requires AutoHotkey v2.0
#SingleInstance Force
#ErrorStdOut
#Warn All, Off
; 完整加载链测试：按 Main.ahk 的真实 #Include 顺序加载全部模块
; 验证启动耗时打点（SCRIPT_LOAD_START + DebugLog）加载无错误
; 测试期间屏蔽日志写入、跳过闪屏，避免污染正式日志与弹窗
#Include "..\..\src\Config\Config.ahk"
DEBUG_LOG_ENABLED := false     ; 屏蔽日志写入，避免污染正式日志
SplashEnabled := false         ; 跳过闪屏窗口
#Include "..\..\src\DebugLog\DebugLog.ahk"
#Include "..\..\src\DebugLog\GlobalError.ahk"
#Include "..\..\src\Splash\Splash.ahk"
#Include "..\..\src\Startup\Startup.ahk"
#Include "..\..\src\Indicator\IME.ahk"
#Include "..\..\src\Indicator\Indicator.ahk"
#Include "..\..\src\InputSwitch\CapsLock.ahk"
#Include "..\..\src\Clipboard\Clipboard.ahk"   ; 剪贴板模块（纯文本粘贴，内含 PastePlain.ahk）
#Include "..\..\src\Screenshot\Screenshot.ahk"
#Include "..\..\src\Hotkeys\Hotkeys.ahk"       ; 自定义快捷键（注册/校验）
#Include "..\..\src\Settings\Settings.ahk"
#Include "..\..\src\Updater\Updater.ahk"        ; GitHub 自动更新（仅编译 exe 生效）
#Include "..\..\src\TrayMenu\TrayMenu.ahk"

testFile := A_Temp "\_tmp_main_load_test.txt"
try FileDelete(testFile)
failCount := 0   ; 任一段 FAIL 即非零退出（此前恒 ExitApp 0，失败对调用方/CI 完全不可见）

; 看门狗：15 秒强制退出，防止测试期间创建的窗口残留（Updater 纯逻辑验证需要比原来多几个毫秒但整体仍远小于 15 秒）
SetTimer(() => ExitApp(), 15000)

; 复现 Main.ahk 的启动耗时打点表达式，验证变量可用、拼接无错
try {
    elapsed := A_TickCount - SCRIPT_LOAD_START
    DebugLog("启动耗时: Splash 加载完成 " elapsed " ms")
    DebugLog("启动耗时: Screenshot 加载完成 " elapsed " ms")
    DebugLog("=== 脚本启动 v" APP_VERSION "（总加载耗时 " elapsed " ms）===")
    FileAppend "OK: 完整加载链通过，耗时 " elapsed " ms`n", testFile
} catch as err {
    failCount += 1
    FileAppend "FAIL: " err.Message " @" err.Line "`n", testFile
}

; 验证自定义快捷键动态注册（真实模块 + 真实注册函数）
try {
    RegisterCustomHotkeys()
    ; 已注册的热键可用 Hotkey 开关指令探测（未注册会抛错）；
    ; 截图功能关闭时其热键按设计不注册（避免吞键），故仅在该功能开启时探测
    Hotkey PastePlainKey, "On"
    if ScreenshotEnabled
        Hotkey ScreenshotKey, "On"
    FileAppend "OK: 自定义快捷键注册成功 (" PastePlainKey " / " (ScreenshotEnabled ? ScreenshotKey : "截图已关闭，未注册") ")`n", testFile
} catch as err {
    failCount += 1
    FileAppend "FAIL: 自定义快捷键注册失败: " err.Message " @" err.Line "`n", testFile
}

; 验证 Updater 纯逻辑（不触发网络请求）：JSON 解析 + 版本比较判定
try {
    sample := '{"tag_name":"v0.4.0","assets":[{"name":"zestcaps_v0.4.0.exe","browser_download_url":"https://github.com/x/y/releases/download/v0.4.0/zestcaps_v0.4.0.exe"},{"name":"x.sha256","browser_download_url":"https://github.com/x/y/releases/download/v0.4.0/x.exe.sha256"}]}'
    res := Map()
    ParseGithubRelease(sample, &res)
    if res["latestVersion"] != "0.4.0"
        throw Error("tag 解析失败: " res["latestVersion"])
    if res["exeUrl"] != "https://github.com/x/y/releases/download/v0.4.0/zestcaps_v0.4.0.exe"
        throw Error("exeUrl 解析失败")
    if res["shaUrl"] != "https://github.com/x/y/releases/download/v0.4.0/zestcaps_v0.4.0.exe.sha256"
        throw Error("shaUrl 解析失败")
    ; 版本比较：AP.exe 当前 0.3.2 < 0.4.0 → 需要更新
    if VerCompare(res["latestVersion"], APP_VERSION) <= 0
        throw Error("版本比较判定错误")
    FileAppend "OK: Updater.JSON解析/版本比较通过`n", testFile
} catch as err {
    failCount += 1
    FileAppend "FAIL: Updater 逻辑: " err.Message " @" err.Line "`n", testFile
}

; 验证 Updater 的 sha256 首行哈希读取 + 计算函数（本地自算互证，不依赖网络）
try {
    probe := A_Temp "\_tmp_updater_sha_test.txt"
    FileAppend "abcdef1234567890abcdef1234567890  probe.txt`n", probe, "UTF-8-RAW"
    h := ReadFirstHash(probe)
    if h != "abcdef1234567890abcdef1234567890"
        throw Error("ReadFirstHash 失败: " h)
    if SHA256Hex(A_ScriptFullPath) = ""
        throw Error("SHA256Hex 计算失败")
    try FileDelete(probe)
    FileAppend "OK: Updater.SHA256读取/计算通过`n", testFile
} catch as err {
    failCount += 1
    FileAppend "FAIL: Updater SHA256: " err.Message " @" err.Line "`n", testFile
}

; 汇总：回显结果到 stdout（重定向/CI 可见）并按失败数决定退出码
try FileAppend (failCount ? "RESULT: FAILED`n" : "RESULT: PASSED`n"), testFile
if FileExist(testFile) {
    try FileAppend FileRead(testFile), "*"
    try FileDelete(testFile)   ; 一次性结果文件用完即删
}
ExitApp failCount ? 1 : 0
