; ==================================================================
; 回归测试：闪屏「开启」时初始化路径可正常加载（补齐 v0.4.1 漏测分支）
; 背景：Splash.ahk 顶层的 `if SplashEnabled { ... _SplashDraw ... }` 只在开启时执行；
;   test_main_load / test_splash_skip 都强制 SplashEnabled=false，故「开」分支无覆盖 ——
;   v0.4.1 因字体缓存全局初始化顺序错误，恰在该分支启动即抛
;   「This global variable has not been assigned a value」导致无法启动，CI 未发现。
; 本测试强制 SplashEnabled=true，真正跑一遍闪屏初始化，验证加载链不被中断。
; 判定：显式注册 OnError，任何未捕获错误（含自动执行段中断）都写 FAIL 并非零退出；
;   闪屏初始化完整走完、后续模块入口函数均已定义时写 OK 并以 0 退出。
; 说明：会短暂显示闪屏窗口，属 GUI 用例，归入 run_gui_tests.ahk（与 test_splash_skip 互为对照）。
; 运行：AutoHotkey64 test\Splash\test_splash_on.ahk
; ==================================================================
#Requires AutoHotkey v2.0
#SingleInstance Force
#ErrorStdOut
#Warn All, Off

resultFile := A_Temp "\_tmp_splash_on_test.txt"
try FileDelete(resultFile)
failReported := false

; 未捕获错误 → 写 FAIL 并立即非零退出。
; 必须显式注册：否则 v0.4.1 那种初始化顺序错误会弹模态错误框，把用例（及其调用方）永久挂住。
SplashOnFail(Thrown, Mode) {
    global resultFile, failReported
    if failReported            ; 退出清理若再次抛错，避免递归
        ExitApp 1
    failReported := true
    msg := Thrown is Error ? Thrown.Message " @" Thrown.Line : String(Thrown)
    try FileAppend "FAIL: 未捕获异常[" Mode "]: " msg "`n", resultFile
    try FileAppend "FAIL: 未捕获异常[" Mode "]: " msg "`n", "*"
    ExitApp 1
}
OnError(SplashOnFail)

; 看门狗：GUI 用例约定必须自带，防止初始化异常/意外模态导致调用方一起挂住
SetTimer(Watchdog, 10000)
Watchdog() {
    global resultFile
    try FileAppend "FAIL: TIMEOUT 看门狗触发`n", resultFile
    ExitApp 1
}

#Include "..\..\src\Config\Config.ahk"
DEBUG_LOG_ENABLED := false     ; 屏蔽日志写入，避免污染正式日志
#Include "..\..\src\DebugLog\DebugLog.ahk"

; 关键：覆盖 Config 读取值，强制走闪屏「开」分支（test_splash_skip 走的是「关」分支）
SplashEnabled := true
#Include "..\..\src\Splash\Splash.ahk"
#Include "..\..\src\Startup\Startup.ahk"
#Include "..\..\src\Settings\Settings.ahk"
#Include "..\..\src\TrayMenu\TrayMenu.ahk"

ok := false
try {
    ; splashInit=true：闪屏初始化（含 _SplashDraw）完整走完；
    ; 后续模块入口已定义：说明 include 链未被中途抛错打断
    ok := IsSet(splashInit) && splashInit && IsSet(SetStartup) && IsSet(OpenSettings) && IsSet(InitTrayMenu)
} catch as err {
    ok := false
    try FileAppend "FAIL: " err.Message " @" err.Line "`n", resultFile
}
if ok {
    try FileAppend "OK: 闪屏开启时初始化及后续模块加载正常`n", resultFile
} else {
    try FileAppend "FAIL: 闪屏开启时初始化或后续模块加载异常`n", resultFile
}
if FileExist(resultFile)
    try FileAppend FileRead(resultFile), "*"   ; 有重定向（CI）时回显明细
ExitApp ok ? 0 : 1
