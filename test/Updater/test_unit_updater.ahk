; ==================================================================
; 单元测试：Updater 模块 —— Release JSON 解析 / sha256 首行读取 / SHA256 计算
; 覆盖纯函数：ParseGithubRelease、ReadFirstHash、SHA256Hex
; 单跑：AutoHotkey64 test\Updater\test_unit_updater.ahk
; 聚合：AutoHotkey64 test\run_all_tests.ahk
; 判定：失败数 > 0 时退出码非 0；详细结果见 junit_unit_updater.xml 与 stdout
; 说明：
;   - Updater.ahk 无 #Include 依赖，且只在函数内以 global 引用 Config 常量（加载期不读配置），
;     故本测试不 include src\Config\Config.ahk，避免 Config.ahk 按 A_ScriptDir
;     在 test 目录下生成 config.ini，污染工作区
;   - 下方先补 APP_VERSION / APP_GITHUB_API_URL 最小占位值，保证相关函数被调用时
;     不触发 #Warn All 的 UseUnsetGlobal 告警
;   - 临时文件统一放 A_Temp、以 _tmp_ 前缀命名，每个用例结束即删
; ==================================================================
#Requires AutoHotkey v2.0
#SingleInstance Force
#ErrorStdOut
#Warn All, StdOut

#Include "..\lib\Yunit\Yunit.ahk"
#Include "..\lib\Yunit\Stdout.ahk"
#Include "..\lib\Yunit\JUnit.ahk"

; Config 常量占位（仅本测试使用：Config.ahk 不加载，避免其在 test 目录生成 config.ini）
APP_VERSION := "0.0.0"
APP_GITHUB_API_URL := ""
#Include "..\..\src\Updater\Updater.ahk"

; ==================================================================
; 测试辅助（必须是脚本级函数：Yunit 会把测试类的每个方法都当成用例执行，
; 带参助手方法放在类里会被无参调用而报错）
; ==================================================================

; 写入精确字节内容（UTF-8-RAW：无 BOM、无换行；纯 ASCII 即原始字节）
UpdaterTestWriteRaw(path, text) {
    if FileExist(path)
        try FileDelete(path)
    FileAppend text, path, "UTF-8-RAW"
}

; 清理临时文件（逐个删除，不用通配符）
UpdaterTestCleanup(paths) {
    for p in paths {
        if FileExist(p)
            try FileDelete(p)
    }
}

; ==================================================================
; 用例
; ==================================================================
class UpdaterUnitTest {
    Begin() {
        ; 每个用例独立的临时路径（A_Temp + _tmp_ 前缀）
        this._abc := A_Temp "\_tmp_unit_updater_abc.txt"
        this._same := A_Temp "\_tmp_unit_updater_same.txt"
        this._empty := A_Temp "\_tmp_unit_updater_empty.bin"
        this._sha := A_Temp "\_tmp_unit_updater_sha256.txt"
        this._missing := A_Temp "\_tmp_unit_updater_missing.txt"
        if FileExist(this._missing)
            try FileDelete(this._missing)
    }

    End() {
        UpdaterTestCleanup([this._abc, this._same, this._empty, this._sha])
    }

    ; -------- ParseGithubRelease --------
    test_解析tag与首个exe下载地址() {
        ; 贴近 GitHub Releases API 真实返回：缩进多行 + 资源列表
        json := '
        (
        {
          "tag_name": "v0.4.0",
          "assets": [
            {
              "name": "zestcaps_v0.4.0.exe",
              "browser_download_url": "https://github.com/x/y/releases/download/v0.4.0/zestcaps_v0.4.0.exe"
            },
            {
              "name": "zestcaps_v0.4.0.exe.sha256",
              "browser_download_url": "https://github.com/x/y/releases/download/v0.4.0/zestcaps_v0.4.0.exe.sha256"
            }
          ]
        }
        )'
        result := NewUpdateResult("", "0.3.2", false)
        ParseGithubRelease(json, &result)
        Yunit.Assert(result["latestTag"] = "v0.4.0", "latestTag 应为 v0.4.0，实际: [" result["latestTag"] "]")
        Yunit.Assert(result["latestVersion"] = "0.4.0", "latestVersion 应去掉 v 前缀，实际: [" result["latestVersion"] "]")
        Yunit.Assert(result["exeUrl"] = "https://github.com/x/y/releases/download/v0.4.0/zestcaps_v0.4.0.exe", "exeUrl 解析错误，实际: [" result["exeUrl"] "]")
        Yunit.Assert(result["shaUrl"] = result["exeUrl"] ".sha256", "shaUrl 应为 exeUrl + .sha256，实际: [" result["shaUrl"] "]")
    }

    test_跳过sha256与非exe资源() {
        ; sha256 资源排在 exe 之前 → 必须跳过，取真正的 exe 地址
        json := '{"tag_name":"v0.4.1","assets":['
            . '{"browser_download_url":"https://example.com/zestcaps_v0.4.1.exe.sha256"},'
            . '{"browser_download_url":"https://example.com/release_notes.txt"},'
            . '{"browser_download_url":"https://example.com/zestcaps_v0.4.1.zip"},'
            . '{"browser_download_url":"https://example.com/zestcaps_v0.4.1.exe"}]}'
        result := Map()
        ParseGithubRelease(json, &result)
        Yunit.Assert(result.Has("exeUrl"), "应解析出 exeUrl")
        Yunit.Assert(result["exeUrl"] = "https://example.com/zestcaps_v0.4.1.exe", "应取首个 .exe 且非 .sha256 的地址，实际: [" result["exeUrl"] "]")
        Yunit.Assert(result["shaUrl"] = "https://example.com/zestcaps_v0.4.1.exe.sha256", "shaUrl 解析错误，实际: [" result["shaUrl"] "]")
    }

    test_无匹配资源时不写入字段() {
        ; 只有 sha256 资源 → 不应写入 exeUrl / shaUrl，也不应改写已有版本字段
        result := NewUpdateResult("", "0.3.2", false)
        ParseGithubRelease('{"tag_name":"v0.4.1","assets":[{"browser_download_url":"https://example.com/a.exe.sha256"}]}', &result)
        Yunit.Assert(result["latestVersion"] = "0.4.1", "latestVersion 应被解析，实际: [" result["latestVersion"] "]")
        Yunit.Assert(!result.Has("exeUrl"), "无 .exe 资源时不应写入 exeUrl")
        Yunit.Assert(!result.Has("shaUrl"), "无 .exe 资源时不应写入 shaUrl")

        ; 完全无 tag_name/assets → 保持调用方初始化值不变
        untouched := NewUpdateResult("", "0.3.2", false)
        ParseGithubRelease('{"message":"Not Found"}', &untouched)
        Yunit.Assert(untouched["latestVersion"] = "", "无 tag_name 时不应改写 latestVersion，实际: [" untouched["latestVersion"] "]")
        Yunit.Assert(!untouched.Has("latestTag"), "无 tag_name 时不应写入 latestTag")
        Yunit.Assert(untouched["needUpdate"] = false, "解析不应改动 needUpdate")
    }

    test_tag前缀v去除() {
        ; 本仓库发布 tag 恒为 v*（.github\workflows\build.yml 的 tags: 'v*'，
        ; 手动触发时也强制 "v$version"），latestVersion 即"去掉 v 前缀"后的版本号，
        ; 与 build.yml 的 $tag -replace '^v','' 口径一致
        for tag in ["v0.4.0", "v0.4.1", "v1.2.3", "v10.20.30"] {
            result := Map()
            ParseGithubRelease('{"tag_name":"' tag '"}', &result)
            expect := RegExReplace(tag, "^v", "")
            Yunit.Assert(result["latestVersion"] = expect, "latestVersion 应为 " expect "，实际: [" result["latestVersion"] "]")
        }
        ; 版本号需可被 VerCompare 比较（供 UpdaterFinishRequest 判 needUpdate）
        Yunit.Assert(VerCompare("0.4.0", "0.3.2") > 0, "0.4.0 应大于 0.3.2")
    }

    test_tag无v前缀不被截断() {
        ; 回归：曾用 SubStr(tag, 2) 无条件截首字符，"0.4.0" 会被解析成 ".4.0"（版本比较错乱）。
        ; 现在按 '^v' 去前缀，无 v 前缀的 tag 必须原样保留
        for tag in ["0.4.0", "1.0.0", "10.20.30"] {
            result := Map()
            ParseGithubRelease('{"tag_name":"' tag '"}', &result)
            Yunit.Assert(result["latestVersion"] = tag, "无 v 前缀应原样保留 " tag "，实际: [" result["latestVersion"] "]")
            Yunit.Assert(VerCompare(result["latestVersion"], "0.3.3") > 0, tag " 应大于 0.3.3")
        }
        ; 大写 V 前缀同样去除（RegExReplace 用 (?i)）
        result := Map()
        ParseGithubRelease('{"tag_name":"V0.4.0"}', &result)
        Yunit.Assert(result["latestVersion"] = "0.4.0", "大写 V 前缀也应去除，实际: [" result["latestVersion"] "]")
    }

    ; -------- ReadFirstHash --------
    test_ReadFirstHash取首行哈希() {
        ; 发布产物格式（build.yml：Out-File "hash  filename"）：CRLF + 两空格分隔
        line1 := "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        line2 := "88d4266fd4e6338d13b845fcf289579d209c897823b9217da3e161936f031589"
        UpdaterTestWriteRaw(this._sha, line1 "  zestcaps_v0.4.0.exe`r`n" line2 "  other.exe`r`n")
        Yunit.Assert(ReadFirstHash(this._sha) = line1, "应返回首行哈希，实际: [" ReadFirstHash(this._sha) "]")
    }

    test_ReadFirstHash兼容单空格与LF换行() {
        h := "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
        ; LF 换行 + 单空格分隔（sha256sum 风格）
        UpdaterTestWriteRaw(this._sha, h " zestcaps.exe`n")
        Yunit.Assert(ReadFirstHash(this._sha) = h, "单空格/LF 应仍取到哈希，实际: [" ReadFirstHash(this._sha) "]")
        ; 无结尾换行（Out-File -NoNewline 场景）
        UpdaterTestWriteRaw(this._sha, h "  zestcaps.exe")
        Yunit.Assert(ReadFirstHash(this._sha) = h, "无结尾换行应仍取到哈希，实际: [" ReadFirstHash(this._sha) "]")
        ; TAB 分隔（部分 sha256sum 实现）→ 不得把文件名并进哈希
        UpdaterTestWriteRaw(this._sha, h "`tzestcaps.exe`n")
        Yunit.Assert(ReadFirstHash(this._sha) = h, "TAB 分隔应只取哈希，实际: [" ReadFirstHash(this._sha) "]")
        ; 行尾多余空格
        UpdaterTestWriteRaw(this._sha, h "   ")
        Yunit.Assert(ReadFirstHash(this._sha) = h, "行尾空格应被忽略，实际: [" ReadFirstHash(this._sha) "]")
    }

    test_ReadFirstHash文件缺失返回空() {
        Yunit.Assert(!FileExist(this._missing), "前置条件：该路径不应存在")
        Yunit.Assert(ReadFirstHash(this._missing) = "", "文件缺失应返回空串，实际: [" ReadFirstHash(this._missing) "]")
    }

    test_ReadFirstHash空文件与空行返回空() {
        ; 回归：曾直接取 StrSplit(raw, "`n")[1]，文件为 0 字节时抛 "Invalid index"，
        ; 被调用方吞成「下载失败」提示（误导排查）。现在应安全返回空串。
        h := "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
        UpdaterTestWriteRaw(this._sha, "")
        Yunit.Assert(ReadFirstHash(this._sha) = "", "0 字节文件应返回空串，实际: [" ReadFirstHash(this._sha) "]")
        UpdaterTestWriteRaw(this._sha, "   `t`r`n")
        Yunit.Assert(ReadFirstHash(this._sha) = "", "仅空白内容应返回空串，实际: [" ReadFirstHash(this._sha) "]")
        UpdaterTestWriteRaw(this._sha, "`r`n" h "  x.exe`r`n")
        Yunit.Assert(ReadFirstHash(this._sha) = "", "首行为空行应返回空串（不越过首行取哈希），实际: [" ReadFirstHash(this._sha) "]")
    }

    ; -------- SHA256Hex --------
    test_SHA256已知向量abc() {
        ; 精确 3 字节：ASCII "abc"（61 62 63），无 BOM、无换行
        UpdaterTestWriteRaw(this._abc, "abc")
        Yunit.Assert(FileGetSize(this._abc) = 3, "临时文件应恰为 3 字节，实际: " FileGetSize(this._abc))
        hash := SHA256Hex(this._abc)
        Yunit.Assert(hash = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", "abc 的 SHA256 不匹配，实际: [" hash "]")
        Yunit.Assert(RegExMatch(hash, "^[0-9a-f]{64}$") > 0, "应为 64 位小写十六进制，实际: [" hash "]")
    }

    test_SHA256变更后哈希不同() {
        ; 内容相同 → 与文件名/路径无关，哈希相同
        UpdaterTestWriteRaw(this._abc, "abc")
        UpdaterTestWriteRaw(this._same, "abc")
        h1 := SHA256Hex(this._abc)
        Yunit.Assert(SHA256Hex(this._same) = h1, "内容相同应得到相同哈希")
        ; 原地多一个字节 → 哈希必须变化，且等于 "abcd" 的已知值
        UpdaterTestWriteRaw(this._abc, "abcd")
        h2 := SHA256Hex(this._abc)
        Yunit.Assert(h2 != h1, "内容变更后哈希不应相同，实际均为: [" h1 "]")
        Yunit.Assert(h2 = "88d4266fd4e6338d13b845fcf289579d209c897823b9217da3e161936f031589", "abcd 的 SHA256 不匹配，实际: [" h2 "]")
    }

    test_SHA256空文件已知值() {
        UpdaterTestWriteRaw(this._empty, "")
        Yunit.Assert(FileGetSize(this._empty) = 0, "临时文件应为 0 字节")
        Yunit.Assert(SHA256Hex(this._empty) = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "空文件的 SHA256 不匹配，实际: [" SHA256Hex(this._empty) "]")
    }
}

; ---- 运行入口（单跑或由 run_all_tests.ahk 调用）----
YunitJUnit.OutputFile := A_ScriptDir "\junit_unit_updater.xml"
tester := Yunit.Use(YunitStdOut, YunitJUnit)
tester.Test(UpdaterUnitTest)
YunitJUnit.Last.WriteXml()   ; ExitApp 不触发 __Delete，需显式落盘 XML
ExitApp YunitJUnit.Last.tests.fail ? 1 : 0
