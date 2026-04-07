#!/bin/bash
echo "=== Exporting growing_spiral_turtleart task result ==="

SUGAR_ENV="DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus"

# Take final screenshot as evidence
su - ga -c "$SUGAR_ENV scrot /tmp/spiral_task_end.png" 2>/dev/null || true

TA_FILE="/home/ga/Documents/growing_spiral.ta"
TASK_START=$(cat /tmp/growing_spiral_start_ts 2>/dev/null || echo "0")

FILE_EXISTS="false"
FILE_SIZE=0
FILE_MODIFIED="false"

# Check file system metrics
if [ -f "$TA_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat --format=%s "$TA_FILE" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat --format=%Y "$TA_FILE" 2>/dev/null || echo "0")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi
    echo "Found: $TA_FILE ($FILE_SIZE bytes)"
else
    echo "File not found: $TA_FILE"
fi

# Write file system metadata to intermediate JSON
cat > /tmp/spiral_meta.json << EOF
{
    "file_exists": $FILE_EXISTS,
    "file_size": $FILE_SIZE,
    "file_modified": $FILE_MODIFIED
}
EOF

# Parse the TurtleArt JSON securely using Python to extract block structures and logic
python3 << 'PYEOF' > /tmp/growing_spiral_result.json
import json
import os

with open('/tmp/spiral_meta.json') as f:
    result = json.load(f)

# Initialize programmatic logic defaults
result.update({
    "has_start": False,
    "has_repeat": False,
    "has_forward": False,
    "has_turn": False,
    "has_addition": False,
    "count_store_var": 0,
    "count_read_var": 0,
    "has_num_10": False,
    "has_num_20": False,
    "has_num_90": False,
    "has_num_5": False,
    "error": None
})

if result["file_exists"]:
    try:
        with open("/home/ga/Documents/growing_spiral.ta", "r") as f:
            data = json.load(f)
            
        if isinstance(data, list):
            block_names = []
            number_values = []
            
            for item in data:
                # TurtleBlocks structure format: [id, type_or_value, x, y, connections]
                if not isinstance(item, list) or len(item) < 2:
                    continue
                block_type = item[1]
                
                # Command blocks are strings
                if isinstance(block_type, str):
                    if block_type in ["storeinbox1", "storeinbox2", "storein", "setbox"]:
                        block_names.append("store_var")
                    elif block_type in ["box1", "box2", "box", "getbox"]:
                        block_names.append("read_var")
                    elif block_type in ["plus2", "plus"]:
                        block_names.append("addition")
                    elif block_type in ["right", "left"]:
                        block_names.append("turn")
                    else:
                        block_names.append(block_type)
                # Literals are formatted as ["number", value]
                elif isinstance(block_type, list) and len(block_type) == 2:
                    try:
                        number_values.append(float(block_type[1]))
                    except (ValueError, TypeError):
                        pass
                        
            # Detect structural logic components
            result["has_start"] = "start" in block_names
            result["has_repeat"] = "repeat" in block_names
            result["has_forward"] = "forward" in block_names
            result["has_turn"] = "turn" in block_names
            result["has_addition"] = "addition" in block_names
            result["count_store_var"] = block_names.count("store_var")
            result["count_read_var"] = block_names.count("read_var")
            
            # Detect numeric parameters required for the specific spiral
            result["has_num_10"] = 10.0 in number_values
            result["has_num_20"] = 20.0 in number_values
            result["has_num_90"] = 90.0 in number_values or 270.0 in number_values
            result["has_num_5"] = 5.0 in number_values
            
    except Exception as e:
        result["error"] = str(e)

print(json.dumps(result, indent=2))
PYEOF

chmod 666 /tmp/growing_spiral_result.json
echo "Result parsed and saved to /tmp/growing_spiral_result.json"
cat /tmp/growing_spiral_result.json
echo "=== Export complete ==="