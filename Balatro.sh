#!/bin/sh
progdir=$(dirname "$0")/Balatro
cd $progdir
HOME=$progdir
export LD_LIBRARY_PATH="$PWD:$LD_LIBRARY_PATH"
export ALSA_CONFIG_PATH="$PWD/share/alsa/alsa.conf"
export ALSA_CONFIG_DIR="$PWD/share/alsa"
cp -f ./ld-musl-armhf.so.1 /tmp/ld-musl-armhf.so.1 2>/dev/null
{
  echo "=== Balatro Garlic launcher v1 ==="
  echo "--- /proc/fb ---"
  cat /proc/fb 2>&1
  echo "--- /dev/fb* ---"
  ls -lh /dev/fb* 2>&1
  echo "--- /dev/dri ---"
  ls -R /dev/dri 2>&1
  echo "--- /dev/input ---"
  ls /dev/input/event* 2>&1
  echo "--- /proc/bus/input/devices ---"
  cat /proc/bus/input/devices 2>&1
  echo "--- /dev/snd ---"
  ls -R /dev/snd 2>&1
  echo "--- cpu freq ---"
  cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>&1
  cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq 2>&1
  cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_max_freq 2>&1
  echo "--- asound ---"
  cat /proc/asound/cards 2>&1
  cat /proc/asound/pcm 2>&1
  amixer scontents 2>&1 | head -40
  echo "--- musl loader staged ---"
  ls -lh /tmp/ld-musl-armhf.so.1 2>&1
  echo "=== shipped files ==="
  ls -lh ./balatro-runtime ./balatro-audio ./lib*.so* 2>&1
  ls -lh ./Balatro.love ./Balatro.exe 2>&1
} > ./debug.log 2>&1
rm -f ./mark.log
if [ ! -f "./Balatro.love" ] && [ ! -f "./Balatro.exe" ] && [ ! -f "./Balatro" ]; then
  echo "missing Balatro.love - copy your own Balatro.exe or Balatro.love here" >> ./debug.log
  echo "missing game file - check ROMS/PORTS/Balatro/debug.log on PC" >> ./debug.log
  sleep 3
  sync
  exit 1
fi
export BALATRO_PLATFORM=garlic
export BALATRO_RENDER_WIDTH=640
export BALATRO_RENDER_HEIGHT=480
export BALATRO_SHADER_COLOUR_CACHE=1
export BALATRO_SHADER_SPATIAL_CACHE=0
export BALATRO_CARD_OCCLUSION=1
export BALATRO_LAYER_PAIRS=1
export BALATRO_FLAME_SIMD=1
export BALATRO_FUSED_SHADER=1
export BALATRO_PACKED_PIXELS=1
export BALATRO_FRAME_PIPELINE=2
export BALATRO_SHADER_WORKER=1
export BALATRO_DIRECT_PRESENT=1
export BALATRO_ROTATE_180=0
# Video buffering: 1 = draw to visible page (default, no pan flips),
# 2 = pan-flip double buffer. Switch without rebuilding.
export BALATRO_FB_PAGES=1
# NOTE: no BALATRO_INPUT_DEVICE export: runtime auto-scans /dev/input/event*
# (device has event0=power button, event1=RG35XX Gamepad - fixed event0 was wrong).
export BALATRO_AUDIO=1
export BALATRO_AUDIO_PRIORITY=realtime
export BALATRO_PCM_CACHE="$PWD/audio-cache"
export BALATRO_SAVE_DIR="$PWD"
export BALATRO_LOG="$PWD/runtime.log"
export BALATRO_FRAMEBUFFER=/dev/fb0
export TUI_RENDER=framebuffer
./balatro-runtime --onion "$PWD" $@ >> ./debug.log 2>&1
RET=$?
echo "exit code $RET" >> ./debug.log
sync
exit $RET
