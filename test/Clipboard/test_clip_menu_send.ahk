; ==================================================================
; 验证辅助：配合 test_clip_menu.ahk 使用
; 流程：等待菜单显示 → Send 数字键 1（触发 &1 助记符）→ 兜底按 Esc 关闭菜单防残留
; 运行方式：AutoHotkey64 test\test_clip_menu_send.ahk（在 test_clip_menu.ahk 启动约 1 秒后运行）
; ==================================================================
#Requires AutoHotkey v2.0
#SingleInstance Force
#ErrorStdOut
#Warn All, Off

Sleep 1500        ; 等待菜单显示并取得焦点
Send "1"          ; 尝试激活 &1 助记符项
Sleep 3000        ; 等待回调执行
Send "{Esc}"      ; 兜底：关闭可能残留的菜单
Sleep 300
ExitApp 0
