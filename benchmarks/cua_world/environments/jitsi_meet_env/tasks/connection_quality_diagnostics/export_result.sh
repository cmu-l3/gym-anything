#!/bin/bash
# Export script for Connection Quality Diagnostics task

echo "=== Exporting Connection Quality Diagnostics Result ==="

source /workspace/scripts/task_utils.sh

if ! type take_screenshot &>/dev/null; then
    take_screenshot() {
        local path="${1:-/tmp/screenshot.png}"
        DISPLAY=:1 scrot "$path" 2>/dev/null || DISPLAY=:1 import -window root "$path" 2>/dev/null || true
    }
fi

# Take final screenshot
take_screenshot /tmp/quality_task_end.png

# Get task start timestamp
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# --- Check report file ---
REPORT_FILE="/home/ga/Desktop/meeting_quality_report.txt"
REPORT_EXISTS=0
REPORT_SIZE=0
REPORT_MTIME=0

if [ -f "$REPORT_FILE" ]; then
    REPORT_EXISTS=1
    REPORT_SIZE=$(wc -c < "$REPORT_FILE" 2>/dev/null || echo "0")
    REPORT_MTIME=$(stat -c %Y "$REPORT_FILE" 2>/dev/null || echo "0")
fi

# --- Check report content for procedure vocabulary ---
HAS_URL=0
HAS_STATS=0
HAS_QUALITY=0
HAS_TILE_OR_SPEAKER=0

if [ -f "$REPORT_FILE" ]; then
    # URL or room name
    grep -qiE "localhost:8080|QualityTestRoom|Quality.*Test|8080/Quality" "$REPORT_FILE" 2>/dev/null && HAS_URL=1

    # Connection statistics procedure vocabulary:
    # RTT, packet loss, jitter, bitrate, bandwidth, latency only appear in the Jitsi stats panel
    grep -qiE "RTT|packet.*loss|jitter|bitrate|bandwidth|latency|kbps|Mbps|frame.*rate|fps|resolution.*px" \
        "$REPORT_FILE" 2>/dev/null && HAS_STATS=1

    # Video quality dialog vocabulary:
    # 'Low Definition', 'Standard Definition', 'High Definition', 'Full High Definition'
    # These exact strings only appear in Jitsi's quality settings dialog
    grep -qiE "low definition|standard definition|high definition|full high|video quality|LD|SD|HD" \
        "$REPORT_FILE" 2>/dev/null && HAS_QUALITY=1

    # Tile view and speaker stats vocabulary:
    # 'tile view', 'grid view', 'dominant speaker', 'speaker stats', 'time speaking'
    grep -qiE "tile.view|grid.view|tile.*layout|dominant.*speaker|speaker.*stat|time.*speaking|talk.*time" \
        "$REPORT_FILE" 2>/dev/null && HAS_TILE_OR_SPEAKER=1
fi

# --- Write result JSON ---
cat > /tmp/connection_quality_diagnostics_result.json << EOF
{
    "task_start": $TASK_START,
    "report_exists": $REPORT_EXISTS,
    "report_size": $REPORT_SIZE,
    "report_mtime": $REPORT_MTIME,
    "has_url": $HAS_URL,
    "has_stats": $HAS_STATS,
    "has_quality": $HAS_QUALITY,
    "has_tile_or_speaker": $HAS_TILE_OR_SPEAKER,
    "export_timestamp": "$(date -Iseconds)"
}
EOF

echo "Result written to /tmp/connection_quality_diagnostics_result.json"
echo "=== Export Complete ==="
