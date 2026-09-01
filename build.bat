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
set "VER="
for /f "tokens=3" %%v in ('findstr /b /c:"APP_VERSION" "%ROOT%src\Config\Config.ahk"') do set "VER=%%~v"
if not defined VER set "VER=dev"

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
set "AHK_LOG=%TEMP%\_tmp_ahk2exe.log"
"%AHK2EXE%" /silent /in "%SRC%" /out "%OUT%" /icon "%ICON%" /base "%BASE%" /compress 0 > "%AHK_LOG%" 2>&1
set "AHK_RC=%ERRORLEVEL%"
echo Ahk2Exe exit code: %AHK_RC%
if exist "%AHK_LOG%" (
    for /f "usebackq delims=" %%L in ("%AHK_LOG%") do echo %%L
    del "%AHK_LOG%" >nul 2>&1
)

if exist "%OUT%" (
    echo.
    echo [OK] Generated: %OUT%
) else (
    echo.
    echo [FAIL] exe not generated. See errors above.
    if not defined GITHUB_ACTIONS pause
    exit /b 1
)

endlocal
