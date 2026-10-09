@echo off
REM Package clean Balatro release zip for GarlicOS RG35XX - game-free (no Balatro.exe)
REM Mirrors Port_HalfLife HLv2upd flow. Run AFTER build.bat (needs out\ binaries).
REM Output: Balatro_Garlic-release.zip with ROMS\PORTS\ layout.
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
echo === Staged (must NOT contain Balatro.exe) ===
dir "%STAGEBAL%"
dir "%STAGEBAL%\share\alsa" 2>nul | more
where powershell >nul 2>&1
powershell -NoProfile -Command "Get-ChildItem -LiteralPath '%STAGEBAL%' -Recurse -Include 'Balatro.exe','Balatro.love','*.mp3','*.dll' | ForEach-Object { Write-Error ('LEAK: ' + $_.FullName) }; Compress-Archive -Path '%~dp0Balatro_UPD\ROMS' -DestinationPath '%~dp0Balatro_Garlic-release.zip' -Force; Get-ChildItem '%~dp0Balatro_Garlic-release.zip'"
if errorlevel 1 (
  echo Package failed
  exit /b 1
)
echo.
echo Done: Balatro_Garlic-release.zip (game-free - add your own Balatro.exe on SD)
endlocal
