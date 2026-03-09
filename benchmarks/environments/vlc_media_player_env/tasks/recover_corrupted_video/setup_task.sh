#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Recover Corrupted Video Task ==="

kill_vlc ga
sleep 1

# Create directory for corrupted videos
mkdir -p /home/ga/Videos/corrupted
chown ga:ga /home/ga/Videos/corrupted

CORRUPTED_VIDEO="/home/ga/Videos/corrupted/family_video_corrupted.avi"

# Create a test video if it doesn't exist
if [ ! -f "$CORRUPTED_VIDEO" ]; then
    echo "Creating corrupted test video..."
    
    # First create a clean test video (30 seconds, simple content)
    TEMP_CLEAN="/tmp/clean_test_video.mp4"
    ffmpeg -f lavfi -i testsrc=duration=30:size=640x480:rate=25 \
           -f lavfi -i sine=frequency=440:duration=30 \
           -c:v libx264 -preset ultrafast -c:a aac \
           "$TEMP_CLEAN" -y > /tmp/ffmpeg_create.log 2>&1
    
    # Now corrupt it by damaging specific byte ranges
    python3 << 'EOF'
import random
import sys

input_file = "/tmp/clean_test_video.mp4"
output_file = "/home/ga/Videos/corrupted/family_video_corrupted.avi"

try:
    with open(input_file, 'rb') as f:
        data = bytearray(f.read())
    
    file_size = len(data)
    print(f"Original file size: {file_size} bytes")
    
    # Corrupt multiple sections (simulate damaged sectors from old media)
    # Corrupt ~5% of the file in scattered locations
    corruption_ranges = [
        (int(file_size * 0.20), int(file_size * 0.22)),  # 20-22% through file
        (int(file_size * 0.45), int(file_size * 0.47)),  # 45-47% through file
        (int(file_size * 0.70), int(file_size * 0.71)),  # 70-71% through file
    ]
    
    for start, end in corruption_ranges:
        for i in range(start, min(end, file_size)):
            # Mix of zeroing and randomizing to simulate real corruption
            if random.random() < 0.5:
                data[i] = 0
            else:
                data[i] = random.randint(0, 255)
        print(f"Corrupted bytes {start}-{end}")
    
    with open(output_file, 'wb') as f:
        f.write(data)
    
    print(f"Corrupted video created: {output_file}")
    
except Exception as e:
    print(f"Error creating corrupted video: {e}", file=sys.stderr)
    sys.exit(1)
EOF
    
    chown ga:ga "$CORRUPTED_VIDEO"
    rm -f "$TEMP_CLEAN"
    echo "✅ Corrupted video created"
else
    echo "Corrupted video already exists"
fi

# Reset VLC config to defaults (remove any error-handling settings)
VLC_RC="/home/ga/.config/vlc/vlcrc"
mkdir -p "$(dirname "$VLC_RC")"
chown -R ga:ga "/home/ga/.config/vlc"

if [ -f "$VLC_RC" ]; then
    echo "Resetting VLC error-handling settings to defaults..."
    
    # Remove error recovery settings
    sed -i '/^avi-index=/d' "$VLC_RC"
    sed -i '/^file-caching=/d' "$VLC_RC"
    sed -i '/^avcodec-skip-frame=/d' "$VLC_RC"
    sed -i '/^avcodec-hw=/d' "$VLC_RC"
    sed -i '/^avcodec-fast=/d' "$VLC_RC"
    sed -i '/^avcodec-skiploopfilter=/d' "$VLC_RC"
    sed -i '/^sout-mux-caching=/d' "$VLC_RC"
else
    touch "$VLC_RC"
    chown ga:ga "$VLC_RC"
fi

# Set to defaults that won't help with corruption
echo "# Default settings - no error recovery" >> "$VLC_RC"
echo "avi-index=0" >> "$VLC_RC"
echo "file-caching=300" >> "$VLC_RC"

echo "✅ VLC config reset to default (no error recovery)"

# Launch VLC with corrupted video (it will likely stutter/fail/freeze)
echo "Launching VLC with corrupted video..."
su - ga -c "DISPLAY=:1 LIBVA_DRIVER_NAME='' VDPAU_DRIVER='' vlc --avcodec-hw=none --no-video-title-show --loop '$CORRUPTED_VIDEO' > /tmp/vlc_recovery_task.log 2>&1 &"

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

# Let it play for a moment to demonstrate the problem
sleep 3

echo "=== Recover Corrupted Video Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. VLC is playing a corrupted video that stutters/freezes"
echo "  2. Go to Tools → Preferences (Ctrl+P)"
echo "  3. Click 'Show settings: All' at bottom-left"
echo "  4. Navigate to Input / Codecs settings:"
echo "     - Set 'Damaged or incomplete AVI file' to 'Always fix' (avi-index=3)"
echo "     - Increase 'File caching (ms)' to 2000-3000"
echo "  5. Optional additional settings in Input / Codecs → Advanced:"
echo "     - Enable 'Skip frames' (avcodec-skip-frame=1)"
echo "     - Enable 'Skip the loop filter' (avcodec-skiploopfilter=1)"
echo "  6. Click Save and restart VLC or reload video"
echo "  7. Video should now play through despite corruption"