@echo off
echo Setting up Flutter build environment...

REM Set safe gradle home directory
set GRADLE_USER_HOME=C:\gradle-home

REM Create gradle home directory if it doesn't exist
if not exist "C:\gradle-home" mkdir "C:\gradle-home"

REM Set Flutter build directory outside user path
set FLUTTER_BUILD_DIR=C:\flutter-build\freead

REM Create build directory if it doesn't exist
if not exist "C:\flutter-build" mkdir "C:\flutter-build"
if not exist "C:\flutter-build\freead" mkdir "C:\flutter-build\freead"

echo Environment configured successfully!
echo.
echo Available build commands:
echo   flutter run -d chrome                 (Web - works immediately)
echo   flutter run -d windows                (Windows desktop)
echo   flutter run -d [device-id]            (Android - after this setup)
echo.
echo Running Flutter Doctor...
flutter doctor

echo.
echo To build for Android, run:
echo   flutter run -d [your-android-device-id]
echo.
pause
