#!/bin/bash
echo "=== Exporting Fleet Technical Manual Results ==="

# Paths
MANUAL_FILE="/home/ga/Documents/fleet_technical_manual.txt"
CSV_FILE="/home/ga/Documents/model_index.csv"
SCENARIO_DIR="/opt/bridgecommand/Scenarios/z) Fleet Review"
MODELS_ROOT="/opt/bridgecommand/Models"

# Timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# --- 1. Gather Ground Truth Data (Python script embedded) ---
# We parse the ACTUAL Models directory to create a reference for the verifier
# This ensures verification works regardless of specific installed models
echo "Generating ground truth model data..."

python3 -c "
import os
import configparser
import json
import glob

models_root = '$MODELS_ROOT'
ground_truth = {}

# Helper to read ini loosely (BC ini files can be messy)
def parse_boat_ini(path):
    data = {}
    try:
        with open(path, 'r', encoding='utf-8', errors='ignore') as f:
            for line in f:
                if '=' in line:
                    parts = line.split('=', 1)
                    key = parts[0].strip().lower()
                    val = parts[1].strip().split('//')[0].strip() # remove comments
                    data[key] = val
    except Exception as e:
        pass
    return data

# Iterate all subdirectories
if os.path.exists(models_root):
    for model_dir in os.listdir(models_root):
        full_path = os.path.join(models_root, model_dir)
        if os.path.isdir(full_path):
            ini_path = os.path.join(full_path, 'boat.ini')
            if not os.path.exists(ini_path):
                # Try case-insensitive search
                inis = glob.glob(os.path.join(full_path, '*.[Ii][Nn][Ii]'))
                if inis: ini_path = inis[0]
            
            if os.path.exists(ini_path):
                params = parse_boat_ini(ini_path)
                ground_truth[model_dir] = {
                    'name': params.get('name', model_dir),
                    'max_speed': params.get('maxspeed', '0'),
                    'length': params.get('length', '0'),
                    'beam': params.get('width', params.get('beam', '0')), # BC uses Width
                    'draft': params.get('depth', '0') # BC uses Depth for draft usually
                }

with open('/tmp/ground_truth_models.json', 'w') as f:
    json.dump(ground_truth, f)
"

# --- 2. Check Deliverables ---

# Function to get file stats
get_file_info() {
    local f="$1"
    if [ -f "$f" ]; then
        local sz=$(stat -c %s "$f")
        local mt=$(stat -c %Y "$f")
        local created="false"
        if [ "$mt" -gt "$TASK_START" ]; then created="true"; fi
        echo "{\"exists\": true, \"size\": $sz, \"created_during_task\": $created}"
    else
        echo "{\"exists\": false}"
    fi
}

MANUAL_INFO=$(get_file_info "$MANUAL_FILE")
CSV_INFO=$(get_file_info "$CSV_FILE")

# Read content if exists (limit size)
MANUAL_CONTENT=""
if [ -f "$MANUAL_FILE" ]; then
    MANUAL_CONTENT=$(head -n 100 "$MANUAL_FILE" | python3 -c "import json, sys; print(json.dumps(sys.stdin.read()))")
else
    MANUAL_CONTENT="\"\""
fi

CSV_CONTENT=""
if [ -f "$CSV_FILE" ]; then
    CSV_CONTENT=$(cat "$CSV_FILE" | python3 -c "import json, sys; print(json.dumps(sys.stdin.read()))")
else
    CSV_CONTENT="\"\""
fi

# --- 3. Check Scenario ---
SCENARIO_INFO="{\"exists\": false}"
ENV_DATA="{}"
OWNSHIP_DATA="{}"
OTHERSHIP_DATA="{}"

if [ -d "$SCENARIO_DIR" ]; then
    # Check for the 3 required files
    HAS_ENV=$([ -f "$SCENARIO_DIR/environment.ini" ] && echo "true" || echo "false")
    HAS_OWN=$([ -f "$SCENARIO_DIR/ownship.ini" ] && echo "true" || echo "false")
    HAS_OTHER=$([ -f "$SCENARIO_DIR/othership.ini" ] && echo "true" || echo "false")
    
    SCENARIO_INFO="{\"exists\": true, \"has_env\": $HAS_ENV, \"has_own\": $HAS_OWN, \"has_other\": $HAS_OTHER}"

    # Parse key data using python for safety
    if [ "$HAS_ENV" = "true" ]; then
        ENV_DATA=$(python3 -c "
import sys
try:
    with open('$SCENARIO_DIR/environment.ini') as f:
        print(sys.stdin.read()) # placeholder, actual parsing below
except: print('{}')
" << 'EOF'
import json
data = {}
with open(f'{sys.argv[1]}') as f:
    for line in f:
        if '=' in line:
            k,v = line.split('=',1)
            data[k.strip().lower()] = v.strip().strip('"')
print(json.dumps(data))
EOF
)
        # Re-do simple grep parsing for robustness if python fails or for simplicity
        ENV_START=$(grep -i "StartTime" "$SCENARIO_DIR/environment.ini" | cut -d= -f2 | tr -d ' "')
        ENV_VIS=$(grep -i "VisibilityRange" "$SCENARIO_DIR/environment.ini" | cut -d= -f2 | tr -d ' "')
        ENV_WEA=$(grep -i "Weather" "$SCENARIO_DIR/environment.ini" | cut -d= -f2 | tr -d ' "')
        ENV_DATA="{\"start_time\": \"$ENV_START\", \"visibility\": \"$ENV_VIS\", \"weather\": \"$ENV_WEA\"}"
    fi

    if [ "$HAS_OWN" = "true" ]; then
        OWN_TYPE=$(grep -i "^Type" "$SCENARIO_DIR/ownship.ini" | cut -d= -f2 | tr -d ' "')
        OWNSHIP_DATA="{\"type\": \"$OWN_TYPE\"}"
    fi

    if [ "$HAS_OTHER" = "true" ]; then
        # Count occurrences of Type(...)
        OTHER_COUNT=$(grep -i "^Type(" "$SCENARIO_DIR/othership.ini" | wc -l)
        # Extract types list
        OTHER_TYPES=$(grep -i "^Type(" "$SCENARIO_DIR/othership.ini" | cut -d= -f2 | tr -d ' "' | tr '\n' ',' | sed 's/,$//')
        OTHERSHIP_DATA="{\"count\": $OTHER_COUNT, \"types\": \"$OTHER_TYPES\"}"
    fi
fi

# --- 4. Assemble Final JSON ---
cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "manual": {
        "info": $MANUAL_INFO,
        "content": $MANUAL_CONTENT
    },
    "csv": {
        "info": $CSV_INFO,
        "content": $CSV_CONTENT
    },
    "scenario": {
        "info": $SCENARIO_INFO,
        "environment": $ENV_DATA,
        "ownship": $OWNSHIP_DATA,
        "othership": $OTHERSHIP_DATA
    },
    "ground_truth": $(cat /tmp/ground_truth_models.json)
}
EOF

# Ensure permissions
chmod 666 /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"