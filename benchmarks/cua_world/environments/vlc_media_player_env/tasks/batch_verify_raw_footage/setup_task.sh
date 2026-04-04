#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Batch Verify Raw Footage Task ==="

kill_vlc ga
sleep 1

# Create directory structure
echo "Creating directories..."
mkdir -p /home/ga/Videos/wedding_raw
mkdir -p /home/ga/Documents
chown -R ga:ga /home/ga/Videos/wedding_raw
chown -R ga:ga /home/ga/Documents

# Clean up any existing files from previous runs
rm -f /home/ga/Videos/wedding_raw/*.mp4
rm -f /home/ga/Documents/qa_report.txt

echo "Generating test video files..."

# Generate 4 VALID test videos (1920x1080, h264, with audio)

# ceremony_01.mp4 - 245 seconds
echo "Creating ceremony_01.mp4 (valid, 245s)..."
ffmpeg -f lavfi -i "testsrc=duration=245:size=1920x1080:rate=30" \
       -f lavfi -i "sine=frequency=440:duration=245" \
       -c:v libx264 -preset ultrafast -pix_fmt yuv420p \
       -c:a aac -b:a 128k \
       -shortest \
       /home/ga/Videos/wedding_raw/ceremony_01.mp4 -y \
       > /tmp/ffmpeg_ceremony_01.log 2>&1

# reception_speeches.mp4 - 582 seconds
echo "Creating reception_speeches.mp4 (valid, 582s)..."
ffmpeg -f lavfi -i "testsrc=duration=582:size=1920x1080:rate=30" \
       -f lavfi -i "sine=frequency=523:duration=582" \
       -c:v libx264 -preset ultrafast -pix_fmt yuv420p \
       -c:a aac -b:a 128k \
       -shortest \
       /home/ga/Videos/wedding_raw/reception_speeches.mp4 -y \
       > /tmp/ffmpeg_reception_speeches.log 2>&1

# first_dance.mp4 - 198 seconds
echo "Creating first_dance.mp4 (valid, 198s)..."
ffmpeg -f lavfi -i "testsrc=duration=198:size=1920x1080:rate=30" \
       -f lavfi -i "sine=frequency=392:duration=198" \
       -c:v libx264 -preset ultrafast -pix_fmt yuv420p \
       -c:a aac -b:a 128k \
       -shortest \
       /home/ga/Videos/wedding_raw/first_dance.mp4 -y \
       > /tmp/ffmpeg_first_dance.log 2>&1

# venue_broll.mp4 - 67 seconds
echo "Creating venue_broll.mp4 (valid, 67s)..."
ffmpeg -f lavfi -i "testsrc=duration=67:size=1920x1080:rate=30" \
       -f lavfi -i "sine=frequency=330:duration=67" \
       -c:v libx264 -preset ultrafast -pix_fmt yuv420p \
       -c:a aac -b:a 128k \
       -shortest \
       /home/ga/Videos/wedding_raw/venue_broll.mp4 -y \
       > /tmp/ffmpeg_venue_broll.log 2>&1

# ceremony_02.mp4 - PROBLEMATIC (no audio stream) - 180 seconds
echo "Creating ceremony_02.mp4 (DEFECTIVE - no audio, 180s)..."
ffmpeg -f lavfi -i "testsrc=duration=180:size=1920x1080:rate=30" \
       -c:v libx264 -preset ultrafast -pix_fmt yuv420p \
       -an \
       /home/ga/Videos/wedding_raw/ceremony_02.mp4 -y \
       > /tmp/ffmpeg_ceremony_02.log 2>&1

# Verify files were created
echo "Verifying generated files..."
for file in ceremony_01.mp4 ceremony_02.mp4 reception_speeches.mp4 first_dance.mp4 venue_broll.mp4; do
    if [ -f "/home/ga/Videos/wedding_raw/$file" ]; then
        size=$(stat -f%z "/home/ga/Videos/wedding_raw/$file" 2>/dev/null || stat -c%s "/home/ga/Videos/wedding_raw/$file" 2>/dev/null)
        echo "  ✓ $file created (${size} bytes)"
    else
        echo "  ✗ $file FAILED to create"
    fi
done

# Set proper ownership
chown -R ga:ga /home/ga/Videos/wedding_raw
chown -R ga:ga /home/ga/Documents

# Launch VLC (not playing any file, just open)
echo "Launching VLC..."
su - ga -c "DISPLAY=:1 LIBVA_DRIVER_NAME='' VDPAU_DRIVER='' vlc --avcodec-hw=none --no-video-title-show > /tmp/vlc_batch_verify_task.log 2>&1 &"

if ! wait_for_process "vlc" 15; then
    echo "WARNING: VLC failed to start (not critical for this task)"
    # Not critical - agent can use command-line tools
fi

if wait_for_window "VLC media player" 10; then
    # Click on center of the screen to select current desktop (should be done in all tasks), and then focus window.
    echo "Selecting desktop..."
    su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
    sleep 1

    # Focus window
    wid=$(get_vlc_window_id)
    if [ -n "$wid" ]; then
        focus_window "$wid"
    fi
fi

echo "=== Batch Verify Raw Footage Task Setup Complete ==="
echo ""
echo "📋 TASK INSTRUCTIONS:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "You are a freelance video editor who just received 5 raw video"
echo "files from a wedding videographer client. Before starting ANY"
echo "editing work, you must verify all files are valid."
echo ""
echo "📁 Files to analyze: /home/ga/Videos/wedding_raw/"
echo "   • ceremony_01.mp4"
echo "   • ceremony_02.mp4 (⚠️ defective - but you don't know this yet!)"
echo "   • reception_speeches.mp4"
echo "   • first_dance.mp4"
echo "   • venue_broll.mp4"
echo ""
echo "📋 For EACH file, verify:"
echo "   1. File opens and plays without errors"
echo "   2. Contains BOTH video AND audio streams"
echo "   3. Resolution is 1920x1080 (1080p)"
echo "   4. Video codec is H.264"
echo "   5. Duration is greater than 5 seconds"
echo ""
echo "📝 Create QA report: /home/ga/Documents/qa_report.txt"
echo ""
echo "Report must include:"
echo "   • Analysis of each file with technical specs"
echo "   • Clear PASS/FAIL status for each file"
echo "   • Description of any issues found"
echo "   • Summary section with counts and ready/not ready verdict"
echo ""
echo "🛠️ Tools you can use:"
echo "   • VLC Media Player (GUI)"
echo "   • ffprobe (command: ffprobe -v error -show_entries stream=codec_name,width,height:format=duration file.mp4)"
echo "   • Python with vlc_verification_utils"
echo "   • Any other command-line tools"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"