@echo off
setlocal

echo === Pixel — Windows Release Build ===
echo.

where flutter >nul 2>nul
if %ERRORLEVEL% neq 0 (
    echo ERROR: Flutter not found. Install Flutter SDK and add to PATH.
    exit /b 1
)

cd /d "%~dp0\.."

echo [1/3] Getting dependencies...
call flutter pub get

echo [2/3] Running tests...
call flutter test --no-pub
if %ERRORLEVEL% neq 0 (
    echo WARNING: Some tests failed. Continuing build...
)

echo [3/3] Building Windows release...
call flutter build windows --release --no-pub

set EXE_PATH=build\windows\x64\runner\Release\pixel.exe
if exist "%EXE_PATH%" (
    echo.
    echo === BUILD SUCCESSFUL ===
    echo EXE: %CD%\%EXE_PATH%
    echo.
    echo To distribute: zip the entire build\windows\x64\runner\Release\ folder.
) else (
    echo ERROR: pixel.exe not found at expected path.
    exit /b 1
)
