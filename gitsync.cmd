@echo off
chcp 65001 >nul
setlocal
cd /d "%~dp0"

rem ---- 找到 Git Bash（优先用 Git for Windows 自带的 bash，避免误用 WSL）----
set "BASH="
if exist "%ProgramFiles%\Git\bin\bash.exe" set "BASH=%ProgramFiles%\Git\bin\bash.exe"
if not defined BASH if exist "%ProgramFiles(x86)%\Git\bin\bash.exe" set "BASH=%ProgramFiles(x86)%\Git\bin\bash.exe"
if not defined BASH if exist "%LOCALAPPDATA%\Programs\Git\bin\bash.exe" set "BASH=%LOCALAPPDATA%\Programs\Git\bin\bash.exe"
if not defined BASH for /f "delims=" %%i in ('where bash 2^>nul') do if not defined BASH set "BASH=%%i"

if not defined BASH (
  echo [ERROR] Git Bash not found. Please install Git for Windows first.
  echo         https://git-scm.com/download/win
  pause
  exit /b 1
)

"%BASH%" "%~dp0gitsync.sh" %*
set "RC=%ERRORLEVEL%"

rem 双击运行时，结束后停住，方便看结果；带参数运行则直接返回
if "%~1"=="" pause
exit /b %RC%
