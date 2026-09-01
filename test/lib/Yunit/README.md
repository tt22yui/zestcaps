# Yunit (AutoHotkey v2 分支)

第三方单元测试框架，引入自 [Uberi/Yunit](https://github.com/Uberi/Yunit) 的 `v2` 分支。

- 许可：GNU AGPL-3.0（见 [LICENSE](https://github.com/Uberi/Yunit/blob/v2/LICENSE.txt)）
- 文件说明：
  - `Yunit.ahk` — 框架核心（`Yunit.Use(输出模块...).Test(测试类...)`）
  - `Stdout.ahk` — `YunitStdOut`，逐条输出 PASS/FAIL 到 stdout
  - `JUnit.ahk` — `YunitJUnit`，汇总输出 JUnit XML 到 `A_ScriptDir\junit.xml`
- 本项目适配：JUnit.ahk 修正了 AHK v2 下 Error 属性大小写（`Line`/`Message`）并补充 XML 转义。

## 用法

```ahk
#Include "lib\Yunit\Yunit.ahk"
#Include "lib\Yunit\Stdout.ahk"
#Include "lib\Yunit\JUnit.ahk"
#Include "..\src\Config\Config.ahk"

class ConfigUnitTest {
    test_常量存在() {
        Yunit.Assert(IsSet(APP_VERSION))
    }
}

; 跑完退出码 0；失败时 Yunit.Assert 抛错 → 测试标记 FAIL
Yunit.Use(YunitStdOut, YunitJUnit).Test(ConfigUnitTest)
ExitApp 0
```

测试类约定：每个 `test*` 方法是一个用例；`Begin()`/`End()` 为每个用例的前后钩子；
断言失败用 `Yunit.Assert(条件, "信息")`；期望抛出异常时在用例内设置 `this.ExpectedException := Error("...")`。
