#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Extract Research Frames Result ==="

# Directory where frames should be saved
FRAMES_DIR="/home/ga/Pictures/research_frames"

# Create output directory for verification
mkdir -p /tmp/task_output/research_frames

# Expected frame names
EXPECTED_FRAMES=(
    "frame_position_01.png"
    "frame_position_02.png"
    "frame_position_03.png"
    "frame_position_04.png"
    "frame_position_05.png"
)

FRAMES_FOUND=0
FRAMES_MISSING=0

echo "Checking for extracted frames..."

# Check each expected frame
for frame in "${EXPECTED_FRAMES[@]}"; do
    FRAME_PATH="${FRAMES_DIR}/${frame}"
    
    if [ -f "$FRAME_PATH" ]; then
        echo "  ✅ Found: $frame"
        cp "$FRAME_PATH" /tmp/task_output/research_frames/
        FRAMES_FOUND=$((FRAMES_FOUND + 1))
    else
        echo "  ❌ Missing: $frame"
        FRAMES_MISSING=$((FRAMES_MISSING + 1))
    fi
done

# Also check for any other frames that might have been created
echo ""
echo "Looking for any other snapshots in directory..."
OTHER_FRAMES=$(find "$FRAMES_DIR" -name "*.png" -type f 2>/dev/null | wc -l)

if [ "$OTHER_FRAMES" -gt 0 ]; then
    echo "Found $OTHER_FRAMES total PNG files in directory"
    
    # Copy all PNGs (including any with default VLC naming)
    find "$FRAMES_DIR" -name "*.png" -type f -exec cp {} /tmp/task_output/research_frames/ \; 2>/dev/null || true
fi

# Create frame manifest
echo "Creating frame manifest..."
cat > /tmp/task_output/frame_manifest.txt << EOF
Frame Extraction Results
========================
Timestamp: $(date)
Expected frames: ${#EXPECTED_FRAMES[@]}
Frames found: $FRAMES_FOUND
Frames missing: $FRAMES_MISSING

Frame Details:
EOF

# Add details for each frame
for frame in "${EXPECTED_FRAMES[@]}"; do
    FRAME_PATH="${FRAMES_DIR}/${frame}"
    
    if [ -f "$FRAME_PATH" ]; then
        SIZE=$(stat -f%z "$FRAME_PATH" 2>/dev/null || stat -c%s "$FRAME_PATH" 2>/dev/null || echo "0")
        SIZE_KB=$((SIZE / 1024))
        echo "  $frame: EXISTS (${SIZE_KB} KB)" >> /tmp/task_output/frame_manifest.txt
    else
        echo "  $frame: MISSING" >> /tmp/task_output/frame_manifest.txt
    fi
done

# If frames exist, get detailed info using ImageMagick identify
if [ "$FRAMES_FOUND" -gt 0 ]; then
    echo "" >> /tmp/task_output/frame_manifest.txt
    echo "Detailed Image Properties:" >> /tmp/task_output/frame_manifest.txt
    
    for frame in "${EXPECTED_FRAMES[@]}"; do
        FRAME_PATH="${FRAMES_DIR}/${frame}"
        
        if [ -f "$FRAME_PATH" ]; then
            if command -v identify &> /dev/null; then
                identify "$FRAME_PATH" >> /tmp/task_output/frame_manifest.txt 2>&1 || echo "  Could not analyze $frame" >> /tmp/task_output/frame_manifest.txt
            fi
        fi
    done
fi

cat /tmp/task_output/frame_manifest.txt
echo ""

# Close VLC if still running
if is_vlc_running; then
    echo "Closing VLC..."
    wid=$(get_vlc_window_id)
    if [ -n "$wid" ]; then
        focus_window "$wid" || true
    fi
    safe_xdotool ga :1 key --delay 200 ctrl+q
    sleep 2
    
    # Force kill if still running
    if is_vlc_running; then
        kill_vlc ga
    fi
fi

# Create completion marker
echo "$(date)" > /tmp/task_output/vlc_research_frames_completed.txt
echo "Frames found: $FRAMES_FOUND / ${#EXPECTED_FRAMES[@]}" >> /tmp/task_output/vlc_research_frames_completed.txt

echo "✅ Export complete: /tmp/task_output/"
echo "   - Frames copied: $FRAMES_FOUND"
echo "   - Manifest: frame_manifest.txt"

echo "=== Export Complete ==="