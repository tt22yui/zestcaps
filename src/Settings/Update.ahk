; ==================================================================
; Settings 子模块：「检查更新 / 下载并更新」交互
; 由 Settings.ahk #Include。点击即反馈 + 异步检查 + GUI 状态展示；
; 反馈不依赖 TrayTip（系统通知可能被忽略），改用窗口内进度条、状态文本与按钮文字。
; ==================================================================

; 按待下载状态刷新按钮文字：有更新 → 「下载并更新 vX.Y.Z」，否则「检查更新」
; 注：源码模式的检查恒为"无需更新"（见 CheckForUpdateAsync），不会出现下载入口；
;     万一有待下载状态（仅测试会人为注入），点击也会被 HandleUpdateClick 拦成"仅编译版可用"
RefreshUpdateButton(btnUpdate) {
    btnUpdate.Text := UpdateButtonLabel()
}

; 「更新」按钮点击处理：已发现新版本则直接下载，否则发起检查
HandleUpdateClick(btnUpdate, updProg, updStatus) {
    if !A_IsCompiled {
        updStatus.Text := "自动更新仅编译版可用（源码运行不检查网络）"
        return
    }
    ; 防止重复点击
    if !btnUpdate.Enabled
        return
    ; 已有待下载的更新（按钮此刻就是「下载并更新 vX.Y.Z」）：直接下载，不再重新检查
    if HasPendingUpdate() {
        DownloadAndReplaceResult(PendingUpdateField("exeUrl"), PendingUpdateField("shaUrl"), updStatus, btnUpdate)
        return
    }
    btnUpdate.Enabled := false
    btnUpdate.Text := "检查中…"
    updProg.Value := 0
    updProg.Visible := true
    updStatus.Text := "正在检查更新…"
    ; 不确定进度条脉冲动画：检查通常 1 秒内完成，仅用于明确告知"点击已生效"
    upv := 0
    pulse := () => (upv := (upv >= 100 ? 5 : upv + 8), updProg.Value := upv)
    SetTimer pulse, 80
    CheckForUpdateAsync((r) => HandleUpdateDone(btnUpdate, updProg, updStatus, r, pulse))
}

; 处理异步检查结果：停动画、更新状态文本
; 发现新版本 → 登记为待下载并把按钮就地变成「下载并更新 vX.Y.Z」，
; 刻意不用模态弹窗：旧实现弹 Yes/No 确认框，弹窗一旦被关掉/显示失败就没有任何下载入口了
HandleUpdateDone(btnUpdate, updProg, updStatus, result, pulse) {
    global APP_VERSION
    SetTimer pulse, 0
    updProg.Value := 100
    if result["error"] != "" {
        btnUpdate.Enabled := true
        RefreshUpdateButton(btnUpdate)
        updStatus.Text := "检查失败：" result["error"]
        return
    }
    if !result["needUpdate"] {
        btnUpdate.Enabled := true
        RefreshUpdateButton(btnUpdate)
        updStatus.Text := "已是最新版本 v" APP_VERSION
        return
    }
    newVer := result["latestVersion"]
    exeUrl := UpdateResultField(result, "exeUrl")
    if exeUrl = "" {
        btnUpdate.Enabled := true
        RefreshUpdateButton(btnUpdate)
        updStatus.Text := "发现新版本 v" newVer "，但未找到下载文件"
        return
    }
    SetPendingUpdate(newVer, exeUrl, UpdateResultField(result, "shaUrl"))
    btnUpdate.Enabled := true
    RefreshUpdateButton(btnUpdate)
    updStatus.Text := "发现新版本 v" newVer "（当前 v" APP_VERSION "），点按钮下载"
    DebugLog("更新: 发现新版本 v" newVer "，已就地提供下载按钮")
}

; 下载并替换；把下载/校验/替换过程中的状态与失败原因回写到窗口
; （此前失败只走 TrayTip、界面永远停在"正在下载更新…"，用户看不到任何反馈＝以为"只检查不更新"）
; 注：下载改为异步（不阻塞 UI 线程），失败经 done 回调恢复按钮；成功路径会 ExitApp 重启
DownloadAndReplaceResult(exeUrl, shaUrl, updStatus, btnUpdate) {
    updStatus.Text := "正在下载更新…完成后将自动替换并重启。"
    btnUpdate.Enabled := false
    btnUpdate.Text := "下载中…"
    DownloadAndReplace(exeUrl, shaUrl, (msg) => (updStatus.Text := msg, updStatus.Redraw()), (ok) => DownloadAndReplaceDone(ok, btnUpdate))
}

; 下载结束（仅失败会走到这里；成功会 ExitApp 重启）：恢复按钮让用户可直接重试
; （待下载状态仍在，故按钮仍是「下载并更新 vX.Y.Z」）
DownloadAndReplaceDone(ok, btnUpdate) {
    if !ok {
        btnUpdate.Enabled := true
        RefreshUpdateButton(btnUpdate)
    }
}
