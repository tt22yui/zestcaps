; ==================================================================
; 滚动截图（手动滚动 + 自动抓帧拼接）
; 入口：RunScrollCapture(region) —— 由 F1 选区工具栏「滚动截图」动作调用
; 交互：用户自己向下滚动目标内容；本模块轮询区域画面，检测到变化且稳定后
;       自动抓帧并用「垂直重叠匹配」拼接到长图；Esc / 右键结束，返回长图 bitmap。
; 算法（ShareX 思路重写，非拷贝，无 GPL 代码）：
;   1) 逐行 memcmp 在「累计结果底部」与「新帧各行」之间找最长连续匹配（重叠高度）；
;   2) 忽略左右边距（滚动条 / 边缘噪点）；自动识别并剔除固定底栏（吸底区）；
;   3) 本轮无匹配但历史有最佳匹配时沿用（部分成功），避免偶发动态内容中断。
; 依赖：Gdip 库（src\Common\Gdip_All_v2.ahk）；Pin.ahk 的 EscRegister/EscUnregister；
;       Screenshot.ahk 的 CaptureRegion / _DestroyOverlays；Overlay.ahk 的 MonitorIndexAt。
; ==================================================================

; ------------------------------------------------------------------
; 拼接状态：跨帧保留的「最佳匹配」（本轮匹配失败时兜底沿用）
; ------------------------------------------------------------------
ScrollStitchReset(best) {
    best.count := 0
    best.index := 0
    best.ignoreBottom := 0
}

; ------------------------------------------------------------------
; 内存块是否逐字节相等（RtlCompareMemory 返回相等字节数，无需 CRT memcmp）
; ------------------------------------------------------------------
ScrollBytesEqual(a, b, n) {
    return DllCall("ntdll\RtlCompareMemory", "Ptr", a, "Ptr", b, "UPtr", n, "UPtr") = n
}

; ------------------------------------------------------------------
; 两张位图是否逐行完全一致（区域变化检测用；不做缩放/容差）
; ------------------------------------------------------------------
ScrollImagesIdentical(a, b) {
    if !a || !b
        return false
    wa := Gdip_GetImageWidth(a), ha := Gdip_GetImageHeight(a)
    wb := Gdip_GetImageWidth(b), hb := Gdip_GetImageHeight(b)
    if (wa != wb || ha != hb)
        return false
    sA := 0, pA := 0, bdA := 0, sB := 0, pB := 0, bdB := 0
    if Gdip_LockBits(a, 0, 0, wa, ha, &sA, &pA, &bdA, 1, 0x26200A)
        return false
    if Gdip_LockBits(b, 0, 0, wb, hb, &sB, &pB, &bdB, 1, 0x26200A) {
        Gdip_UnlockBits(a, &bdA)
        return false
    }
    same := true
    row := 0
    while (row < ha) {
        if !ScrollBytesEqual(pA + row * sA, pB + row * sB, wa * 4) {
            same := false
            break
        }
        row++
    }
    Gdip_UnlockBits(a, &bdA)
    Gdip_UnlockBits(b, &bdB)
    return same
}

; ------------------------------------------------------------------
; 核心：把新帧 current 拼接到累计结果 result 下方，返回新位图（调用方负责释放）
; result=0 表示首帧（返回 current 的克隆）；拼接失败返回 0
; status：0=成功 1=部分成功（沿用历史最佳匹配）2=失败
; best：跨帧保留的匹配状态（ScrollStitchReset 初始化）
; 实现移植自 ShareX 的 CombineImages 思路（逐行重叠匹配 + 固定底栏剔除），重写为 AHK
; ------------------------------------------------------------------
ScrollStitchFrame(result, current, autoIgnoreBottom, best, &status) {
    status := 0
    curW := Gdip_GetImageWidth(current)
    curH := Gdip_GetImageHeight(current)
    if !result
        return Gdip_CloneBitmapArea(current, 0, 0, curW, curH)

    resW := Gdip_GetImageWidth(result)
    resH := Gdip_GetImageHeight(result)
    sR := 0, pR := 0, bdR := 0, sC := 0, pC := 0, bdC := 0
    if Gdip_LockBits(result, 0, 0, resW, resH, &sR, &pR, &bdR, 1, 0x26200A) {
        status := 2
        return 0
    }
    if Gdip_LockBits(current, 0, 0, curW, curH, &sC, &pC, &bdC, 1, 0x26200A) {
        Gdip_UnlockBits(result, &bdR)
        status := 2
        return 0
    }
    pixelSize := Min(sR // resW, sC // curW)

    ; 忽略左右边距（滚动条 / 边缘噪声），最小值 50px、上限 1/3 宽
    ignoreSide := Max(50, curW // 20)
    ignoreSide := Min(ignoreSide, curW // 3)
    bandW := curW - ignoreSide * 2
    if (bandW < 1 || pixelSize < 1) {
        Gdip_UnlockBits(result, &bdR)
        Gdip_UnlockBits(current, &bdC)
        status := 2
        return 0
    }
    compareLen := pixelSize * bandW
    baseR := pR + pixelSize * ignoreSide
    baseC := pC + pixelSize * ignoreSide

    ; 底部忽略区（固定底栏 / 末行不稳）：从底部向上找首个不同的行，把相同行并入忽略区
    ignoreBotMax := curH // 3
    ignoreBot := Max(50, curH // 10)
    if autoIgnoreBottom {
        lastR := baseR + (resH - 1) * sR
        lastC := baseC + (curH - 1) * sC
        idx := 0
        while (idx <= ignoreBotMax) {
            if !ScrollBytesEqual(lastR - idx * sR, lastC - idx * sC, compareLen) {
                ignoreBot += idx
                break
            }
            idx++
        }
        ignoreBot := Max(ignoreBot, best.ignoreBottom)
    }
    ignoreBot := Min(ignoreBot, ignoreBotMax)
    rectBottom := resH - ignoreBot - 1

    ; 在结果底部行与新帧各行之间找最长连续匹配（即最大重叠高度）
    matchLimit := curH // 2
    matchCount := 0, matchIndex := 0
    curY := curH - 1
    while (curY >= 0 && matchCount < matchLimit) {
        cm := 0, y := 0
        while (curY - y >= 0 && rectBottom - y >= 0 && cm < matchLimit) {
            if ScrollBytesEqual(baseR + (rectBottom - y) * sR, baseC + (curY - y) * sC, compareLen)
                cm++
            else
                break
            y++
        }
        if (cm > matchCount) {
            matchCount := cm
            matchIndex := curY
        }
        curY--
    }
    Gdip_UnlockBits(result, &bdR)
    Gdip_UnlockBits(current, &bdC)

    ; 本轮无匹配但历史有最佳匹配 → 沿用（部分成功），避免偶发动态内容中断整个会话
    bestGuess := false
    if (matchCount = 0 && best.count > 0) {
        matchCount := best.count
        matchIndex := best.index
        ignoreBot := best.ignoreBottom
        bestGuess := true
    }
    if (matchCount > 0) {
        matchHeight := curH - matchIndex - 1
        if (matchHeight > 0) {
            if (matchCount > best.count) {
                best.count := matchCount
                best.index := matchIndex
                best.ignoreBottom := ignoreBot
            }
            newH := resH - ignoreBot + matchHeight
            newRes := Gdip_CreateBitmap(resW, newH)
            g := Gdip_GraphicsFromImage(newRes)
            Gdip_SetCompositingMode(g, 1)      ; SourceCopy：逐像素覆盖，避免透明混合
            Gdip_SetInterpolationMode(g, 5)    ; NearestNeighbor：1:1 拷贝无需插值
            Gdip_DrawImage(g, result, 0, 0, resW, resH - ignoreBot, 0, 0, resW, resH - ignoreBot)
            Gdip_DrawImage(g, current, 0, resH - ignoreBot, curW, matchHeight, 0, matchIndex + 1, curW, matchHeight)
            Gdip_DeleteGraphics(g)
            status := bestGuess ? 1 : 0
            return newRes
        }
    }
    status := 2
    return 0
}

; ------------------------------------------------------------------
; 滚动截图主流程：阻塞直到用户结束（Esc / 右键 / 超时）
; region：选区（RegionSetting）；调用方需已拆掉选区内拦截层/工具栏，
;         并保留蒙版/边框作区域指示（本函数不接管覆盖层）
; 返回：拼接好的长图 bitmap（调用方接管，编辑窗负责释放）；取消/失败返回 0
; ------------------------------------------------------------------
RunScrollCapture(region) {
    global SCROLL_POLL_MS, SCROLL_TIMEOUT_MS
    global ScreenshotEscCancel

    region.GetRegionRect(&rx, &ry, &rw, &rh)
    tip := ScrollTipCreate({l: rx, t: ry, r: rx + rw, b: ry + rh})

    f0 := CaptureRegion(region)
    if !f0 {
        ScrollTipDestroy(tip)
        DebugLog("滚动截图: 初始抓帧失败")
        return 0
    }
    best := {count: 0, index: 0, ignoreBottom: 0}
    ScrollStitchReset(best)
    result := ScrollStitchFrame(0, f0, true, best, &st)
    if !result {
        Gdip_DisposeImage(f0)
        ScrollTipDestroy(tip)
        DebugLog("滚动截图: 初始帧初始化失败")
        return 0
    }
    base := f0            ; 已并入 result 的最近一帧（与 result 引用不同，均可独立释放）
    staged := 0           ; 已检测到变化、等待稳定的候选帧
    frameCount := 1
    ScrollTipUpdate(tip, frameCount, Gdip_GetImageHeight(result))

    stopped := {v: false}
    Hotkey "*RButton", (*) => (stopped.v := true), "On"
    ScreenshotEscCancel := () => (stopped.v := true)
    EscRegister()
    deadline := A_TickCount + SCROLL_TIMEOUT_MS
    try {
        while !stopped.v {
            if A_TickCount > deadline
                break
            Sleep SCROLL_POLL_MS
            cur := CaptureRegion(region)
            if !cur
                continue
            if ScrollImagesIdentical(cur, base) {
                ; 与已并入帧相同：无新内容，丢弃候选项
                if staged {
                    Gdip_DisposeImage(staged)
                    staged := 0
                }
                Gdip_DisposeImage(cur)
                continue
            }
            if staged && ScrollImagesIdentical(cur, staged) {
                ; 连续两帧相同 → 画面稳定，拼接本帧
                newResult := ScrollStitchFrame(result, staged, true, best, &st)
                if newResult {
                    Gdip_DisposeImage(result)
                    result := newResult
                    Gdip_DisposeImage(base)
                    base := cur            ; cur 与 staged 内容一致，接管为已并入帧
                    Gdip_DisposeImage(staged)
                    staged := 0
                    frameCount++
                    ScrollTipUpdate(tip, frameCount, Gdip_GetImageHeight(result))
                    continue               ; cur 已被 base 接管，跳过尾部释放
                }
                ; 拼接失败（无法匹配）：放弃本帧，保持原结果
                Gdip_DisposeImage(staged)
                staged := 0
                Gdip_DisposeImage(cur)
                continue
            }
            ; 画面仍在变化：暂存本帧等待稳定
            if staged
                Gdip_DisposeImage(staged)
            staged := cur
        }
    } finally {
        Hotkey "*RButton", "Off"
        ScreenshotEscCancel := 0
        EscUnregister()
        ScrollTipDestroy(tip)
    }
    if staged
        Gdip_DisposeImage(staged)
    if base
        Gdip_DisposeImage(base)
    DebugLog("滚动截图: 完成，帧数 " frameCount "，高度 " Gdip_GetImageHeight(result))
    return result
}

; ------------------------------------------------------------------
; 提示条：显示操作提示与已捕获帧数（置于选区外，避免进入抓帧画面）
; ------------------------------------------------------------------
ScrollTipCreate(rect) {
    global SCROLL_TIP_BG, SCROLL_TIP_TEXT, SCROLL_TIP_HINT
    g := Gui("-Caption +AlwaysOnTop -DPIScale ToolWindow +E0x08000000")
    g.BackColor := SCROLL_TIP_BG
    g.SetFont("s10", "Microsoft YaHei")
    g.MarginX := 12
    g.MarginY := 8
    hint := g.Add("Text", "c" SCROLL_TIP_TEXT, SCROLL_TIP_HINT)
    status := g.Add("Text", "c" SCROLL_TIP_TEXT " y+4", "已捕获 1 帧")
    g.Show("NA x-32000 y-32000 AutoSize")   ; 先离屏量尺寸，再移到选区外，避免默认位置闪现
    g.GetPos(&gx, &gy, &tw, &th)
    pos := ScrollTipPlace(rect, tw, th)
    g.Move(pos.x, pos.y)
    return {gui: g, hwnd: g.Hwnd, status: status}
}

ScrollTipUpdate(tip, frames, height) {
    if tip && IsObject(tip.status)
        try tip.status.Text := Format("已捕获 {} 帧 · 高度 {} px", frames, height)
}

ScrollTipDestroy(tip) {
    if tip && IsObject(tip.gui)
        try tip.gui.Destroy()
}

; 计算提示条位置：优先选区下方，放不下则上方；仍与选区相交时移到选区右侧/左侧
ScrollTipPlace(rect, tw, th) {
    global SCROLL_TIP_GAP
    idx := MonitorIndexAt((rect.l + rect.r) // 2, (rect.t + rect.b) // 2)
    MonitorGetWorkArea(idx, &ml, &mt, &mr, &mb)
    gap := SCROLL_TIP_GAP
    x := Min(Max(rect.l + (rect.r - rect.l - tw) // 2, ml), mr - tw)
    y := rect.b + gap
    if (y + th > mb)
        y := rect.t - gap - th
    if (y < mt)
        y := mt
    if (y + th > rect.t && y < rect.b) {
        ; 垂直方向仍与选区相交（选区几乎整屏高）：尝试贴选区右侧/左侧
        if (rect.r + gap + tw <= mr) {
            x := rect.r + gap
            y := rect.t
        } else if (rect.l - gap - tw >= ml) {
            x := rect.l - gap - tw
            y := rect.t
        }
    }
    return {x: x, y: y}
}
