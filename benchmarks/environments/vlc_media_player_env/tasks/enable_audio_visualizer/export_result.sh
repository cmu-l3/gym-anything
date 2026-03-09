#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Audio Visualizer Task Result ==="

USER_HOME="/home/ga"
OUTPUT_DIR="$USER_HOME/Pictures/audio_analysis"
VLC_SNAPSHOT_DIR="$USER_HOME/Pictures/vlc"

log() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a /tmp/vlc_audio_viz_export.log; }

# Search for screenshot in multiple possible locations
SCREENSHOT=""
SCREENSHOT_LOCATIONS=(
    "$OUTPUT_DIR/warbler_analysis.png"
    "$VLC_SNAPSHOT_DIR/warbler_analysis.png"
    "$USER_HOME/Pictures/warbler_analysis.png"
    "$USER_HOME/Desktop/warbler_analysis.png"
)

log "Searching for screenshot..."

# First check expected locations
for location in "${SCREENSHOT_LOCATIONS[@]}"; do
    if [ -f "$location" ]; then
        SCREENSHOT="$location"
        log "✅ Found screenshot at expected location: $SCREENSHOT"
        break
    fi
done

# If not found, search for recently created PNG files
if [ -z "$SCREENSHOT" ]; then
    log "Searching for recent PNG files in common directories..."
    
    # Search in output directory (most recent in last 5 minutes)
    RECENT_OUTPUT=$(find "$OUTPUT_DIR" -name "*.png" -type f -mmin -5 2>/dev/null | head -1)
    if [ -n "$RECENT_OUTPUT" ]; then
        SCREENSHOT="$RECENT_OUTPUT"
        log "Found recent file in output dir: $SCREENSHOT"
    fi
    
    # Search in VLC snapshot directory
    if [ -z "$SCREENSHOT" ]; then
        RECENT_VLC=$(find "$VLC_SNAPSHOT_DIR" -name "*.png" -type f -mmin -5 2>/dev/null | head -1)
        if [ -n "$RECENT_VLC" ]; then
            SCREENSHOT="$RECENT_VLC"
            log "Found recent VLC snapshot: $SCREENSHOT"
        fi
    fi
    
    # Search in Pictures directory
    if [ -z "$SCREENSHOT" ]; then
        RECENT_PIC=$(find "$USER_HOME/Pictures" -name "*.png" -type f -mmin -5 2>/dev/null | head -1)
        if [ -n "$RECENT_PIC" ]; then
            SCREENSHOT="$RECENT_PIC"
            log "Found recent file in Pictures: $SCREENSHOT"
        fi
    fi
fi

# Copy screenshot if found
if [ -n "$SCREENSHOT" ] && [ -f "$SCREENSHOT" ]; then
    log "Copying screenshot to /tmp for verification..."
    cp "$SCREENSHOT" /tmp/vlc_audio_viz_screenshot.png
    
    # Get file info
    FILE_SIZE=$(stat -f%z "$SCREENSHOT" 2>/dev/null || stat -c%s "$SCREENSHOT" 2>/dev/null || echo "0")
    FILE_SIZE_KB=$((FILE_SIZE / 1024))
    
    log "Screenshot details:"
    log "  Path: $SCREENSHOT"
    log "  Size: ${FILE_SIZE_KB} KB"
    
    ls -lh "$SCREENSHOT" | tee -a /tmp/vlc_audio_viz_export.log
    
    # Create metadata JSON
    cat > /tmp/vlc_audio_viz_metadata.json <<EOF
{
    "screenshot_found": true,
    "screenshot_path": "$SCREENSHOT",
    "screenshot_size_kb": $FILE_SIZE_KB,
    "timestamp": "$(date -Iseconds)"
}
EOF
else
    log "⚠️ WARNING: No screenshot found"
    
    cat > /tmp/vlc_audio_viz_metadata.json <<EOF
{
    "screenshot_found": false,
    "screenshot_path": "",
    "screenshot_size_kb": 0,
    "timestamp": "$(date -Iseconds)",
    "searched_locations": [
        "$OUTPUT_DIR/warbler_analysis.png",
        "$VLC_SNAPSHOT_DIR/*.png",
        "$USER_HOME/Pictures/*.png"
    ]
}
EOF
    
    # Create empty marker file
    touch /tmp/vlc_audio_viz_no_screenshot.txt
fi

# Check VLC config for any visualization settings (supplementary info)
VLC_RC="$USER_HOME/.config/vlc/vlcrc"
if [ -f "$VLC_RC" ]; then
    log "Checking VLC config for visualization settings..."
    
    # Extract visualization-related settings
    grep -E "(audio-visual|visual|effect-list|vout)" "$VLC_RC" > /tmp/vlc_audio_viz_config.txt 2>/dev/null || echo "No visualization settings found" > /tmp/vlc_audio_viz_config.txt
    
    log "VLC config excerpt:"
    cat /tmp/vlc_audio_viz_config.txt | tee -a /tmp/vlc_audio_viz_export.log
else
    echo "VLC config not found" > /tmp/vlc_audio_viz_config.txt
    log "⚠️ VLC config not found"
fi

# Close VLC gracefully
if is_vlc_running; then
    log "Closing VLC..."
    
    wid=$(get_vlc_window_id)
    if [ -n "$wid" ]; then
        focus_window "$wid" 2>/dev/null || true
        sleep 0.5
    fi
    
    safe_xdotool ga :1 key --delay 200 ctrl+q 2>/dev/null || true
    sleep 2
    
    # Force kill if still running
    if is_vlc_running; then
        log "Force killing VLC..."
        kill_vlc ga
    fi
fi

# Create completion marker
echo "$(date)" > /tmp/vlc_audio_viz_completed.txt
echo "Audio visualizer task export completed" >> /tmp/vlc_audio_viz_completed.txt

log "=== Export Complete ==="
log "Screenshot status: $([ -n "$SCREENSHOT" ] && echo "FOUND" || echo "NOT FOUND")"