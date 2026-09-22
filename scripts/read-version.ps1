# ==================================================================
# 读取应用版本号（唯一真源 src\Config\Config.ahk 的 APP_VERSION）
# 输出：纯版本号（不含 v 前缀），如 0.4.0
# 由 build.bat 与 .github\workflows\build.yml 共用，避免版本解析规则双份漂移
# 解析规则：匹配行首 APP_VERSION := "x.y.z"，取首个引号内的值
# 兼容 Windows PowerShell 5.1（powershell）与 PowerShell 7（pwsh）
# ==================================================================
$cfg = Join-Path $PSScriptRoot "..\src\Config\Config.ahk"
$line = Get-Content -LiteralPath $cfg -Encoding UTF8 |
    Where-Object { $_ -match '^\s*APP_VERSION\s*:=' } | Select-Object -First 1
$m = [regex]::Match($line, '"([^"]+)"')
if (-not $m.Success) {
    Write-Error "未能从 src\Config\Config.ahk 解析 APP_VERSION"
    exit 1
}
Write-Output $m.Groups[1].Value
