---
alwaysApply: true
---

# 目录结构约定

- 新增功能/模块时，统一在 `src/` 目录下新建子目录，并将对应的脚本放入该子目录中。
- 子目录以功能命名（如 `InputSwitch`、`Clipboard`、`Screenshot`），与现有模块风格保持一致。
- 模块内的共享/第三方代码统一放入 `Common/` 目录中。
