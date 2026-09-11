# 工具栏合并：选区模式与编辑模式共用一套跨阶段持久工具栏

## Context（背景）

截图工具存在两套悬浮工具栏：

- **选区工具栏**（[Screenshot.ahk](src/Screenshot/Screenshot.ahk) `SelToolbarCreate`)：单行 row1 = 工具 ▭/→/◯/▦ + 保存/钉屏/复制。
- **编辑工具栏**（[Editor.ahk](src/Screenshot/Editor.ahk) `EditorCreateToolbar`)：两行 row1（结构同前）+ row2（颜色/线宽/清除）。

两套 row1 几乎一模一样，但各自创建/销毁、选中态分读 `state.tool` 与 `EditorTool`。选区→编辑切换时 row1 被隐藏→重建→重淡入，视觉上有"消失又出现"的跳动。

**目标**：合并为**一套跨阶段持久**的工具栏。选区阶段只显示 row1、隐藏 row2；点工具=选工具+自动色1+进入编辑；进编辑时 **row1 原样保留**（不重建、不重淡入），只补显 row2、把锚点从"选区矩形"重锚到"编辑窗"，过渡最丝滑；同时消除 row1 重复代码。

**统一思路**：把 `EditorTool` / `EditorColorIdx` 提升为选区+编辑**共享的单一真源**；工具点击行为用**单一分发回调 + 全局 `ToolbarPhase` 阶段标志**区分（规避 AHK v2 `OnEvent` 二次注册追加 handler 无法覆盖的问题）；选区动作结果从 `state.action` 改走全局 `ScreenToolbarResult`（使回调不捕获选区局部 `state`，可跨阶段复用）；生命周期上给销毁函数加 `keepToolbar` 参数，编辑路径由编辑器接管 row1 的所有权。

**部署原则**：优先改已有文件，不新建模块文件；row1/row2 构建与分发收敛到 `Editor.ahk`（工具栏本就是其概念归属），`Screenshot.ahk` 只留选区阶段的薄胶水。

---

## 文件改动总览

### 1. Editor.ahk —— 工具栏构建与分发（核心）

**新增全局**（文件顶部）：
- `ToolbarPhase := ""` —— `"selection"` / `"editor"` / `""`，决定按钮点击行为。
- `ScreenToolbarResult := ""` —— 选区阶段动作结果通道（`"editor"`/`save`/`pin`/`copy`），替代 `state.action`。

**复用既有全局**：`EditorTool` / `EditorColorIdx` / `EditorPenWidthIdx`（单一真源）、`EditorToolbar` / `EditorColorToolbar`（row1/row2 句柄，row1 跨阶段持久）、`EditorToolbarW/H`（尺寸缓存）。

**新增函数**：
- `ScreenToolbarCreateRow1(dpiFrom := 0)`：拆旧 row1 构建（`EditorCreateToolbar` L532-569 与 `SelToolbarCreate` row1 的公共部分）。幂等：`if EditorToolbar return EditorToolbar`。`dpiFrom > 0` 时 `SetToolbarDpiScale(dpiFrom)`（编辑窗复用其 DPI）；否则按旧选区写法临时 Show 读鼠标所在屏 DPI。工具按钮接 `ToolbarToolClick.Bind(name)`，输出按钮接 `ToolbarOutputClick.Bind("save"/"pin"/"copy")`。`selFn := EditorIsSelectedTool.Bind(EditorToolButtons)`，`ToolbarHoverActive := .HoverState`。AutoSize→缓存 W/H→CacheRects→Hide。返回 `EditorToolbar`。
- `ScreenToolbarCreateRow2()`：拆旧 row2 构建（L571-599）。幂等：`if EditorColorToolbar return`。挂 `ToolbarHoverAux := .HoverState`。AutoSize→缓存→Hide。
- `ToolbarToolClick(name, *)`：`phase="selection"` → 写 `EditorTool := name`、`EditorColorIdx := 1`、`ScreenToolbarResult := "editor"`（进入编辑，old 行为）；`phase="editor"` → 只写 `EditorTool` + `EditorToolbarRefresh()`（颜色不重置）。
- `ToolbarOutputClick(action, *)`：`phase="selection"` → `ScreenToolbarResult := action`；`phase="editor"` → 转发 `EditorSave/EditorPin/EditorCopy`。
- `EditorPromoteSelectionToolbar()`：`SetToolbarDpiScale(EditorHwnd)` → `ScreenToolbarCreateRow2()`（幂等补行2）→ `ToolbarPhase := "editor"` → `EditorRepositionToolbar()`（锚点切到编辑窗）→ Show 两行 → FadeIn 两行。

**改动既有函数**：
- 删除 `EditorSetTool`（L663，并入 `ToolbarToolClick`）。
- `EditorCreateToolbar()` 瘦身（保留函数名，供快速截图全量路径）：`if EditorToolbar return`（防御）→ `SetToolbarDpiScale(EditorHwnd)` → `ScreenToolbarCreateRow1(EditorHwnd)` + `ScreenToolbarCreateRow2()` → `ToolbarPhase := "editor"` → `EditorRepositionToolbar()` → Show + FadeIn。
- `ShowEditor`（L152 附近）：`if EditorToolbar`（非 0，已由选区 promote）→ `EditorPromoteSelectionToolbar()`；`else` → `EditorCreateToolbar()`（快速截图建全量）。随后统一 `EditorToolbarRefresh()`。
- `EditorIsSelectedTool` / `EditorToolbarRefresh` / `EditorCloseOverlays` / `EditorSave` 及其 dialog 隐藏/恢复链、DragWindow 的 hide/show：均不变（行1/行2 变量名本就一致）。

### 2. Screenshot.ahk —— 选区阶段薄胶水

- **删除**全局 `SelToolbarW/H`（L43），统一用 `EditorToolbarW/H`。
- **state 对象裁剪**（L321-322）：去掉 `action/tool/colorIdx/selTb/toolBtns`，仅留 `canceled/confirmed/isDragging/dragStartX/Y/hoverX/Y/region`。选区开始时重置单一真源：`EditorTool := ""`、`EditorColorIdx := 1`、`ScreenToolbarResult := ""`。
- `SelToolbarCreate(state, region)` 瘦身为薄包装：`tb := ScreenToolbarCreateRow1(0)` → `ToolbarPhase := "selection"` → `SelToolbarsReposition(tb, region)` → Show + FadeIn；返回 `tb`（`ScreenshotAdjustCtx.toolbar` 仍记 row1 引用供 `_ApplyAdjustRect` 跟随）。
- `SelToolbarsReposition`：内部 `SelToolbarW/H` → `EditorToolbarW/H`，其余不动。
- `_DestroyOverlays`（L478）加 `keepToolbar := false` 参数：`if toolbar && !keepToolbar { ...销毁 + 清 ToolbarHoverActive... }`；`keepToolbar=true` 时整块跳过（**不清 `ToolbarHoverActive`**，编辑接管期继续要用）。
- `FinishSelectionOverlays(keepMask, keepBorders, keepToolbar := false)`（L505）：透传 `keepToolbar` 给 `_DestroyOverlays`。
- **结果通道改写**：`state.action` → 全局 `ScreenToolbarResult`：
  - 等待循环 L570：`while !state.canceled && ScreenToolbarResult = ""`
  - 返回 L577：`return state.canceled ? "cancel" : ScreenToolbarResult`
  - 保存框取消重置 L449/L452：`ScreenToolbarResult := ""`
  - 双击复制 L605 / L626：`ScreenToolbarResult := "copy"`
  - L462-463 `initialTool/initialColor` → `EditorTool` / `EditorColorIdx`
- **编辑入口 Bind**（L950）：`FinishSelectionOverlays.Bind(true, true, true)` —— 保留 row1 所有权给编辑器。
- **删除** `SelToolbarAction`（L850-859）与 `SelIsToolSelected`（L839-844）。

### 3. Common\ToolbarUI.ahk / Main.ahk
预计**无需改动**（复用 `ToolbarPlaceUnder` 多行、悬停、Swatch、分隔线原语）。加载顺序已保证 `Screenshot #Include Editor.ahk`。实施时确认无额外 include 需改。

---

## 生命周期所有权转移（防重复销毁 / 泄漏 / 悬空）

| 事件 | row1 | row2 | 归属 |
|---|---|---|---|
| 选区建 row1 | 创建，active 指向其 HoverState | 无 | 选区 |
| ShowEditor `leftoverCleanup.Bind(true,true,true)` | `keepToolbar` 跳过销毁，`ScreenshotSelOverlays` 清 0，active 保持 | — | 移交编辑器 |
| ShowEditor promote | 复用不重建 | `ScreenToolbarCreateRow2` 建，aux 指向 | 编辑器 |
| Editor 结束 `EditorCloseOverlays` | 销毁 + 清 active | 销毁 + 清 aux | — |
| 选区 cancel/save/copy/pin/异常 | 默认 keepToolbar=false 销毁 + 清 active | — | — |

- **不重复销毁**：编辑路径唯一销毁入口 `EditorCloseOverlays`（ShowEditor 的 try/catch 兜底 `EditorCleanup` 也经它）；`leftoverCleanup` 因 keepToolbar=true 不再销毁 row1；Screenshot 外层 catch（L952）的 `FinishSelectionOverlays()` 因 `ScreenshotSelOverlays` 已清 0 而早退 no-op。
- **不悬空**：销毁时都先判 `ToolbarHoverActive = 该 HoverState` 才清 0；keepToolbar 路径下 active 合法持续指向 row1。

---

## 两条分支（覆盖快速截图路径）

- **拖出矩形**：`SelToolbarCreate` 建 row1 → 点工具 → `ScreenToolbarResult := "editor"` → ShowEditor promote（补 row2）。
- **只点窗口不拖矩形**（`isDragging=false`，Screenshot L426-427 分支不变）：不建 row1 → `EditorToolbar=0` → ShowEditor 走 `else EditorCreateToolbar()` 全量两行，`ToolbarPhase := "editor"`。

---

## 潜在陷阱与规避

1. **OnEvent 二次注册追加**：靠 `ScreenToolbarCreateRow1/2` 的 `if 已存在 return` 幂等守卫 + promote 不重建 row1，确保每控件只 `OnEvent("Click",...)` 一次。
2. **闭包捕获悬空**：不再把选区局部 `state` Bind 进回调，改用全局 `ScreenToolbarResult` + `EditorTool` + phase 分流。
3. **资源残留误选中**：每会话选区开始必须 `EditorTool := ""`，否则上一会话残留会被 `EditorIsSelectedTool` 误判选中态。
4. **DPI**：row1 在选区用"临时 Show 读鼠标 DPI"定格；row2 在 promote 用 `SetToolbarDpiScale(EditorHwnd)`。编辑窗定位在选区之上（同屏→同 DPI），尺寸缓存一致。`ToolbarDpiScale` 是单全局，promote 建 row2 会覆盖它——但 row1 尺寸已缓存（AutoSize 后不再重排），无影响。
5. **MaskOverlay/BorderStrips**：只动锚点，无结构改动；`FinishSelectionOverlays(true,true,true)` 依旧 keep mask/borders 就地升级。
6. **DragWindow**：编辑阶段 `EditorLButtonDown/Up` 已按 `EditorToolbar/EditorColorToolbar` 处理两行，变量名一致无需改；promote 后 row2 存在，`EditorRepositionToolbar` 自然带两行。

---

## 验证

1. **编译加载检查**（遵循仓库规则）：全量加载链 stderr 无 `Error`/`Warning`。
2. **现有测试回归**（必须通过，均在 `test/Screenshot/`）：
   - `test_toolbar_dpi.ahk`（测 Common/ToolbarUI 原语）
   - `test_dblclick_copy.ahk`（纯逻辑；头注释引用 `state.action`，逻辑不受影响；若 `#Warn` 静态误报按该文件既有惯例处理）
   - `test_pin_resize.ahk`（pin 路径 `FinishSelectionOverlays(false,true)` keepToolbar 默认 false）
3. **新增集成脚本** `test/Screenshot/test_toolbar_promote.ahk`（GUI 系统依赖型，按规则：头部四件套、带看门狗、`#Include` 按 Main 顺序、结果写临时文件禁弹窗判定）验证：
   - 选区建 row1：`EditorToolbar` 存在、`ToolbarPhase="selection"`、row2 为 0、`ScreenToolbarResult=""`。
   - promote：`EditorColorToolbar` 非 0、`ToolbarPhase="editor"`、`EditorToolbar` 引用前后一致（`==` 证不重建）、锚点切到编辑窗。
   - `ToolbarToolClick`：选区 phase 写真源+置色+`ScreenToolbarResult="editor"`；编辑 phase 再点不改色。
   - `_DestroyOverlays(keepToolbar:=true)` 不销毁 row1、不清 active；`false` 则销毁+清。
4. 本改动为 GUI 系统依赖型，不强求 Yunit 纯逻辑单测；不新增 run_all_tests 项。

## 执行顺序

1. Editor.ahk：新增全局 + `ScreenToolbarCreateRow1/Row2` + `ToolbarToolClick/ToolbarOutputClick` + `EditorPromoteSelectionToolbar`；瘦身 `EditorCreateToolbar`；改 `ShowEditor` 分支；删 `EditorSetTool`。
2. Screenshot.ahk：删 `SelToolbarW/H`、state 裁剪 + 真源/结果通道重置、`SelToolbarCreate` 瘦身、`SelToolbarsReposition` 改全局名、`_DestroyOverlays`/`FinishSelectionOverlays` 加 `keepToolbar`、L950 Bind、结果通道改写、删 `SelToolbarAction`/`SelIsToolSelected`。
3. 编译加载检查 → 回归 3 个现有测试。
4. 补 `test_toolbar_promote.ahk` 验证。