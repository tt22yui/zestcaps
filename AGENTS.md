# AGENTS.md

本文件供各类 AI 编程/编码代理读取，作**跨工具常驻入口**（Claude Code、Trae 等）。

## Skills

仓库的 `release` 技能位于 [`.trae/skills/release/SKILL.md`](.trae/skills/release/SKILL.md)，遵循通用 Agent Skills 规范（`SKILL.md`），可整体拷贝或软链到任意 AI 工具的技能目录使用。

| 技能 | 位置 | 用途 | 触发 |
|------|------|------|------|
| release | [.trae/skills/release/SKILL.md](.trae/skills/release/SKILL.md) | 软件发布前置流程：更新发布日志、patch 版本号 +1、git 提交、建本地 `v*` tag（默认不推送） | 「发布 / 发版 / 打 tag / 更新发布日志 / 准备发新版本」 |

## 规则约定

本项目完整规则以 [`.trae/rules/`](.trae/rules/) 为权威，摘要见 [CLAUDE.md](CLAUDE.md)。本文件仅作入口，**不重复维护规则**，避免两处漂移。