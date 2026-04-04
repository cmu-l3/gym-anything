#!/bin/bash
echo "=== Exporting relocate_event_manual_picks_scolv result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true
TASK="relocate_event_manual_picks_scolv"

TASK_START=$(cat /tmp/${TASK}_start_ts 2>/dev/null || echo "0")
INITIAL_MANUAL_COUNT=$(cat /tmp/${TASK}_initial_manual_count 2>/dev/null || echo "0")
INITIAL_LAT=$(cat /tmp/${TASK}_initial_lat 2>/dev/null || echo "0")
INITIAL_LON=$(cat /tmp/${TASK}_initial_lon 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 import -window root /tmp/${TASK}_end_screenshot.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/${TASK}_end_screenshot.png 2>/dev/null || true

# Query: count of Origins with evaluationMode='manual'
MANUAL_ORIGIN_COUNT=$(mysql -u sysop -psysop seiscomp -N -B -e \
    "SELECT COUNT(*) FROM Origin WHERE evaluationMode='manual'" 2>/dev/null || echo "0")
echo "Manual origins found: $MANUAL_ORIGIN_COUNT"

# Query: get manual origin coordinates
MANUAL_LAT=$(mysql -u sysop -psysop seiscomp -N -B -e \
    "SELECT latitude_value FROM Origin WHERE evaluationMode='manual' ORDER BY _oid DESC LIMIT 1" 2>/dev/null || echo "")
MANUAL_LON=$(mysql -u sysop -psysop seiscomp -N -B -e \
    "SELECT longitude_value FROM Origin WHERE evaluationMode='manual' ORDER BY _oid DESC LIMIT 1" 2>/dev/null || echo "")
echo "Manual origin coords: lat=$MANUAL_LAT lon=$MANUAL_LON"

# Query: count P arrivals for manual origin
P_ARRIVAL_COUNT=$(mysql -u sysop -psysop seiscomp -N -B -e \
    "SELECT COUNT(a._oid) FROM Arrival a
     JOIN Origin o ON a._parent_oid = o._oid
     WHERE o.evaluationMode='manual'
     AND (a.phase_code = 'P' OR a.phase_code LIKE 'P%')" 2>/dev/null || echo "0")
echo "P arrivals for manual origin: $P_ARRIVAL_COUNT"

# Query: count all arrivals for manual origin (including S)
TOTAL_ARRIVAL_COUNT=$(mysql -u sysop -psysop seiscomp -N -B -e \
    "SELECT COUNT(a._oid) FROM Arrival a
     JOIN Origin o ON a._parent_oid = o._oid
     WHERE o.evaluationMode='manual'" 2>/dev/null || echo "0")
echo "Total arrivals for manual origin: $TOTAL_ARRIVAL_COUNT"

# Query: get the preferredOriginID for the event
PREFERRED_ORIGIN=$(mysql -u sysop -psysop seiscomp -N -B -e \
    "SELECT e.preferredOriginID FROM Event e LIMIT 1" 2>/dev/null || echo "")
echo "Event preferred origin: $PREFERRED_ORIGIN"

# Check if manual origin is now the preferred origin
PREFERRED_IS_MANUAL=$(mysql -u sysop -psysop seiscomp -N -B -e \
    "SELECT COUNT(*) FROM Event e
     JOIN PublicObject po ON po.publicID = e.preferredOriginID
     JOIN Origin o ON o._oid = po._oid
     WHERE o.evaluationMode = 'manual'" 2>/dev/null || echo "0")
echo "Preferred origin is manual: $PREFERRED_IS_MANUAL"

# Compute whether lat/lon changed significantly (as float comparison via python)
LAT_LON_CHANGED=$(python3 -c "
try:
    ilat = float('${INITIAL_LAT}')
    ilon = float('${INITIAL_LON}')
    mlat = float('${MANUAL_LAT}') if '${MANUAL_LAT}' else None
    mlon = float('${MANUAL_LON}') if '${MANUAL_LON}' else None
    if mlat is None or mlon is None:
        print('false')
    elif abs(mlat - ilat) > 0.001 or abs(mlon - ilon) > 0.001:
        print('true')
    else:
        print('false')
except:
    print('false')
" 2>/dev/null || echo "false")
echo "Lat/lon changed from initial: $LAT_LON_CHANGED"

cat > /tmp/${TASK}_result.json << EOF
{
    "task": "$TASK",
    "task_start": $TASK_START,
    "initial_manual_count": $INITIAL_MANUAL_COUNT,
    "manual_origin_count": ${MANUAL_ORIGIN_COUNT:-0},
    "p_arrival_count": ${P_ARRIVAL_COUNT:-0},
    "total_arrival_count": ${TOTAL_ARRIVAL_COUNT:-0},
    "manual_lat": "${MANUAL_LAT}",
    "manual_lon": "${MANUAL_LON}",
    "initial_lat": "${INITIAL_LAT}",
    "initial_lon": "${INITIAL_LON}",
    "lat_lon_changed": $LAT_LON_CHANGED,
    "preferred_is_manual": ${PREFERRED_IS_MANUAL:-0}
}
EOF

echo "Result written to /tmp/${TASK}_result.json"
cat /tmp/${TASK}_result.json
echo "=== Export complete ==="
