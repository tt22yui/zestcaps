; ==================================================================
; 验证：原生弹出菜单数字键助记符（&1 &2 ...）在菜单显示期间可按键激活
; 说明：菜单 Show() 期间本脚本定时器不触发（AHK 菜单模态循环特性），
;       故由独立进程 test_clip_menu_send.ahk 发送数字键，本脚本只弹菜单并记录结果。
; 运行方式：AutoHotkey64 test\test_clip_menu.ahk（配合 send 脚本一起跑，见 test_clip_menu_send.ahk 头部注释）
; 结果写入 %TEMP%\_tmp_clip_menu.txt
; ==================================================================
#Requires AutoHotkey v2.0
#SingleInstance Force
#ErrorStdOut
#Warn All, Off

resultFile := A_Temp "\_tmp_clip_menu.txt"
if FileExist(resultFile)
    try FileDelete(resultFile)

hit := false
CB(ItemName, ItemPos, MenuObj) {
    global hit, resultFile
    hit := true
    FileAppend "PASS 数字键激活了菜单项: " ItemName "`n", resultFile
}

m := Menu()
m.Add("&1. 第一条", CB)
m.Add("&2. 第二条", CB)
m.Add("&3. 第三条", CB)

m.Show()

if !hit
    FileAppend "FAIL 数字键未能激活菜单项`n", resultFile
ExitApp 0
