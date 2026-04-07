#!/bin/bash
echo "=== Setting up Pop Song Radio Edit task ==="

source /workspace/scripts/task_utils.sh

# Record task start timestamp for anti-gaming
date +%s > /tmp/task_start_time.txt

# Clean any previous runs
kill_ardour
rm -rf /home/ga/Audio/sessions/Radio_Edit_Project 2>/dev/null || true
rm -rf /home/ga/Audio/delivery 2>/dev/null || true
rm -rf /home/ga/Audio/radio_edit_raw 2>/dev/null || true

# Create required directories
su - ga -c "mkdir -p /home/ga/Audio/delivery"
su - ga -c "mkdir -p /home/ga/Audio/radio_edit_raw"
su - ga -c "mkdir -p /home/ga/Audio/sessions"

# Generate a 4-minute source file (looping the available sample to guarantee reliable offline data)
echo "Generating 4-minute extended mix..."
SAMPLE_FILE="/home/ga/Audio/samples/moonlight_sonata.wav"
if [ ! -f "$SAMPLE_FILE" ]; then
    # Fallback to any wav
    SAMPLE_FILE=$(find /home/ga/Audio/samples -name "*.wav" | head -1)
fi

# Loop the ~30s sample 8 times to create a 4-minute continuous track
if [ -n "$SAMPLE_FILE" ] && [ -f "$SAMPLE_FILE" ]; then
    su - ga -c "ffmpeg -y -stream_loop 8 -i '$SAMPLE_FILE' -t 240 -c:a pcm_s16le -ar 44100 /home/ga/Audio/radio_edit_raw/extended_mix.wav 2>/dev/null"
else
    # Ultimate fallback: generate 4 mins of 440Hz sine wave if no samples exist
    su - ga -c "ffmpeg -y -f lavfi -i 'sine=frequency=440:duration=240' -c:a pcm_s16le -ar 44100 /home/ga/Audio/radio_edit_raw/extended_mix.wav 2>/dev/null"
fi

# Get original file size for verification reference
ORIGINAL_SIZE=$(stat -c %s /home/ga/Audio/radio_edit_raw/extended_mix.wav 2>/dev/null || echo "0")
echo "$ORIGINAL_SIZE" > /tmp/original_file_size.txt

# Create the Ardour session
echo "Creating Radio_Edit_Project session..."
ARDOUR_BIN=$(get_ardour_bin)
ARDOUR_VERSION=$(get_ardour_version)
SESSION_DIR="/home/ga/Audio/sessions/Radio_Edit_Project"

su - ga -c "${ARDOUR_BIN}-new_session -s 44100 '$SESSION_DIR' Radio_Edit_Project > /dev/null 2>&1 || ardour-new_session -s 44100 '$SESSION_DIR' Radio_Edit_Project > /dev/null 2>&1"

# Launch Ardour with the empty session
echo "Launching Ardour..."
launch_ardour_session "$SESSION_DIR/Radio_Edit_Project.ardour"

sleep 4

# Take initial screenshot
echo "Capturing initial state..."
take_screenshot /tmp/task_initial.png

# Verify screenshot
if [ -f /tmp/task_initial.png ]; then
    SIZE=$(stat -c %s /tmp/task_initial.png 2>/dev/null || echo "0")
    echo "Initial screenshot captured: ${SIZE} bytes"
else
    echo "WARNING: Could not capture initial screenshot"
fi

echo "=== Task setup complete ==="