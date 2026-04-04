#!/bin/bash
echo "=== Exporting nighttime_colregs_assessment Result ==="

BC_DATA="/opt/bridgecommand"
SCENARIO_DIR="$BC_DATA/Scenarios/n) Solent COLREGS Night Assessment"
BC_CONFIG="/home/ga/.config/Bridge Command/bc5.ini"
BC_DATA_CONFIG="$BC_DATA/bc5.ini"
BRIEFING_FILE="/home/ga/Documents/colregs_assessment_briefing.txt"

# Take final screenshot
su - ga -c "DISPLAY=:1 scrot /tmp/task_final.png" 2>/dev/null || true

# Check scenario directory existence
SCENARIO_EXISTS="false"
ENV_INI_EXISTS="false"
OWNSHIP_INI_EXISTS="false"
OTHERSHIP_INI_EXISTS="false"

if [ -d "$SCENARIO_DIR" ]; then
    SCENARIO_EXISTS="true"
    [ -f "$SCENARIO_DIR/environment.ini" ] && ENV_INI_EXISTS="true"
    [ -f "$SCENARIO_DIR/ownship.ini" ] && OWNSHIP_INI_EXISTS="true"
    [ -f "$SCENARIO_DIR/othership.ini" ] && OTHERSHIP_INI_EXISTS="true"
fi

# Parse environment.ini
ENV_SETTING=""
ENV_START_TIME=""
ENV_VISIBILITY=""
ENV_WEATHER=""
if [ "$ENV_INI_EXISTS" = "true" ]; then
    ENV_SETTING=$(grep -oP 'Setting="\K[^"]+' "$SCENARIO_DIR/environment.ini" 2>/dev/null || grep -oP 'Setting=\K.*' "$SCENARIO_DIR/environment.ini" 2>/dev/null || echo "")
    ENV_START_TIME=$(grep -oP 'StartTime=\K[0-9.]+' "$SCENARIO_DIR/environment.ini" 2>/dev/null || echo "")
    ENV_VISIBILITY=$(grep -oP 'VisibilityRange=\K[0-9.]+' "$SCENARIO_DIR/environment.ini" 2>/dev/null || echo "")
    ENV_WEATHER=$(grep -oP 'Weather=\K[0-9.]+' "$SCENARIO_DIR/environment.ini" 2>/dev/null || echo "")
fi

# Parse ownship.ini
OWN_SHIP_NAME=""
OWN_LAT=""
OWN_LONG=""
OWN_SPEED=""
OWN_BEARING=""
if [ "$OWNSHIP_INI_EXISTS" = "true" ]; then
    OWN_SHIP_NAME=$(grep -oP 'ShipName="\K[^"]+' "$SCENARIO_DIR/ownship.ini" 2>/dev/null || grep -oP 'ShipName=\K.*' "$SCENARIO_DIR/ownship.ini" 2>/dev/null || echo "")
    OWN_LAT=$(grep -oP 'InitialLat=\K[0-9.-]+' "$SCENARIO_DIR/ownship.ini" 2>/dev/null || echo "")
    OWN_LONG=$(grep -oP 'InitialLong=\K[0-9.-]+' "$SCENARIO_DIR/ownship.ini" 2>/dev/null || echo "")
    OWN_SPEED=$(grep -oP 'InitialSpeed=\K[0-9.]+' "$SCENARIO_DIR/ownship.ini" 2>/dev/null || echo "")
    OWN_BEARING=$(grep -oP 'InitialBearing=\K[0-9.]+' "$SCENARIO_DIR/ownship.ini" 2>/dev/null || echo "")
fi

# Parse othership.ini — count vessels and extract types
VESSEL_COUNT=0
VESSEL_TYPES=""
VESSEL_DETAILS=""
if [ "$OTHERSHIP_INI_EXISTS" = "true" ]; then
    VESSEL_COUNT=$(grep -oP 'Number=\K[0-9]+' "$SCENARIO_DIR/othership.ini" 2>/dev/null || echo "0")
    # Extract all vessel types
    VESSEL_TYPES=$(grep -oP 'Type\([0-9]+\)="\K[^"]+' "$SCENARIO_DIR/othership.ini" 2>/dev/null | tr '\n' ',' | sed 's/,$//')
    # Get full othership content for detailed analysis
    VESSEL_DETAILS=$(cat "$SCENARIO_DIR/othership.ini" 2>/dev/null | python3 -c "
import sys, json
content = sys.stdin.read()
# Count legs per vessel
lines = content.strip().split('\n')
vessels = {}
for line in lines:
    line = line.strip()
    if line.startswith('Type('):
        idx = line.split('(')[1].split(')')[0]
        val = line.split('=')[1].strip().strip('\"')
        vessels.setdefault(idx, {})['type'] = val
    elif line.startswith('InitLat('):
        idx = line.split('(')[1].split(')')[0]
        vessels.setdefault(idx, {})['lat'] = line.split('=')[1].strip()
    elif line.startswith('InitLong('):
        idx = line.split('(')[1].split(')')[0]
        vessels.setdefault(idx, {})['long'] = line.split('=')[1].strip()
    elif line.startswith('Legs('):
        idx = line.split('(')[1].split(')')[0]
        vessels.setdefault(idx, {})['legs'] = line.split('=')[1].strip()
    elif line.startswith('Bearing('):
        parts = line.split('(')[1].split(')')[0].split(',')
        idx = parts[0]
        leg = parts[1]
        vessels.setdefault(idx, {}).setdefault('bearings', []).append(line.split('=')[1].strip())
    elif line.startswith('Speed('):
        parts = line.split('(')[1].split(')')[0].split(',')
        idx = parts[0]
        vessels.setdefault(idx, {}).setdefault('speeds', []).append(line.split('=')[1].strip())
print(json.dumps(vessels))
" 2>/dev/null || echo "{}")
fi

# Check radar config from all possible locations
ARPA_ON=""
FULL_RADAR=""
RADAR_RES=""
MAX_RANGE=""

# Check user config first, then data dir config
for cfg in "$BC_CONFIG" "$BC_DATA_CONFIG" "/home/ga/.Bridge Command/5.10/bc5.ini"; do
    if [ -f "$cfg" ]; then
        val=$(grep -oP 'arpa_on=\K[0-9]+' "$cfg" 2>/dev/null)
        [ -n "$val" ] && ARPA_ON="$val"
        val=$(grep -oP 'full_radar=\K[0-9]+' "$cfg" 2>/dev/null)
        [ -n "$val" ] && FULL_RADAR="$val"
        val=$(grep -oP 'radar_range_resolution=\K[0-9]+' "$cfg" 2>/dev/null)
        [ -n "$val" ] && RADAR_RES="$val"
        val=$(grep -oP 'max_radar_range=\K[0-9]+' "$cfg" 2>/dev/null)
        [ -n "$val" ] && MAX_RANGE="$val"
    fi
done

# Also check if settings were saved in quoted format (BC ini editor uses quotes)
for cfg in "/home/ga/.Bridge Command/5.10/bc5.ini"; do
    if [ -f "$cfg" ]; then
        val=$(grep -oP 'arpa_on="\K[^"]+' "$cfg" 2>/dev/null)
        [ -n "$val" ] && ARPA_ON="$val"
        val=$(grep -oP 'full_radar="\K[^"]+' "$cfg" 2>/dev/null)
        [ -n "$val" ] && FULL_RADAR="$val"
        val=$(grep -oP 'radar_range_resolution="\K[^"]+' "$cfg" 2>/dev/null)
        [ -n "$val" ] && RADAR_RES="$val"
        val=$(grep -oP 'max_radar_range="\K[^"]+' "$cfg" 2>/dev/null)
        [ -n "$val" ] && MAX_RANGE="$val"
    fi
done

# Check briefing file
BRIEFING_EXISTS="false"
BRIEFING_CONTENT=""
if [ -f "$BRIEFING_FILE" ]; then
    BRIEFING_EXISTS="true"
    BRIEFING_CONTENT=$(cat "$BRIEFING_FILE" 2>/dev/null | head -200)
fi

# Get baseline
INITIAL_SCENARIO_COUNT=$(cat /tmp/initial_scenario_count 2>/dev/null || echo "0")
CURRENT_SCENARIO_COUNT=$(ls -d "$BC_DATA/Scenarios/"*/ 2>/dev/null | wc -l)

# Build result JSON
python3 -c "
import json
result = {
    'task': 'nighttime_colregs_assessment',
    'scenario_exists': $( [ \"$SCENARIO_EXISTS\" = \"true\" ] && echo 'True' || echo 'False' ),
    'env_ini_exists': $( [ \"$ENV_INI_EXISTS\" = \"true\" ] && echo 'True' || echo 'False' ),
    'ownship_ini_exists': $( [ \"$OWNSHIP_INI_EXISTS\" = \"true\" ] && echo 'True' || echo 'False' ),
    'othership_ini_exists': $( [ \"$OTHERSHIP_INI_EXISTS\" = \"true\" ] && echo 'True' || echo 'False' ),
    'environment': {
        'setting': '''${ENV_SETTING}''',
        'start_time': '''${ENV_START_TIME}''',
        'visibility_range': '''${ENV_VISIBILITY}''',
        'weather': '''${ENV_WEATHER}'''
    },
    'ownship': {
        'name': '''${OWN_SHIP_NAME}''',
        'lat': '''${OWN_LAT}''',
        'long': '''${OWN_LONG}''',
        'speed': '''${OWN_SPEED}''',
        'bearing': '''${OWN_BEARING}'''
    },
    'othership': {
        'vessel_count': int('${VESSEL_COUNT}' or '0'),
        'vessel_types': '''${VESSEL_TYPES}''',
        'vessel_details': json.loads('''${VESSEL_DETAILS}''' or '{}')
    },
    'radar_config': {
        'arpa_on': '''${ARPA_ON}''',
        'full_radar': '''${FULL_RADAR}''',
        'radar_range_resolution': '''${RADAR_RES}''',
        'max_radar_range': '''${MAX_RANGE}'''
    },
    'briefing': {
        'exists': $( [ \"$BRIEFING_EXISTS\" = \"true\" ] && echo 'True' || echo 'False' ),
        'content': '''$(echo "$BRIEFING_CONTENT" | sed "s/'/\\\\'/g")'''
    },
    'baseline': {
        'initial_scenario_count': int('${INITIAL_SCENARIO_COUNT}' or '0'),
        'current_scenario_count': $CURRENT_SCENARIO_COUNT
    }
}
with open('/tmp/nighttime_colregs_assessment_result.json', 'w') as f:
    json.dump(result, f, indent=2)
print(json.dumps(result, indent=2))
"

echo "=== Export Complete ==="
