@echo off
REM Build Balatro runtime for GarlicOS RG35XX - requires Docker Desktop running
REM Upstream: Producdevity/balatro-miyoo-mini-port (GPLv3) + Garlic ALSA/audio patch
docker build -t balatro-garlic .
if errorlevel 1 (
  echo Build failed - start Docker Desktop first, then re-run
  exit /b 1
)
if not exist out mkdir out
docker run --rm -v "%cd%/out:/out" balatro-garlic
echo.
echo === Built ===
dir out
echo.
echo Next (SD reader only, NO ADB):
echo 1. Copy out\balatro-runtime + out\balatro-audio + out\libasound.so* + out\libc.so + out\ld-musl-armhf.so.1 + out\share to SD: ROMS/PORTS/Balatro/
echo    Copy Balatro.sh to SD: ROMS/PORTS/ (next to the other .sh launchers)
echo 2. Copy your Balatro.exe or Balatro.love into ROMS/PORTS/Balatro/
echo 3. Safely eject, boot -^> PORTS -^> Balatro (first launch prepares audio, screen looks frozen - do not power off)
echo 4. If black screen: power off, open ROMS/PORTS/Balatro/debug.log + runtime.log on PC
