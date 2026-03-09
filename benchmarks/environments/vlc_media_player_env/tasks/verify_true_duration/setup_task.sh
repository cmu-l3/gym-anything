#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

TASK_NAME="verify_true_duration"
LOG="/tmp/${TASK_NAME}_setup.log"

echo "=== Setting up ${TASK_NAME} Task ===" | tee "$LOG"

# Kill any existing VLC instances
kill_vlc ga
sleep 1

# Create necessary directories
mkdir -p /home/ga/Videos
mkdir -p /home/ga/Documents
chown -R ga:ga /home/ga/Videos
chown -R ga:ga /home/ga/Documents

echo "Generating test video with corrupted duration metadata..." | tee -a "$LOG"

# Step 1: Create a 2-minute (120 second) video with actual content
# Using a colorful test pattern so it's visually obvious when it ends
echo "Creating base video (2 minutes actual content)..." | tee -a "$LOG"
ffmpeg -f lavfi -i testsrc=duration=120:size=854x480:rate=30 \
    -f lavfi -i sine=frequency=440:duration=120 \
    -c:v libx264 -preset ultrafast -crf 23 \
    -c:a aac -b:a 128k \
    -y /tmp/interview_base.mp4 2>&1 | tee -a "$LOG"

if [ ! -f /tmp/interview_base.mp4 ]; then
    echo "ERROR: Failed to create base video" | tee -a "$LOG"
    exit 1
fi

echo "Base video created successfully" | tee -a "$LOG"

# Step 2: Create a version with corrupted duration metadata
# We'll create a file that CLAIMS to be 10 minutes (600 seconds) but only has 2 minutes of content
# This simulates an interrupted download where the container metadata is wrong
echo "Creating version with corrupted duration metadata..." | tee -a "$LOG"

# Method: Use MP4Box or ffmpeg to inject wrong duration in the container
# We'll use ffmpeg to create a file with duration metadata set incorrectly
# by creating a concat with a fake duration entry

# Alternative simpler approach: Create a file and manually truncate it to simulate interrupted download
# But first create a longer video's HEADER, then write only 2 minutes of actual data

# Simplest approach: Create the illusion by using ffmpeg's metadata option
# Create a 2-minute video but with duration tag claiming 600 seconds
ffmpeg -i /tmp/interview_base.mp4 \
    -c copy \
    -metadata duration="600" \
    -metadata title="2hr Interview Session" \
    -y /home/ga/Videos/interview_recording.mp4 2>&1 | tee -a "$LOG"

# The above may not work as expected since duration is not a simple metadata tag
# Better approach: Create a file that's actually incomplete

# Let's use a different strategy: create a 10-minute video reference but only write 2 minutes
# by creating a concat file and then truncating

# Most reliable approach for this scenario: Create actual truncated file
# Step 1: Create a 10-minute header reference
echo "Creating a properly truncated file to simulate interrupted download..." | tee -a "$LOG"

# Create a 10-minute video template (just headers, very fast)
ffmpeg -f lavfi -i testsrc=duration=600:size=854x480:rate=30 \
    -f lavfi -i sine=frequency=440:duration=600 \
    -c:v libx264 -preset ultrafast -crf 28 -g 300 \
    -c:a aac -b:a 128k \
    -movflags +faststart \
    -y /tmp/interview_long.mp4 2>&1 | tee -a "$LOG"

# Now truncate this file to approximately where 2 minutes of data would be
# Calculate approximate byte position for 2 minutes (rough estimate)
FULL_SIZE=$(stat -f%z /tmp/interview_long.mp4 2>/dev/null || stat -c%s /tmp/interview_long.mp4)
# Assuming linear encoding, 2 min = 2/10 of file = 20%
TRUNCATE_SIZE=$((FULL_SIZE / 5))

echo "Truncating file from $FULL_SIZE to approximately $TRUNCATE_SIZE bytes" | tee -a "$LOG"
dd if=/tmp/interview_long.mp4 of=/home/ga/Videos/interview_recording.mp4 bs=1M count=$((TRUNCATE_SIZE / 1048576 + 1)) 2>&1 | tee -a "$LOG"

# Verify the file was created
if [ ! -f /home/ga/Videos/interview_recording.mp4 ]; then
    echo "ERROR: Failed to create corrupted video" | tee -a "$LOG"
    exit 1
fi

echo "Corrupted video created successfully" | tee -a "$LOG"
ls -lh /home/ga/Videos/interview_recording.mp4 | tee -a "$LOG"

# Try to get duration info for logging
echo "Checking video metadata..." | tee -a "$LOG"
ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 \
    /home/ga/Videos/interview_recording.mp4 2>&1 | tee -a "$LOG" || echo "ffprobe had issues (expected for corrupted file)"

# Set ownership
chown -R ga:ga /home/ga/Videos
chown -R ga:ga /home/ga/Documents

# Create a helpful README for the user
cat > /home/ga/Documents/task_instructions.txt << 'EOF'
=== TASK: Verify True Duration ===

File location: /home/ga/Videos/interview_recording.mp4
Reported metadata: Claims to be ~10 minutes long

Your job: Determine the ACTUAL playable duration.

Expected output: /home/ga/Documents/duration_report.txt

Required format:
METADATA_DURATION: [seconds]
ACTUAL_DURATION: [seconds]
VERIFICATION_METHOD: [how you checked]

Hints:
- Open the file in VLC
- Check VLC's Media Information (Tools → Media Information, or Ctrl+I)
- Try seeking to the end and playing - what happens?
- Watch for freezing, errors, or jumps
- The actual duration is likely much shorter than the metadata claims

This is a common problem with interrupted downloads!

Good luck!
EOF

chown ga:ga /home/ga/Documents/task_instructions.txt

# Launch VLC with the corrupted video
echo "Launching VLC with the test video..." | tee -a "$LOG"
su - ga -c "DISPLAY=:1 LIBVA_DRIVER_NAME='' VDPAU_DRIVER='' vlc --avcodec-hw=none --no-video-title-show /home/ga/Videos/interview_recording.mp4 > /tmp/vlc_duration_task.log 2>&1 &"

if ! wait_for_process "vlc" 15; then
    echo "ERROR: VLC failed to start" | tee -a "$LOG"
    exit 1
fi

if ! wait_for_window "VLC media player" 20; then
    echo "ERROR: VLC window did not appear" | tee -a "$LOG"
    exit 1
fi

# Click on center of the screen to select current desktop (should be done in all tasks), and then focus window.
echo "Selecting desktop..." | tee -a "$LOG"
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

# Focus window
wid=$(get_vlc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
fi

# Pause the video to let agent investigate
echo "Pausing video for investigation..." | tee -a "$LOG"
sleep 2
su - ga -c "DISPLAY=:1 xdotool key space" || true

echo "[$(date)] Setup complete!" | tee -a "$LOG"
echo "" | tee -a "$LOG"
echo "=== Task Instructions ===" | tee -a "$LOG"
echo "1. The video file claims to be ~10 minutes long" | tee -a "$LOG"
echo "2. Investigate the ACTUAL playable duration" | tee -a "$LOG"
echo "3. Document your findings in /home/ga/Documents/duration_report.txt" | tee -a "$LOG"
echo "4. Use format:" | tee -a "$LOG"
echo "   METADATA_DURATION: [seconds]" | tee -a "$LOG"
echo "   ACTUAL_DURATION: [seconds]" | tee -a "$LOG"
echo "   VERIFICATION_METHOD: [description]" | tee -a "$LOG"
echo "" | tee -a "$LOG"
echo "Tip: Try seeking to the end, check Media Information, observe playback behavior" | tee -a "$LOG"

echo "=== Verify True Duration Task Setup Complete ==="