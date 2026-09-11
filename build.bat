@echo off

REM ==================================================================
REM One-click build: zestcaps_v<version>.exe
REM Entry script: src\Main.ahk   Icon: resources\capslock.ico
REM Version: read from src\Config\Config.ahk (APP_VERSION)
REM ==================================================================

setlocal enabledelayedexpansion
set "ROOT=%~dp0"
set "SRC=%ROOT%src\Main.ahk"
set "ICON=%ROOT%resources\capslock.ico"

REM ---------- Read version from Config.ahk ----------
REM 依赖 src\Config\Config.ahk 中形如  APP_VERSION := "0.3.3"  的单行定义（:= 两侧有空格）
set "VER="
for /f "tokens=3" %%v in ('findstr /b /c:"APP_VERSION" "%ROOT%src\Config\Config.ahk"') do set "VER=%%~v"
REM 解析失败必须报错退出，不能静默降级成 dev（否则产物名变成 zestcaps_vdev.exe 却仍算成功）
if not defined VER (
    echo [ERROR] Failed to parse APP_VERSION from src\Config\Config.ahk
    echo         Expected a line like: APP_VERSION := "0.3.3"
    if not defined GITHUB_ACTIONS pause
    exit /b 1
)

set "OUT=%ROOT%output\zestcaps_v%VER%.exe"

REM ---------- Ensure output directory exists ----------
if not exist "%ROOT%output" mkdir "%ROOT%output"

REM ---------- 候选 AutoHotkey 安装根目录（去重，仅在此定义一次） ----------
set "AHK_ROOT1=C:\Program Files\AutoHotkey"
set "AHK_ROOT2=C:\Program Files (x86)\AutoHotkey"
set "AHK_ROOT3=%LOCALAPPDATA%\Programs\AutoHotkey"

REM ---------- 从首个存在的安装根推导编译器 Ahk2Exe 与基础解释器 AutoHotkey64(v2) ----------
set "AHK2EXE="
set "BASE="

REM ---------- CI 便携根（AHK_ROOT）：ZIP 免安装，Compiler 与 AutoHotkey64.exe 位于该根下 ----------
if defined AHK_ROOT (
    if not defined AHK2EXE if exist "%AHK_ROOT%\Compiler\Ahk2Exe.exe" set "AHK2EXE=%AHK_ROOT%\Compiler\Ahk2Exe.exe"
    if not defined BASE if exist "%AHK_ROOT%\AutoHotkey64.exe" set "BASE=%AHK_ROOT%\AutoHotkey64.exe"
    if not defined BASE if exist "%AHK_ROOT%\v2\AutoHotkey64.exe" set "BASE=%AHK_ROOT%\v2\AutoHotkey64.exe"
)

for %%R in (AHK_ROOT1 AHK_ROOT2 AHK_ROOT3) do (
    for /f "delims=" %%P in ("!%%R!") do (
        if not defined AHK2EXE if exist "%%P\Compiler\Ahk2Exe.exe" set "AHK2EXE=%%P\Compiler\Ahk2Exe.exe"
        if not defined BASE if exist "%%P\v2\AutoHotkey64.exe" set "BASE=%%P\v2\AutoHotkey64.exe"
    )
)

if not defined AHK2EXE (
    echo [ERROR] Ahk2Exe.exe not found. Install AutoHotkey v2 with the Compiler component.
    if not defined GITHUB_ACTIONS pause
    exit /b 1
)

if not defined BASE (
    echo [ERROR] AutoHotkey64.exe ^(v2^) not found.
    if not defined GITHUB_ACTIONS pause
    exit /b 1
)

REM ---------- Validate input files ----------
if not exist "%SRC%" (
    echo [ERROR] Source not found: %SRC%
    if not defined GITHUB_ACTIONS pause
    exit /b 1
)
if not exist "%ICON%" (
    echo [ERROR] Icon not found: %ICON%
    if not defined GITHUB_ACTIONS pause
    exit /b 1
)

echo.
echo Compiler : %AHK2EXE%
echo Base      : %BASE%
echo Source    : %SRC%
echo Output    : %OUT%
echo Icon      : %ICON%
echo.
echo Compiling...

REM 直接调用（非 start）以读取退出码，并将 Ahk2Exe 输出重定向到临时日志以便排查
REM 保留 /silent：它只关掉 Ahk2Exe 的图形进度界面，编译错误仍会写入下方日志（实测）
set "AHK_LOG=%TEMP%\_tmp_ahk2exe.log"
REM 编译前先删除旧产物：否则本次编译失败时，上一版 exe 仍在，会被下方的存在性判断误判为成功
if exist "%OUT%" del /f /q "%OUT%"
"%AHK2EXE%" /silent /in "%SRC%" /out "%OUT%" /icon "%ICON%" /base "%BASE%" /compress 0 > "%AHK_LOG%" 2>&1
set "AHK_RC=%ERRORLEVEL%"
echo Ahk2Exe exit code: %AHK_RC%
if exist "%AHK_LOG%" (
    REM 关掉延迟展开再回显：Ahk2Exe 输出里若含 ! 会被延迟展开吃掉（日志失真）
    setlocal DisableDelayedExpansion
    for /f "usebackq delims=" %%L in ("%AHK_LOG%") do echo %%L
    endlocal
    del "%AHK_LOG%" >nul 2>&1
)

REM 双重判定：非零退出码 或 未生成产物（已先删旧产物，故产物存在即本次编译成功）
if not "%AHK_RC%"=="0" (
    echo.
    echo [FAIL] Ahk2Exe exited with code %AHK_RC%. See errors above.
    if not defined GITHUB_ACTIONS pause
    exit /b %AHK_RC%
)

if not exist "%OUT%" (
    echo.
    echo [FAIL] exe not generated. See errors above.
    if not defined GITHUB_ACTIONS pause
    exit /b 1
)

echo.
echo [OK] Generated: %OUT%
endlocal
exit /b 0
