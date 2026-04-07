#!/bin/bash
echo "=== Exporting tiny_house_floor_plan results ==="

source /workspace/scripts/task_utils.sh

TASK_NAME="tiny_house_floor_plan"
TARGET_FILE="/home/ga/Documents/SweetHome3D/tiny_house_plan.sh3d"
RESULT_JSON="/tmp/${TASK_NAME}_result.json"
START_TS_FILE="/tmp/${TASK_NAME}_start_ts"
EXTRACT_DIR="/tmp/sh3d_extract_${TASK_NAME}"

# 1. Take final screenshot
DISPLAY=:1 import -window root /tmp/${TASK_NAME}_end_screenshot.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/${TASK_NAME}_end_screenshot.png 2>/dev/null || true
echo "Final screenshot captured"

# 2. Kill application to ensure file locks are released
kill_sweet_home_3d
sleep 3

# 3. Locate the saved file
TASK_START=$(cat "$START_TS_FILE" 2>/dev/null || echo "0")
FOUND_FILE=""

if [ -f "$TARGET_FILE" ]; then
    FOUND_FILE="$TARGET_FILE"
    echo "Found target file exactly at: $FOUND_FILE"
else
    # Fallback: search for any newly created .sh3d file since task start
    for CANDIDATE in /home/ga/Documents/SweetHome3D/*.sh3d /home/ga/Desktop/*.sh3d /home/ga/*.sh3d; do
        [ -f "$CANDIDATE" ] || continue
        FMTIME=$(stat -c %Y "$CANDIDATE" 2>/dev/null || echo "0")
        if [ "$FMTIME" -gt "$TASK_START" ]; then
            echo "Found newer .sh3d: $CANDIDATE (mtime=$FMTIME vs task_start=$TASK_START)"
            FOUND_FILE="$CANDIDATE"
            break
        fi
    done
fi

if [ -z "$FOUND_FILE" ]; then
    echo "No valid output file found."
    cat > "$RESULT_JSON" << EOF
{
  "file_exists": false,
  "file_size": 0,
  "file_mtime": 0,
  "task_start_time": $TASK_START
}
EOF
    echo "Export complete (file missing)."
    exit 0
fi

# 4. Extract and parse the .sh3d (ZIP) file using Python
FILE_SIZE=$(stat -c%s "$FOUND_FILE" 2>/dev/null || echo "0")
FILE_MTIME=$(stat -c%Y "$FOUND_FILE" 2>/dev/null || echo "0")

rm -rf "$EXTRACT_DIR"
mkdir -p "$EXTRACT_DIR"
unzip -q -o "$FOUND_FILE" "Home.xml" -d "$EXTRACT_DIR" 2>/dev/null || \
unzip -q -o "$FOUND_FILE" "*.xml" -d "$EXTRACT_DIR" 2>/dev/null || true

HOME_XML=$(find "$EXTRACT_DIR" -name "Home.xml" -o -name "home.xml" | head -1)

if [ -z "$HOME_XML" ] || [ ! -f "$HOME_XML" ]; then
    echo "Could not extract Home.xml from $FOUND_FILE"
    cat > "$RESULT_JSON" << EOF
{
  "file_exists": true,
  "file_size": $FILE_SIZE,
  "file_mtime": $FILE_MTIME,
  "task_start_time": $TASK_START,
  "error": "No Home.xml found in archive"
}
EOF
    exit 0
fi

echo "Parsing Home.xml at $HOME_XML ..."

python3 << PYEOF > "$RESULT_JSON"
import xml.etree.ElementTree as ET
import json, re, sys, math

result = {
    "file_exists": True,
    "file_size": int("$FILE_SIZE"),
    "file_mtime": int("$FILE_MTIME"),
    "task_start_time": int("$TASK_START"),
    "wall_count": 0,
    "room_count": 0,
    "room_names": [],
    "total_furniture": 0,
    "door_window_count": 0,
    "doors": 0,
    "windows": 0,
    "dimension_count": 0,
    "valid_dimension_count": 0,
    "sofas": 0,
    "chairs": 0,
    "tables": 0,
    "beds": 0,
    "shelves_wardrobes": 0,
    "appliances": 0,
    "toilets": 0,
    "sinks": 0,
    "lamps": 0
}

# Keywords for categorization
kw = {
    "sofas": r"sofa|couch|loveseat|settee|futon",
    "chairs": r"chair|stool|seat|armchair|bench",
    "tables": r"table|desk|counter|coffee",
    "beds": r"\bbed\b|mattress|bunk|cot",
    "shelves_wardrobes": r"shelf|wardrobe|closet|cabinet|bookcase|cupboard|dresser|nightstand|storage|rack|drawer|chest|armoire",
    "appliances": r"stove|oven|refrigerator|fridge|microwave|dishwasher|washer|dryer|range|cooktop|freezer",
    "toilets": r"toilet|wc|lavatory|bidet",
    "sinks": r"sink|basin|washbasin|lavabo",
    "lamps": r"lamp|light|sconce|chandelier|ceiling\s*light|pendant"
}

try:
    tree = ET.parse("$HOME_XML")
    root = tree.getroot()
    
    for elem in root.iter():
        tag = elem.tag.split("}")[-1] if "}" in elem.tag else elem.tag
        
        if tag == "wall":
            result["wall_count"] += 1
            
        elif tag == "room":
            result["room_count"] += 1
            rname = elem.get("name", "").strip()
            if rname:
                result["room_names"].append(rname)
                
        elif tag == "dimensionLine":
            result["dimension_count"] += 1
            try:
                xs = float(elem.get('xStart', 0))
                ys = float(elem.get('yStart', 0))
                xe = float(elem.get('xEnd', 0))
                ye = float(elem.get('yEnd', 0))
                length = math.sqrt((xe-xs)**2 + (ye-ys)**2)
                if length > 10:  # > 10cm is considered a valid dimension
                    result["valid_dimension_count"] += 1
            except:
                pass
                
        elif tag in ("pieceOfFurniture", "doorOrWindow", "homeFurnitureGroup"):
            is_dw = elem.get("doorOrWindow", "false").lower() == "true" or tag == "doorOrWindow"
            name = (elem.get("name", "") or "").lower()
            cat_id = (elem.get("catalogId", "") or "").lower()
            combined = f"{name} {cat_id}"
            
            if is_dw:
                result["door_window_count"] += 1
                if re.search(r"door|entry|gate|french", combined):
                    result["doors"] += 1
                elif re.search(r"window|casement|skylight|pane|glazing", combined):
                    result["windows"] += 1
                else:
                    if "door" in combined:
                        result["doors"] += 1
                    else:
                        result["windows"] += 1
                continue
                
            result["total_furniture"] += 1
            for cat, pattern in kw.items():
                if re.search(pattern, combined, re.IGNORECASE):
                    result[cat] += 1
                    break

except Exception as e:
    result["error"] = str(e)

print(json.dumps(result, indent=2))
PYEOF

rm -rf "$EXTRACT_DIR"

echo "JSON output saved to $RESULT_JSON"
cat "$RESULT_JSON"
echo "=== tiny_house_floor_plan export complete ==="