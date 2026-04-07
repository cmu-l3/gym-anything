#!/bin/bash
echo "=== Exporting physics trajectory task result ==="

SUGAR_ENV="DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus"

# Take final screenshot
su - ga -c "$SUGAR_ENV scrot /tmp/rocket_task_end.png" 2>/dev/null || true

START_TS=$(cat /tmp/task_start_ts 2>/dev/null || echo "0")
SCRIPT_FILE="/home/ga/Documents/trajectory_model.py"
CSV_FILE="/home/ga/Documents/rocket_trajectory.csv"

SCRIPT_EXISTS="false"
if [ -f "$SCRIPT_FILE" ]; then 
    SCRIPT_EXISTS="true"
fi

CSV_EXISTS="false"
CSV_MODIFIED="false"
CSV_SIZE=0

if [ -f "$CSV_FILE" ]; then
    CSV_EXISTS="true"
    CSV_SIZE=$(stat --format=%s "$CSV_FILE" 2>/dev/null || echo "0")
    CSV_MTIME=$(stat --format=%Y "$CSV_FILE" 2>/dev/null || echo "0")
    
    # Verify file was created/modified AFTER task started
    if [ "$CSV_MTIME" -gt "$START_TS" ]; then
        CSV_MODIFIED="true"
    fi
    
    # Copy the CSV to /tmp with open permissions so the host verifier can read it via copy_from_env
    cp "$CSV_FILE" /tmp/rocket_trajectory.csv
    chmod 666 /tmp/rocket_trajectory.csv
fi

# Create export JSON payload
cat > /tmp/rocket_result.json << EOF
{
    "script_exists": $SCRIPT_EXISTS,
    "csv_exists": $CSV_EXISTS,
    "csv_modified": $CSV_MODIFIED,
    "csv_size": $CSV_SIZE
}
EOF
chmod 666 /tmp/rocket_result.json

echo "Result saved to /tmp/rocket_result.json"
cat /tmp/rocket_result.json
echo "=== Export complete ==="