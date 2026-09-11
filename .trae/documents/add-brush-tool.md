# 增加截图「画笔」工具实现计划

## Context

截图标注编辑器（src\Screenshot\Editor.ahk）当前支持 矩形 / 箭头 / 椭圆 / 马赛克 四种标注工具，均基于「两点」数据模型（x1/y1→x2/y2）。用户希望新增**自由手绘画笔**工具，用于在截图上手写自由线条。

已与用户确认的技术方向：
- **笔画风格**：圆角折线（逐点连线 + 线帽/线连接用 Round）。
- **点采样**：拖动时按最小距离间隔抽稀采集点，限制点总量，保证长笔画性能与缩放一致性。
- 颜色 / 线宽档位复用现有体系（EDIT_COLORS / EDIT_LINE_WIDTHS）。

## 关键耦合确认（已探明，无需改动）

- **Pin 钉屏**：走 `EditorRenderFull` → `EditorDrawAnnotation`，故新增 `case "brush"` 后钉屏/缩放自动覆盖；Pin.ahk **不改为**。
- **清除 / 清理 / 右键取消**：均只迭代 `EditorReleaseAnnotationCache`（对无 mosaic 的 ann 天然 no-op）；brush 无 GDI+ 资源、`points` 为普通数组随 GC 释放。`EditorReleaseAnnotationCache` **保持现状**。
- 无 Ctrl+Z 撤销，无撤销资源耦合。

## 改动文件

### 1) src\Config\Config.ahk（右侧面 EDIT_MOSAIC_CELL 附近，约 L121）

新增常量：

```
EDIT_BRUSH_MIN_DIST := 3   ; 画笔抽稀最小间距（显示空间像素）
```

> 用「显示空间」阈值（乘以 EditorScale 计算距离）：编辑窗只缩不放，显示空间阈值使不同缩放下的视觉疏密一致。

### 2) src\Screenshot\Editor.ahk

**(a) 数据模型**（L58-65 `class EditorAnnotation`）：新增字段

```
points := []   ; 画笔折线点（每项 {x,y}，图片空间）；仅 type="brush" 使用
```

x1/y1 保留首点、x2/y2 保留末点，直接复用 `EditorLButtonUp` 的过小判断。

**(b) 绘制函数**（新增，置于 `EditorDrawArrow` 之后、`EditorDrawMosaic` 之前）：

```
; 画笔：圆角折线（线帽 Round + 线连接 Round，平滑无尖角）
EditorDrawBrush(G, ann, s) {
    if !ann.points || ann.points.Length < 2
        return                          ; 单点/空点不发散（过小已由 LButtonUp 拦截）
    pPen := Gdip_CreatePen(ann.color, Max(1, ann.penWidth * s))
    DllCall("gdiplus\GdipSetPenStartCap", "ptr", pPen, "int", 2)  ; LineCapRound
    DllCall("gdiplus\GdipSetPenEndCap",   "ptr", pPen, "int", 2)  ; LineCapRound
    DllCall("gdiplus\GdipSetPenLineJoin", "ptr", pPen, "int", 2)  ; LineJoinRound
    pts := ""
    for p in ann.points
        pts .= Format("{1:.2f},{2:.2f}|", p.x * s, p.y * s)
    Gdip_DrawLines(G, pPen, RTrim(pts, "|"))
    Gdip_DeletePen(pPen)
}
```

- 复用 Gdip 库 `Gdip_DrawLines`（Gdip_All_v2.ahk L1056，入参 `"x,y|x,y|..."` 字符串）。
- 线帽裸 DllCall 与现有 `EditorDrawArrow`（L329-330）写法一致；`GdipSetPenLineJoin` 库无封装，裸 DllCall，LineJoinRound=2。
- 保留 2 位小数避免 s<1 时逐点取整锯齿。

**(c) 分发**（L306-324 `EditorDrawAnnotation` switch）：在 `case "mosaic"` 前新增

```
case "brush":
    EditorDrawBrush(G, ann, s)
```

**(d) 抽稀采集辅助函数**（新增，靠近鼠标事件区）：

```
EditorBrushAppendPoint(pend, x, y) {
    global EDIT_BRUSH_MIN_DIST, EditorScale
    if !pend.points
        return
    if !pend.points.Length {
        pend.points.Push({x: x, y: y})
        return
    }
    last := pend.points[-1]                       ; AHK v2 数组负索引取末元素
    dx := (x - last.x) * EditorScale
    dy := (y - last.y) * EditorScale
    if (dx * dx + dy * dy >= EDIT_BRUSH_MIN_DIST * EDIT_BRUSH_MIN_DIST)
        pend.points.Push({x: x, y: y})
}
```

**(e) 鼠标三事件最小改动**（不影响现有工具）：

- `EditorLButtonDown`：在写完 x2/y2 后，若 `EditorTool = "brush"` 则初始化 `EditorPending.points := []` 并 `EditorBrushAppendPoint(EditorPending, x1, y1)`。
- `EditorMouseMove`：在 `if !EditorPending` 之后、`EditorRender()` 之前，若 `EditorTool = "brush"` 则 `EditorBrushAppendPoint(EditorPending, x2, y2)`（x2/y2 即当前鼠标图像空间坐标）。
- `EditorLButtonUp`：过小判断处加 brush 守卫（把 `EditorTool` 加入该函数 `global`）：
  - `if (EditorTool = "brush" && EditorPending.points.Length < 2)` → 走释放丢弃分支；
  - 否则沿用现有 `Abs(dx)>2 || Abs(dy)>2` 判提交/丢弃。

**(f) 工具栏**（L579 `tools` 数组）：末尾追加

```
, ["✎", "brush", "画笔"]
```

- 图标字形 `✎`(U+270E) 需先验证 Segoe UI Symbol 存在性；缺则换 `✏`(U+270F) 或几何字符。其余（EditorToolButtons/Labels/Refresh/ToolbarToolClick）为数组遍历通用逻辑，自动生效。
- 工具栏图标占用较小值：先看工具栏是否因新增按钮溢出，若需可整体 AutoSize（`ScreenToolbarCreateRow1` 已按 AutoSize 定位，新增一钮自动扩展行宽，无溢出风险，仅确认布局不越屏）。

## 性能与取舍

- 每帧重画整条折线 O(n) 可接受：抽稀已把 n 钳制（显示 3px 阈值 → 满屏 4K 约 ≤2000 点），`GdipDrawLines` 单次原生调用微秒级，相对 10ms 消息频率无感。
- **不做**点集 Buffer 预烘焙 / 增量分块专项：显示(s=EditorScale)、输出(s=1.0)、层烘焙三处缩放系数不同，必须逐点重算，拼字符串 O(n) 即最优。

## 验证

1. **编译加载检查**：命令行加载 src\Main.ahk（`2>&1` 合并 stdout/stderr），确认无 `Error`/`Warning`。
2. **Headless 渲染脚本**（tmp\ 下 `_tmp_brushtest.ahk`，禁止弹框、try/catch 内写结果文件、无窗口故无需看门狗）：
   - include 顺序：`..\src\Config\Config.ahk` → `..\src\Common\Gdip_All_v2.ahk` → `..\src\Screenshot\Editor.ahk`（Editor 顶层仅全局声明/类定义，不触发 ShowEditor，include 安全）。
   - 构建多种 `EditorAnnotation`（`type="brush"`/color/points/penWidth），组合 `[2,3,6]` 三种线宽 × `[1.0,0.5]` 两种缩放 s，样本覆盖水平/垂直/45°斜线/Z 形急弯/近闭合环。
   - 以 `EditorDrawBrush(G, ann, s)` 分区渲染到一张 600×400 白底位图，保存 `tmp\_tmp_brushtest.png`。
   - 判定：端点圆弧帽、拐角圆滑无尖刺、s=0.5 时整体等比重绘。
   - 完成后按文件名逐个删除 `_tmp_brushtest.ahk` / `_tmp_brushtest.png` 及结果文件。

## 风险

1. 铅笔字形可用性（主要）：先验证，缺则换字形。
2. 抽稀口径：采用显示空间阈值，简化为缩放一致的取舍。
3. `Gdip_DrawLines` 对单点零长路径未定义：`points.Length < 2` 直接 return 规避。