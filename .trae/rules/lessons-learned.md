---
alwaysApply: true
---

# 经验教训（Lessons Learned）

## 构建与 CI

- autohotkey.com 下载链接被 Cloudflare JS 挑战拦截，改用 GitHub Releases 下载 ZIP 免安装版本。
- GitHub Actions 中使用 `GITHUB_TOKEN` 访问其他仓库会返回 401，改用匿名 API 或其他下载方式。
- winget 安装 AutoHotkey 在 GitHub Actions 环境存在兼容性问题，已弃用。
- 使用 `&` 调用 `AutoHotkey64.exe` 无法获取 GUI 进程退出码，改用 `Start-Process -Wait -PassThru` 读取真实退出码。
- `build.bat` 的 `/silent` 参数会隐藏 Ahk2Exe 编译错误，需修改为捕获并打印真实退出码和输出。
- 本机 PowerShell 是 5.1、CI 是 PowerShell 7，**语法与行为差异会导致「本地通过、CI 失败」**：如 `$LASTEXITCODE` 对 GUI 程序、三元运算符 `? :`（5.1 不支持）等。CI 相关改动应优先沿用工作流中已验证的写法，或在 PS 7 下验证。

## AHK v2 实测陷阱

- **第三方库勿与 AHK 内置函数同名**：`src/Common/Gdip_All_v2.ahk` 末尾曾自定义 `IsNumber`/`IsInteger`，静默覆盖 AHK 内置同名函数（只认数字类型、不认 `"09"` 这类数字字符串），曾导致设置窗口「保存设置总是报清空时刻格式错误」与 `config.ini` 整数配置被静默回退默认值；且该问题只在真实运行环境（加载了 Gdip）复现，只加载 Config 的探针/单测里却正常，极易误判。**已修复：库内函数改名 `Gdip_IsNumber`/`Gdip_IsInteger`**。约定：**判断「字符串是不是数字」统一用项目内的正则封装 `IsIntText()`**，不要用内置 `IsNumber()`（后者还会接受 `1.5`/`1e3` 等写法）。
- **`MsgBox` 的选项串必须是 AHK 认得的写法**：图标关键字只有 `Iconx`（错误）、`Icon?`（问号）、`Icon!`（警告）、`Iconi`（信息），**没有 `IconQuestion`**。写了非法选项，`MsgBox` 直接抛 `Invalid option.`，而 `GlobalError.ahk` 的 `OnError` 处理器为防模态框阻塞脚本会 `return 1` 把异常**静默吞掉**（只写日志），表现为「界面上提示有新版本，然后毫无反应」——排查这类「静默无反应」时，**先翻日志里的 `全局异常` 记录**。凡是「用户看不到任何反馈」的交互，都别让关键动作只依赖一个可能抛错的调用。
- **AHK v2 的 `Map[key]` 读「缺失键」会抛 `Item has no value.`**（不是返回空串）：读可能不存在的键必须用 `Map.Get(key, 默认值)` 或先 `Map.Has(key)` 判断。曾因此让「发布未附带 exe 资源」分支在到达判断前就抛错，同样被全局处理器吞掉。项目内已封装 `UpdateResultField()` / `PendingUpdateField()` 兜底。
- **测试脚本的顶层变量都是脚本级全局**（与 `src` 下所有模块同处一个作用域）：命名必须避开 `src` 里的局部变量名（如 `btn`、`file`、`b`），否则触发 `#Warn All` 的 `LocalSameAsGlobal` 告警；测试要求 0 告警，故改名即可（如 `btn` → `updBtnCtrl`）。
- **全局状态的初始化必须早于其首次使用**：`src` 各模块大量用「顶层 `global X := 初值`」初始化状态，而自动执行段自上而下执行；若某函数的顶层调用排在初始化语句之前，函数内读 `X` 会抛 `This global variable has not been assigned a value`。加状态时一律把初始化放到文件顶部、任何顶层调用之前（v0.4.1 闪屏字体缓存即因此启动即崩，见 Splash.ahk / Indicator.ahk）。
