; ==================================================================
; 配置 —— 仅功能开关状态从 config.ini 读取，其余参数硬编码
; 修改 config.ini 后需重启脚本生效
; ==================================================================
CONFIG_FILE := A_ScriptDir "\config.ini"

; 启动计时起点：进程已启动，记录此刻用于统计各模块加载耗时（见 Main.ahk 的 DebugLog 打点）
SCRIPT_LOAD_START := A_TickCount

; ==================================================================
; 应用版本号（硬编码，用于启动日志/托盘标题/发布文件名）
; ==================================================================
APP_VERSION := "0.3.3"
; ==================================================================

; ==================================================================
; GitHub 自动更新（仅编译 exe 生效；值须与仓库/Release 一致）
; ==================================================================
APP_GITHUB_OWNER := "tt22yui"    ; GitHub 用户名
APP_GITHUB_REPO  := "zestcaps"   ; 仓库名
APP_GITHUB_API_URL := "https://api.github.com/repos/" APP_GITHUB_OWNER "/" APP_GITHUB_REPO "/releases/latest"  ; 最新 release 接口
; ==================================================================

; 配置文件不存在时自动创建（仅写入菜单开关状态）
; 注意：创建动作刻意放在本文件末尾——本文件在 GlobalError / DebugLog 注册之前加载，
;       早期执行的文件 I/O 一旦抛异常会弹模态错误框并中断整个脚本启动（见文件末尾同名段落）

; ==================================================================
; 托盘菜单文字（硬编码）
; ==================================================================
MENU_TITLE      := "ZestCaps v" APP_VERSION      ; 托盘菜单顶部标题
MENU_SETTINGS   := "设置..."                       ; 设置窗口菜单项
MENU_RESTART    := "重启脚本"                      ; 重启脚本菜单项
MENU_EXIT       := "退出"                          ; 退出脚本菜单项
; ==================================================================

; ==================================================================
; 设置窗口「快捷键」文本框提示语（AHK 原生热键格式说明）
; ==================================================================
HOTKEY_FORMAT_HINT := "格式：^=Ctrl； +=Shift； !=Alt； #=Win"
; ==================================================================

; ==================================================================
; 输入状态指示器参数（硬编码）
; ==================================================================
IND_UPDATE_INTERVAL     := 10                ; 指示器位置刷新间隔（毫秒），10ms≈100Hz 才跟手；鼠标位置未变化时跳过窗口位移（IME 检测每拍仍会执行）
IND_WIDTH               := 28                ; 指示器窗口宽度（像素）
IND_HEIGHT              := 24                ; 指示器窗口高度（像素）
IND_OFFSET_X            := 16                ; 相对鼠标光标的水平偏移（像素）
IND_OFFSET_Y            := 20                ; 相对鼠标光标的垂直偏移（像素）
IND_BRIEF_SHOW_DURATION := 1000              ; 按 CapsLock 后强制显示时长（毫秒），超时后按光标类型决定
IND_FADE_IN_MS          := 150               ; 指示器淡入时长（毫秒）
IND_FADE_OUT_MS         := 130               ; 指示器淡出时长（毫秒）
IND_FADE_PERIOD         := 15                ; 淡入淡出透明度步进周期（毫秒）
IND_FONT_SIZE           := "s9"              ; 字体大小（AHK 格式：s+数字）
IND_FONT_WEIGHT         := "w700"            ; 字体粗细（w400=正常 w700=加粗）
IND_FONT_NAME           := "Microsoft YaHei" ; 字体名称
; 中文
IND_TEXT_CN   := "中"         ; 中文输入法时显示的文字
IND_COLOR_CN  := "cWhite"   ; 中文输入法时文字颜色
IND_BG_CN     := "1FAE6B"   ; 中文输入法时背景颜色（语义绿·现代校准，白字可读）
; 英文
IND_TEXT_EN   := "英"         ; 英文输入法时显示的文字
IND_COLOR_EN  := "cWhite"   ; 英文输入法时文字颜色
IND_BG_EN     := "2F6FD8"   ; 英文输入法时背景颜色（语义蓝·现代校准，白字可读）
; 大写
IND_TEXT_A    := "A"          ; CapsLock 大写时显示的文字
IND_COLOR_A   := "cWhite"   ; CapsLock 大写时文字颜色
IND_BG_A      := "E07B2A"   ; CapsLock 大写时背景颜色（语义橙·现代校准，白字可读）
; ==================================================================

; ==================================================================
; CapsLock 键行为参数（硬编码）
; ==================================================================
CAPS_SHORT_PRESS            := 0.3   ; 短按判定阈值（秒），低于此时间视为短按切换输入法
CAPS_RELEASE_TIMEOUT        := 1     ; 长按后等待按键释放的超时（秒），防止假死
CAPS_COOLDOWN_MS            := 400   ; 快速连按冷却时间（毫秒），防止 IME 状态震荡
CAPS_BUSY_TIMEOUT_MS        := 5000  ; 看门狗：capsBusy 持续占用超时（毫秒），超时强制复位防假死
CAPS_WATCHDOG_INTERVAL_MS   := 2000  ; 看门狗检测周期（毫秒）
; ==================================================================

; ==================================================================
; 功能开关初始状态（从 config.ini 读取，设置窗口保存时自动写回）
; ==================================================================
IndicatorEnabled        := IniReadText(CONFIG_FILE, "Indicator", "IndicatorEnabled", 1) = "1"            ; 鼠标输入状态指示器：1=开 0=关
PastePlainEnabled       := IniReadText(CONFIG_FILE, "Features", "PastePlainEnabled", 1) = "1"            ; 纯文本粘贴（默认 Ctrl+Shift+V，热键可配置）：1=开 0=关
ScreenshotEnabled       := IniReadText(CONFIG_FILE, "Features", "ScreenshotEnabled", 1) = "1"            ; 简单截图（默认 F1，热键可配置）：1=开 0=关
StartupEnabled          := IniReadText(CONFIG_FILE, "Features", "StartupEnabled", 0) = "1"                ; 开机自动启动：1=开 0=关（默认关）
DesktopShortcutEnabled  := IniReadText(CONFIG_FILE, "Features", "DesktopShortcutEnabled", 0) = "1"          ; 桌面快捷方式：1=创建 0=不创建（默认关）
SplashEnabled           := IniReadText(CONFIG_FILE, "Features", "SplashEnabled", 1) = "1"                 ; 启动闪屏动画：1=开 0=关
RecycleBinEnabled       := IniReadText(CONFIG_FILE, "Features", "RecycleBinEnabled", 0) = "1"             ; 定时清空回收站：1=开 0=关（默认关）
AutoUpdateEnabled       := IniReadText(CONFIG_FILE, "Features", "AutoUpdateEnabled", 1) = "1"             ; 自动检查更新：1=开 0=关（默认开，仅编译版生效）
; ==================================================================
; 定时清空回收站参数（KeepDays/Time 由设置页保存到 config.ini 的 [RecycleBin] 段）
; ==================================================================
RB_DEFAULT_KEEP_DAYS    := 30                                         ; 默认保留天数：删除超过 N 天才清空
RB_DEFAULT_TIME         := "12:00"                                    ; 默认每日执行时刻（HH:mm，24 小时制）
; 保留天数/执行时刻均走兜底读取：手改 ini 写成 abc / 9:05 / 空值都不会再让启动失败
RecycleBinKeepDays      := IniReadInt(CONFIG_FILE, "RecycleBin", "KeepDays", RB_DEFAULT_KEEP_DAYS)  ; 保留天数（设置页可调）
RecycleBinTime          := NormalizeClockTime(IniReadText(CONFIG_FILE, "RecycleBin", "Time", RB_DEFAULT_TIME), RB_DEFAULT_TIME)  ; 每日执行时刻 HH:mm（设置页可调）
; 模块内引用名（RB* 前缀）读取自 config.ini
RBKeepDays              := RecycleBinKeepDays
RBTime                  := RecycleBinTime
; ==================================================================

; ==================================================================
; 区域截图参数（硬编码）
; ==================================================================
SCREENSHOT_FILENAME     := "Screen yyyyMMdd-HHmmss.png"   ; 截图默认文件名模板（FormatTime 格式，保存对话框的默认文件名）
SCREENSHOT_TIMEOUT_MS   := 30000                          ; 截图流程超时（毫秒）：按 F1 后超时未完成自动取消并恢复屏幕，防止蒙版卡住
MASK_COLOR              := 0x1F1F1F                     ; 截图蒙版颜色（PixPin 风格：深灰近黑，选区外内容明显变暗突出选区）
MASK_TRANSPARENCY       := 96                             ; 截图蒙版透明度（0-255，越大越不透明）
SEL_ALPHA               := 1                              ; 选区内部透明拦截层透明度（1=几乎不可见，用于拦截洞内点击防穿透）
SMALL_DELTA             := 5                              ; 鼠标移动超过该距离才刷新窗口高亮（像素）
DRAG_THRESHOLD          := 5                              ; 单击与拖动的判定阈值（像素）
RESIZE_GRAB             := 8                              ; 选区微调：沿选区外沿可拖拽改大小的抓取带宽（像素）
MIN_SEL_SIZE            := 8                              ; 选区微调：改大小时的最小宽/高（像素）
; ==================================================================

; ==================================================================
; 截图标注编辑窗参数（硬编码）
; ==================================================================
EDIT_SCREEN_MARGIN  := 40                                          ; 编辑窗距屏幕边缘的最小边距（像素）
EDIT_LINE_WIDTHS        := [2, 3, 6]                     ; 标注线宽档位（图片空间像素）：细/中/粗
EDIT_LINE_WIDTH_DISPLAY := [8, 11, 15]   ; 粗细图标圆点字号（点，仅图标视觉，与实际线宽对应）
EDIT_LINE_WIDTH_DEFAULT := 2                             ; 默认线宽档位（EDIT_LINE_WIDTHS 下标，1 起始；默认中档）
EDIT_MOSAIC_CELL        := 12                                    ; 马赛克格子尺寸（图片空间像素）：越大格子越粗，像素化越明显
EDIT_MOSAIC_BRUSH_R     := [10, 15, 22]                  ; 马赛克笔头半径（图片空间像素），按线条粗细档位（细/中/粗）取：笔划扫过的格子被像素化
EDIT_BRUSH_MIN_DIST := 3                                          ; 画笔抽稀最小间距（显示空间像素，缩放后视觉疏密一致）
EDIT_TEXT_FONT_SIZE  := [22, 30, 42]                              ; 文本标注字号档位（图片空间像素），按线条粗细档位（细/中/粗）取
EDIT_TEXT_FONT       := "Microsoft YaHei"                           ; 文本标注字体
EDIT_TEXT_BG_ALPHA   := 0xB3                                          ; 文本底色块不透明度（~70%，Flameshot 式深色底块，复杂背景下保证可读性）
EDIT_TEXT_PADDING    := 5                                               ; 文本四周留白（图片空间像素，底色块相对文字多出的边距）
EDIT_TEXT_BG         := "1E1E1E"                                          ; 文本输入覆盖窗 Edit 底色（近似最终深色底块，仅供输入预览用）
EDIT_BORDER_WIDTH   := 3                                           ; 覆盖层边框宽度（像素，选区/编辑器/钉屏三阶段统一）
EDIT_BORDER_COLOR   := 0xCC00A2E8                                 ; 覆盖层边框颜色（半透明天蓝 AARRGGBB，统一选区/编辑器/钉屏）
EDIT_COLORS         := [0xFFFF0000, 0xFF00B050, 0xFF0070C0, 0xFFFFC000, 0xFF000000, 0xFFFFFFFF]  ; 标注颜色集（红/绿/蓝/黄/黑/白）
; ==================================================================
; 设计语言 —— 统一配色体系（精细暗色 · 效率工具）
; 三条主线叠加：中性灰阶(板底→文字) + 签名强调色(靛蓝，统一选中/主强调) + 语义三色(中/英/A)
; 语义三色按使用场景各有一套适配饱和的变体（指示器白字小芯片用深色、闪屏暗卡大芯片用亮色），
; 共用色相保持全局同源；中性灰阶与强调色供工具栏/卡片等暗色表面统一引用。
; ==================================================================
; 中性灰阶（冷调暗色，从板底到文字逐级提亮）
UI_BG              := "16171C"   ; 最深板底（工具栏 / 闪屏卡片背景）
UI_SURFACE         := "20222A"   ; 二级表面（按钮默认底）
UI_SURFACE_HOVER   := "2A2D36"   ; 表面悬停
UI_BORDER          := "3A3E49"   ; 分隔线 / 外框
UI_TEXT            := "EAECF1"   ; 主文字（亮）
UI_TEXT_DIM        := "999FAD"   ; 次要文字（冷灰蓝）
; 签名强调色：靛蓝趋蓝，暗底上校正明度、调高饱和度，醒目而不刺眼；区别于下方语义蓝
UI_ACCENT          := "5B8BFF"
UI_ACCENT_WASH     := "1F2A44"   ; 选中工具背景：低饱和深靛墨，暗底上温和凸显（精制选中态）
UI_ACCENT_TEXT     := "AEC6FF"   ; 选中工具文字：亮靛，在靛墨底上清晰可读的精致强调
; ---- 工具栏样式（深色主题；多数色直接引用设计语言 token，颜色为 6 位十六进制 RGB 字符串）----
; 深浅对比优化：工具栏面板保持最深冷灰（UIBG），在浅色/深色截图上都自带面板承托；
; 重点提升「面板内部」元素对比——文字提纯白、分隔线/色块外框提亮，浅背景下深色工具栏内结构更醒目
EDIT_TB_BG          := UI_BG             ; 工具栏背景色（最深板底）
EDIT_TB_BTN_BG      := UI_SURFACE        ; 按钮默认背景色
EDIT_TB_BTN_HOVER   := UI_SURFACE_HOVER  ; 按钮悬停背景色
EDIT_TB_BTN_SEL     := "243A63"          ; 按钮选中背景色（靛蓝墨，略提亮——浅背景下选中格更易辨，精制选中态见 ToolbarUI.Apply）
EDIT_TB_BTN_SEL_TEXT := "D3E2FF"         ; 按钮选中文字色（亮靛，更高亮，浅背景下选中态更醒目）
EDIT_TB_BTN_TEXT    := "FFFFFF"          ; 按钮文字颜色（纯白，与深板对比最足）
EDIT_TB_SEP         := "464C59"          ; 分组分隔线颜色（提亮，深面板内分组结构更清晰）
EDIT_TB_RING        := "4A515E"          ; 色块外框默认颜色（提亮，深面板内色块/图标边界更分明）
EDIT_TB_RING_SEL    := "FFFFFF"          ; 色块外框选中颜色（白色高亮，区分选中填色）
PIN_MAX_RATIO       := 0.9                                         ; 钉屏图片最大占屏幕边长比例（等比缩放，防止超屏）
; ==================================================================

; ==================================================================
; 启动闪屏动画参数（硬编码）
; ==================================================================
SPLASH_WIDTH        := 340      ; 闪屏窗口宽度（像素）
SPLASH_HEIGHT       := 170      ; 闪屏窗口高度（像素）
SPLASH_RADIUS       := 14       ; 卡片圆角半径（像素）
; 启动闪屏动画时长（硬编码）—— 只需调总时长，其余时长自动按比例派生
SPLASH_DURATION_MS  := 500     ; 总显示时长（毫秒，含淡入淡出），唯一需要手动调整的时长
SPLASH_FPS          := 60      ; 动画刷新率（帧/秒，一般无需改动）
; 派生时长：淡入淡出 = 总时长的 1/8（至少 50ms 保证过渡可见）；芯片轮换一周 = 总时长；单段颜色 = 周期的 1/4
SPLASH_FADE_MS      := Max(50, Ceil(SPLASH_DURATION_MS / 8))
SPLASH_CYCLE_MS     := SPLASH_DURATION_MS
SPLASH_SEG_MS       := Ceil(SPLASH_CYCLE_MS / 4)
; 画面配色（6 位十六进制 RGB；芯片激活色用闪屏专属三色 SPLASH_ACCENT_*，独立于指示器配色）
; 深色毛玻璃卡片：冷调深灰蓝底、高不透明（≈90%），白字；深浅主题下卡片都醒目、文字都清晰，
; 透明度由 SPLASH_BG_ALPHA / SPLASH_BORDER_ALPHA 控制（此值偏大即越不透明）
SPLASH_BG           := UI_BG    ; 卡片背景 RGB（引用设计语言最深板底，深色毛玻璃底）
SPLASH_BG_ALPHA     := 230      ; 卡片背景透明度（0-255，越大越不透明；默认 230≈90% 近不透明，保证白字可读）
SPLASH_BORDER       := UI_BORDER ; 卡片描边 RGB（引用设计语言分隔线色，柔和勾勒毛玻璃边缘）
SPLASH_BORDER_ALPHA := 90       ; 卡片描边透明度（0-255，略强调边界的柔和描边）
SPLASH_TITLE        := "ZestCaps"                            ; 标题文字
SPLASH_TITLE_SIZE   := 22      ; 标题字号（像素）
SPLASH_TITLE_COLOR  := "FFFFFF" ; 标题文字颜色（白色，深色卡片上高对比）
SPLASH_SUBTITLE     := "v" APP_VERSION " · 中 / 英 / A 一键切换"  ; 副标题文字
SPLASH_SUB_SIZE     := 11      ; 副标题字号（像素）
SPLASH_SUB_COLOR    := "B7C0CE" ; 副标题文字颜色（浅冷灰，略低于白字形成层级）
SPLASH_CHIP_IDLE    := "39414F" ; 芯片未点亮背景（比卡片稍亮的冷灰，显出芯片层级）
SPLASH_CHIP_TEXT    := "9AA3B2" ; 芯片文字（未点亮，浅灰）
; 闪屏专属三色（柔和校准版，仅用于闪屏芯片；比原鲜艳版饱和度略降、亮度适中，与冷调深卡更和谐）
SPLASH_ACCENT_CN    := "3ECF8E" ; 中文（柔和绿）
SPLASH_ACCENT_EN    := "5AA9E6" ; 英文（柔和蓝）
SPLASH_ACCENT_A     := "F0A55A" ; 大写（柔和橙）
SPLASH_FONT_TITLE   := "Segoe UI"          ; 标题字体
SPLASH_FONT_CJK     := "Microsoft YaHei"   ; 副标题/芯片字体（中文）
; ==================================================================

; ==================================================================
; 调试日志 —— 用于排查按键卡死等问题
; 设为 false 可关闭日志；日志文件超过 DEBUG_LOG_MAX_SIZE_KB 自动清空
; ==================================================================
DEBUG_LOG_ENABLED     := true
DEBUG_LOG_FILE        := A_ScriptDir "\Log\capslock_debug.log"
DEBUG_LOG_MAX_SIZE_KB := 800
; ==================================================================

; ==================================================================
; 配置读取工具
; 本文件在 GlobalError 注册之前加载，故所有 ini 读取必须自行兜底：
; IniRead 在文件不可读时、Integer() 在值非数字时都会抛异常，
; 一旦抛出即弹模态错误框并中断整个脚本启动（托盘/热键全部失效），必须在此层拦截
; ==================================================================

; 读取整数配置项：缺失 / 空值 / 非数字 / 读取异常均回退到 fallback
IniReadInt(filename, section, key, fallback) {
    try {
        raw := IniRead(filename, section, key, fallback)
        if IsNumber(raw)
            return Integer(raw)
    }
    return Integer(fallback)
}

; 读取文本配置项：缺失 / 空值 / 读取异常均回退到 fallback
IniReadText(filename, section, key, fallback) {
    try {
        raw := IniRead(filename, section, key, fallback)
        if raw != ""
            return raw
    }
    return fallback
}

; 规范化每日执行时刻为补零的 "HH:mm"（兼容 "9:05" 这类写法）；非法值回退默认值
NormalizeClockTime(raw, fallback) {
    try {
        if RegExMatch(raw, "^(\d{1,2}):(\d{1,2})$", &m) {
            hour := Integer(m[1]), minute := Integer(m[2])
            if (hour <= 23 && minute <= 59)
                return Format("{:02}:{:02}", hour, minute)
        }
    }
    return fallback
}
; ==================================================================

; ==================================================================
; 首次运行自动创建 config.ini（写入默认开关状态）
; 刻意放在文件末尾：此时 DEBUG_LOG_FILE 已就绪，失败可尽力写日志；
; 且整体 try 兜底——程序目录只读（装在 Program Files、只读介质）时
; 不应连带整个脚本启动失败，缺配置时上方 IniRead* 会自然使用内置默认值
; ==================================================================
if !FileExist(CONFIG_FILE) {
    try {
        IniWrite 1, CONFIG_FILE, "Indicator", "IndicatorEnabled"
        IniWrite 1, CONFIG_FILE, "Features", "PastePlainEnabled"
        IniWrite 1, CONFIG_FILE, "Features", "ScreenshotEnabled"
        IniWrite 0, CONFIG_FILE, "Features", "StartupEnabled"
        IniWrite 0, CONFIG_FILE, "Features", "DesktopShortcutEnabled"
        IniWrite 1, CONFIG_FILE, "Features", "SplashEnabled"
        IniWrite 0, CONFIG_FILE, "Features", "RecycleBinEnabled"
        IniWrite 1, CONFIG_FILE, "Features", "AutoUpdateEnabled"
    } catch as configErr {
        ; 变量名刻意不用 err：顶层（自动执行段）赋值会创建全局 err，
        ; 使各处函数内 `catch as err` 被 #Warn LocalSameAsGlobal 判为「局部与全局同名」而刷告警
        DebugLog("配置: 创建 config.ini 失败（本次使用内置默认值运行）- " configErr.Message)
    }
}
; ==================================================================
