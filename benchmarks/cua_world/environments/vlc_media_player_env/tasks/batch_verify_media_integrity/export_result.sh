#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Batch Verify Media Integrity Result ==="

# Close VLC if running
if is_vlc_running; then
    echo "Closing VLC..."
    wid=$(get_vlc_window_id)
    if [ -n "$wid" ]; then
        focus_window "$wid" || true
    fi
    safe_xdotool ga :1 key --delay 200 ctrl+q 2>/dev/null || true
    sleep 2
    
    # Force kill if still running
    if is_vlc_running; then
        kill_vlc ga
    fi
fi

# Copy verified_good directory contents to temp location for verification
VERIFIED_DIR="/home/ga/Videos/verified_good"
if [ -d "$VERIFIED_DIR" ]; then
    echo "✅ Verified directory exists"
    
    # Copy each file to temp location for verification
    for file in "$VERIFIED_DIR"/*; do
        if [ -f "$file" ]; then
            filename=$(basename "$file")
            cp "$file" "/tmp/verified_${filename}" 2>/dev/null || true
            echo "Copied: $filename"
        fi
    done
    
    # Create a manifest of verified files
    ls -1 "$VERIFIED_DIR" > /tmp/verified_files_list.txt 2>/dev/null || echo "" > /tmp/verified_files_list.txt
    echo "Verified files list created"
else
    echo "⚠️ Verified directory not found"
    echo "" > /tmp/verified_files_list.txt
fi

# Copy verification report if it exists
REPORT_FILE="/home/ga/Videos/verification_report.txt"
if [ -f "$REPORT_FILE" ]; then
    echo "✅ Verification report found"
    cp "$REPORT_FILE" /tmp/verification_report.txt
    cat "$REPORT_FILE"
else
    echo "⚠️ Verification report not found"
    echo "" > /tmp/verification_report.txt
fi

# Create completion marker with summary
cat > /tmp/batch_verify_completed.json <<EOF
{
    "timestamp": "$(date -Iseconds)",
    "verified_dir_exists": $([ -d "$VERIFIED_DIR" ] && echo "true" || echo "false"),
    "report_exists": $([ -f "$REPORT_FILE" ] && echo "true" || echo "false"),
    "file_count": $(ls -1 "$VERIFIED_DIR" 2>/dev/null | wc -l)
}
EOF

echo "✅ Export complete"
cat /tmp/batch_verify_completed.json

echo "=== Export Complete ==="