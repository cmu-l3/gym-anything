#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Verify Delivery Specs Task ==="

# Kill any existing VLC instances
kill_vlc ga
sleep 1

# Ensure Documents directory exists
mkdir -p /home/ga/Documents
mkdir -p /home/ga/Videos
chown -R ga:ga /home/ga/Documents
chown -R ga:ga /home/ga/Videos

# Create specification document
cat > /home/ga/Documents/delivery_specs.txt << 'EOF'
PROJECT: Company Promo Video
REQUIRED SPECIFICATIONS:
- Resolution: 1920x1080 (Full HD)
- Video Codec: H.264
- Bitrate: ~5 Mbps (±0.5 Mbps acceptable)
- Format: MP4 container
- Min Duration: 30 seconds

NOTE: All specifications must be met for delivery acceptance.
Please verify the delivered file meets these requirements before approving payment.
EOF

chown ga:ga /home/ga/Documents/delivery_specs.txt
chmod 644 /home/ga/Documents/delivery_specs.txt

# Randomly decide if video meets specs (50% chance)
SCENARIO=$((RANDOM % 4))

echo "Selected scenario: $SCENARIO"

case $SCENARIO in
    0)
        # Compliant: 1920x1080, H.264, ~5Mbps, 35 seconds
        echo "Generating COMPLIANT video..."
        ffmpeg -f lavfi -i testsrc=duration=35:size=1920x1080:rate=30 \
               -f lavfi -i sine=frequency=440:duration=35 \
               -c:v libx264 -b:v 5000k -maxrate 5000k -bufsize 10000k \
               -c:a aac -b:a 128k \
               -movflags +faststart \
               /home/ga/Videos/client_delivery.mp4 -y \
               > /tmp/ffmpeg_setup.log 2>&1
        echo "PASS" > /tmp/expected_verdict.txt
        echo "compliant" > /tmp/scenario_type.txt
        ;;
    1)
        # Non-compliant: Wrong resolution (1280x720 instead of 1920x1080)
        echo "Generating NON-COMPLIANT video (wrong resolution)..."
        ffmpeg -f lavfi -i testsrc=duration=35:size=1280x720:rate=30 \
               -f lavfi -i sine=frequency=440:duration=35 \
               -c:v libx264 -b:v 5000k -maxrate 5000k -bufsize 10000k \
               -c:a aac -b:a 128k \
               -movflags +faststart \
               /home/ga/Videos/client_delivery.mp4 -y \
               > /tmp/ffmpeg_setup.log 2>&1
        echo "FAIL" > /tmp/expected_verdict.txt
        echo "wrong_resolution" > /tmp/scenario_type.txt
        ;;
    2)
        # Non-compliant: Wrong bitrate (3Mbps instead of 5Mbps)
        echo "Generating NON-COMPLIANT video (low bitrate)..."
        ffmpeg -f lavfi -i testsrc=duration=35:size=1920x1080:rate=30 \
               -f lavfi -i sine=frequency=440:duration=35 \
               -c:v libx264 -b:v 3000k -maxrate 3000k -bufsize 6000k \
               -c:a aac -b:a 128k \
               -movflags +faststart \
               /home/ga/Videos/client_delivery.mp4 -y \
               > /tmp/ffmpeg_setup.log 2>&1
        echo "FAIL" > /tmp/expected_verdict.txt
        echo "low_bitrate" > /tmp/scenario_type.txt
        ;;
    3)
        # Non-compliant: Too short (25 seconds instead of 30+)
        echo "Generating NON-COMPLIANT video (too short)..."
        ffmpeg -f lavfi -i testsrc=duration=25:size=1920x1080:rate=30 \
               -f lavfi -i sine=frequency=440:duration=25 \
               -c:v libx264 -b:v 5000k -maxrate 5000k -bufsize 10000k \
               -c:a aac -b:a 128k \
               -movflags +faststart \
               /home/ga/Videos/client_delivery.mp4 -y \
               > /tmp/ffmpeg_setup.log 2>&1
        echo "FAIL" > /tmp/expected_verdict.txt
        echo "too_short" > /tmp/scenario_type.txt
        ;;
esac

# Verify video was created
if [ ! -f /home/ga/Videos/client_delivery.mp4 ]; then
    echo "ERROR: Failed to create video file"
    cat /tmp/ffmpeg_setup.log
    exit 1
fi

chown ga:ga /home/ga/Videos/client_delivery.mp4
chmod 644 /home/ga/Videos/client_delivery.mp4

echo "Video created: $(ls -lh /home/ga/Videos/client_delivery.mp4)"

# Store ground truth for verifier using ffprobe
ffprobe -v error -select_streams v:0 \
    -show_entries stream=codec_name,width,height,bit_rate,r_frame_rate \
    -show_entries format=duration,format_name,size \
    -of json /home/ga/Videos/client_delivery.mp4 > /tmp/ground_truth.json 2>&1

echo "Ground truth stored"
cat /tmp/ground_truth.json

# Launch VLC (without opening the video - agent needs to do that)
echo "Launching VLC..."
su - ga -c "DISPLAY=:1 LIBVA_DRIVER_NAME='' VDPAU_DRIVER='' vlc --avcodec-hw=none --no-video-title-show > /tmp/vlc_verify_specs_task.log 2>&1 &"

if ! wait_for_process "vlc" 15; then
    echo "ERROR: VLC failed to start"
    cat /tmp/vlc_verify_specs_task.log
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

# Focus VLC window
wid=$(get_vlc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
fi

echo "=== Verify Delivery Specs Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. Read specification requirements: /home/ga/Documents/delivery_specs.txt"
echo "  2. Open video file: /home/ga/Videos/client_delivery.mp4 (Media → Open File)"
echo "  3. Access Media Information: Tools → Media Information (Ctrl+I)"
echo "  4. Go to 'Codec Details' tab to see technical properties"
echo "  5. Check: Resolution, Codec, Bitrate, Format, Duration"
echo "  6. Create report: /home/ga/Documents/verification_report.txt"
echo "  7. Mark each spec as PASS or FAIL"
echo "  8. Give overall verdict: PASS (all specs met) or FAIL (any spec failed)"
echo "  9. Recommend: ACCEPT DELIVERY or REQUEST REVISION"