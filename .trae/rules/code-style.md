---
alwaysApply: true
---

# 代码风格约定

## 命名

- 常量/配置项：`UPPER_SNAKE_CASE`（如 `CAPS_COOLDOWN_MS`、`IND_WIDTH`、`CONFIG_FILE`）。
- 函数名：PascalCase（如 `HandleCapsLock`、`ShowInputIndicator`）。
- 模块功能开关变量：PascalCase（如 `IndicatorEnabled`、`PastePlainEnabled`、`ScreenshotEnabled`）。

## 注释

- 注释统一使用中文。
- 章节用 `; ====` 分隔线包裹，小节用 `; -----` 分隔线。
- 函数定义前添加功能说明注释头。
- 关键参数/逻辑在代码旁添加行尾注释说明。

## 头部指令与作用域

- 脚本顶部声明 `#Requires AutoHotkey v2.0` 与 `#SingleInstance Force`。
- 全局变量显式使用 `global` 声明；函数内需跨调用保留的变量用 `static`；避免隐式全局变量。
- 文件/资源路径统一基于 `A_ScriptDir`，不依赖工作目录。

## 语法写法

- 字符串使用双引号；字符串内的引号用反引号转义（`` `" ``），不使用反斜杠。
- 复杂字符串拼接使用 `Format()`。
- 布尔判断直接写 `if var`，不写 `if var = true`。
- 禁用旧式语法：不使用 `%var%`、不使用 `=` 赋值（v2 已移除）、函数调用一律带括号。

## 排版格式

- 缩进使用 4 空格。
- `{` 与 if/else/函数 同行。
- 运算符两侧留空格（`a := b + c`），逗号后留空格，函数名与 `(` 之间不留空格。
- 超长行使用续行拆分，保持可读性。

## 热键

- 热键定义使用修饰键缩写（如 `^+v::`），并在上方注释注明完整含义（如 `Ctrl+Shift+V`）。

## 健壮性

- 对可能失败的调用（文件操作、配置读写、系统/窗口调用、网络请求等）使用 `try/catch` 或等效机制包裹。
- 使用语言/框架推荐的容器与集合类型（如 `Map()`）而非伪数组等易错写法。
- 避免隐式全局变量，作用域保持一致与显式。

## 测试脚本头部

- 测试脚本在常规头部（`#Requires AutoHotkey v2.0` / `#SingleInstance Force`）基础上，额外声明 `#ErrorStdOut` 与 `#Warn All, StdOut`（四件套），详见 [debug-workflow.md](debug-workflow.md)。
