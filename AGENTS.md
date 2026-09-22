# AGENTS.md

本文件是仓库的**跨工具常驻入口**（Claude Code、Trae 等）。这里**只做导航**，不维护规则正文——规则一律维护在 `.trae/rules/`，避免多处漂移。

## 规则

完整规则以 [`.trae/rules/`](.trae/rules/) 为权威，各文件用途如下（索引同见 [ai-engineering-practices.md](.trae/rules/ai-engineering-practices.md)）：

| 规则 | 位置 | 覆盖 |
|------|------|------|
| 通用 AI 工程规范 | [ai-engineering-practices.md](.trae/rules/ai-engineering-practices.md) | 身份、职责边界、细则索引 |
| 角色与 git 约束 | [agent-role.md](.trae/rules/agent-role.md) | AHK 专家身份、`git push` 禁令、提交前处理未提交改动、开源隐私保护 |
| 代码风格 | [code-style.md](.trae/rules/code-style.md) | 命名、注释、作用域、语法、排版、健壮性 |
| 调试与验证 | [debug-workflow.md](.trae/rules/debug-workflow.md) | 开发流程、测试脚本、单元测试、GUI 看门狗、产物清理 |
| 目录结构 | [directory-structure.md](.trae/rules/directory-structure.md) | `src/` 按功能建目录、共享/第三方代码入 `Common/` |
| 项目专属约束 | [project-constraints.md](.trae/rules/project-constraints.md) | 构建与 CI、版本与发布、发布日志收录范围、仓库卫生 |
| 经验教训 | [lessons-learned.md](.trae/rules/lessons-learned.md) | 构建/CI 踩坑、AHK v2 实测陷阱 |
| git 提交信息 | [git-commit-message.md](.trae/rules/git-commit-message.md) | Conventional Commits（中文） |

## 技能

仓库技能位于 `.trae/skills/`，遵循通用 Agent Skills 规范（`SKILL.md`），可整体拷贝或软链到任意 AI 工具的技能目录使用。

| 技能 | 位置 | 用途 | 触发 |
|------|------|------|------|
| release | [.trae/skills/release/SKILL.md](.trae/skills/release/SKILL.md) | 软件发布前置流程：更新发布日志、patch 版本号 +1、git 提交、建本地 `v*` tag（默认不推送） | 「发布 / 发版 / 打 tag / 更新发布日志 / 准备发新版本」 |

## 各工具的入口

- Claude Code：读 [CLAUDE.md](CLAUDE.md)（同样只作导航）。
- Trae / 其他：直接读本文件。
