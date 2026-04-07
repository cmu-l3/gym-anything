#!/bin/bash
echo "=== Exporting validate_automated_detection_pipeline result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true
TASK="validate_automated_detection_pipeline"

TASK_START=$(cat /tmp/${TASK}_start_ts 2>/dev/null || echo "0")
INITIAL_AUTO_PICKS=$(cat /tmp/${TASK}_initial_auto_picks 2>/dev/null || echo "0")
INITIAL_AUTO_ORIGINS=$(cat /tmp/${TASK}_initial_auto_origins 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/${TASK}_end_screenshot.png 2>/dev/null || true

# ─── 1. Check station bindings ──────────────────────────────────────────────

STATIONS_WITH_SCAUTOPICK=0
for STA in GSI SANI BKB; do
    KEY_FILE="$SEISCOMP_ROOT/etc/key/station_GE_${STA}"
    if [ -f "$KEY_FILE" ] && grep -qi "scautopick" "$KEY_FILE" 2>/dev/null; then
        STATIONS_WITH_SCAUTOPICK=$((STATIONS_WITH_SCAUTOPICK + 1))
    fi
done
echo "Stations with scautopick binding: $STATIONS_WITH_SCAUTOPICK"

# ─── 2. Check scautopick config for bandpass filter ─────────────────────────

HAS_SCAUTOPICK_CFG="false"
SCAUTOPICK_FILTER=""

SCAUTOPICK_CFG="$SEISCOMP_ROOT/etc/scautopick.cfg"
if [ -f "$SCAUTOPICK_CFG" ]; then
    HAS_SCAUTOPICK_CFG="true"
    SCAUTOPICK_FILTER=$(grep -i "filter\|BW(" "$SCAUTOPICK_CFG" 2>/dev/null | head -1 || echo "")
fi

# Also check profile-based configs
for PROFILE_DIR in "$SEISCOMP_ROOT/etc/key/scautopick"/*; do
    if [ -d "$PROFILE_DIR" ] || [ -f "$PROFILE_DIR" ]; then
        PROFILE_FILTER=$(grep -ri "filter\|BW(" "$PROFILE_DIR" 2>/dev/null | head -1 || echo "")
        if [ -n "$PROFILE_FILTER" ] && [ -z "$SCAUTOPICK_FILTER" ]; then
            HAS_SCAUTOPICK_CFG="true"
            SCAUTOPICK_FILTER="$PROFILE_FILTER"
        fi
    fi
done 2>/dev/null

echo "scautopick.cfg exists: $HAS_SCAUTOPICK_CFG"
echo "scautopick filter: $SCAUTOPICK_FILTER"

# ─── 3. Count automatic picks in database ───────────────────────────────────

AUTO_PICK_COUNT=$(mysql -u sysop -psysop seiscomp -N -B -e \
    "SELECT COUNT(*) FROM Pick WHERE evaluationMode='automatic'" 2>/dev/null || echo "0")

PICKS_GSI=$(mysql -u sysop -psysop seiscomp -N -B -e \
    "SELECT COUNT(*) FROM Pick WHERE waveformID_stationCode='GSI' AND evaluationMode='automatic'" 2>/dev/null || echo "0")
PICKS_BKB=$(mysql -u sysop -psysop seiscomp -N -B -e \
    "SELECT COUNT(*) FROM Pick WHERE waveformID_stationCode='BKB' AND evaluationMode='automatic'" 2>/dev/null || echo "0")
PICKS_SANI=$(mysql -u sysop -psysop seiscomp -N -B -e \
    "SELECT COUNT(*) FROM Pick WHERE waveformID_stationCode='SANI' AND evaluationMode='automatic'" 2>/dev/null || echo "0")

echo "Automatic picks: total=$AUTO_PICK_COUNT GSI=$PICKS_GSI BKB=$PICKS_BKB SANI=$PICKS_SANI"

# ─── 4. Count automatic origins in database ─────────────────────────────────

AUTO_ORIGIN_COUNT=$(mysql -u sysop -psysop seiscomp -N -B -e \
    "SELECT COUNT(*) FROM Origin WHERE evaluationMode='automatic'" 2>/dev/null || echo "0")

# Get the first automatic origin's coordinates if any exist
ORIGIN_LAT=""
ORIGIN_LON=""
if [ "$AUTO_ORIGIN_COUNT" -gt 0 ] 2>/dev/null; then
    ORIGIN_LAT=$(mysql -u sysop -psysop seiscomp -N -B -e \
        "SELECT latitude_value FROM Origin WHERE evaluationMode='automatic' ORDER BY _oid DESC LIMIT 1" 2>/dev/null || echo "")
    ORIGIN_LON=$(mysql -u sysop -psysop seiscomp -N -B -e \
        "SELECT longitude_value FROM Origin WHERE evaluationMode='automatic' ORDER BY _oid DESC LIMIT 1" 2>/dev/null || echo "")
fi
echo "Automatic origins: $AUTO_ORIGIN_COUNT (lat=$ORIGIN_LAT lon=$ORIGIN_LON)"

# ─── 5. Check validation script ─────────────────────────────────────────────

SCRIPT_PATH="/home/ga/validate_pipeline.py"
SCRIPT_EXISTS="false"
SCRIPT_SIZE=0
SCRIPT_CREATED_DURING_TASK="false"
SCRIPT_IS_VALID_PYTHON="false"

if [ -f "$SCRIPT_PATH" ]; then
    SCRIPT_EXISTS="true"
    SCRIPT_SIZE=$(wc -c < "$SCRIPT_PATH" 2>/dev/null || echo "0")
    SCRIPT_MTIME=$(stat -c %Y "$SCRIPT_PATH" 2>/dev/null || echo "0")
    if [ "$SCRIPT_MTIME" -ge "$TASK_START" ]; then
        SCRIPT_CREATED_DURING_TASK="true"
    fi
    # Check if it parses as valid Python
    if python3 -c "import py_compile; py_compile.compile('$SCRIPT_PATH', doraise=True)" 2>/dev/null; then
        SCRIPT_IS_VALID_PYTHON="true"
    fi
    # Copy for verifier access
    cp "$SCRIPT_PATH" /tmp/${TASK}_script.py 2>/dev/null
    chmod 644 /tmp/${TASK}_script.py 2>/dev/null
fi
echo "Script: exists=$SCRIPT_EXISTS size=$SCRIPT_SIZE valid_python=$SCRIPT_IS_VALID_PYTHON"

# ─── 6. Check JSON report ───────────────────────────────────────────────────

REPORT_PATH="/home/ga/pipeline_report.json"
REPORT_EXISTS="false"
REPORT_SIZE=0
REPORT_CREATED_DURING_TASK="false"
REPORT_IS_VALID_JSON="false"
REPORT_HAS_PICK_COUNT="false"
REPORT_HAS_ORIGIN_COUNT="false"
REPORT_HAS_ORIGIN_LAT="false"
REPORT_HAS_ORIGIN_LON="false"
REPORT_HAS_STATION_PICKS="false"
REPORT_PICK_COUNT=0
REPORT_ORIGIN_COUNT=0
REPORT_ORIGIN_LAT=""
REPORT_ORIGIN_LON=""
REPORT_STATION_COUNT=0

if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_SIZE=$(wc -c < "$REPORT_PATH" 2>/dev/null || echo "0")
    REPORT_MTIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    if [ "$REPORT_MTIME" -ge "$TASK_START" ]; then
        REPORT_CREATED_DURING_TASK="true"
    fi

    # Validate JSON and extract fields
    REPORT_PARSED=$(python3 -c "
import json, sys
try:
    with open('$REPORT_PATH') as f:
        d = json.load(f)
    r = {}
    r['valid'] = True
    r['has_pick_count'] = 'pick_count' in d
    r['has_origin_count'] = 'origin_count' in d
    r['has_origin_lat'] = 'origin_lat' in d
    r['has_origin_lon'] = 'origin_lon' in d
    r['has_station_picks'] = 'station_picks' in d and isinstance(d.get('station_picks'), list)
    r['pick_count'] = int(d.get('pick_count', 0))
    r['origin_count'] = int(d.get('origin_count', 0))
    r['origin_lat'] = str(d.get('origin_lat', ''))
    r['origin_lon'] = str(d.get('origin_lon', ''))
    r['station_count'] = len(d.get('station_picks', []))
    # Check station_picks entries have required fields
    sp = d.get('station_picks', [])
    has_all_fields = all(
        isinstance(s, dict) and 'code' in s and 'pick_time' in s and 'distance_km' in s
        for s in sp
    ) if sp else False
    r['station_picks_valid'] = has_all_fields
    for k, v in r.items():
        print(f'{k}={v}')
except Exception as e:
    print(f'valid=False')
    print(f'error={e}')
" 2>/dev/null)

    if echo "$REPORT_PARSED" | grep -q "valid=True"; then
        REPORT_IS_VALID_JSON="true"
        REPORT_HAS_PICK_COUNT=$(echo "$REPORT_PARSED" | grep "has_pick_count=" | cut -d= -f2)
        REPORT_HAS_ORIGIN_COUNT=$(echo "$REPORT_PARSED" | grep "has_origin_count=" | cut -d= -f2)
        REPORT_HAS_ORIGIN_LAT=$(echo "$REPORT_PARSED" | grep "has_origin_lat=" | cut -d= -f2)
        REPORT_HAS_ORIGIN_LON=$(echo "$REPORT_PARSED" | grep "has_origin_lon=" | cut -d= -f2)
        REPORT_HAS_STATION_PICKS=$(echo "$REPORT_PARSED" | grep "has_station_picks=" | cut -d= -f2)
        REPORT_PICK_COUNT=$(echo "$REPORT_PARSED" | grep "^pick_count=" | cut -d= -f2)
        REPORT_ORIGIN_COUNT=$(echo "$REPORT_PARSED" | grep "^origin_count=" | cut -d= -f2)
        REPORT_ORIGIN_LAT=$(echo "$REPORT_PARSED" | grep "^origin_lat=" | cut -d= -f2)
        REPORT_ORIGIN_LON=$(echo "$REPORT_PARSED" | grep "^origin_lon=" | cut -d= -f2)
        REPORT_STATION_COUNT=$(echo "$REPORT_PARSED" | grep "station_count=" | cut -d= -f2)
    fi

    # Copy for verifier access
    cp "$REPORT_PATH" /tmp/${TASK}_report.json 2>/dev/null
    chmod 644 /tmp/${TASK}_report.json 2>/dev/null
fi

echo "Report: exists=$REPORT_EXISTS valid_json=$REPORT_IS_VALID_JSON size=$REPORT_SIZE"

# ─── 7. Write result JSON ───────────────────────────────────────────────────

FILTER_ESCAPED=$(echo "$SCAUTOPICK_FILTER" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read().strip()))" 2>/dev/null || echo '""')
ORIGIN_LAT_JSON=$(echo "$ORIGIN_LAT" | python3 -c "import sys; v=sys.stdin.read().strip(); print(v if v else 'null')" 2>/dev/null || echo "null")
ORIGIN_LON_JSON=$(echo "$ORIGIN_LON" | python3 -c "import sys; v=sys.stdin.read().strip(); print(v if v else 'null')" 2>/dev/null || echo "null")
REPORT_ORIGIN_LAT_JSON=$(echo "$REPORT_ORIGIN_LAT" | python3 -c "import sys; v=sys.stdin.read().strip(); print(v if v else 'null')" 2>/dev/null || echo "null")
REPORT_ORIGIN_LON_JSON=$(echo "$REPORT_ORIGIN_LON" | python3 -c "import sys; v=sys.stdin.read().strip(); print(v if v else 'null')" 2>/dev/null || echo "null")

cat > /tmp/${TASK}_result.json << EOF
{
    "task": "$TASK",
    "task_start": $TASK_START,
    "initial_auto_picks": $INITIAL_AUTO_PICKS,
    "initial_auto_origins": $INITIAL_AUTO_ORIGINS,
    "stations_with_scautopick": $STATIONS_WITH_SCAUTOPICK,
    "has_scautopick_cfg": $HAS_SCAUTOPICK_CFG,
    "scautopick_filter": $FILTER_ESCAPED,
    "auto_pick_count": ${AUTO_PICK_COUNT:-0},
    "picks_gsi": ${PICKS_GSI:-0},
    "picks_bkb": ${PICKS_BKB:-0},
    "picks_sani": ${PICKS_SANI:-0},
    "auto_origin_count": ${AUTO_ORIGIN_COUNT:-0},
    "db_origin_lat": $ORIGIN_LAT_JSON,
    "db_origin_lon": $ORIGIN_LON_JSON,
    "script_exists": $SCRIPT_EXISTS,
    "script_size": $SCRIPT_SIZE,
    "script_created_during_task": $SCRIPT_CREATED_DURING_TASK,
    "script_is_valid_python": $SCRIPT_IS_VALID_PYTHON,
    "report_exists": $REPORT_EXISTS,
    "report_size": $REPORT_SIZE,
    "report_created_during_task": $REPORT_CREATED_DURING_TASK,
    "report_is_valid_json": $REPORT_IS_VALID_JSON,
    "report_has_pick_count": $REPORT_HAS_PICK_COUNT,
    "report_has_origin_count": $REPORT_HAS_ORIGIN_COUNT,
    "report_has_origin_lat": $REPORT_HAS_ORIGIN_LAT,
    "report_has_origin_lon": $REPORT_HAS_ORIGIN_LON,
    "report_has_station_picks": $REPORT_HAS_STATION_PICKS,
    "report_pick_count": ${REPORT_PICK_COUNT:-0},
    "report_origin_count": ${REPORT_ORIGIN_COUNT:-0},
    "report_origin_lat": $REPORT_ORIGIN_LAT_JSON,
    "report_origin_lon": $REPORT_ORIGIN_LON_JSON,
    "report_station_count": ${REPORT_STATION_COUNT:-0}
}
EOF

echo "Result written to /tmp/${TASK}_result.json"
cat /tmp/${TASK}_result.json
echo "=== Export complete ==="
