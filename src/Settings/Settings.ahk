; ==================================================================
; 设置窗口 —— 集中编辑 config.ini 中的功能开关
; 入口：托盘菜单「设置...」（见 TrayMenu.ahk）
; 结构：Tab3 页签分组 —— 「通用」（启动相关）/「指示器」/「剪贴板」（粘贴）/「截图」（开关），
;       各功能模块开关归入各自页签，对应快捷键也跟随所在页签（文本框直接填写 AHK 原生格式），
;       新增模块只需加页签
; 保存后写回 config.ini 并重启脚本生效（与 Config.ahk 的读取约定一致）
; 本文件为入口 + 通用小工具；其余拆分到子模块：
;   - Window.ahk：OpenSettings 及六个页签构建器
;   - Save.ahk：SaveSettings + 参数校验 + 时刻/秒数解析
;   - Update.ahk：「检查更新 / 下载并更新」按钮交互
; ==================================================================

#Include "Window.ahk"
#Include "Save.ahk"
#Include "Update.ahk"

; 重启脚本（设置保存 / 托盘「重启」共用）
; Reload 前先隐藏托盘图标：AHK 退出时不总是主动移除托盘图标，
; 残留的旧图标需鼠标悬停通知区域才被系统刷新清除（Windows 缓存行为），
; 提前隐藏可避免 Reload 后出现两个托盘图标的幻影图标
RestartScript() {
    DebugLog("重启: 调用 Reload（先隐藏托盘图标避免残留）")
    A_IconHidden := true
    Reload()
}

; 关闭设置窗口（关闭按钮 / Esc / 取消按钮共用）
CloseSettings(GuiObj) {
    GuiObj.Destroy()
}
