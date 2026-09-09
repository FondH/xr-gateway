@echo off
setlocal EnableExtensions

REM Update the official source while retaining this branch's custom commits.
REM Any local tracked or untracked changes are restored after the update.
set "ROOT=%~dp0.."
set "GOPROXY=https://goproxy.cn,direct"
set "STASH_CREATED="
set "GO_BIN=go"

for /f %%i in ('git -C "%ROOT%" describe --tags --always') do set "OLDVER=%%i"
for /f %%i in ('git -C "%ROOT%" branch --show-current') do set "BRANCH=%%i"

if not defined BRANCH (
  echo [ERROR] No current Git branch was found.
  goto :fail
)

echo [1/6] Saving local changes...
for /f %%i in ('git -C "%ROOT%" status --porcelain') do set "DIRTY=1"
if defined DIRTY (
  git -C "%ROOT%" stash push --include-untracked -m "sub2api-update-autostash" || goto :fail
  set "STASH_CREATED=1"
)

echo [2/6] Fetching official source...
git -C "%ROOT%" fetch origin || goto :update_fail

echo [3/6] Applying the official update and local customizations...
if /I "%BRANCH%"=="main" (
  git -C "%ROOT%" merge --ff-only origin/main || goto :update_fail
) else (
  git -C "%ROOT%" rebase origin/main || goto :rebase_conflict
)

if defined STASH_CREATED (
  echo [4/6] Restoring local changes...
  git -C "%ROOT%" stash pop || goto :stash_conflict
) else (
  echo [4/6] No local changes to restore.
)

echo [5/6] Installing and building the frontend...
pushd "%ROOT%\frontend" || goto :fail
call pnpm install || goto :fail
call pnpm run build || goto :fail
popd

echo [6/6] Building and restarting the backend...
where go >nul 2>&1
if errorlevel 1 (
  if exist "G:\Programer\go\bin\go.exe" (
    set "GO_BIN=G:\Programer\go\bin\go.exe"
  ) else (
    goto :go_missing
  )
)
taskkill /F /IM sub2api.exe >nul 2>&1
pushd "%~dp0" || goto :fail
"%GO_BIN%" build -tags embed -o sub2api.exe ./cmd/server || goto :fail
popd
start "" "%~dp0run_sub2api.bat"

for /f %%i in ('git -C "%ROOT%" describe --tags --always') do set "NEWVER=%%i"
echo.
echo ============================================
echo Update complete: %OLDVER% -^> %NEWVER%
echo ============================================
goto :done

:rebase_conflict
echo.
echo [ERROR] A conflict occurred while applying local customizations.
echo Resolve the marked files and run "git rebase --continue".
echo When the rebase is complete, run "git stash pop" to restore local changes.
goto :done

:stash_conflict
echo.
echo [ERROR] The update succeeded, but restoring local changes has a conflict.
echo Resolve the marked files. The automatic backup remains in Git stash.
goto :done

:update_fail
echo.
echo [ERROR] The official update failed. Local changes remain in Git stash.
echo After fixing the update issue, run "git stash pop" to restore local changes.
goto :done

:go_missing
echo.
echo [ERROR] Go was not found on PATH. Install the Go version required by backend\go.mod.
goto :done

:fail
echo.
echo [ERROR] Update failed.

:done
endlocal
pause
