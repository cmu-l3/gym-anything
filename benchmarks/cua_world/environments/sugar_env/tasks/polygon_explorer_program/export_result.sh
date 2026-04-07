#!/bin/bash
# Do NOT use set -e: grep -c returns exit 1 on 0 matches, causing premature exit
echo "=== Exporting polygon_explorer_program task result ==="

SUGAR_ENV="DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus"

# Take final screenshot
su - ga -c "$SUGAR_ENV scrot /tmp/polygon_task_end.png" 2>/dev/null || true

TA_FILE="/home/ga/Documents/polygon_explorer.ta"
FILE_EXISTS="false"
FILE_SIZE=0
FILE_MTIME=0
TASK_START=$(cat /tmp/polygon_explorer_start_ts 2>/dev/null || echo "0")
FILE_MODIFIED="false"

HAS_START="false"
HAS_REPEAT="false"
HAS_REPEAT_4="false"
HAS_REPEAT_3="false"
HAS_FORWARD="false"
HAS_FORWARD_100="false"
HAS_RIGHT_90="false"
HAS_RIGHT_120="false"
BLOCK_COUNT=0

if [ -f "$TA_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat --format=%s "$TA_FILE" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat --format=%Y "$TA_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi
    echo "Found: $TA_FILE ($FILE_SIZE bytes, mtime=$FILE_MTIME, start=$TASK_START)"

    # Parse the TurtleArt JSON to check block structure
    python3 << 'PYEOF' > /tmp/polygon_analysis.json 2>/dev/null || echo '{"error":"parse_failed"}' > /tmp/polygon_analysis.json
import json
import sys

result = {
    "has_start": False,
    "has_repeat": False,
    "has_repeat_4": False,
    "has_repeat_3": False,
    "has_forward": False,
    "has_forward_100": False,
    "has_right_90": False,
    "has_right_120": False,
    "block_count": 0,
    "block_names": [],
    "number_values": []
}

try:
    with open("/home/ga/Documents/polygon_explorer.ta", "r") as f:
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
            elif block_type == "repeat":
                result["has_repeat"] = True
            elif block_type == "forward":
                result["has_forward"] = True
            elif block_type in ("right", "setheading"):
                pass  # counted below via number context
        elif isinstance(block_type, list) and len(block_type) == 2:
            try:
                val = float(block_type[1])
                number_values.append(val)
            except (ValueError, TypeError):
                pass

    result["block_count"] = len(data)
    result["block_names"] = list(set(block_names))
    result["number_values"] = number_values

    # Check for specific values
    result["has_repeat_4"] = 4 in number_values or 4.0 in number_values
    result["has_repeat_3"] = 3 in number_values or 3.0 in number_values
    result["has_forward_100"] = 100 in number_values or 100.0 in number_values
    result["has_right_90"] = 90 in number_values or 90.0 in number_values
    result["has_right_120"] = 120 in number_values or 120.0 in number_values

    # Check block names for forward and right
    result["has_forward"] = "forward" in block_names
    result["has_repeat"] = "repeat" in block_names
    # right can be "right" or "left" (both turn)
    result["has_right"] = "right" in block_names or "left" in block_names

except Exception as e:
    result["error"] = str(e)

print(json.dumps(result))
PYEOF

    if [ -f /tmp/polygon_analysis.json ]; then
        HAS_START=$(python3 -c "import json; d=json.load(open('/tmp/polygon_analysis.json')); print(str(d.get('has_start',False)).lower())" 2>/dev/null || echo "false")
        HAS_REPEAT=$(python3 -c "import json; d=json.load(open('/tmp/polygon_analysis.json')); print(str(d.get('has_repeat',False)).lower())" 2>/dev/null || echo "false")
        HAS_REPEAT_4=$(python3 -c "import json; d=json.load(open('/tmp/polygon_analysis.json')); print(str(d.get('has_repeat_4',False)).lower())" 2>/dev/null || echo "false")
        HAS_REPEAT_3=$(python3 -c "import json; d=json.load(open('/tmp/polygon_analysis.json')); print(str(d.get('has_repeat_3',False)).lower())" 2>/dev/null || echo "false")
        HAS_FORWARD=$(python3 -c "import json; d=json.load(open('/tmp/polygon_analysis.json')); print(str(d.get('has_forward',False)).lower())" 2>/dev/null || echo "false")
        HAS_FORWARD_100=$(python3 -c "import json; d=json.load(open('/tmp/polygon_analysis.json')); print(str(d.get('has_forward_100',False)).lower())" 2>/dev/null || echo "false")
        HAS_RIGHT_90=$(python3 -c "import json; d=json.load(open('/tmp/polygon_analysis.json')); print(str(d.get('has_right_90',False)).lower())" 2>/dev/null || echo "false")
        HAS_RIGHT_120=$(python3 -c "import json; d=json.load(open('/tmp/polygon_analysis.json')); print(str(d.get('has_right_120',False)).lower())" 2>/dev/null || echo "false")
        BLOCK_COUNT=$(python3 -c "import json; d=json.load(open('/tmp/polygon_analysis.json')); print(d.get('block_count',0))" 2>/dev/null || echo "0")
    fi
else
    echo "ERROR: File not found: $TA_FILE"
fi

cat > /tmp/polygon_explorer_program_result.json << EOF
{
    "file_exists": $FILE_EXISTS,
    "file_size": $FILE_SIZE,
    "file_modified": $FILE_MODIFIED,
    "has_start": $HAS_START,
    "has_repeat": $HAS_REPEAT,
    "has_repeat_4": $HAS_REPEAT_4,
    "has_repeat_3": $HAS_REPEAT_3,
    "has_forward": $HAS_FORWARD,
    "has_forward_100": $HAS_FORWARD_100,
    "has_right_90": $HAS_RIGHT_90,
    "has_right_120": $HAS_RIGHT_120,
    "block_count": $BLOCK_COUNT
}
EOF

chmod 666 /tmp/polygon_explorer_program_result.json
echo "Result saved to /tmp/polygon_explorer_program_result.json"
cat /tmp/polygon_explorer_program_result.json
echo "=== Export complete ==="
