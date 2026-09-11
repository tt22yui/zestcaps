---
name: "release"
description: "Executes a software release prep workflow: update the changelog, bump the patch version by one, commit to git, and create a local v* tag, without pushing by default. Invoke when the user asks to release, tag a version, bump a version number, or update the release log."
---

# Release 发布技能

按步骤完成一次软件发布的前置工作：更新发布日志 → 升版本号 → git 提交 → 建本地 tag。**默认不推送远程**，推送仅在用户明确指示时执行。

## 触发时机

- 用户说「发布 / 发版 / 打 tag / 更新发布日志 / 准备发新版本」等。
- 用户要求把已提交的特性整理成一个新版本。

## 流程

### 1. 识别本项目约定

先确认两个位置，不同项目可能不同：

- **发布日志文件**：查找 `CHANGELOG.md`（或 README 中的版本记录、`RELEASES.md` 等）。
- **版本号定义文件**：常见于 `src/Config/Config.ahk` 的 `APP_VERSION`、`Cargo.toml` 的 `version`、`package.json` 的 `version` 等。以该项目实际为准。

> 版本号只应在**一处**定义；若发现多处，以项目约定处为准并保持一致。

### 2. 更新发布日志

- 在日志顶部的版本区按 **Keep a Changelog** 格式新增一节：

  ```markdown
  ## [x.y.z] - YYYY-MM-DD

  ### 新增
  - ...

  ### 修复
  - ...

  ### 变更
  - ...
  ```

- 条目从 `[Unreleased]` 的未发布内容或近期提交中提取，语言与项目主流语言一致。
- 版本号和日期先占位，第 3 步确定后再回填（日期用当前日期）。

### 3. 检查 tag 并升版本号

- 读取当前版本（版本定义文件 / 最新 tag `vX.Y.Z`）。
- **若用户没有明确指定新版本号** → 将当前版本 **patch 位 +1**：
  - `0.3.2 → 0.3.3`、`1.0.0 → 1.0.1`（`semver` 规则，不足位自动补 `0`）。
- **防冲突校验**：确认新版本对应的 tag `v<新版本>` 尚不存在（`git tag -l "v<新版本>"` 为空才继续）；若已存在，停下来询问用户（可能重复发布）。
- **同步版本定义文件**：把版本号改为新版本，保证构建读取到新版本（产物命名、启动日志等自动跟随）。

### 4. git 提交（本地）

- 暂存本次改动（发布日志 + 版本号变更等相关文件）。
- 提交前检查暂存内容不含隐私/密钥/个人路径。
- 用 conventional commit 提交到**本地**：

  ```bash
  git commit -m "chore(release): 发布 v<新版本>"
  ```

### 5. 建本地 tag（不 push）

- 在本地创建 tag，**不得 push**：

  ```bash
  git tag "v<新版本>"
  ```

- 结尾向用户说明：剩余发布动作（`git push` 与 `git push --tags` 触发 CI 发布）**留给你主动执行**。

## 硬性约束

- **不自动 `git push`**：除非用户在当前对话里明确要求推送，否则只提交、建本地 tag。
- 日志日期使用「今天」实际日期；若跨天，以执行当天为准。
- 新版本号未被明确指定时，只升 patch，不擅自升级 minor/major。