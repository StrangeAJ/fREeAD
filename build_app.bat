@echo off
title Flutter Build Fix for Windows Username with Spaces
echo =============================================================
echo  FreeAd RSS Reader - Build Fix for Windows Path Issues
echo =============================================================
echo.

REM Set safe environment variables
set GRADLE_USER_HOME=C:\gradle-home
set JAVA_OPTS=-Djava.io.tmpdir=C:\temp\gradle

echo Environment configured:
echo   GRADLE_USER_HOME: %GRADLE_USER_HOME%
echo   JAVA_OPTS: %JAVA_OPTS%
echo.

echo Available build options:
echo   1. Android Device (Pixel 7 Pro)
echo   2. Web (Chrome)  
echo   3. Windows Desktop
echo   4. Clean Build
echo   5. Exit
echo.

:menu
set /p choice="Select build option (1-5): "

if "%choice%"=="1" (
    echo Building for Android device...
    flutter run -d 36081FDH3002B6
    goto end
)

if "%choice%"=="2" (
    echo Building for web...
    flutter run -d chrome
    goto end
)

if "%choice%"=="3" (
    echo Building for Windows desktop...
    flutter run -d windows
    goto end
)

if "%choice%"=="4" (
    echo Cleaning build...
    flutter clean
    echo Build cleaned successfully!
    goto menu
)

if "%choice%"=="5" (
    goto end
)

echo Invalid choice. Please select 1-5.
goto menu

:end
echo.
echo Build process completed.
pause
