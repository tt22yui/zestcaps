# 马赛克工具改为「笔触式」实现计划

## Context

截图标注编辑器的「马赛克」工具当前是**拖拽矩形区域**局部打码。用户希望改为「像画笔一样沿自由轨迹涂抹马赛克」（brush-style mosaic），交互与已实现的新画笔工具一致。

已与用户确认：
- **直接替换**：把现有 "mosaic" 工具整体改为笔触式，工具栏保持一个马赛克按钮（图标 ▦ 不变），不新增并存工具。
- **笔头粗细跟随线宽档位**：马赛克笔头半径 = 当前所选线宽 × 放大系数（EDIT_LINE_WIDTHS=[2,3,6] 太细，需系数放大到可见马赛克笔头）。

## 核心思路

沿用「采样压缩 + 最近邻放大」的马赛克机制，但作用域从矩形改为「沿笔触路径的圆头蒙版」：

1. 笔触用复用画笔的 `ann.points`（多点折线），笔头半径 `R = ann.penWidth * MULT`（图片空间）。
2. 渲染时先对**笔触外接包围盒**（所有点外扩 R，裁剪到图内）做一次马赛克压缩缓存（`ann.mosaic`，复用现有字段与缓存/释放逻辑）。
3. 再用 GDI+ 裁剪蒙版（Graphics 的 `SetClipPath` + 沿各点叠加圆）只把**笔触经过的圆头轮廓**内的区域呈现为马赛克，其余保持原图。

## 关键耦合（已探明）

- Gdip 库已具备所需 API：`Gdip_CreatePath`(L2537)、`Gdip_AddPathEllipse`(L2544)、`Gdip_SetClipPath`(L2720, CombineMode=0 即替换)、`Gdip_ResetClip`(L2726)、`Gdip_DeletePath`(L2565)。
- 多圆的单个 GraphicsPath 在 `SetClipPath(Replace)` 下解析为全部圆的并集 → 正好形成圆头笔触蒙版。
- `EditorReleaseAnnotationCache`(L426) 只释放 `ann.mosaic`，笔触马赛克仍只有一张缓存 band，**无需改动**。
- `EditorDrawAnnotation` 的 `case "mosaic"` 分发起始点不变（仍指 `EditorDrawMosaic`）。
- 工具栏 "mosaic" 条目不变。

## 改动文件

### 1) src\Config\Config.ahk（EDIT_MOSAIC_CELL 附近 L121 之后）

新增常量：

```
EDIT_MOSAIC_BRUSH_MULT := 8   ; 马赛克笔头半径 = 线宽 × 此系数（图片空间像素）
```

> EDIT_LINE_WIDTHS=[2,3,6] → 笔头半径 16/24/48，直径 32/48/96，涂抹明显且三档可辨。粒度仍由 EDIT_MOSAIC_CELL=10 决定块大小。

### 2) src\Screenshot\Editor.ahk

**（a）重写 `EditorDrawMosaic(G, ann, s)`（L391-423）**，改为笔触渲染：

```
EditorDrawMosaic(G, ann, s) {
    global EditorBaseBitmap, EditorImgW, EditorImgH, EDIT_MOSAIC_CELL, EDIT_MOSAIC_BRUSH_MULT
    if !ann.points || ann.points.Length < 2
        return
    R := Max(8, ann.penWidth * EDIT_MOSAIC_BRUSH_MULT)   ; 笔头半径（图片空间）
    ; 外接包围盒（图片空间，外扩 R，裁剪到图内）
    minX := Min(全部 p.x) - R,  minY := Min(全部 p.y) - R
    maxX := Max(全部 p.x) + R,  maxY := Max(全部 p.y) + R
    x1 := Max(0, minX), y1 := Max(0, minY)
    x2 := Min(EditorImgW, maxX), y2 := Min(EditorImgH, maxY)
    rw := x2 - x1, rh := y2 - y1
    if (rw < 2 || rh < 2)
        return
    ; 缓存 band：包围盒尺寸变化（拖动点增多/变大）→ 重建
    if (ann.mosaic && (ann.mosaicRw != rw || ann.mosaicRh != rh)) {
        Gdip_DisposeImage(ann.mosaic)
        ann.mosaic := 0
    }
    if !ann.mosaic {
        k := EDIT_MOSAIC_CELL
        smallW := Max(1, Round(rw / k)), smallH := Max(1, Round(rh / k))
        ann.mosaic := Gdip_CreateBitmap(smallW, smallH)
        G2 := Gdip_GraphicsFromImage(ann.mosaic)
        Gdip_SetInterpolationMode(G2, 3)          ; Bilinear 压缩平均
        Gdip_DrawImage(G2, EditorBaseBitmap, 0, 0, smallW, smallH, x1, y1, rw, rh)
        Gdip_DeleteGraphics(G2)
        ann.mosaicRw := rw, ann.mosaicRh := rh
    }
    ; 圆头笔触蒙版：沿各点叠加圆、缩放 s，裁剪后仅笔触区域呈现马赛克
    Gdip_GetImageDimensions(ann.mosaic, &mw, &mh)
    Gdip_SetInterpolationMode(G, 5)               ; NearestNeighbor 放大 → 像素块
    Gdip_SetClipPath(G, Gdip_CreatePillPath(ann.points, R * s), 0)  ; CombineMode=Replace
    Gdip_DrawImage(G, ann.mosaic, x1 * s, y1 * s, rw * s, rh * s, 0, 0, mw, mh)
    Gdip_ResetClip(G)
    Gdip_SetInterpolationMode(G, 6)               ; 恢复高质双线性
}
```

辅助（沿点生成圆头蒙版路径；仅内部使用）：

```
; 生成笔触圆头蒙版路径：沿各点画半径为 radius 的圆（并集形成圆头笔迹）
EditorCreatePillPath(points, radius) {
    pPath := Gdip_CreatePath()
    for p in points
        Gdip_AddPathEllipse(pPath, p.x * s - radius, p.y * s - radius, 2*radius, 2*radius)  ; 注意 s 需传入
    return pPath
}
```

> 注意：`Gdip_AddPathEllipse` 需要显示坐标，故 `EditorCreatePillPath` 需接收 s 参数（圆心 `p.x*s, p.y*s`，直径 `R*s`）。用于`Gdip_SetClipPath(G, EditorCreatePillPath(ann.points, s, R*s), 0)`，用后 `Gdip_DeletePath`。
> 路径本身不缩放，需在构造时逐点多 s 与 R*s。

**（b）鼠标事件三处把 `EditorTool = "brush"` 扩展为 `EditorTool in "brush","mosaic"`（或给 points 系工具统一）**：
- `EditorLButtonDown`（L466-469）：初始化 points 的条件改为 `EditorTool in "brush","mosaic"`。
- `EditorMouseMove`（L491-492）：追加采样点条件同样扩展。
- `EditorLButtonUp`（L544）：`tooSmall := EditorPending.type in "brush","mosaic" && EditorPending.points.Length < 2`。

> （可选，更整洁）定义工具常量集合 `EDIT_STROKE_TOOLS := ["brush","mosaic"]` 并在三处用 Map 判断，避免重复字符串字面量；但为最小改动，用 `in` 操作符即可，注释注明。

**（c）工具栏**：mosaic 条目与图标 ▦ 不变，无需改动。

## 性能与取舍

- 每次包围盒变化重压缩整个 band = O(band 面积)；拖动时随包围盒增长重做。对通常规模可接受（与现状矩形马赛克同量级），不做增量分块优化。
- 圆头蒙版路径点数受 `EDIT_BRUSH_MIN_DIST` 抽稀约束（≈每 3px 一点），规模小；`GdipSetClipPath` + 单次 `DrawImage` 高效。
- 不新增 `ann.mosaic` 之外的资源；释放逻辑（`EditorReleaseAnnotationCache`）不变。

## 验证

1. **Headless 渲染脚本**（tmp\ 下 `_tmp_mosaic_brush.ahk`，禁弹框、结果写文件、无窗口故无看门狗）：
   - `#Include` 顺序：Config → Gdip → Editor（Editor 顶层仅定义，不触发 ShowEditor）。
   - 设置全局 `EditorBaseBitmap` 为一张彩色渐变/条纹源图，`EditorImgW/H` 为其尺寸。
   - 构造若干 `EditorAnnotation`（`type="mosaic"`、`points` 为一段折线/曲线、`penWidth` 遍历 [2,3,6]），以 `EditorDrawMosaic(G, ann, 1.0)` 与 `s=0.5` 各渲染到一张 640×400 白底位图，保存 `tmp\_tmp_mosaic_brush.png`。
   - 判定：马赛克块**只出现在圆头笔迹内**（非矩形）、笔头随 penWidth 变粗、s=0.5 等比缩小且马赛克颗粒同步缩放、边缘圆滑无锯齿缺口。
2. **编译加载检查**：加载链 exit=0、stderr/stdout 无 `Error`/`Warning`（仅残留既有 #Include 跨文件的静态误报可忽略，正式代码不屏蔽）。
3. 完成后按文件名删除 `_tmp_*` 脚本与结果文件（保留预览 PNG 供查看）。

## 风险

1. 圆头笔迹在采样点间距大于笔头直径时有缝隙（快速甩动）：以 `EDIT_BRUSH_MIN_DIST=3` ≪ 最小笔头直径(≤32) 兜底，正常速度无缝隙；如遇极端快速需插值补圆，暂不做。
2. `Gdip_SetClipPath` 的 CombineMode 需确认 0=Replace（已查实现即 `"int", CombineMode`，传 0）。
3. `EditorCreatePillPath` 需要 s 传入才正确缩放圆头尺寸，务必在构造时缩放。