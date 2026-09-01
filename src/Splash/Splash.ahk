; ==================================================================
; 启动闪屏动画 —— GDI+ 分层窗口，纯代码绘制，无图片资源
; 画面：深色毛玻璃圆角卡片（高不透明冷调深灰蓝，深/浅主题都醒目）+ 标题/副标题 + 底部 中/英/A 状态芯片循环点亮（柔和绿/蓝/橙）
; 流程：淡入 → 停留 → 淡出 → 自动销毁；定时器驱动，不阻塞热键注册
; 依赖：Config.ahk（SPLASH_* 参数、SPLASH_ACCENT_* 闪屏专属三色）、Common\Gdip_All_v2.ahk
; 注意：本文件顶层严禁使用 return —— #Include 文件的顶层 return 会终止
;       主脚本后续加载（托盘菜单/热键等全部失效），开关判断用 if 块包裹
; ==================================================================
#Include "..\Common\Gdip_All_v2.ahk"

; 声明依赖的全局配置（消除静态分析误报）
global SPLASH_WIDTH, SPLASH_HEIGHT, SPLASH_RADIUS, SPLASH_DURATION_MS, SPLASH_FADE_MS, SPLASH_FPS
global SPLASH_CYCLE_MS, SPLASH_SEG_MS
global SPLASH_BG, SPLASH_BG_ALPHA, SPLASH_BORDER, SPLASH_BORDER_ALPHA
global SPLASH_TITLE, SPLASH_SUBTITLE, SPLASH_TITLE_SIZE, SPLASH_SUB_SIZE
global SPLASH_TITLE_COLOR, SPLASH_SUB_COLOR
global SPLASH_CHIP_IDLE, SPLASH_CHIP_TEXT, SPLASH_FONT_TITLE, SPLASH_FONT_CJK
global SPLASH_ACCENT_CN, SPLASH_ACCENT_EN, SPLASH_ACCENT_A
global SplashEnabled

; 闪屏开关关闭时跳过整个闪屏流程（设置界面可开启）
if SplashEnabled {
    ; GDI+ 初始化失败时跳过闪屏，不阻塞脚本
    if !(splashToken := Gdip_Startup()) {
        DebugLog("闪屏: GDI+ 初始化失败，跳过")
    } else {
        splashInit := true

        ; 初始化失败（如系统环境异常）时兜底清理，避免闪屏窗口残留不退出
        try {
            ; 创建分层窗口（置顶 / 无边框 / 不抢焦点 / 点击穿透 / WS_EX_LAYERED / 禁用 DPI 缩放）
            ; 圆角由位图 alpha 通道实现（逐像素透明），无需 WinSetRegion
            ; -DPIScale：保证窗口物理尺寸 = 位图尺寸 = UpdateLayeredWindow psize 一致（否则高 DPI 下分层渲染失败）
            SplashGUI := Gui("-DPIScale +AlwaysOnTop -Caption +ToolWindow +E0x20 +E0x08000000 +E0x80000")
            SplashGUI.BackColor := SPLASH_BG
            splashHwnd := SplashGUI.Hwnd

            ; 绘图上下文：位图 + 兼容 DC + GDI+ 图形
            splashHbm := CreateDIBSection(SPLASH_WIDTH, SPLASH_HEIGHT)
            splashHdc := CreateCompatibleDC()
            splashObm := SelectObject(splashHdc, splashHbm)
            splashG := Gdip_GraphicsFromHDC(splashHdc)
            Gdip_SetSmoothingMode(splashG, 4)        ; AntiAlias
            Gdip_SetTextRenderingHint(splashG, 4)    ; AntiAliasGridFit

            ; 动画计时起点，定时器驱动（非阻塞）
            splashStartTime := A_TickCount
            ; 首帧先绘制并应用分层窗口，再 Show：分层窗口的纯色 BackColor（毛玻璃卡片白色）在内容就绪前
            ; 不会被用户看到，避免「白闪」；也验证半透明卡片合成（圆角外透明、卡片内半透明白）
            _SplashDraw(splashG, 0)
            UpdateLayeredWindow(splashHwnd, splashHdc, "", "", SPLASH_WIDTH, SPLASH_HEIGHT, 255)
            SplashGUI.Show("w" SPLASH_WIDTH " h" SPLASH_HEIGHT " Center NoActivate")
            SetTimer _SplashTick, Ceil(1000 / SPLASH_FPS)

            ; 脚本退出时确保释放 GDI+ 资源（OnExit 只接受函数对象，裸函数名即引用）
            OnExit(_SplashExit)
        } catch as err {
            DebugLog("闪屏: 初始化失败 - " err.Message " @" err.Line)
            _SplashCleanup()
        }
    }
}

; ------------------------------------------------------------------
; 每帧回调：绘制画面 + 更新分层窗口（含淡入淡出透明度）
; ------------------------------------------------------------------
_SplashTick() {
    global splashG, splashHdc, splashHwnd, splashStartTime
    global SPLASH_DURATION_MS, SPLASH_WIDTH, SPLASH_HEIGHT
    elapsed := A_TickCount - splashStartTime
    if (elapsed >= SPLASH_DURATION_MS) {
        SetTimer _SplashTick, 0
        _SplashCleanup()
        return
    }
    _SplashDraw(splashG, elapsed)
    _SplashAlpha(elapsed, &alpha)
    ; x/y 留空保持窗口当前位置，避免分层窗口被重新定位
    UpdateLayeredWindow(splashHwnd, splashHdc, "", "", SPLASH_WIDTH, SPLASH_HEIGHT, alpha)
}

; 淡入淡出透明度计算
_SplashAlpha(elapsed, &alpha) {
    global SPLASH_DURATION_MS, SPLASH_FADE_MS
    alpha := 255
    if (elapsed < SPLASH_FADE_MS)
        alpha := 255 * elapsed / SPLASH_FADE_MS
    else if (elapsed > SPLASH_DURATION_MS - SPLASH_FADE_MS)
        alpha := 255 * (SPLASH_DURATION_MS - elapsed) / SPLASH_FADE_MS
    alpha := Min(255, Max(0, Round(alpha)))
}

; 绘制一帧画面
_SplashDraw(G, elapsed) {
    global SPLASH_WIDTH, SPLASH_HEIGHT, SPLASH_RADIUS
    global SPLASH_CYCLE_MS, SPLASH_SEG_MS
    global SPLASH_BG, SPLASH_BG_ALPHA, SPLASH_BORDER, SPLASH_BORDER_ALPHA
    global SPLASH_TITLE, SPLASH_SUBTITLE, SPLASH_TITLE_SIZE, SPLASH_SUB_SIZE
    global SPLASH_TITLE_COLOR, SPLASH_SUB_COLOR
    global SPLASH_CHIP_IDLE, SPLASH_CHIP_TEXT, SPLASH_FONT_TITLE, SPLASH_FONT_CJK
    global SPLASH_ACCENT_CN, SPLASH_ACCENT_EN, SPLASH_ACCENT_A
    global UI_ACCENT

    static labels := ["中", "英", "A"]
    static colors := 0
    if !colors
        colors := [SPLASH_ACCENT_CN, SPLASH_ACCENT_EN, SPLASH_ACCENT_A]

    ; 透明底（圆角外区域透出桌面）
    Gdip_GraphicsClear(G, 0x00000000)

    ; 毛玻璃圆角卡片：半透明白填充 + 半透明浅灰描边（背景透出，深色文字可读）
    pBg := Gdip_BrushCreateSolid(Format("0x{:02X}{}", SPLASH_BG_ALPHA, SPLASH_BG))
    Gdip_FillRoundedRectangle(G, pBg, 1, 1, SPLASH_WIDTH - 2, SPLASH_HEIGHT - 2, SPLASH_RADIUS)
    Gdip_DeleteBrush(pBg)
    pBorder := Gdip_CreatePen(Format("0x{:02X}{}", SPLASH_BORDER_ALPHA, SPLASH_BORDER), 1)
    Gdip_DrawRoundedRectangle(G, pBorder, 1, 1, SPLASH_WIDTH - 2, SPLASH_HEIGHT - 2, SPLASH_RADIUS)
    Gdip_DeletePen(pBorder)

    ; 当前芯片索引（随总时长循环轮换）
    seg := Floor(Mod(elapsed, SPLASH_CYCLE_MS) / SPLASH_SEG_MS)

    ; 标题 / 副标题
    _SplashText(G, SPLASH_TITLE, 0, 36, SPLASH_WIDTH, 30, SPLASH_TITLE_SIZE, SPLASH_TITLE_COLOR, SPLASH_FONT_TITLE, true)
    _SplashText(G, SPLASH_SUBTITLE, 0, 68, SPLASH_WIDTH, 22, SPLASH_SUB_SIZE, SPLASH_SUB_COLOR, SPLASH_FONT_CJK)

    ; 签名强调线：副标题下一道居中的靛蓝细线（UI_ACCENT），暗色卡片上作为品牌点缀
    ; 位于副标题文字(≈y72-85)与芯片行(y100)之间的留白处，不挤占任何元素
    dividerW := 56, dividerThick := 2
    pAccentDivider := Gdip_CreatePen(Format("0xFF{}", UI_ACCENT), dividerThick)
    Gdip_DrawLine(G, pAccentDivider, (SPLASH_WIDTH - dividerW) / 2, 90, (SPLASH_WIDTH + dividerW) / 2, 90)
    Gdip_DeletePen(pAccentDivider)

    ; 底部 中/英/A 芯片（激活色 = 闪屏专属鲜艳三色，循环点亮）
    chipW := 44, chipH := 26, gap := 12
    startX := (SPLASH_WIDTH - (3 * chipW + 2 * gap)) / 2
    chipY := 100
    loop 3 {
        i := A_Index - 1
        x0 := startX + i * (chipW + gap)
        fill := (i = seg) ? colors[i + 1] : SPLASH_CHIP_IDLE
        txt := (i = seg) ? "FFFFFF" : SPLASH_CHIP_TEXT
        pChip := Gdip_BrushCreateSolid("0xFF" fill)
        Gdip_FillRoundedRectangle(G, pChip, x0, chipY, chipW, chipH, 13)
        Gdip_DeleteBrush(pChip)
        _SplashText(G, labels[i + 1], x0, chipY, chipW, chipH, 12, txt, SPLASH_FONT_CJK, i = seg)
    }
}

; ------------------------------------------------------------------
; 绘制文本：水平居中 + 垂直按行高估算居中
; 直接调用 gdiplus 图元绘制（库的 Gdip_TextToGraphics 为 v1 移植，存在兼容性问题，故绕开）
; ------------------------------------------------------------------
_SplashText(G, text, x, y, w, h, size, color, font, bold := false) {
    hFamily := Gdip_FontFamilyCreate(font)
    hFont := Gdip_FontCreate(hFamily, size, bold ? 1 : 0)
    hFormat := Gdip_StringFormatCreate()
    Gdip_SetStringFormatAlign(hFormat, 1)   ; Center
    pBrush := Gdip_BrushCreateSolid("0xFF" color)
    ; 垂直居中：行高约 1.2 倍字号
    y2 := y + Round((h - size * 1.2) / 2)
    CreateRectF(&rc, x, y2, w, h - (y2 - y))
    DllCall("gdiplus\GdipDrawString", "ptr", G, "str", text, "int", -1, "ptr", hFont, "ptr", rc.Ptr, "ptr", hFormat, "ptr", pBrush)
    Gdip_DeleteBrush(pBrush)
    Gdip_DeleteStringFormat(hFormat)
    Gdip_DeleteFont(hFont)
    Gdip_DeleteFontFamily(hFamily)
}

; 释放资源并销毁窗口（幂等；句柄未初始化时安全跳过）
_SplashCleanup() {
    global splashInit, splashToken, splashG, splashHdc, splashHbm, splashObm, SplashGUI
    if !splashInit
        return
    splashInit := false
    SetTimer _SplashTick, 0
    if splashHdc {
        SelectObject(splashHdc, splashObm)   ; 恢复原对象，解除 hbm 选中
        DeleteDC(splashHdc)
        splashHdc := ""
    }
    if splashHbm {
        DeleteObject(splashHbm)
        splashHbm := ""
    }
    if splashG {
        Gdip_DeleteGraphics(splashG)
        splashG := ""
    }
    if splashToken {
        Gdip_Shutdown(splashToken)
        splashToken := ""
    }
    try SplashGUI.Destroy()
    SplashGUI := 0
}

; 脚本退出时兜底清理
_SplashExit(*) {
    DebugLog("OnExit: 闪屏清理开始")
    _SplashCleanup()
    DebugLog("OnExit: 闪屏清理完成")
}
