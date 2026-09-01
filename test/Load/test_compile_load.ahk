; 编译加载检查：按 Main.ahk 的加载顺序加载相关真实模块链（Config → DebugLog → Screenshot），
; 验证改动无编译 Error/Warning。运行后检查 stderr 是否输出 Error / Warning 即判定通过。
;
; 历史教训（v2.0.26 实测，供复盘）：
;   - 不在此处注册 OnError(LogErr)：
;       a) 回调函数未定义就注册 → 抛 "Invalid callback function"
;       b) 即使在 try{} 块内、回调已先定义，块作用域仍会把函数名解析为未赋值的局部变量
;          → 同样抛 "Invalid callback function"（见 exp2c_try / exp2d_fixed）
;       c) 若 return true 吞掉错误，又会干扰 stderr 检查
;     改用 #ErrorStdOut：加载期任何错误/警告直接输出到 stderr 且退出码非 0，无弹框。
;   - 必须加载 DebugLog.ahk（Main.ahk 先于 Screenshot 加载它）：Screenshot.ahk 调用了
;     DebugLog()，若不加载会触发 #Warn UseUnsetLocal 警告（"This local variable appears
;     to never be assigned a value. Specifically: DebugLog"）。
;   - 不加载 GlobalError.ahk：其 OnError 会吞掉运行时错误，干扰 stderr 判定。
; 运行方式：AutoHotkey64 test\test_compile_load.ahk
#Requires AutoHotkey v2.0
#ErrorStdOut
#Warn All, StdOut
doneFile := A_Temp "\_tmp_compile_done.txt"
if FileExist(doneFile)
    try FileDelete(doneFile)
#Include "..\..\src\Config\Config.ahk"
#Include "..\..\src\DebugLog\DebugLog.ahk"
#Include "..\..\src\Clipboard\Clipboard.ahk"            ; 剪贴板模块（纯文本粘贴）
#Include "..\..\src\Screenshot\Screenshot.ahk"
#Include "..\..\src\Hotkeys\Hotkeys.ahk"                ; 可配置快捷键（读取/注册/校验）
#Include "..\..\src\Startup\Startup.ahk"   ; Settings 依赖（SetStartup）
#Include "..\..\src\Settings\Settings.ahk"   ; 托盘菜单依赖（OpenSettings/RestartScript）
#Include "..\..\src\TrayMenu\TrayMenu.ahk"   ; 托盘菜单（含 OnMessage 0x404 托盘单击处理）
try FileAppend "LOAD_OK`n", A_Temp "\_tmp_compile_done.txt"
ExitApp 0
