#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Diagnose Metadata Corruption Task ==="

# Kill any existing VLC instances
kill_vlc ga
sleep 1

# Create necessary directories
mkdir -p /home/ga/Videos/corrupted
mkdir -p /home/ga/Documents
chown -R ga:ga /home/ga/Videos/corrupted /home/ga/Documents

# Generate a test video with actual duration of 270 seconds (4 minutes 30 seconds)
echo "Generating 270-second test video..."
su - ga -c "ffmpeg -f lavfi -i testsrc=duration=270:size=640x480:rate=30 \
       -f lavfi -i sine=frequency=1000:duration=270 \
       -pix_fmt yuv420p -c:v libx264 -preset ultrafast -tune zerolatency \
       -c:a aac -b:a 128k -t 270 \
       /tmp/full_birthday_video.avi -y 2>/dev/null" || {
    echo "ERROR: Failed to generate test video"
    exit 1
}

# Verify the source video was created correctly
if [ ! -f /tmp/full_birthday_video.avi ]; then
    echo "ERROR: Source video not created"
    exit 1
fi

SOURCE_DURATION=$(ffprobe -v error -show_entries format=duration \
                  -of default=noprint_wrappers=1:nokey=1 \
                  /tmp/full_birthday_video.avi 2>/dev/null || echo "0")

echo "Source video duration: ${SOURCE_DURATION}s"

# Create corrupted version with wrong duration in metadata
# Strategy: Manipulate the AVI header to report incorrect duration
# We'll create a file that reports 47 seconds in its header but contains 270 seconds of data

echo "Creating corrupted version with metadata claiming 47 seconds..."

# Method 1: Use ffmpeg to create a misleading header
# Create a 47-second header/index but with 270 seconds of actual stream data
su - ga -c "ffmpeg -i /tmp/full_birthday_video.avi \
       -c copy -t 47 -avoid_negative_ts 1 \
       /tmp/header_47s.avi -y 2>/dev/null" || true

# Now append the full stream data (this creates index/data mismatch)
# Copy full video as raw stream
su - ga -c "ffmpeg -i /tmp/full_birthday_video.avi -c copy -f avi \
       -fflags +bitexact+igndts -avoid_negative_ts disabled \
       /tmp/full_stream_raw.avi -y 2>/dev/null" || true

# Alternative approach: Create video and manually corrupt the duration field
# For AVI files, we can manipulate the 'avih' header
# Create the full video first, then we'll modify its header

su - ga -c "cp /tmp/full_birthday_video.avi /home/ga/Videos/corrupted/birthday_1995.avi"

# Use Python to corrupt the AVI header duration field
python3 <<'PYTHON_SCRIPT'
import struct
import sys

avi_file = "/home/ga/Videos/corrupted/birthday_1995.avi"

try:
    with open(avi_file, "r+b") as f:
        data = f.read()
        
        # Find the 'avih' chunk in AVI header
        avih_pos = data.find(b'avih')
        
        if avih_pos != -1:
            # The avih header structure has dwMicroSecPerFrame at offset 8
            # We want to manipulate the total frames or duration
            # AVI header: 'avih' + size (4 bytes) + dwMicroSecPerFrame (4) + dwMaxBytesPerSec (4) + ...
            # At offset avih_pos + 8 + 16 bytes is dwTotalFrames
            
            # Calculate frame count for 47 seconds at 30fps
            fake_frames = int(47 * 30)  # 1410 frames for 47 seconds
            
            # The dwTotalFrames field is at avih_pos + 8 + 16
            frames_offset = avih_pos + 8 + 16
            
            if frames_offset + 4 < len(data):
                # Write the fake frame count
                f.seek(frames_offset)
                f.write(struct.pack('<I', fake_frames))
                print(f"✓ Corrupted AVI header: set frame count to {fake_frames} (47s worth)")
            else:
                print("⚠ Could not find frame count field")
        else:
            print("⚠ Could not find avih header")
            
except Exception as e:
    print(f"⚠ Could not corrupt AVI header: {e}")
    sys.exit(0)  # Don't fail the setup
PYTHON_SCRIPT

# Verify the corruption attempt
METADATA_DURATION=$(ffprobe -v error -show_entries format=duration \
                     -of default=noprint_wrappers=1:nokey=1 \
                     /home/ga/Videos/corrupted/birthday_1995.avi 2>/dev/null || echo "unknown")

echo "Corrupted file metadata reports: ${METADATA_DURATION}s"
echo "Actual video stream duration: 270s"

# Note: ffprobe might still detect the correct duration from streams
# The point is that the container metadata is unreliable
# VLC's timeline display might show incorrect information

# Set proper ownership
chown ga:ga /home/ga/Videos/corrupted/birthday_1995.avi

# Clean up temporary files
rm -f /tmp/full_birthday_video.avi /tmp/header_47s.avi /tmp/full_stream_raw.avi

# Create a reference file documenting the corruption for verification purposes
cat > /tmp/corruption_ground_truth.txt <<EOF
True Duration: 270 seconds
Claimed Duration: 47 seconds
Video File: /home/ga/Videos/corrupted/birthday_1995.avi
EOF

echo "=== Diagnose Metadata Corruption Task Setup Complete ==="
echo ""
echo "📝 Task Instructions:"
echo "  File: /home/ga/Videos/corrupted/birthday_1995.avi"
echo "  Problem: Duration metadata is corrupted (claims ~47s, actually ~270s)"
echo ""
echo "  Your Task:"
echo "  1. Analyze the video file to determine its TRUE duration"
echo "  2. Create a diagnostic report at: /home/ga/Documents/media_diagnostics.txt"
echo "  3. Report must include:"
echo "     - Claimed duration from metadata"
echo "     - Actual measured duration"
echo "     - Explanation of discrepancy"
echo "     - Verification method used"
echo ""
echo "  Tools available:"
echo "  - VLC Media Player (visual playback)"
echo "  - ffprobe (command-line analysis)"
echo "  - Text editor (gedit, nano, vim)"
echo ""
echo "  Example command: ffprobe -v error -count_frames -select_streams v:0 \\
       -show_entries stream=nb_read_frames /path/to/file"