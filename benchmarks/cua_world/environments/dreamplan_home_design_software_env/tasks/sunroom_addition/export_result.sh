#!/bin/bash
echo "=== Exporting sunroom_addition results ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
NOW=$(date +%s)

# ---------- Helper: check a file and return JSON fields ----------
check_file() {
    local LINUX_PATH="$1"
    local EXISTS="false"
    local IS_NEW="false"
    local FILE_SIZE="0"
    local FILE_MTIME="0"

    if [ -f "$LINUX_PATH" ]; then
        EXISTS="true"
        FILE_SIZE=$(stat -c %s "$LINUX_PATH" 2>/dev/null || echo "0")
        FILE_MTIME=$(stat -c %Y "$LINUX_PATH" 2>/dev/null || echo "0")
        if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
            IS_NEW="true"
        fi
    fi

    echo "{\"exists\": $EXISTS, \"size_bytes\": $FILE_SIZE, \"mtime_unix\": $FILE_MTIME, \"is_new\": $IS_NEW}"
}

# ---------- Check each required output file ----------
FLOORPLAN_RESULT=$(check_file "/mnt/c/Users/Docker/Desktop/sunroom_floorplan.jpg")
EXTERIOR_RESULT=$(check_file "/mnt/c/Users/Docker/Desktop/sunroom_exterior.jpg")
INTERIOR_RESULT=$(check_file "/mnt/c/Users/Docker/Desktop/sunroom_interior.jpg")
PROJECT_RESULT=$(check_file "/mnt/c/Users/Docker/Documents/sunroom_design.dpn")

echo "sunroom_floorplan.jpg: $FLOORPLAN_RESULT"
echo "sunroom_exterior.jpg:  $EXTERIOR_RESULT"
echo "sunroom_interior.jpg:  $INTERIOR_RESULT"
echo "sunroom_design.dpn:    $PROJECT_RESULT"

# ---------- Check if DreamPlan is still running ----------
APP_RUNNING="false"
if tasklist.exe 2>/dev/null | grep -qi "dreamplan.exe"; then
    APP_RUNNING="true"
fi

# ---------- Capture final screenshot ----------
echo "Capturing final screenshot..."
powershell.exe -Command "
Add-Type -AssemblyName System.Windows.Forms;
Add-Type -AssemblyName System.Drawing;
\$screen = [System.Windows.Forms.Screen]::PrimaryScreen;
\$bitmap = New-Object System.Drawing.Bitmap \$screen.Bounds.Width, \$screen.Bounds.Height;
\$graphics = [System.Drawing.Graphics]::FromImage(\$bitmap);
\$graphics.CopyFromScreen(\$screen.Bounds.X, \$screen.Bounds.Y, 0, 0, \$bitmap.Size);
\$bitmap.Save('C:\Users\Docker\AppData\Local\Temp\task_final.png');
\$graphics.Dispose();
\$bitmap.Dispose();
" 2>/dev/null || true

if [ -f "/mnt/c/Users/Docker/AppData/Local/Temp/task_final.png" ]; then
    cp "/mnt/c/Users/Docker/AppData/Local/Temp/task_final.png" /tmp/task_final.png 2>/dev/null || true
fi

# ---------- Write result JSON ----------
TEMP_JSON="/tmp/result_gen.json"
cat > "$TEMP_JSON" << EOF
{
    "task": "sunroom_addition",
    "task_start": $TASK_START,
    "task_end": $NOW,
    "sunroom_floorplan_jpg": $FLOORPLAN_RESULT,
    "sunroom_exterior_jpg": $EXTERIOR_RESULT,
    "sunroom_interior_jpg": $INTERIOR_RESULT,
    "sunroom_design_dpn": $PROJECT_RESULT,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo ""
echo "=== Export complete ==="
