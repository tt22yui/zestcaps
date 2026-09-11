; ==================================================================
; 全链路语法 / 告警 校验入口（供 CI 与本地用 /validate 调用，不执行任何代码）
;
; 用法：
;   AutoHotkey64.exe /validate /ErrorStdOut test\Load\validate_main.ahk
;   退出码 0 = 通过；非 0（实测语法错误为 2）= 失败，stderr 含文件:行与原因
;
; 为什么单独做入口：
;   - /validate 只做加载期校验，不注册热键/托盘/定时器，无窗口无副作用（已实测不执行脚本体）；
;   - 直接校验 src\Main.ahk 也可，但缺少统一出口；执行型加载检查（test_compile_load.ahk）
;     虽覆盖同类范围，却会真的把模块跑起来（注册托盘菜单等），且无条件 ExitApp 0 会掩盖失败；
;   - 本入口覆盖 Main.ahk 的完整 #Include 链，能拦住「某个模块有语法错但单测没引用到」的情况。
;
; 为什么用 #Warn All：
;   默认 #Warn 下「变量未赋值」类会弹模态框阻断启动，属必须拦住的问题；
;   实测全链路已零告警（含曾经的 LocalSameAsGlobal），故直接开全量告警当门禁——
;   任何新告警（拼错变量名、局部与全局同名、不可达代码等）都会让 CI 变红。
;   告警走 StdOut 输出，CI 以「退出码非 0 或有任何输出」判定失败。
; ==================================================================
#Requires AutoHotkey v2.0
#Warn All, StdOut
#ErrorStdOut

#Include "..\..\src\Main.ahk"
