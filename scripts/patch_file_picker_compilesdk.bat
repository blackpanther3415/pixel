@echo off
REM Re-applies the file_picker compileSdk patch after `flutter pub get`
REM refreshes the pub cache. file_picker 8.x hardcodes compileSdk 34, which
REM fails AGP's checkAarMetadata because its dependency
REM (flutter_plugin_android_lifecycle) requires compile against 36.
setlocal
set "TARGET=D:\Pixel-environment\pub-cache\hosted\pub.dev\file_picker-8.3.7\android\build.gradle"
if not exist "%TARGET%" (
    echo file_picker build.gradle not found at %TARGET%
    exit /b 1
)
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$p='%TARGET%'; $c=Get-Content $p -Raw;" ^
  "$c=$c -replace 'compileSdk 34','compileSdk 36';" ^
  "$c=$c -replace 'compileSdkVersion 34','compileSdkVersion 36';" ^
  "Set-Content -Path $p -Value $c; " ^
  "Write-Output ('patched: ' + (Select-String -Path $p -Pattern 'compileSdk' ).Line)"
echo PATCH_DONE