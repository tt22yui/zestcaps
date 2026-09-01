; 最小实验：函数内读取未声明的全局变量（模拟 test_settings_gui 看门狗写法）
; 结论判断：读取未设置变量是否抛错/退出码
#Requires AutoHotkey v2.0
#SingleInstance Force
#ErrorStdOut
#Warn All, StdOut
MENU_TITLE := "CapsLock v2.6"
rf := A_Temp "\_tmp_unsetsetvar.txt"
if FileExist(rf)
    try FileDelete(rf)
SetTimer Wd, 1000
Wd() {
    ; 未声明 global MENU_TITLE —— 读取未设置局部变量
    if WinExist("设置 - " MENU_TITLE)
        WinClose("设置 - " MENU_TITLE)
    ExitApp()
}
FileAppend "MAIN_OK`n", rf
