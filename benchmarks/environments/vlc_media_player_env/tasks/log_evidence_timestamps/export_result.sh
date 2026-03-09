#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Log Evidence Timestamps Result ==="

# Check for timestamp log file
LOG_PATHS=(
    "/home/ga/Documents/evidence_log.txt"
    "/home/ga/Documents/evidence_log.csv"
    "/home/ga/Documents/event_log.txt"
    "/home/ga/Documents/timeline.txt"
    "/home/ga/Documents/timestamps.txt"
    "/home/ga/Documents/evidence_timeline.txt"
)

LOG_FOUND=""
for log_path in "${LOG_PATHS[@]}"; do
    if [ -f "$log_path" ]; then
        LOG_FOUND="$log_path"
        echo "✅ Found log file: $log_path"
        break
    fi
done

if [ -n "$LOG_FOUND" ]; then
    cp "$LOG_FOUND" /tmp/vlc_evidence_log.txt
    echo "Log file contents:"
    cat "$LOG_FOUND"
else
    echo "⚠️ No timestamp log file found at expected locations"
    # Create empty placeholder
    touch /tmp/vlc_evidence_log.txt
fi

# Check for optional snapshots
SNAPSHOT_DIR="/home/ga/Pictures/evidence"
SNAPSHOT_COUNT=0

if [ -d "$SNAPSHOT_DIR" ]; then
    SNAPSHOT_COUNT=$(find "$SNAPSHOT_DIR" -type f \( -name "*.png" -o -name "*.jpg" -o -name "*.jpeg" \) -mmin -10 2>/dev/null | wc -l)
    echo "Found $SNAPSHOT_COUNT snapshot(s) in evidence directory"
    
    if [ "$SNAPSHOT_COUNT" -gt 0 ]; then
        # Create a list of snapshots for verification
        find "$SNAPSHOT_DIR" -type f \( -name "*.png" -o -name "*.jpg" -o -name "*.jpeg" \) -mmin -10 > /tmp/vlc_evidence_snapshots.txt
        
        # Copy first snapshot as sample
        FIRST_SNAPSHOT=$(head -1 /tmp/vlc_evidence_snapshots.txt)
        if [ -n "$FIRST_SNAPSHOT" ] && [ -f "$FIRST_SNAPSHOT" ]; then
            cp "$FIRST_SNAPSHOT" /tmp/vlc_evidence_sample_snapshot.png
        fi
    fi
fi

# Create summary JSON
cat > /tmp/vlc_evidence_summary.json <<EOF
{
    "log_file_found": $([ -n "$LOG_FOUND" ] && echo "true" || echo "false"),
    "log_file_path": "$LOG_FOUND",
    "snapshot_count": $SNAPSHOT_COUNT,
    "completed_at": "$(date -Iseconds)"
}
EOF

echo "✅ Summary saved to /tmp/vlc_evidence_summary.json"
cat /tmp/vlc_evidence_summary.json

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

# Fallback kill if still running
if is_vlc_running; then
    kill_vlc ga
fi

echo "$(date)" > /tmp/vlc_evidence_completed.txt
echo "Evidence timestamp logging task completed" >> /tmp/vlc_evidence_completed.txt

echo "=== Export Complete ==="