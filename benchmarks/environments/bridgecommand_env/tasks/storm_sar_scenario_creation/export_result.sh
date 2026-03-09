#!/bin/bash
echo "=== Exporting storm_sar_scenario_creation Result ==="

BC_DATA="/opt/bridgecommand"
SCENARIO_DIR="$BC_DATA/Scenarios/p) Lizard SAR Exercise Storm"
BC_CONFIG="/home/ga/.config/Bridge Command/bc5.ini"
BRIEFING_FILE="/home/ga/Documents/sar_briefing.txt"

su - ga -c "DISPLAY=:1 scrot /tmp/task_final.png" 2>/dev/null || true

# Check scenario structure
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
ENV_WEATHER=""
ENV_RAIN=""
ENV_VISIBILITY=""
ENV_VARIATION=""
ENV_MONTH=""
ENV_YEAR=""
if [ "$ENV_INI_EXISTS" = "true" ]; then
    ENV_SETTING=$(grep -oP 'Setting="\K[^"]+' "$SCENARIO_DIR/environment.ini" 2>/dev/null || grep -oP 'Setting=\K.*' "$SCENARIO_DIR/environment.ini" 2>/dev/null || echo "")
    ENV_START_TIME=$(grep -oP 'StartTime=\K[0-9.]+' "$SCENARIO_DIR/environment.ini" 2>/dev/null || echo "")
    ENV_WEATHER=$(grep -oP 'Weather=\K[0-9.]+' "$SCENARIO_DIR/environment.ini" 2>/dev/null || echo "")
    ENV_RAIN=$(grep -oP 'Rain=\K[0-9.]+' "$SCENARIO_DIR/environment.ini" 2>/dev/null || echo "")
    ENV_VISIBILITY=$(grep -oP 'VisibilityRange=\K[0-9.]+' "$SCENARIO_DIR/environment.ini" 2>/dev/null || echo "")
    ENV_VARIATION=$(grep -oP 'Variation=\K[0-9.-]+' "$SCENARIO_DIR/environment.ini" 2>/dev/null || echo "")
    ENV_MONTH=$(grep -oP 'StartMonth=\K[0-9]+' "$SCENARIO_DIR/environment.ini" 2>/dev/null || echo "")
    ENV_YEAR=$(grep -oP 'StartYear=\K[0-9]+' "$SCENARIO_DIR/environment.ini" 2>/dev/null || echo "")
fi

# Parse ownship.ini
OWN_NAME=""
OWN_LAT=""
OWN_LONG=""
OWN_SPEED=""
OWN_BEARING=""
OWN_GPS=""
OWN_DEPTH=""
if [ "$OWNSHIP_INI_EXISTS" = "true" ]; then
    OWN_NAME=$(grep -oP 'ShipName="\K[^"]+' "$SCENARIO_DIR/ownship.ini" 2>/dev/null || grep -oP 'ShipName=\K.*' "$SCENARIO_DIR/ownship.ini" 2>/dev/null || echo "")
    OWN_LAT=$(grep -oP 'InitialLat=\K[0-9.-]+' "$SCENARIO_DIR/ownship.ini" 2>/dev/null || echo "")
    OWN_LONG=$(grep -oP 'InitialLong=\K[0-9.-]+' "$SCENARIO_DIR/ownship.ini" 2>/dev/null || echo "")
    OWN_SPEED=$(grep -oP 'InitialSpeed=\K[0-9.]+' "$SCENARIO_DIR/ownship.ini" 2>/dev/null || echo "")
    OWN_BEARING=$(grep -oP 'InitialBearing=\K[0-9.]+' "$SCENARIO_DIR/ownship.ini" 2>/dev/null || echo "")
    OWN_GPS=$(grep -oP 'HasGPS=\K[0-9]+' "$SCENARIO_DIR/ownship.ini" 2>/dev/null || echo "")
    OWN_DEPTH=$(grep -oP 'HasDepthSounder=\K[0-9]+' "$SCENARIO_DIR/ownship.ini" 2>/dev/null || echo "")
fi

# Parse othership.ini
VESSEL_COUNT=0
VESSEL_TYPES=""
if [ "$OTHERSHIP_INI_EXISTS" = "true" ]; then
    VESSEL_COUNT=$(grep -oP 'Number=\K[0-9]+' "$SCENARIO_DIR/othership.ini" 2>/dev/null || echo "0")
    VESSEL_TYPES=$(grep -oP 'Type\([0-9]+\)="\K[^"]+' "$SCENARIO_DIR/othership.ini" 2>/dev/null | tr '\n' ',' | sed 's/,$//')
    # Count legs
    VESSELS_WITH_LEGS=$(grep -c 'Legs(' "$SCENARIO_DIR/othership.ini" 2>/dev/null || echo "0")
fi

# Check radar config from all locations
ARPA_ON=""
FULL_RADAR=""
RADAR_RES=""
ANGULAR_RES=""
MAX_RANGE=""
HIDE_INST=""
for cfg in "$BC_CONFIG" "$BC_DATA/bc5.ini" "/home/ga/.Bridge Command/5.10/bc5.ini"; do
    if [ -f "$cfg" ]; then
        val=$(grep -oP 'arpa_on=\K[0-9]+' "$cfg" 2>/dev/null || grep -oP 'arpa_on="\K[^"]+' "$cfg" 2>/dev/null)
        [ -n "$val" ] && ARPA_ON="$val"
        val=$(grep -oP 'full_radar=\K[0-9]+' "$cfg" 2>/dev/null || grep -oP 'full_radar="\K[^"]+' "$cfg" 2>/dev/null)
        [ -n "$val" ] && FULL_RADAR="$val"
        val=$(grep -oP 'radar_range_resolution=\K[0-9]+' "$cfg" 2>/dev/null || grep -oP 'radar_range_resolution="\K[^"]+' "$cfg" 2>/dev/null)
        [ -n "$val" ] && RADAR_RES="$val"
        val=$(grep -oP 'radar_angular_resolution=\K[0-9]+' "$cfg" 2>/dev/null || grep -oP 'radar_angular_resolution="\K[^"]+' "$cfg" 2>/dev/null)
        [ -n "$val" ] && ANGULAR_RES="$val"
        val=$(grep -oP 'max_radar_range=\K[0-9]+' "$cfg" 2>/dev/null || grep -oP 'max_radar_range="\K[^"]+' "$cfg" 2>/dev/null)
        [ -n "$val" ] && MAX_RANGE="$val"
        val=$(grep -oP 'hide_instruments=\K[0-9]+' "$cfg" 2>/dev/null || grep -oP 'hide_instruments="\K[^"]+' "$cfg" 2>/dev/null)
        [ -n "$val" ] && HIDE_INST="$val"
    fi
done

# Check briefing
BRIEFING_EXISTS="false"
BRIEFING_LINE_COUNT=0
if [ -f "$BRIEFING_FILE" ]; then
    BRIEFING_EXISTS="true"
    BRIEFING_LINE_COUNT=$(wc -l < "$BRIEFING_FILE" 2>/dev/null || echo "0")
fi

# Build result JSON
python3 -c "
import json

briefing_content = ''
if '$BRIEFING_EXISTS' == 'true':
    try:
        with open('$BRIEFING_FILE', 'r') as f:
            briefing_content = f.read()[:8000]
    except:
        pass

result = {
    'task': 'storm_sar_scenario_creation',
    'scenario_exists': $( [ \"$SCENARIO_EXISTS\" = \"true\" ] && echo 'True' || echo 'False'),
    'env_ini_exists': $( [ \"$ENV_INI_EXISTS\" = \"true\" ] && echo 'True' || echo 'False'),
    'ownship_ini_exists': $( [ \"$OWNSHIP_INI_EXISTS\" = \"true\" ] && echo 'True' || echo 'False'),
    'othership_ini_exists': $( [ \"$OTHERSHIP_INI_EXISTS\" = \"true\" ] && echo 'True' || echo 'False'),
    'environment': {
        'setting': '${ENV_SETTING}',
        'start_time': '${ENV_START_TIME}',
        'weather': '${ENV_WEATHER}',
        'rain': '${ENV_RAIN}',
        'visibility': '${ENV_VISIBILITY}',
        'variation': '${ENV_VARIATION}',
        'month': '${ENV_MONTH}',
        'year': '${ENV_YEAR}'
    },
    'ownship': {
        'name': '${OWN_NAME}',
        'lat': '${OWN_LAT}',
        'long': '${OWN_LONG}',
        'speed': '${OWN_SPEED}',
        'bearing': '${OWN_BEARING}',
        'gps': '${OWN_GPS}',
        'depth_sounder': '${OWN_DEPTH}'
    },
    'othership': {
        'vessel_count': int('${VESSEL_COUNT}' or '0'),
        'vessel_types': '${VESSEL_TYPES}',
        'vessels_with_legs': int('${VESSELS_WITH_LEGS}' or '0')
    },
    'radar_config': {
        'arpa_on': '${ARPA_ON}',
        'full_radar': '${FULL_RADAR}',
        'radar_range_resolution': '${RADAR_RES}',
        'radar_angular_resolution': '${ANGULAR_RES}',
        'max_radar_range': '${MAX_RANGE}',
        'hide_instruments': '${HIDE_INST}'
    },
    'briefing': {
        'exists': $( [ \"$BRIEFING_EXISTS\" = \"true\" ] && echo 'True' || echo 'False'),
        'line_count': $BRIEFING_LINE_COUNT,
        'content': briefing_content
    }
}

with open('/tmp/storm_sar_scenario_creation_result.json', 'w') as f:
    json.dump(result, f, indent=2)
print(json.dumps(result, indent=2)[:2000])
"

echo "=== Export Complete ==="
