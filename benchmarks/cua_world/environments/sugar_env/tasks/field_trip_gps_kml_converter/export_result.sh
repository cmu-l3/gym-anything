#!/bin/bash
echo "=== Exporting field_trip_gps_kml_converter task result ==="

SUGAR_ENV="DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus"

su - ga -c "$SUGAR_ENV scrot /tmp/task_final.png" 2>/dev/null || true

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

KML_FILE="/home/ga/Documents/route.kml"

# Check if kml file exists and was modified
KML_EXISTS="false"
KML_MODIFIED="false"
KML_SIZE=0

if [ -f "$KML_FILE" ]; then
    KML_EXISTS="true"
    KML_SIZE=$(stat --format=%s "$KML_FILE" 2>/dev/null || echo "0")
    KML_MTIME=$(stat --format=%Y "$KML_FILE" 2>/dev/null || echo "0")
    if [ "$KML_MTIME" -gt "$TASK_START" ]; then
        KML_MODIFIED="true"
    fi
fi

# Check if script exists
SCRIPT_EXISTS="false"
SCRIPT_NAME=""
if [ -f "/home/ga/Documents/kml_generator.py" ]; then
    SCRIPT_EXISTS="true"
    SCRIPT_NAME="kml_generator.py"
elif [ -f "/home/ga/Documents/kml_generator.sh" ]; then
    SCRIPT_EXISTS="true"
    SCRIPT_NAME="kml_generator.sh"
fi

cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "kml_exists": $KML_EXISTS,
    "kml_modified": $KML_MODIFIED,
    "kml_size": $KML_SIZE,
    "script_exists": $SCRIPT_EXISTS,
    "script_name": "$SCRIPT_NAME"
}
EOF

chmod 666 /tmp/task_result.json
echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="