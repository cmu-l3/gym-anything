#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Fix Subtitle Encoding Task ==="

kill_vlc ga
sleep 1

# Ensure directories exist
mkdir -p /home/ga/Videos/subtitles
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Videos/subtitles /home/ga/Documents

# Check if iconv is installed (should be in base system)
if ! command -v iconv &> /dev/null; then
    echo "Installing iconv..."
    apt-get update && apt-get install -y libc-bin
fi

# Create subtitle file with Japanese text in UTF-8 first (as temp)
cat > /tmp/subtitles_utf8.srt << 'EOF'
1
00:00:01,000 --> 00:00:03,000
こんにちは、世界

2
00:00:04,000 --> 00:00:06,000
字幕テスト

3
00:00:07,000 --> 00:00:09,000
これは日本語です

4
00:00:10,000 --> 00:00:12,000
エンコーディング問題

5
00:00:13,000 --> 00:00:15,000
正しく表示されますか？
EOF

# Convert UTF-8 subtitle to Shift-JIS (the "broken" version)
iconv -f UTF-8 -t SHIFT-JIS /tmp/subtitles_utf8.srt > /home/ga/Videos/subtitles/subtitles_broken.srt

# Verify the file was created
if [ ! -f /home/ga/Videos/subtitles/subtitles_broken.srt ]; then
    echo "ERROR: Failed to create Shift-JIS subtitle file"
    exit 1
fi

# Create hint file
cat > /home/ga/Documents/subtitle_encoding_hint.txt << 'EOF'
SUBTITLE ENCODING PROBLEM DETECTED
===================================

The subtitle file appears to show garbled text (mojibake).
This usually indicates a character encoding mismatch.

The subtitle file was created on a Japanese system.
Common Japanese text encodings include:
  - Shift-JIS (also written as SHIFT_JIS, SJIS)
  - EUC-JP
  - ISO-2022-JP

Current VLC default: UTF-8

SOLUTION OPTIONS:

Option A - Configure VLC:
  1. Open Tools → Preferences (Ctrl+P)
  2. Click "Show settings: All" (bottom left)
  3. Navigate to: Input / Codecs → Subtitles/OSD → Subtitles
  4. Find "Text subtitles decoder"
  5. Change "Subtitle text encoding" to "Shift-JIS"
  6. Save and reload the subtitle file

Option B - Convert the file:
  1. Open terminal (Ctrl+Alt+T)
  2. Use iconv to convert encoding:
     cd /home/ga/Videos/subtitles
     iconv -f SHIFT-JIS -t UTF-8 subtitles_broken.srt > subtitles_fixed.srt
  3. Load the new subtitles_fixed.srt file in VLC

Hint: You can check file encoding with:
  file -bi filename.srt
EOF

# Ensure VLC uses default UTF-8 encoding (remove any previous encoding settings)
VLC_RC="/home/ga/.config/vlc/vlcrc"
mkdir -p /home/ga/.config/vlc
if [ -f "$VLC_RC" ]; then
    sed -i '/subsdec-encoding=/d' "$VLC_RC"
    sed -i '/sub-language=/d' "$VLC_RC"
fi

# Set ownership
chown -R ga:ga /home/ga/Videos /home/ga/Documents /home/ga/.config

# Launch VLC with video and subtitle file
echo "Launching VLC with video and subtitle..."
su - ga -c "DISPLAY=:1 LIBVA_DRIVER_NAME='' VDPAU_DRIVER='' vlc --avcodec-hw=none --no-video-title-show --sub-file=/home/ga/Videos/subtitles/subtitles_broken.srt /home/ga/Videos/sample_video.mp4 > /tmp/vlc_subtitle_encoding_task.log 2>&1 &"

if ! wait_for_process "vlc" 15; then
    echo "ERROR: VLC failed to start"
    exit 1
fi

if ! wait_for_window "VLC media player" 20; then
    echo "ERROR: VLC window did not appear"
    exit 1
fi

# Click on center of the screen to select current desktop
echo "Selecting desktop..."
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

# Focus window
wid=$(get_vlc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
fi

# Wait for video to start and subtitles to render
sleep 2

echo "=== Fix Subtitle Encoding Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. VLC is playing a video with GARBLED subtitles (mojibake)"
echo "  2. Read the hint file: /home/ga/Documents/subtitle_encoding_hint.txt"
echo "  3. Choose one solution:"
echo ""
echo "  Option A - Configure VLC encoding:"
echo "    - Tools → Preferences → Show All → Input/Codecs → Subtitles"
echo "    - Change 'Subtitle text encoding' to 'Shift-JIS'"
echo "    - Save and reload subtitle"
echo ""
echo "  Option B - Convert file to UTF-8:"
echo "    - Open terminal: Ctrl+Alt+T"
echo "    - Run: cd /home/ga/Videos/subtitles"
echo "    - Run: iconv -f SHIFT-JIS -t UTF-8 subtitles_broken.srt > subtitles_fixed.srt"
echo "    - Reload subtitle in VLC: Subtitle → Load File"