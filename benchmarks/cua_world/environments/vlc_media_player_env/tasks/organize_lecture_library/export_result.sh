#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Organize Lecture Library Result ==="

COURSES_DIR="/home/ga/Videos/Courses"
RAW_DIR="/home/ga/Downloads/lectures_raw"

# Create export directory structure
EXPORT_DIR="/tmp/organized_lectures"
rm -rf "$EXPORT_DIR"
mkdir -p "$EXPORT_DIR"

# Export organized folder structure if it exists
if [ -d "$COURSES_DIR" ]; then
    echo "Exporting organized course structure..."
    
    # Copy entire Courses directory structure
    cp -r "$COURSES_DIR" "$EXPORT_DIR/" 2>/dev/null || true
    
    # List what was organized
    if [ -d "$EXPORT_DIR/Courses" ]; then
        echo "✅ Organized structure found:"
        find "$EXPORT_DIR/Courses" -type f -o -type d | sort
    else
        echo "⚠️ No organized structure found"
    fi
else
    echo "⚠️ Courses directory not found"
fi

# Check raw directory status (should be empty if cleaned up)
RAW_FILES_COUNT=0
if [ -d "$RAW_DIR" ]; then
    RAW_FILES_COUNT=$(find "$RAW_DIR" -type f -name "*.mp4" 2>/dev/null | wc -l)
    echo "Raw folder remaining files: $RAW_FILES_COUNT"
fi

# Create result summary JSON
cat > /tmp/organization_summary.json <<EOF
{
    "courses_dir_exists": $([ -d "$COURSES_DIR" ] && echo "true" || echo "false"),
    "raw_files_remaining": $RAW_FILES_COUNT,
    "export_dir": "$EXPORT_DIR",
    "timestamp": "$(date -Iseconds)"
}
EOF

echo "✅ Organization summary saved"
cat /tmp/organization_summary.json

# Close VLC if running
if is_vlc_running; then
    echo "Closing VLC..."
    wid=$(get_vlc_window_id)
    if [ -n "$wid" ]; then
        focus_window "$wid" || true
    fi
    safe_xdotool ga :1 key --delay 200 ctrl+q || true
    sleep 1
    kill_vlc ga || true
fi

# Create completion marker
echo "$(date)" > /tmp/vlc_organize_completed.txt
echo "Lecture library organization task completed" >> /tmp/vlc_organize_completed.txt

echo "=== Export Complete ==="