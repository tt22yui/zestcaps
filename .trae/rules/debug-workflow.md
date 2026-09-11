---
alwaysApply: true
---

# 调试与验证约定

## 新功能开发流程

- 新功能/新模块立项前，**先参考已有成熟项目（优先开源）**的同类做法与交互设计，提炼可借鉴点（功能、交互、源码写法），再设计自身方案。
- 方案细节（功能范围、交互方式、默认值等）**以向导形式与用户逐项确认**（如 AskUserQuestion），确认后再动手实施。
- 开发新模块/新功能时，**先写测试脚本验证关键技术的可行性**（如窗口操作、DllCall、消息钩子等不熟悉的 API），确认可行后再正式集成到模块中。
- **轻量改动**（仅新增/修改配置项、常量、简单逻辑调整，不涉及不熟悉的 API 或复杂窗口交互）：只需通过「验证与检查」一节的编译加载检查（stderr 无 Error/Warning）即可，无需额外编写功能验证脚本。

## 测试脚本规范

- 测试脚本统一放在 `test/` 目录（与正式代码分离），命名使用语义化名称（如 `test_penwidth.ahk`），不使用 `_tmp_*` 前缀。
- **临时调试脚本**（排查问题时一次性生成的诊断/探针脚本，不纳入回归）：**不得放进 `test/`**，统一放到项目根目录 `tmp/` 文件夹（已在 `.gitignore` 中忽略，**永不提交**），命名用 `_tmp_` 前缀（如 `_tmp_probe_clip.ahk`）以便识别；验证完成后**立即删除**，不留存；只有确定要长期复用/复盘时，才移到 `test/` 纳入保留。
- 引用仓库文件时用相对脚本路径（如 `#Include "..\src\Config\Config.ahk"`），不依赖工作目录；且**按 Main.ahk 的真实加载顺序加载依赖模块**（如 Config → DebugLog → Screenshot），避免 `#Warn UseUnsetLocal` 等误报。
- 头部强制四件套：`#Requires AutoHotkey v2.0` + `#SingleInstance Force` + `#ErrorStdOut` + `#Warn All, StdOut`。各指令作用分工（AHK v2 实测与官方文档）：
  - `#ErrorStdOut` **只覆盖加载期语法错误**（官方文档原文仅针对 "syntax error that prevents the script from launching"），将其重定向到 stderr 而不是弹框；**不覆盖未捕获的运行时错误**——v2 中运行时错误一律弹框，只能靠 OnError 回调或 try/catch 处理，与 `#ErrorStdOut` 无关。
  - `#Warn All, StdOut` 把静态警告（如 UseUnsetLocal/VarUnset）输出到 stdout 而非默认弹框。**脚本不写 `#Warn` 时，AHK 默认所有警告都以 MsgBox 弹框**——这是"警告弹框"的根因，必须显式声明 `StdOut` 或 `Off`。`#Warn` 指令位置无关紧要（官方文档：location is not significant），放头部即可。
  - 注意：AHK 不是控制台程序，`#ErrorStdOut` 的 stderr 与 `#Warn StdOut` 的 stdout 都需重定向/管道（如 `2>&1`）才能被读取，直接双击运行看不到错误内容。
- **严禁使用任何弹窗/交互/通知指令**（`MsgBox`、`InputBox`、`FileSelect`、`DirSelect`、`TrayTip` 等）：错误统一在 `try/catch` 内写入临时结果文件，配合 `#ErrorStdOut` 由运行方读取 stderr/结果文件判断失败原因。
- **AHK v2 实测陷阱（务必避开）**：测试脚本不得注册 `OnError` 回调——若 `OnError(LogErr)` 位于 `try{}` 块内，AHK v2 块作用域会把函数名 `LogErr` 解析为「未赋值的局部变量」，必然抛 `Error: Invalid callback function.`，且与定义顺序无关；若回调未定义就注册同样抛错。加载期语法错误由 `#ErrorStdOut` 兜底；**运行时未捕获错误的弹框只能靠 try/catch 包住可疑位置来避免**（`#ErrorStdOut` 不覆盖运行时错误）；若确实需要全局捕获（如正式模块的 `GlobalError.ahk`），须**先定义回调 + 在顶层裸调用 `OnError`**，切勿放入 `try{}` 块。

## 单元测试（Yunit）

- 纯逻辑模块（Config、DebugLog、Clipboard 纯函数等）**必须编写单元测试**；系统依赖型模块（窗口/剪贴板/输入法/托盘等）继续用集成测试脚本，不强求单测。
- 框架采用开源 Yunit（AGPL-3.0），已引入到 `test/lib/Yunit/`（Yunit.ahk + Stdout.ahk + JUnit.ahk + README，含许可说明）。**不要修改 Yunit.ahk 核心**；适配只改 Stdout.ahk / JUnit.ahk 等输出模块，并保留注释说明。
- 单测文件命名 `test_unit_<模块>.ahk`，放 `test/` 目录；头部四件套 + Include Yunit 三件（Yunit.ahk / Stdout.ahk / JUnit.ahk）+ 按 Main.ahk 真实顺序 Include 被测模块。
- 测试类约定：类内每个 `test*` 方法为一个用例；`Begin()`/`End()` 为每个用例的前后钩子（在此改全局/临时文件，结束恢复原值）；断言用 `Yunit.Assert(条件, "失败信息")`；期望抛异常时在用例内设 `this.ExpectedException := Error("...")`。
- 运行入口固定模板（放在文件末尾）：

```ahk
YunitJUnit.OutputFile := A_ScriptDir "\junit_unit_<模块>.xml"
tester := Yunit.Use(YunitStdOut, YunitJUnit)
tester.Test(<模块>UnitTest)
YunitJUnit.Last.WriteXml()   ; ExitApp 不触发 __Delete，必须显式落盘
ExitApp YunitJUnit.Last.tests.fail ? 1 : 0
```

- 聚合运行：`test/run_all_tests.ahk` 用 RunWait 逐个运行各单测，按退出码汇总；**新增单测时把脚本名追加到该文件 `tests` 列表**。单跑：直接运行 `test_unit_<模块>.ahk`（有 stdout 管道时能看到逐条 PASS/FAIL）。
- **AHK v2 实测陷阱（务必避开）**：
  - AHK 是 GUI 程序：**无 stdout 管道/重定向时 `FileAppend(..., "*")` 抛 `(6) 句柄无效` 并弹框**（属运行时错误，非警告）。YunitStdOut 已用 try/catch 静默——无管道时不回显但**不弹框**；要看逐条结果须从 PowerShell 管道（如 `*>&1`）运行。
  - **`ExitApp` 不触发对象的 `__Delete()` 析构**：YunitJUnit 靠 `__Delete` 写 XML 会不落盘，必须显式调用 `WriteXml()`（模板已包含）。
  - **`FileOpen` 默认按系统 ANSI 编码写入**：写 XML 必须显式 `"UTF-8-RAW"`，否则中文乱码且外部解析器报错。
  - 测 Clipboard 等加载即注册 OnExit / OnClipboardChange 的模块时，退出前用 `OnExit(回调, 0)` 移除退出落盘，避免测试退出改写用户真实数据。
- 判定与产物：失败数 > 0 → 退出码非 0；每模块独立生成 `test/junit_unit_<模块>.xml`（合法 UTF-8），可直接供 CI（如 GitHub Actions）收集。

## 验证与检查

- 所有测试脚本运行前，确保脚本**编译无错误、无警告**：用真实模块文件（通过 `#Include` 加载）验证完整加载流程，避免只测单文件导致遗漏；运行后检查是否有 `Error` / `Warning` 输出（`#ErrorStdOut` 走 stderr、`#Warn StdOut` 走 stdout，用 `2>&1` 合并后统一检查）。
- 若脚本仍有非必要的静态分析误报（如跨 `#Include` 的全局变量误报），可再追加 `#Warn All, Off` 覆盖（后出现的 `#Warn` 生效，放头部末尾即可），但正式模块代码不得屏蔽；屏蔽后以运行期 stderr 输出为准。

## 无窗口与窗口测试

- 自行调试排查问题时，请使用无窗口（headless）的脚本，避免弹窗打扰用户；验证结果写入临时文件（如 `tmp\_tmp_*.txt`，放项目根目录 `tmp/` 下），通过读取结果文件判断测试是否通过。
- 窗口/GUI 测试中创建的可见窗口是**测试对象**，不受弹窗禁令约束；但**任何创建可见窗口的测试脚本**（GUI、工具栏、遮罩蒙版等）**必须内置看门狗**（倒计时自动恢复保护），避免脚本出错或卡住后窗口残留打扰用户：
  - 脚本启动后立即注册一个 `SetTimer`（如 5 秒），到期强制销毁所有测试窗口并 `ExitApp`。
  - 若脚本卡死在窗口操作（如 WinSetRegion/DllCall 挂起），看门狗必须仍能触发恢复屏幕。
  - 测试完成后立即销毁窗口并退出，不留残留。
  - 全屏窗口/遮罩蒙版场景下看门狗为强制要求（防止全屏被蒙住导致用户无法操作）。

## 产物清理

- `test/` 目录下的测试脚本与日志文件**保留不删除**，留作后续复盘与复用。
- 测试运行产生的临时结果文件（如 `tmp\_tmp_*.txt`）与临时调试脚本（如 `tmp\_tmp_*.ahk`）**用完即清理**，不遗留任何 `_tmp_*` 文件在 `tmp/` 或仓库中；清理时**禁止使用 `Get-ChildItem *_tmp* | Remove-Item` 一类通配批量删除**，须按具体文件名逐个删除，避免误删其他文件。
- 删除/读取/操作临时文件时，**严禁把操作直接裸露在脚本顶部**：删除前先 `if FileExist(文件路径)` 判断，或放入 `try` 包裹的代码块；若文件可能不存在，统一定义并使用 `SafeDelete(文件路径)` 函数。

## 授权

- 需要工具/命令授权时，尽量一次性批量请求授权，不要逐条弹窗请求用户确认。
