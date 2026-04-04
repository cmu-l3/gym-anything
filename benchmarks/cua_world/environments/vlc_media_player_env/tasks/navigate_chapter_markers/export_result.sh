#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Navigate Chapter Markers Result ==="

# Check for specifically named snapshots
SOLAR_SNAPSHOT="/home/ga/Pictures/vlc/solar_power.png"
WIND_SNAPSHOT="/home/ga/Pictures/vlc/wind_energy.png"

SOLAR_FOUND="false"
WIND_FOUND="false"

# Check for solar power snapshot
if [ -f "$SOLAR_SNAPSHOT" ]; then
    echo "✅ Solar Power snapshot found: $SOLAR_SNAPSHOT"
    cp "$SOLAR_SNAPSHOT" /tmp/vlc_chapter_solar.png
    SOLAR_FOUND="true"
else
    echo "⚠️ Solar Power snapshot not found at expected location"
    
    # Look for any recent snapshot that might be solar (by timestamp or content)
    # Check for snapshots in the 20-50 second range
    RECENT_SNAPSHOT=$(ls -t /home/ga/Pictures/vlc/vlc-snap* 2>/dev/null | head -1)
    if [ -n "$RECENT_SNAPSHOT" ]; then
        echo "Found recent snapshot, copying as potential solar: $RECENT_SNAPSHOT"
        cp "$RECENT_SNAPSHOT" /tmp/vlc_chapter_solar.png || true
    fi
fi

# Check for wind energy snapshot
if [ -f "$WIND_SNAPSHOT" ]; then
    echo "✅ Wind Energy snapshot found: $WIND_SNAPSHOT"
    cp "$WIND_SNAPSHOT" /tmp/vlc_chapter_wind.png
    WIND_FOUND="true"
else
    echo "⚠️ Wind Energy snapshot not found at expected location"
    
    # Look for second most recent snapshot
    RECENT_SNAPSHOT=$(ls -t /home/ga/Pictures/vlc/vlc-snap* 2>/dev/null | sed -n '2p')
    if [ -n "$RECENT_SNAPSHOT" ]; then
        echo "Found recent snapshot, copying as potential wind: $RECENT_SNAPSHOT"
        cp "$RECENT_SNAPSHOT" /tmp/vlc_chapter_wind.png || true
    fi
fi

# If specific names not found, try to find any two snapshots
if [ "$SOLAR_FOUND" = "false" ] || [ "$WIND_FOUND" = "false" ]; then
    echo "Looking for any snapshots in VLC directory..."
    SNAPSHOT_COUNT=$(ls /home/ga/Pictures/vlc/vlc-snap* 2>/dev/null | wc -l)
    echo "Found $SNAPSHOT_COUNT snapshot(s)"
    
    if [ "$SNAPSHOT_COUNT" -ge 2 ]; then
        # Copy first two snapshots as solar and wind
        SNAP1=$(ls -t /home/ga/Pictures/vlc/vlc-snap* 2>/dev/null | sed -n '1p')
        SNAP2=$(ls -t /home/ga/Pictures/vlc/vlc-snap* 2>/dev/null | sed -n '2p')
        
        if [ -n "$SNAP1" ] && [ "$SOLAR_FOUND" = "false" ]; then
            cp "$SNAP1" /tmp/vlc_chapter_solar.png
            echo "Copied first snapshot as solar: $SNAP1"
        fi
        
        if [ -n "$SNAP2" ] && [ "$WIND_FOUND" = "false" ]; then
            cp "$SNAP2" /tmp/vlc_chapter_wind.png
            echo "Copied second snapshot as wind: $SNAP2"
        fi
    fi
fi

# Check VLC logs for chapter navigation evidence
CHAPTER_NAV_DETECTED="false"

if [ -f /tmp/vlc_chapter_task.log ]; then
    # Look for chapter-related log entries
    if grep -i "chapter" /tmp/vlc_chapter_task.log > /dev/null 2>&1; then
        CHAPTER_NAV_DETECTED="true"
        echo "✅ Chapter navigation detected in VLC logs"
    fi
fi

# Copy VLC log for verification
if [ -f /tmp/vlc_chapter_task.log ]; then
    cp /tmp/vlc_chapter_task.log /tmp/vlc_chapter_result.log
fi

# Create result summary JSON
cat > /tmp/vlc_chapter_result.json <<EOF
{
    "solar_snapshot_found": $SOLAR_FOUND,
    "wind_snapshot_found": $WIND_FOUND,
    "chapter_navigation_detected": $CHAPTER_NAV_DETECTED,
    "timestamp": "$(date)"
}
EOF

echo "✅ Chapter navigation result saved"
cat /tmp/vlc_chapter_result.json

# Close VLC
if is_vlc_running; then
    wid=$(get_vlc_window_id)
    if [ -n "$wid" ]; then
        focus_window "$wid" || true
    fi
    echo "Closing VLC..."
    safe_xdotool ga :1 key --delay 200 ctrl+q
    sleep 2
fi

echo "$(date)" > /tmp/vlc_chapter_completed.txt
echo "Navigate chapter markers task completed" >> /tmp/vlc_chapter_completed.txt

echo "=== Export Complete ==="