#!/bin/bash
echo "=== Exporting Fiscal Reconciliation and Regional Analysis Results ==="

source /workspace/scripts/task_utils.sh

# 1. Capture final screenshot (while LO is still running)
take_screenshot /tmp/task_final.png

# 2. Gracefully close LibreOffice to flush HSQLDB buffers to the ODB ZIP.
#    This is CRITICAL: HSQLDB writes changes to database/script only on save/exit.
#    Without this, the ODB file may appear unmodified even if the agent made changes.
echo "Closing LibreOffice to flush changes..."

# Try graceful save+quit first
WID=$(DISPLAY=:1 xdotool search --class soffice 2>/dev/null | head -1)
if [ -z "$WID" ]; then
    WID=$(DISPLAY=:1 xdotool search --name "chinook" 2>/dev/null | head -1)
fi

if [ -n "$WID" ]; then
    DISPLAY=:1 xdotool windowfocus --sync "$WID" 2>/dev/null || true
    sleep 0.5
    DISPLAY=:1 xdotool key ctrl+s
    sleep 3
    DISPLAY=:1 xdotool key ctrl+q
    sleep 2
    # Dismiss any "save changes?" dialog
    DISPLAY=:1 xdotool key Return
    sleep 1
fi

# Wait for clean exit, then force-kill if needed
for i in $(seq 1 30); do
    if ! pgrep -f soffice > /dev/null 2>&1; then
        echo "LibreOffice exited after ${i}s"
        break
    fi
    sleep 1
done

if pgrep -f soffice > /dev/null 2>&1; then
    echo "Force-killing LibreOffice..."
    pkill -f "soffice" || true
    sleep 2
    pkill -9 -f "soffice" || true
    sleep 1
fi

# 3. Gather file statistics
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
ODB_PATH="/home/ga/chinook.odb"

if [ -f "$ODB_PATH" ]; then
    ODB_EXISTS="true"
    ODB_SIZE=$(stat -c%s "$ODB_PATH")
    ODB_MTIME=$(stat -c%Y "$ODB_PATH")

    # Modification detection via MD5 comparison (more reliable than timestamp)
    INITIAL_MD5=$(cat /tmp/initial_odb_checksum.txt 2>/dev/null || echo "")
    CURRENT_MD5=$(md5sum "$ODB_PATH" | awk '{print $1}')

    if [ "$INITIAL_MD5" != "$CURRENT_MD5" ]; then
        ODB_MODIFIED="true"
    else
        ODB_MODIFIED="false"
    fi
else
    ODB_EXISTS="false"
    ODB_SIZE=0
    ODB_MTIME=0
    ODB_MODIFIED="false"
fi

# 4. Create result JSON
cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "task_end": $(date +%s),
    "odb_exists": $ODB_EXISTS,
    "odb_modified": $ODB_MODIFIED,
    "odb_size": $ODB_SIZE,
    "odb_mtime": $ODB_MTIME,
    "screenshot_path": "/tmp/task_final.png",
    "database_path": "$ODB_PATH",
    "ground_truth_path": "/tmp/ground_truth.json"
}
EOF

# 5. Ensure permissions for copy_from_env
chmod 644 /tmp/task_result.json
chmod 644 /tmp/ground_truth.json
chmod 644 /home/ga/chinook.odb 2>/dev/null || true

echo "Results exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="
