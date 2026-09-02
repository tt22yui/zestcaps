# CLAUDE.md

本文件为仓库 `CLAUDE.md` 指南，汇总自 `.trae/rules/` 下的规则（git-commit-message.md 除外）供参考。实际以 `.trae/rules/` 内各规则文件为准。

## 角色与职责

- 本仓库主语言为 AutoHotkey（AHK v2）。工作时应遵循 AHK v2 语法与特性，并结合 Rust / React / TypeScript / Tailwind / Vite 等技术栈的最优实践。

- 对代码风格、健壮性、可维护性、交互细节提出专业建议。

- 遵循本仓库全部规则文件。

## git 操作约束

- **禁止 AI 自动** **`git push`**：改动仅提交到本地（`git commit`）即可；推送由用户主动执行或在其明确指示下进行，未获明确指示前不得推送到远程仓库。

- **开源隐私保护**：本仓库为开源项目。提交前须检查暂存内容是否含隐私/敏感信息，不得暴露——包括但不限于：个人真实路径（用户名/机器名）、密钥与口令、个人邮箱/姓名、本机配置文件（`.env`、`config.ini` 等含本地状态的文件）、日志中的敏感信息。发现可疑内容应暂停提交并向用户确认。

## 职责边界

- 只做被要求的事，不越界扩展。

- 不主动创建文档（`.md`/README）除非用户明确要求。

- 优先修改已有文件而非新建文件，避免文件堆砌。

## 代码风格

### 命名

- 常量/配置项：`UPPER_SNAKE_CASE`（如 `CAPS_COOLDOWN_MS`、`APP_VERSION`）。

- 函数/类：`PascalCase`（如 `HandleCapsLock`、`ShowInputIndicator`）。

- 模块功能开关变量：`PascalCase`（如 `IndicatorEnabled`、`PastePlainEnabled`）。

### 注释

- 使用项目主流语言（中文）书写注释。

- 章节用 `; ====` 或 `# ====` 分隔线包裹，小节用 `; -----`。

- 函数定义前添加功能说明注释头。

- 关键参数/逻辑在代码旁添加行尾注释。

### AHK 头部指令与作用域

- 脚本顶部声明 `#Requires AutoHotkey v2.0` 与 `#SingleInstance Force`。

- 全局变量显式使用 `global`；函数内需跨调用保留的变量用 `static`；避免隐式全局变量。

- 文件/资源路径统一基于 `A_ScriptDir`，不依赖工作目录。

### 语法写法

- 字符串使用双引号；字符串内引号用反引号（\`）转义，不用反斜杠。

- 复杂字符串拼接使用 `Format()`。

- 布尔判断直接写 `if var`。

- 禁用旧式语法：不使用 `%var%`、不使用 `=` 赋值，函数调用一律带括号。

### 排版格式

- 缩进 4 空格。

- `{` 与 if/else/函数 同行。

- 运算符两侧留空格，逗号后留空格，函数名与 `(` 之间不留空格。

- 超长行用续行拆分。

### 热键与健壮性

- 热键定义使用修饰键缩写（如 `^+v::`），上方注释注明完整含义。

- 使用 `Map()` 而非伪数组/关联数组。

- 对可能失败的调用（文件操作、IniRead、系统/窗口/网络调用等）用 try/catch 或等效机制包裹。

## 通用结构约定

- 新增功能/模块时，统一在 `src/` 目录下新建子目录（如 `InputSwitch`、`Clipboard`、`Screenshot`）。

- 模块内的共享/第三方代码统一放入 `Common/` 目录。

## 调试与验证

### 新功能开发流程

- 立项前先参考已有成熟项目（优先开源）的同类做法与交互设计，提炼可借鉴点再设计方案。

- 方案细节以向导形式与用户逐项确认（如 AskUserQuestion），确认后再实施。

- 涉及不熟悉 API（系统调用、原生窗口、消息钩子等）时，先写测试脚本验证关键技术可行性，确认可行再正式集成。

- 轻量改动（仅常量/简单逻辑调整，不涉及陌生 API）只需通过编译/加载检查即可，无需额外验证脚本。

### 测试与调试脚本

- 测试脚本放 `test/` 目录，命名语义化，按 Main.ahk 真实加载顺序引入被测模块。

- 临时调试脚本（一次性诊断/探针）放项目根 `tmp/`（已 gitignore，永不提交），命名 `_tmp_` 前缀，用完立即删除；确需长期复用再移入 `test/`。

- 严禁使用弹窗/交互/通知指令（MsgBox、InputBox、TrayTip 等）进行调试判定；错误统一在 try/catch 内写入结果文件，配合 stderr/退出码判定。

- 引用仓库文件用相对脚本路径（如 `#Include "..\src\Config\Config.ahk"`）。

- AHK 测试头部强制四件套：`#Requires AutoHotkey v2.0` + `#SingleInstance Force` + `#ErrorStdOut` + `#Warn All, StdOut`。

### 单元测试（Yunit）

- 纯逻辑模块必须编写单元测试；系统依赖型模块（窗口/剪贴板/输入法/托盘等）继续用集成测试脚本。

- 框架采用 Yunit（AGPL-3.0），已引入 `test/lib/Yunit/`；不要修改 Yunit.ahk 核心，适配只改 Stdout.ahk / JUnit.ahk。

- 单测文件命名 `test_unit_<模块>.ahk`；新增单测时追加到 `test/run_all_tests.ahk` 的 `tests` 列表。

- 失败数 > 0 → 退出码非 0。

### 窗口/GUI 测试

- 任何创建可见窗口的测试脚本必须内置看门狗（倒计时定时器，如 5 秒），到期强制销毁所有测试窗口并退出，防止残留。

- 全屏窗口/遮罩蒙版场景下看门狗为强制要求。

- 测试完成立即销毁窗口并退出，不留残留。

### 产物清理

- 结果/日志文件按是否复用决定去留：长期复用保留在 `test/`，一次性 `_tmp_*` 用完即删。

- 删除前先 `if FileExist` 判断或放入 try 包裹，可封装 `SafeDelete` 函数。

- 清理按具体文件名逐个删除，禁止通配符批量删除（避免误删）。

## 硬性约束（项目专属）

- 自动构建 workflow 需通过 `workflow_dispatch` 手动触发或推送 `v*` 标签自动触发。

- 构建前必须运行 Yunit 单测（`test/run_all_tests.ahk`），非零退出码即中止构建。

- 版本号获取方式：tag 触发取 tag 名，手动触发从 `src/Config/Config.ahk` 读取 `APP_VERSION`。

- 发布策略：打标签直接正式发布（不再存草稿）。

- 版本号升级只需修改 `src/Config/Config.ahk` 的 `APP_VERSION`（启动日志、托盘标题、构建产物命名均自动同步）。

- `.gitignore` 需包含 `src/Log/` 目录以忽略日志文件。

## 经验教训（Lessons Learned）

- autohotkey.com 下载链接被 Cloudflare JS 挑战拦截，改用 GitHub Releases 下载 ZIP 免安装版本。

- GitHub Actions 中使用 `GITHUB_TOKEN` 访问其他仓库会返回 401，改用匿名 API 或其他下载方式。

- winget 安装 AutoHotkey 在 GitHub Actions 环境存在兼容性问题，已弃用。

- 使用 `&` 调用 AutoHotkey64.exe 无法获取 GUI 进程退出码，改用 `Start-Process -Wait -PassThru` 读取真实退出码。

- `build.bat` 的 `/silent` 参数会隐藏 Ahk2Exe 编译错误，需修改为捕获并打印真实退出码和输出。

