@echo off
REM Package clean Balatro release zip for GarlicOS RG35XX - game-free (no Balatro.exe)
REM Mirrors Port_HalfLife HLv2upd flow. Run AFTER build.bat (needs out\ binaries).
REM Output: Balatro_Garlic-release-v1.zip with ROMS\PORTS\ layout.
setlocal
set STAGE=%~dp0Balatro_UPD\ROMS\PORTS
set STAGEBAL=%STAGE%\Balatro
if not exist "%~dp0out\balatro-runtime" (
  echo Missing out\balatro-runtime - run build.bat first
  exit /b 1
)
rmdir /S /Q "%~dp0Balatro_UPD" 2>nul
mkdir "%STAGEBAL%" 2>nul
copy /Y "%~dp0Balatro.sh" "%STAGE%\Balatro.sh" >nul
copy /Y "%~dp0out\balatro-runtime" "%STAGEBAL%\balatro-runtime" >nul
copy /Y "%~dp0out\balatro-audio" "%STAGEBAL%\balatro-audio" >nul
copy /Y "%~dp0out\libasound.so*" "%STAGEBAL%\" >nul
copy /Y "%~dp0out\libc.so" "%STAGEBAL%\libc.so" >nul
copy /Y "%~dp0out\ld-musl-armhf.so.1" "%STAGEBAL%\ld-musl-armhf.so.1" >nul
mkdir "%STAGEBAL%\share" 2>nul
xcopy /E /I /Y "%~dp0out\share" "%STAGEBAL%\share" >nul
REM Normalize to nested share\alsa layout (Balatro.sh expects share\alsa\alsa.conf).
REM out\share can carry flat duplicates from `cp -r alsa /out/share`; drop them.
rmdir /S /Q "%STAGEBAL%\share\cards" 2>nul
rmdir /S /Q "%STAGEBAL%\share\ctl" 2>nul
rmdir /S /Q "%STAGEBAL%\share\pcm" 2>nul
del /Q "%STAGEBAL%\share\alsa.conf" 2>nul
if not exist "%STAGEBAL%\share\alsa\alsa.conf" (
  echo Missing share\alsa\alsa.conf after staging - check out\share layout
  exit /b 1
)
REM License files ride with the binaries (GPLv3-only: license must accompany the binary).
mkdir "%STAGEBAL%\licenses" 2>nul
copy /Y "%~dp0LICENSE" "%STAGEBAL%\LICENSE.txt" >nul
copy /Y "%~dp0upstream\NOTICE" "%STAGEBAL%\NOTICE" >nul
xcopy /E /I /Y "%~dp0upstream\licenses" "%STAGEBAL%\licenses" >nul
echo === Staged (must NOT contain Balatro.exe) ===
dir "%STAGEBAL%"
dir "%STAGEBAL%\share\alsa" 2>nul
where powershell >nul 2>&1
REM NOTE: -Include only filters with -Path wildcards (dir\*), NOT -LiteralPath.
REM A match exits 1 so errorlevel below actually fails the packaging.
powershell -NoProfile -Command "$bad = @(Get-ChildItem -Path '%STAGEBAL%\*' -Recurse -Include 'Balatro.exe','Balatro.love','*.mp3','*.dll'); if ($bad.Count -gt 0) { $bad | ForEach-Object { Write-Host ('LEAK: ' + $_.FullName) }; exit 1 }; Compress-Archive -Path '%~dp0Balatro_UPD\ROMS' -DestinationPath '%~dp0Balatro_Garlic-release-v1.zip' -Force; Get-ChildItem '%~dp0Balatro_Garlic-release-v1.zip'"
if errorlevel 1 (
  echo Package failed
  exit /b 1
)
echo.
echo Done: Balatro_Garlic-release-v1.zip (game-free - add your own Balatro.exe on SD)
endlocal
