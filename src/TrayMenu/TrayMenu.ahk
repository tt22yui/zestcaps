; ==================================================================
; 托盘菜单初始化 —— 精简为「设置 / 重启 / 退出」三个入口；
; 托盘图标左键单击直接打开设置窗口（右键仍弹出菜单）
; 各功能开关已统一收进设置界面（Settings.ahk）
; ==================================================================

InitTrayMenu() {
    global APP_VERSION, MENU_TITLE, MENU_SETTINGS, MENU_RESTART, MENU_EXIT
    ; 托盘图标悬停提示（多行）：产品简介（一句定位）
    A_IconTip := "ZestCaps v" APP_VERSION "`n输入法切换 · 截图标注 · 效率工具"
    ; 删除AHK自带的全部默认菜单项
    A_TrayMenu.Delete()
    ; 顶部标题（禁用态，不可点击）
    A_TrayMenu.Add(MENU_TITLE, (*) => 0)
    A_TrayMenu.Disable(MENU_TITLE)
    A_TrayMenu.Add()
    ; 设置窗口入口（lambda 写法，避免函数体内裸函数名被解析为未赋值局部变量）
    A_TrayMenu.Add(MENU_SETTINGS, (*) => OpenSettings())
    ; 重启（先隐藏托盘图标避免 Reload 后幻影图标残留，见 Settings.ahk RestartScript）
    A_TrayMenu.Add(MENU_RESTART, (*) => RestartScript())
    A_TrayMenu.Add(MENU_EXIT, (*) => ExitApp())
    ; 托盘图标左键单击：直接打开设置窗口（右键仍弹出菜单）。
    ; AHK v2 的 Menu 对象没有 OnEvent 方法，托盘点击需用 OnMessage(0x404) 监听内部托盘消息：
    ; 回调 lParam 为鼠标消息，WM_LBUTTONUP(0x202) 时打开设置并返回非零阻止默认菜单，其余放行
    OnMessage(0x404, TrayIconMsg)
}

; 托盘图标消息回调（wParam=图标ID，lParam=鼠标消息，msg=0x404，hwnd=脚本主窗口）
TrayIconMsg(wParam, lParam, msg, hwnd) {
    if (lParam = 0x202) {  ; WM_LBUTTONUP：左键单击抬起 → 打开设置窗口
        OpenSettings()
        return 1  ; 返回非零阻止默认行为（单击不再弹出菜单）
    }
    if (lParam = 0x205) {  ; WM_RBUTTONUP：右键单击抬起 → 显式弹出原右键菜单
        A_TrayMenu.Show()  ; 注册 0x404 回调后默认菜单可能被抑制，显式弹出确保保留
        return 1
    }
    return 0  ; 其他托盘事件：放行默认行为
}

InitTrayMenu()
