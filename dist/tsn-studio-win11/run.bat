@echo off
chcp 65001 >nul
cd /d %~dp0
echo ========================================
echo   TSN Studio - 本地服务启动
echo   浏览器访问: http://localhost:8137/tsn-studio-win11/
echo   按 Ctrl+C 停止服务
echo ========================================
python -m http.server 8137
pause
