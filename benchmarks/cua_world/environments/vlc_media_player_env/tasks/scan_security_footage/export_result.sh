#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Scan Security Footage Result ==="

# Check for snapshots in evidence directory and VLC default directory
EVIDENCE_DIR="/home/ga/Pictures/security_evidence"
VLC_DIR="/home/ga/Pictures/vlc"

SNAPSHOTS_FOUND=0

# Collect all recent snapshots (modified in last 10 minutes)
echo "Searching for snapshots..."

for dir in "$EVIDENCE_DIR" "$VLC_DIR"; do
    if [ -d "$dir" ]; then
        echo "Checking directory: $dir"
        
        # Find PNG/JPG files modified recently
        while IFS= read -r -d '' snapshot; do
            if [ -f "$snapshot" ]; then
                # Check if file was modified in last 10 minutes
                if [ $(($(date +%s) - $(stat -c %Y "$snapshot"))) -lt 600 ]; then
                    SNAPSHOTS_FOUND=$((SNAPSHOTS_FOUND + 1))
                    dest_name="security_snapshot_${SNAPSHOTS_FOUND}.png"
                    cp "$snapshot" "/tmp/$dest_name"
                    echo "✅ Found snapshot: $snapshot -> /tmp/$dest_name"
                fi
            fi
        done < <(find "$dir" -name "*.png" -o -name "*.jpg" -print0 2>/dev/null)
    fi
done

echo "Total snapshots found: $SNAPSHOTS_FOUND"

# Create summary file
cat > /tmp/vlc_security_snapshots_summary.json <<EOF
{
    "snapshot_count": $SNAPSHOTS_FOUND,
    "evidence_dir": "$EVIDENCE_DIR",
    "timestamp": "$(date -Iseconds)"
}
EOF

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

# Create completion marker
echo "$(date)" > /tmp/vlc_security_completed.txt
echo "Security footage scanning task completed" >> /tmp/vlc_security_completed.txt
echo "Snapshots captured: $SNAPSHOTS_FOUND" >> /tmp/vlc_security_completed.txt

echo "=== Export Complete ==="