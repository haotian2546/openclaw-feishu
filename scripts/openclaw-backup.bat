@echo off
setlocal enabledelayedexpansion
chcp 65001 >nul 2>&1

:: ============================================================
:: OpenClaw 完整备份与还原工具 (Windows)
:: 支持跨系统迁移，保留所有数据
:: ============================================================

set "VERSION=1.0.0"

if defined OPENCLAW_HOME (
    set "OPENCLAW_DIR=%OPENCLAW_HOME%"
) else (
    set "OPENCLAW_DIR=%USERPROFILE%\.openclaw"
)

if defined OPENCLAW_BACKUP_DIR (
    set "BACKUP_DIR=%OPENCLAW_BACKUP_DIR%"
) else (
    set "BACKUP_DIR=%USERPROFILE%\openclaw-backups"
)

for /f "tokens=2 delims==" %%I in ('wmic os get localdatetime /value 2^>nul') do set "DT=%%I"
set "DATE_TAG=%DT:~0,4%%DT:~4,2%%DT:~6,2%_%DT:~8,2%%DT:~10,2%%DT:~12,2%"

if "%~1"=="" goto :usage
if "%~1"=="help" goto :usage
if "%~1"=="-h" goto :usage
if "%~1"=="--help" goto :usage
if "%~1"=="backup" goto :backup
if "%~1"=="restore" goto :restore_entry
if "%~1"=="list" goto :list
if "%~1"=="info" goto :info_entry

:usage
echo.
echo OpenClaw 备份还原工具 v%VERSION% (Windows)
echo.
echo 用法:
echo   %~nx0 backup  [--output ^<path^>]  [--no-media]
echo   %~nx0 restore ^<backup_file^>      [--dry-run]   [--force]
echo   %~nx0 list
echo   %~nx0 info    ^<backup_file^>
echo.
echo 命令:
echo   backup   创建完整备份
echo   restore  从备份还原
echo   list     列出所有本地备份
echo   info     查看备份详情
echo.
echo 备份选项:
echo   --output ^<path^>   指定输出路径（默认 %%USERPROFILE%%\openclaw-backups\）
echo   --no-media        不备份媒体文件（语音、图片等）
echo.
echo 还原选项:
echo   --dry-run         仅预览，不实际还原
echo   --force           覆盖已有数据（默认会提示确认）
echo.
echo 环境变量:
echo   OPENCLAW_HOME       OpenClaw 数据目录（默认 %%USERPROFILE%%\.openclaw）
echo   OPENCLAW_BACKUP_DIR 备份存储目录（默认 %%USERPROFILE%%\openclaw-backups）
echo.
exit /b 0

:: ============================================================
:: 备份
:: ============================================================
:backup
shift
set "OUTPUT_DIR=%BACKUP_DIR%"
set "INCLUDE_MEDIA=1"

:backup_args
if "%~1"=="" goto :backup_start
if "%~1"=="--output" (
    set "OUTPUT_DIR=%~2"
    shift & shift
    goto :backup_args
)
if "%~1"=="--no-media" (
    set "INCLUDE_MEDIA=0"
    shift
    goto :backup_args
)
echo [ERROR] 未知选项: %~1
exit /b 1

:backup_start
if not exist "%OPENCLAW_DIR%" (
    echo [ERROR] OpenClaw 目录不存在: %OPENCLAW_DIR%
    exit /b 1
)

if not exist "%OUTPUT_DIR%" mkdir "%OUTPUT_DIR%"

set "BACKUP_NAME=openclaw_%DATE_TAG%"
set "STAGING=%TEMP%\%BACKUP_NAME%"
if exist "%STAGING%" rmdir /s /q "%STAGING%"
mkdir "%STAGING%"

echo [INFO] 开始备份 OpenClaw 数据...
echo [INFO] 源目录: %OPENCLAW_DIR%

:: 核心配置
echo [INFO] 备份核心配置...
if exist "%OPENCLAW_DIR%\openclaw.json" (
    copy /y "%OPENCLAW_DIR%\openclaw.json" "%STAGING%\" >nul
    echo [OK] openclaw.json
) else (
    echo [WARN] openclaw.json 不存在
)
for %%f in ("%OPENCLAW_DIR%\openclaw.json.bak*") do (
    copy /y "%%f" "%STAGING%\" >nul 2>nul
)

:: Agent 数据
if exist "%OPENCLAW_DIR%\agents" (
    echo [INFO] 备份 Agent 数据（聊天记录、会话）...
    xcopy /e /i /q /y "%OPENCLAW_DIR%\agents" "%STAGING%\agents" >nul
    echo [OK] agents
)

:: Workspace
if exist "%OPENCLAW_DIR%\workspace" (
    echo [INFO] 备份 Workspace（记忆、人设、技能）...
    xcopy /e /i /q /y "%OPENCLAW_DIR%\workspace" "%STAGING%\workspace" >nul
    echo [OK] workspace
)

:: 设备配对
if exist "%OPENCLAW_DIR%\devices" (
    echo [INFO] 备份设备配对信息...
    xcopy /e /i /q /y "%OPENCLAW_DIR%\devices" "%STAGING%\devices" >nul
    echo [OK] devices
)

:: 身份认证
if exist "%OPENCLAW_DIR%\identity" (
    echo [INFO] 备份身份认证...
    xcopy /e /i /q /y "%OPENCLAW_DIR%\identity" "%STAGING%\identity" >nul
    echo [OK] identity
)

:: 凭据
if exist "%OPENCLAW_DIR%\credentials" (
    echo [INFO] 备份凭据...
    xcopy /e /i /q /y "%OPENCLAW_DIR%\credentials" "%STAGING%\credentials" >nul
    echo [OK] credentials
)

:: 定时任务
if exist "%OPENCLAW_DIR%\cron" (
    echo [INFO] 备份定时任务...
    xcopy /e /i /q /y "%OPENCLAW_DIR%\cron" "%STAGING%\cron" >nul
    echo [OK] cron
)

:: 执行审批
if exist "%OPENCLAW_DIR%\exec-approvals.json" (
    copy /y "%OPENCLAW_DIR%\exec-approvals.json" "%STAGING%\" >nul
)

:: Canvas
if exist "%OPENCLAW_DIR%\canvas" (
    xcopy /e /i /q /y "%OPENCLAW_DIR%\canvas" "%STAGING%\canvas" >nul
    echo [OK] canvas
)

:: 媒体文件
if "%INCLUDE_MEDIA%"=="1" (
    if exist "%OPENCLAW_DIR%\media" (
        echo [INFO] 备份媒体文件...
        xcopy /e /i /q /y "%OPENCLAW_DIR%\media" "%STAGING%\media" >nul
        echo [OK] media
    )
) else (
    echo [WARN] 跳过媒体文件（--no-media）
)

:: 写入元数据
(
echo {
echo   "version": "%VERSION%",
echo   "createdAt": "%DATE_TAG%",
echo   "hostname": "%COMPUTERNAME%",
echo   "os": "Windows-%PROCESSOR_ARCHITECTURE%",
echo   "openclawDir": "%OPENCLAW_DIR:\=/%",
echo   "includeMedia": %INCLUDE_MEDIA%,
echo   "encrypted": false
echo }
) > "%STAGING%\.backup-meta.json"

:: 打包（使用 PowerShell 的 zip）
set "ARCHIVE=%OUTPUT_DIR%\%BACKUP_NAME%.zip"
echo [INFO] 打包中...
powershell -NoProfile -Command "Compress-Archive -Path '%STAGING%\*' -DestinationPath '%ARCHIVE%' -Force"

rmdir /s /q "%STAGING%"

echo.
echo [OK] 备份完成！
echo   文件: %ARCHIVE%
for %%A in ("%ARCHIVE%") do echo   大小: %%~zA bytes
echo.
exit /b 0

:: ============================================================
:: 还原
:: ============================================================
:restore_entry
shift
if "%~1"=="" (
    echo [ERROR] 请指定备份文件路径
    echo 用法: %~nx0 restore ^<backup_file^> [--dry-run] [--force]
    exit /b 1
)
set "BACKUP_FILE=%~1"
shift
set "DRY_RUN=0"
set "FORCE=0"

:restore_args
if "%~1"=="" goto :restore_start
if "%~1"=="--dry-run" (
    set "DRY_RUN=1"
    shift
    goto :restore_args
)
if "%~1"=="--force" (
    set "FORCE=1"
    shift
    goto :restore_args
)
echo [ERROR] 未知选项: %~1
exit /b 1

:restore_start
if not exist "%BACKUP_FILE%" (
    echo [ERROR] 备份文件不存在: %BACKUP_FILE%
    exit /b 1
)

:: 解压到临时目录
set "TMP_RESTORE=%TEMP%\openclaw_restore_%DATE_TAG%"
if exist "%TMP_RESTORE%" rmdir /s /q "%TMP_RESTORE%"
mkdir "%TMP_RESTORE%"

:: 支持 .zip 和 .tar.gz（tar.gz 需要 tar 命令，Win10+ 自带）
echo "%BACKUP_FILE%" | findstr /i ".zip" >nul
if %errorlevel%==0 (
    powershell -NoProfile -Command "Expand-Archive -Path '%BACKUP_FILE%' -DestinationPath '%TMP_RESTORE%' -Force"
) else (
    tar -xzf "%BACKUP_FILE%" -C "%TMP_RESTORE%" 2>nul
    if errorlevel 1 (
        echo [ERROR] 解压失败，请确认文件格式为 .zip 或 .tar.gz
        rmdir /s /q "%TMP_RESTORE%"
        exit /b 1
    )
)

:: 找到备份根目录（含 .backup-meta.json 的目录）
set "BACKUP_ROOT="
for /r "%TMP_RESTORE%" %%f in (.backup-meta.json) do (
    if exist "%%f" set "BACKUP_ROOT=%%~dpf"
)
:: 去掉末尾反斜杠
if defined BACKUP_ROOT set "BACKUP_ROOT=%BACKUP_ROOT:~0,-1%"

if not defined BACKUP_ROOT (
    echo [ERROR] 无效的备份文件（缺少元数据）
    rmdir /s /q "%TMP_RESTORE%"
    exit /b 1
)

:: 显示备份信息
echo.
echo [INFO] 备份信息:
type "%BACKUP_ROOT%\.backup-meta.json"
echo.

:: 列出内容
echo [INFO] 将还原以下内容到 %OPENCLAW_DIR%:
for /d %%d in ("%BACKUP_ROOT%\*") do (
    echo   [DIR] %%~nxd\
)
for %%f in ("%BACKUP_ROOT%\*") do (
    if not "%%~nxf"==".backup-meta.json" (
        echo   [FILE] %%~nxf
    )
)

if "%DRY_RUN%"=="1" (
    echo.
    echo [WARN] 预览模式，未执行还原
    rmdir /s /q "%TMP_RESTORE%"
    exit /b 0
)

:: 确认
if "%FORCE%"=="0" (
    echo.
    echo [WARN] 还原将覆盖 %OPENCLAW_DIR% 中的同名文件
    set /p "CONFIRM=确认还原？(y/N) "
    if /i not "!CONFIRM!"=="y" (
        echo [INFO] 已取消
        rmdir /s /q "%TMP_RESTORE%"
        exit /b 0
    )
)

:: 还原前备份当前数据
if exist "%OPENCLAW_DIR%" (
    set "PRE_BACKUP=%BACKUP_DIR%\pre_restore_%DATE_TAG%.zip"
    if not exist "%BACKUP_DIR%" mkdir "%BACKUP_DIR%"
    echo [INFO] 还原前自动备份当前数据...
    powershell -NoProfile -Command "Compress-Archive -Path '%OPENCLAW_DIR%\*' -DestinationPath '!PRE_BACKUP!' -Force" 2>nul
    echo [OK] 当前数据已备份到 !PRE_BACKUP!
)

:: 执行还原
if not exist "%OPENCLAW_DIR%" mkdir "%OPENCLAW_DIR%"
echo [INFO] 正在还原...

for /d %%d in ("%BACKUP_ROOT%\*") do (
    if exist "%OPENCLAW_DIR%\%%~nxd" rmdir /s /q "%OPENCLAW_DIR%\%%~nxd"
    xcopy /e /i /q /y "%%d" "%OPENCLAW_DIR%\%%~nxd" >nul
    echo [OK] %%~nxd\
)
for %%f in ("%BACKUP_ROOT%\*") do (
    if not "%%~nxf"==".backup-meta.json" (
        copy /y "%%f" "%OPENCLAW_DIR%\" >nul
        echo [OK] %%~nxf
    )
)

rmdir /s /q "%TMP_RESTORE%"

echo.
echo [OK] 还原完成！
echo [WARN] 请重启 OpenClaw Gateway 使配置生效：
echo   openclaw gateway restart
echo.
exit /b 0

:: ============================================================
:: 列出备份
:: ============================================================
:list
if not exist "%BACKUP_DIR%" (
    echo [INFO] 暂无备份（目录 %BACKUP_DIR% 不存在）
    exit /b 0
)

echo.
echo OpenClaw 备份列表 (%BACKUP_DIR%):
echo -----------------------------------------------
set "FOUND=0"
for %%f in ("%BACKUP_DIR%\openclaw_*.zip" "%BACKUP_DIR%\openclaw_*.tar.gz") do (
    if exist "%%f" (
        set "FOUND=1"
        echo   %%~nxf    %%~zf bytes    %%~tf
    )
)
if "%FOUND%"=="0" echo [INFO] 暂无备份
echo.
exit /b 0

:: ============================================================
:: 查看备份详情
:: ============================================================
:info_entry
shift
if "%~1"=="" (
    echo [ERROR] 请指定备份文件路径
    exit /b 1
)
set "INFO_FILE=%~1"

if not exist "%INFO_FILE%" (
    echo [ERROR] 文件不存在: %INFO_FILE%
    exit /b 1
)

set "TMP_INFO=%TEMP%\openclaw_info_%DATE_TAG%"
if exist "%TMP_INFO%" rmdir /s /q "%TMP_INFO%"
mkdir "%TMP_INFO%"

echo "%INFO_FILE%" | findstr /i ".zip" >nul
if %errorlevel%==0 (
    powershell -NoProfile -Command "Expand-Archive -Path '%INFO_FILE%' -DestinationPath '%TMP_INFO%' -Force"
) else (
    tar -xzf "%INFO_FILE%" -C "%TMP_INFO%" 2>nul
)

set "INFO_ROOT="
for /r "%TMP_INFO%" %%f in (.backup-meta.json) do (
    if exist "%%f" set "INFO_ROOT=%%~dpf"
)
if defined INFO_ROOT set "INFO_ROOT=%INFO_ROOT:~0,-1%"

if not defined INFO_ROOT (
    echo [ERROR] 无效的备份文件
    rmdir /s /q "%TMP_INFO%"
    exit /b 1
)

echo.
echo =======================================
echo  备份详情: %~nx1
echo =======================================
type "%INFO_ROOT%\.backup-meta.json"
echo.
echo  内容:
for /d %%d in ("%INFO_ROOT%\*") do echo    [DIR] %%~nxd\
for %%f in ("%INFO_ROOT%\*") do (
    if not "%%~nxf"==".backup-meta.json" echo    [FILE] %%~nxf
)
echo.
for %%A in ("%INFO_FILE%") do echo  压缩包大小: %%~zA bytes
echo.

rmdir /s /q "%TMP_INFO%"
exit /b 0
