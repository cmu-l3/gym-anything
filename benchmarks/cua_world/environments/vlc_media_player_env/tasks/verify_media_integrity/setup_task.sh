#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Verify Media Integrity Task ==="

# Kill any existing VLC instances
kill_vlc ga
sleep 1

# Create verification directory
VERIFY_DIR="/home/ga/Videos/verification"
mkdir -p "$VERIFY_DIR"
chown -R ga:ga "$VERIFY_DIR"

# Create Documents directory for report
mkdir -p /home/ga/Documents
chown -R ga:ga /home/ga/Documents

# Create expected specifications file
cat > "$VERIFY_DIR/expected_specs.txt" <<'EOF'
Expected Specifications for documentary_lecture.mp4:
- Resolution: 1920x1080 (1080p)
- Duration: 60 seconds (±5 seconds)
- Video Codec: H.264
- File Size: >50 MB
EOF

chown ga:ga "$VERIFY_DIR/expected_specs.txt"

echo "📄 Expected specifications file created"

# Generate test video with MISMATCHED specs
# Expected: 1920x1080, 60s, H.264
# Actual: 1280x720, 30s, H.264 (resolution and duration mismatch)
echo "🎬 Generating test video with intentional spec mismatch..."

VIDEO_FILE="$VERIFY_DIR/documentary_lecture.mp4"

# Generate 1280x720 video at 30 seconds duration (NOT the expected 1920x1080 @ 60s)
# This creates the mismatch scenario
su - ga -c "ffmpeg -f lavfi -i testsrc=duration=30:size=1280x720:rate=30 \
    -f lavfi -i sine=frequency=440:duration=30 \
    -c:v libx264 -preset fast -crf 23 \
    -c:a aac -b:a 128k \
    -y '$VIDEO_FILE' > /tmp/ffmpeg_verification_gen.log 2>&1"

if [ ! -f "$VIDEO_FILE" ]; then
    echo "❌ ERROR: Failed to generate test video"
    cat /tmp/ffmpeg_verification_gen.log
    exit 1
fi

# Verify the generated video has the intentional mismatch
VIDEO_INFO=$(ffprobe -v error -select_streams v:0 -show_entries stream=width,height,codec_name -show_entries format=duration -of json "$VIDEO_FILE" 2>/dev/null)
echo "✅ Test video generated with specs:"
echo "$VIDEO_INFO" | grep -E "width|height|codec_name|duration" || true

# Don't launch VLC - let the agent open it
echo "VLC not launched - agent should open the file"

echo "=== Verify Media Integrity Task Setup Complete ==="
echo ""
echo "📝 Task Instructions:"
echo "  1. Open /home/ga/Videos/verification/documentary_lecture.mp4 in VLC"
echo "  2. Access Tools → Media Information (Ctrl+I)"
echo "  3. Check the Codec Information tab for:"
echo "     - Video resolution (width x height)"
echo "     - Video codec name"
echo "     - Duration"
echo "  4. Compare against expected specs in:"
echo "     /home/ga/Videos/verification/expected_specs.txt"
echo "  5. Create verification report at:"
echo "     /home/ga/Documents/verification_report.txt"
echo "  6. Document findings with format:"
echo "     - Actual Resolution: [width]x[height]"
echo "     - Actual Codec: [codec_name]"
echo "     - Actual Duration: [seconds or MM:SS]"
echo "     - Status: PASS or FAIL"
echo "     - Notes: [any discrepancies]"
echo ""
echo "⚠️  Note: Expected specs are 1920x1080, 60s, H.264"
echo "    Actual video is intentionally different!"