#!/bin/bash
echo "=== Exporting IALA Region B Channel Result ==="

# Paths
SCENARIO_DIR="/opt/bridgecommand/Scenarios/w) Miami IALA B Approach"
ENV_INI="$SCENARIO_DIR/environment.ini"
OWN_INI="$SCENARIO_DIR/ownship.ini"
OTHER_INI="$SCENARIO_DIR/othership.ini"
DOC_FILE="/home/ga/Documents/channel_configuration_plan.txt"

# Timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Capture final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Check existence
SCENARIO_EXISTS="false"
[ -d "$SCENARIO_DIR" ] && SCENARIO_EXISTS="true"

FILES_EXIST="false"
[ -f "$ENV_INI" ] && [ -f "$OWN_INI" ] && [ -f "$OTHER_INI" ] && FILES_EXIST="true"

DOC_EXISTS="false"
[ -f "$DOC_FILE" ] && DOC_EXISTS="true"

# Extract Ownship Data
OWN_LAT="0"
OWN_LONG="0"
OWN_HEADING="0"

if [ -f "$OWN_INI" ]; then
    OWN_LAT=$(grep -i "InitialLat" "$OWN_INI" | cut -d'=' -f2 | tr -d '[:space:]')
    OWN_LONG=$(grep -i "InitialLong" "$OWN_INI" | cut -d'=' -f2 | tr -d '[:space:]')
    OWN_HEADING=$(grep -i "InitialBearing" "$OWN_INI" | cut -d'=' -f2 | tr -d '[:space:]')
fi

# Extract Othership Data (Buoys)
# Python script to parse the indexed INI format of Bridge Command
# Format: Type(1)=X, InitLat(1)=Y, InitLong(1)=Z
BUOY_JSON=$(python3 -c "
import sys, re, json

try:
    with open('$OTHER_INI', 'r') as f:
        content = f.read()

    buoys = {}
    
    # Extract total number
    num_match = re.search(r'Number=(\d+)', content, re.IGNORECASE)
    total_count = int(num_match.group(1)) if num_match else 0

    # Extract items
    # Regex to find indexed keys like Type(1)=...
    type_matches = re.findall(r'Type\((\d+)\)=[\"\'\s]*([^\"\n\r]+)', content, re.IGNORECASE)
    lat_matches = re.findall(r'InitLat\((\d+)\)=([\d\.-]+)', content, re.IGNORECASE)
    long_matches = re.findall(r'InitLong\((\d+)\)=([\d\.-]+)', content, re.IGNORECASE)

    for idx, val in type_matches:
        if idx not in buoys: buoys[idx] = {}
        buoys[idx]['type'] = val.strip()
    
    for idx, val in lat_matches:
        if idx not in buoys: buoys[idx] = {}
        buoys[idx]['lat'] = float(val)

    for idx, val in long_matches:
        if idx not in buoys: buoys[idx] = {}
        buoys[idx]['long'] = float(val)

    result = {
        'count': total_count,
        'items': list(buoys.values())
    }
    print(json.dumps(result))

except Exception as e:
    print(json.dumps({'count': 0, 'items': [], 'error': str(e)}))
" 2>/dev/null || echo "{\"count\": 0, \"items\": []}")

# Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "scenario_exists": $SCENARIO_EXISTS,
    "files_exist": $FILES_EXIST,
    "doc_exists": $DOC_EXISTS,
    "ownship": {
        "lat": "$OWN_LAT",
        "long": "$OWN_LONG",
        "heading": "$OWN_HEADING"
    },
    "buoys": $BUOY_JSON,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 644 /tmp/task_result.json

echo "Export complete. Result:"
cat /tmp/task_result.json