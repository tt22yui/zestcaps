---
alwaysApply: true
---

# 项目专属硬性约束

## 构建与 CI

- 自动构建 workflow 需通过 `workflow_dispatch` 手动触发，或推送 `v*` 标签自动触发。
- 构建前必须运行 Yunit 单测（`test/run_all_tests.ahk`），非零退出码即中止构建。
- 版本号获取方式：tag 触发取 tag 名；手动触发从 `src/Config/Config.ahk` 读取 `APP_VERSION`。

## 版本与发布

- 版本号只在一处定义：`src/Config/Config.ahk` 的 `APP_VERSION`（启动日志、托盘标题、构建产物命名均自动同步）；升级版本只改这一处。
- 发布策略：打标签直接正式发布（不再存草稿）。
- 发布日志（`CHANGELOG.md`）只记录用户可感知的变更：**收录**新增功能、bug 修复、行为变更、性能优化、移除/废弃；**不收录**重构、测试、CI/构建、依赖升级、AI 技能、文档等纯工程性内容。发布流程见 [release 技能](../skills/release/SKILL.md)。

## 仓库卫生

- `.gitignore` 需包含 `src/Log/` 目录以忽略日志文件。
