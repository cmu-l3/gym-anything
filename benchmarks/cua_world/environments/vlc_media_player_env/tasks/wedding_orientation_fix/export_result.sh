#!/bin/bash
# Export results for wedding_orientation_fix task
set -e

source /workspace/scripts/task_utils.sh

echo "Exporting results for wedding_orientation_fix..."

# Capture final state screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Prepare export directories in /tmp
mkdir -p /tmp/wedding_corrected
mkdir -p /tmp/wedding_export

# 1. Copy corrected clips
for f in /home/ga/Videos/corrected/*.mp4; do
    if [ -f "$f" ]; then
        cp -f "$f" "/tmp/wedding_corrected/$(basename "$f")" 2>/dev/null || true
    fi
done

# 2. Copy the highlight reel
if [ -f "/home/ga/Videos/wedding_highlight.mp4" ]; then
    cp -f "/home/ga/Videos/wedding_highlight.mp4" "/tmp/wedding_export/wedding_highlight.mp4" 2>/dev/null || true
fi

# 3. Copy the shot correction log
if [ -f "/home/ga/Documents/shot_correction_log.json" ]; then
    cp -f "/home/ga/Documents/shot_correction_log.json" "/tmp/wedding_export/shot_correction_log.json" 2>/dev/null || true
fi

# 4. Check reel modification time for anti-gaming
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
REEL_MTIME=$(stat -c %Y /home/ga/Videos/wedding_highlight.mp4 2>/dev/null || echo "0")
if [ "$REEL_MTIME" -gt "$TASK_START" ]; then
    REEL_NEW="true"
else
    REEL_NEW="false"
fi

cat > /tmp/wedding_export/meta.json << EOF
{
    "task_start_time": $TASK_START,
    "reel_mtime": $REEL_MTIME,
    "reel_newly_created": $REEL_NEW
}
EOF

# Ensure permissions
chmod -R 777 /tmp/wedding_corrected /tmp/wedding_export

# Clean up VLC
kill_vlc

echo "Export complete for wedding_orientation_fix"