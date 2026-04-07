#!/bin/bash
# Do NOT use set -e
echo "=== Exporting turtleart_seattle_rainfall task result ==="

SUGAR_ENV="DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus"

# Take final screenshot for visual verification later
su - ga -c "$SUGAR_ENV scrot /tmp/rainfall_task_end.png" 2>/dev/null || true

TA_FILE="/home/ga/Documents/seattle_rainfall.ta"
TASK_START=$(cat /tmp/seattle_rainfall_start_ts 2>/dev/null || echo "0")

FILE_EXISTS="false"
FILE_SIZE=0
FILE_MODIFIED="false"

if [ -f "$TA_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat --format=%s "$TA_FILE" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat --format=%Y "$TA_FILE" 2>/dev/null || echo "0")
    
    # Check if the file was modified/created after task start time
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi

    # Parse TurtleArt JSON structure using Python
    python3 << 'PYEOF' > /tmp/rainfall_analysis.json 2>/dev/null || echo '{"error":"parse_failed"}' > /tmp/rainfall_analysis.json
import json
import sys

result = {
    "is_valid_json": False,
    "has_start": False,
    "has_forward": False,
    "has_turn": False,
    "has_142": False,
    "has_89": False,
    "has_95": False,
    "has_70": False,
    "has_48": False,
    "has_50": False,
    "has_spacing": False,
    "block_count": 0,
    "error": None
}

try:
    with open("/home/ga/Documents/seattle_rainfall.ta", "r") as f:
        data = json.load(f)
    
    if isinstance(data, list):
        result["is_valid_json"] = True
        result["block_count"] = len(data)
        
        block_names = []
        number_values = []
        
        # Traverse AST and extract literal values and commands
        for item in data:
            if not isinstance(item, list) or len(item) < 2:
                continue
            block_type = item[1]
            
            if isinstance(block_type, str):
                block_names.append(block_type)
            elif isinstance(block_type, list) and len(block_type) == 2:
                try:
                    number_values.append(float(block_type[1]))
                except (ValueError, TypeError):
                    pass
        
        result["has_start"] = "start" in block_names
        result["has_forward"] = "forward" in block_names or "sety" in block_names
        result["has_turn"] = "right" in block_names or "left" in block_names or "setheading" in block_names or "setx" in block_names
        
        # Check specific task data values
        result["has_142"] = 142 in number_values or 142.0 in number_values
        result["has_89"] = 89 in number_values or 89.0 in number_values
        result["has_95"] = 95 in number_values or 95.0 in number_values
        result["has_70"] = 70 in number_values or 70.0 in number_values
        result["has_48"] = 48 in number_values or 48.0 in number_values
        
        # Check constants
        result["has_50"] = 50 in number_values or 50.0 in number_values
        result["has_spacing"] = 20 in number_values or 20.0 in number_values or 70 in number_values or 70.0 in number_values

except Exception as e:
    result["error"] = str(e)

print(json.dumps(result))
PYEOF
else:
    echo '{"error":"file_not_found"}' > /tmp/rainfall_analysis.json
fi

# Create final task result JSON object mapping logic outputs
cat > /tmp/seattle_rainfall_result.json << EOF
{
    "file_exists": $FILE_EXISTS,
    "file_size": $FILE_SIZE,
    "file_modified": $FILE_MODIFIED,
    "analysis": $(cat /tmp/rainfall_analysis.json)
}
EOF

chmod 666 /tmp/seattle_rainfall_result.json
echo "Result saved to /tmp/seattle_rainfall_result.json"
cat /tmp/seattle_rainfall_result.json
echo "=== Export complete ==="