@echo off
chcp 65001 >nul
REM ============================================================
REM  sub2api 一键更新脚本（源码部署）
REM  流程: 拉取官方更新并自动重放本地定制功能 -> 构建 -> 重启
REM  - 与 run_sub2api.bat 同级，双击运行即可
REM  - 配置 backend\config.yaml 与数据 backend\data\ 不受影响
REM  - 实际监听端口以 config.yaml 为准（当前 18271）
REM  - GOPROXY 走国内镜像，避免 Go 工具链/依赖下载失败
REM ============================================================
setlocal
set GOPROXY=https://goproxy.cn,direct
set "ROOT=%~dp0.."

for /f %%i in ('git -C "%ROOT%" describe --tags') do set "OLDVER=%%i"

for /f %%i in ('git -C "%ROOT%" branch --show-current') do set "BRANCH=%%i"
echo [1/5] 获取官方最新代码...
git -C "%ROOT%" fetch origin || goto :fail

echo [2/5] 自动应用本地定制功能...
if /I "%BRANCH%"=="main" (
  git -C "%ROOT%" pull --ff-only origin main || goto :fail
) else (
  git -C "%ROOT%" rebase origin/main || goto :fail
)

echo [3/5] 安装前端依赖 (pnpm install)...
pushd "%ROOT%\frontend" || goto :fail
call pnpm install || goto :fail

echo [4/5] 构建前端 (pnpm run build)...
call pnpm run build || goto :fail
popd

echo [5/5] 停止旧服务并编译后端...
taskkill /F /IM sub2api.exe >nul 2>&1
pushd "%~dp0" || goto :fail
G:\Programer\go\bin\go build -tags embed -o sub2api.exe ./cmd/server || goto :fail
popd

echo 重启服务...
start "" "%~dp0run_sub2api.bat"

for /f %%i in ('git -C "%ROOT%" describe --tags') do set "NEWVER=%%i"
echo.
echo ============================================
echo   更新完成: %OLDVER% -^> %NEWVER%
echo   服务已在新窗口启动，稍候几秒即可访问
echo ============================================
endlocal
pause
exit /b 0

:fail
echo.
echo [错误] 更新失败！
echo 如果服务已被停止，请手动双击 run_sub2api.bat 启动
pause
exit /b 1
