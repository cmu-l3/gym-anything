#!/bin/bash
echo "=== Exporting japan_flag_turtleart task result ==="

SUGAR_ENV="DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus"

# Take final screenshot
su - ga -c "$SUGAR_ENV scrot /tmp/japan_flag_end.png" 2>/dev/null || true

TA_FILE="/home/ga/Documents/japan_flag.ta"
FILE_EXISTS="false"
FILE_SIZE=0
FILE_MTIME=0
TASK_START=$(cat /tmp/japan_flag_start_ts 2>/dev/null || echo "0")
FILE_MODIFIED="false"

if [ -f "$TA_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat --format=%s "$TA_FILE" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat --format=%Y "$TA_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi
    echo "Found: $TA_FILE ($FILE_SIZE bytes, mtime=$FILE_MTIME, start=$TASK_START)"

    # Parse the TurtleArt JSON to check block structure
    python3 << 'PYEOF' > /tmp/japan_flag_analysis.json 2>/dev/null || echo '{"error":"parse_failed"}' > /tmp/japan_flag_analysis.json
import json
import sys

result = {
    "has_start": False,
    "has_penup": False,
    "has_setcolor": False,
    "has_color_0": False,
    "has_fill": False,
    "has_arc": False,
    "has_arc_360": False,
    "has_valid_radius": False,
    "has_endfill": False,
    "block_count": 0,
    "error": None
}

try:
    with open("/home/ga/Documents/japan_flag.ta", "r") as f:
        data = json.load(f)

    if not isinstance(data, list):
        result["error"] = "not_array"
        print(json.dumps(result))
        sys.exit(0)

    block_names = []
    number_values = []

    for item in data:
        if not isinstance(item, list) or len(item) < 2:
            continue
        block_type = item[1]

        # Block name is either a string or ["type", value]
        if isinstance(block_type, str):
            block_names.append(block_type)
            if block_type == "start":
                result["has_start"] = True
            elif block_type == "penup":
                result["has_penup"] = True
            elif block_type == "setcolor":
                result["has_setcolor"] = True
            elif block_type in ("fill", "startfill"):
                result["has_fill"] = True
            elif block_type == "arc":
                result["has_arc"] = True
            elif block_type in ("endfill", "stopfill"):
                result["has_endfill"] = True
        elif isinstance(block_type, list) and len(block_type) == 2:
            try:
                val = float(block_type[1])
                number_values.append(val)
            except (ValueError, TypeError):
                pass

    result["block_count"] = len(data)
    
    # Check for specific numeric values
    result["has_color_0"] = (0 in number_values or 0.0 in number_values)
    result["has_arc_360"] = (360 in number_values or 360.0 in number_values)
    result["has_valid_radius"] = any(50 <= v <= 200 for v in number_values)

except Exception as e:
    result["error"] = str(e)

print(json.dumps(result))
PYEOF

else:
    echo '{"error":"file_not_found"}' > /tmp/japan_flag_analysis.json
fi

cat > /tmp/japan_flag_result.json << EOF
{
    "file_exists": $FILE_EXISTS,
    "file_size": $FILE_SIZE,
    "file_modified": $FILE_MODIFIED,
    "analysis": $(cat /tmp/japan_flag_analysis.json)
}
EOF

chmod 666 /tmp/japan_flag_result.json
echo "Result saved to /tmp/japan_flag_result.json"
cat /tmp/japan_flag_result.json
echo "=== Export complete ==="