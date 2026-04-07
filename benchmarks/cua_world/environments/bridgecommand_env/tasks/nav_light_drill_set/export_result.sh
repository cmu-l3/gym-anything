#!/bin/bash
echo "=== Exporting nav_light_drill_set result ==="

# Define paths
SCENARIO_ROOT="/opt/bridgecommand/Scenarios"
ANSWER_KEY="/home/ga/Documents/light_drill_answer_key.txt"
STUDENT_SHEET="/home/ga/Documents/light_drill_student_sheet.txt"
BC_CONFIG_USER="/home/ga/.config/Bridge Command/bc5.ini"
BC_CONFIG_DATA="/opt/bridgecommand/bc5.ini"

# Define the expected scenario directory names
SCENARIOS=(
    "p) Light Drill 1 - Power Driven"
    "q) Light Drill 2 - Sailing Vessel"
    "r) Light Drill 3 - Vessel Restricted Ability"
    "s) Light Drill 4 - Fishing Vessel"
    "t) Light Drill 5 - Vessel Aground"
)

# Helper function to read INI value
get_ini_val() {
    local file="$1"
    local key="$2"
    if [ -f "$file" ]; then
        # Handle both quoted and unquoted values, case insensitive keys
        grep -i -oP "${key}\s*=\s*\K.*" "$file" | sed 's/"//g' | head -1
    fi
}

# Initialize JSON construction
TEMP_JSON=$(mktemp /tmp/result_partial.XXXXXX.json)
echo '{ "scenarios": {}, "documents": {}, "config": {} }' > "$TEMP_JSON"

# --- 1. INSPECT SCENARIOS ---
echo "Inspecting scenarios..."

for dir_name in "${SCENARIOS[@]}"; do
    full_path="$SCENARIO_ROOT/$dir_name"
    exists=false
    env_valid=false
    own_valid=false
    other_valid=false
    
    start_time=""
    visibility=""
    weather=""
    own_speed=""
    vessel_count=""
    vessel_type=""
    
    if [ -d "$full_path" ]; then
        exists=true
        
        # Check environment.ini
        if [ -f "$full_path/environment.ini" ]; then
            env_valid=true
            start_time=$(get_ini_val "$full_path/environment.ini" "StartTime")
            visibility=$(get_ini_val "$full_path/environment.ini" "VisibilityRange")
            weather=$(get_ini_val "$full_path/environment.ini" "Weather")
        fi
        
        # Check ownship.ini
        if [ -f "$full_path/ownship.ini" ]; then
            own_valid=true
            own_speed=$(get_ini_val "$full_path/ownship.ini" "InitialSpeed")
        fi
        
        # Check othership.ini
        if [ -f "$full_path/othership.ini" ]; then
            other_valid=true
            vessel_count=$(get_ini_val "$full_path/othership.ini" "Number")
            # Get first vessel type (Type(1)=...)
            vessel_type=$(grep -i "Type(1)" "$full_path/othership.ini" | cut -d'=' -f2 | sed 's/"//g' | tr -d '\r')
        fi
    fi
    
    # Update JSON using python for safety
    python3 -c "
import json
import sys

data = json.load(open('$TEMP_JSON'))
scenarios = data['scenarios']
scenarios['$dir_name'] = {
    'exists': $exists,
    'files': {
        'environment': $env_valid,
        'ownship': $own_valid,
        'othership': $other_valid
    },
    'data': {
        'start_time': '$start_time',
        'visibility': '$visibility',
        'weather': '$weather',
        'own_speed': '$own_speed',
        'vessel_count': '$vessel_count',
        'vessel_type': '''$vessel_type'''
    }
}
with open('$TEMP_JSON', 'w') as f:
    json.dump(data, f)
"
done

# --- 2. INSPECT DOCUMENTS ---
echo "Inspecting documents..."
ANSWER_KEY_CONTENT=""
STUDENT_SHEET_CONTENT=""
ANSWER_KEY_EXISTS="false"
STUDENT_SHEET_EXISTS="false"

if [ -f "$ANSWER_KEY" ]; then
    ANSWER_KEY_EXISTS="true"
    ANSWER_KEY_CONTENT=$(cat "$ANSWER_KEY" | head -n 100)
fi

if [ -f "$STUDENT_SHEET" ]; then
    STUDENT_SHEET_EXISTS="true"
    STUDENT_SHEET_CONTENT=$(cat "$STUDENT_SHEET" | head -n 100)
fi

# Update JSON
python3 -c "
import json
data = json.load(open('$TEMP_JSON'))
data['documents'] = {
    'answer_key': {
        'exists': $ANSWER_KEY_EXISTS,
        'content': '''$ANSWER_KEY_CONTENT'''
    },
    'student_sheet': {
        'exists': $STUDENT_SHEET_EXISTS,
        'content': '''$STUDENT_SHEET_CONTENT'''
    }
}
with open('$TEMP_JSON', 'w') as f:
    json.dump(data, f)
"

# --- 3. INSPECT CONFIG ---
echo "Inspecting configuration..."
HIDE_INST=""
FULL_RADAR=""

# Check both user config and data config
for cfg in "$BC_CONFIG_USER" "$BC_CONFIG_DATA"; do
    if [ -f "$cfg" ]; then
        h=$(get_ini_val "$cfg" "hide_instruments")
        if [ -n "$h" ]; then HIDE_INST="$h"; fi
        
        f=$(get_ini_val "$cfg" "full_radar")
        if [ -n "$f" ]; then FULL_RADAR="$f"; fi
    fi
done

# Update JSON
python3 -c "
import json
data = json.load(open('$TEMP_JSON'))
data['config'] = {
    'hide_instruments': '$HIDE_INST',
    'full_radar': '$FULL_RADAR'
}
with open('$TEMP_JSON', 'w') as f:
    json.dump(data, f)
"

# --- 4. FINALIZE ---
# Move to final location
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm "$TEMP_JSON"

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"