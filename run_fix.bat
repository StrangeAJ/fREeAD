@echo off
echo.
echo ===== Flutter RSS Reader - Quick Fix =====
echo.
echo The build is failing due to two issues:
echo 1. Path conflict: File "Ashish" exists in C:\Users\
echo 2. Symlink support: Developer Mode not enabled
echo.
echo SOLUTION 1: Enable Developer Mode (Recommended)
echo.
echo Please follow these steps:
echo 1. Press Windows + R
echo 2. Type: ms-settings:developers
echo 3. Press Enter
echo 4. Toggle "Developer Mode" to ON
echo 5. Restart this script
echo.
echo SOLUTION 2: Copy project to different location
echo.
echo 1. Create new folder: C:\Dev\freead
echo 2. Copy all files from current location
echo 3. Run from the new location
echo.
echo SOLUTION 3: Use web version (Works immediately)
echo.
echo Running web version now...
echo.
flutter run -d chrome
pause
