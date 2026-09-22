; ==================================================================
; 显示器命中共享工具（选区 / 编辑器 / 钉屏 / 工具栏 共用）
; 自 Overlay.ahk 抽出：ToolbarPlaceUnder 原另写了一份相同的命中循环，合并去重（P1-4）
; 仅依赖 AHK 内置 Monitor* 函数，无其它模块依赖。
; ==================================================================

; 返回坐标点所在的显示器编号（1-based；未命中任何显示器时返回 1 兜底）
MonitorIndexAt(x, y) {
    Loop MonitorGetCount() {
        MonitorGet(A_Index, &ml, &mt, &mr, &mb)
        if (x >= ml && x < mr && y >= mt && y < mb)
            return A_Index
    }
    return 1
}
