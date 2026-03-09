#!/bin/bash
echo "=== Exporting multi_event_magnitude_comparison_scolv result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true
TASK="multi_event_magnitude_comparison_scolv"

TASK_START=$(cat /tmp/${TASK}_start_ts 2>/dev/null || echo "0")
INITIAL_EVENT_COUNT=$(cat /tmp/${TASK}_initial_event_count 2>/dev/null || echo "1")

# Take final screenshot
take_screenshot /tmp/${TASK}_end_screenshot.png 2>/dev/null || true

# ─── 1. Count events in database ────────────────────────────────────────────

CURRENT_EVENT_COUNT=$(mysql -u sysop -psysop seiscomp -N -B -e \
    "SELECT COUNT(*) FROM Event" 2>/dev/null || echo "0")
echo "Current event count: $CURRENT_EVENT_COUNT"

# ─── 2. Check for aftershock event (origin near 37.31, 136.79) ──────────────

AFTERSHOCK_EXISTS=$(mysql -u sysop -psysop seiscomp -N -B -e \
    "SELECT COUNT(*) FROM Origin
     WHERE ABS(latitude_value - 37.3107) < 0.5
     AND ABS(longitude_value - 136.7858) < 0.5
     AND ABS(depth_value - 10000) < 20000" 2>/dev/null || echo "0")
echo "Aftershock origin found: $AFTERSHOCK_EXISTS"

# ─── 3. Check aftershock event type ─────────────────────────────────────────

AFTERSHOCK_EVENT_TYPE=$(mysql -u sysop -psysop seiscomp -N -B -e \
    "SELECT e.type FROM Event e
     JOIN PublicObject po ON po.publicID = e.preferredOriginID
     JOIN Origin o ON o._oid = po._oid
     WHERE ABS(o.latitude_value - 37.3107) < 0.5
     AND ABS(o.longitude_value - 136.7858) < 0.5
     LIMIT 1" 2>/dev/null || echo "")
echo "Aftershock event type: '$AFTERSHOCK_EVENT_TYPE'"

# Check if event type is set to 'earthquake'
AFTERSHOCK_TYPE_CORRECT="false"
if [ "$AFTERSHOCK_EVENT_TYPE" = "earthquake" ]; then
    AFTERSHOCK_TYPE_CORRECT="true"
fi

# ─── 4. Check aftershock magnitude info ─────────────────────────────────────

AFTERSHOCK_MAG_TYPE=$(mysql -u sysop -psysop seiscomp -N -B -e \
    "SELECT m.type FROM Magnitude m
     JOIN Origin o ON m._parent_oid = o._oid
     WHERE ABS(o.latitude_value - 37.3107) < 0.5
     AND ABS(o.longitude_value - 136.7858) < 0.5
     ORDER BY m._oid DESC LIMIT 1" 2>/dev/null || echo "")

# Also check preferred magnitude type via Event table
AFTERSHOCK_PREF_MAG_TYPE=$(mysql -u sysop -psysop seiscomp -N -B -e \
    "SELECT m.type FROM Event e
     JOIN PublicObject pom ON pom.publicID = e.preferredMagnitudeID
     JOIN Magnitude m ON m._oid = pom._oid
     JOIN PublicObject poo ON poo.publicID = e.preferredOriginID
     JOIN Origin o ON o._oid = poo._oid
     WHERE ABS(o.latitude_value - 37.3107) < 0.5
     AND ABS(o.longitude_value - 136.7858) < 0.5
     LIMIT 1" 2>/dev/null || echo "")

echo "Aftershock magnitude type: '$AFTERSHOCK_MAG_TYPE'"
echo "Aftershock preferred mag type: '$AFTERSHOCK_PREF_MAG_TYPE'"

# Check for Mw(mB) magnitude type anywhere in the aftershock event
AFTERSHOCK_HAS_MWMB="false"
MAG_TYPE_CHECK=$(mysql -u sysop -psysop seiscomp -N -B -e \
    "SELECT COUNT(*) FROM Magnitude m
     JOIN Origin o ON m._parent_oid = o._oid
     WHERE ABS(o.latitude_value - 37.3107) < 0.5
     AND ABS(o.longitude_value - 136.7858) < 0.5
     AND m.type = 'Mw(mB)'" 2>/dev/null || echo "0")
[ "$MAG_TYPE_CHECK" -gt 0 ] 2>/dev/null && AFTERSHOCK_HAS_MWMB="true"
# Also check via preferred magnitude
echo "$AFTERSHOCK_PREF_MAG_TYPE" | grep -q "Mw(mB)" && AFTERSHOCK_HAS_MWMB="true"
echo "$AFTERSHOCK_MAG_TYPE" | grep -q "Mw(mB)" && AFTERSHOCK_HAS_MWMB="true"

echo "Aftershock has Mw(mB): $AFTERSHOCK_HAS_MWMB"

# ─── 5. Check bulletin file ─────────────────────────────────────────────────

BULLETIN_FILE="/home/ga/Desktop/event_comparison.txt"
BULLETIN_EXISTS="false"
BULLETIN_SIZE=0
BULLETIN_HAS_MAINSHOCK="false"
BULLETIN_HAS_AFTERSHOCK="false"
BULLETIN_HAS_MAGNITUDES="false"

if [ -f "$BULLETIN_FILE" ]; then
    BULLETIN_EXISTS="true"
    BULLETIN_SIZE=$(wc -c < "$BULLETIN_FILE" 2>/dev/null || echo "0")
    CONTENT=$(cat "$BULLETIN_FILE" 2>/dev/null || echo "")

    # Check for mainshock indicators (M7.5, ~37.23/37.49, Noto)
    if echo "$CONTENT" | grep -qiE "(7\.5|37\.(2|4|5)|Noto|m0xl|mainshock)"; then
        BULLETIN_HAS_MAINSHOCK="true"
    fi

    # Check for aftershock indicators (M6.2, ~37.31)
    if echo "$CONTENT" | grep -qiE "(6\.2|37\.3|m13n|aftershock)"; then
        BULLETIN_HAS_AFTERSHOCK="true"
    fi

    # Check for magnitude values
    if echo "$CONTENT" | grep -qiE "(magnitude|mag|[67]\.[0-9])"; then
        BULLETIN_HAS_MAGNITUDES="true"
    fi
fi
echo "Bulletin exists: $BULLETIN_EXISTS (size=$BULLETIN_SIZE)"
echo "Bulletin has mainshock: $BULLETIN_HAS_MAINSHOCK"
echo "Bulletin has aftershock: $BULLETIN_HAS_AFTERSHOCK"

# ─── 6. Write result JSON ───────────────────────────────────────────────────

AFTERSHOCK_EVENT_TYPE_ESCAPED=$(echo "$AFTERSHOCK_EVENT_TYPE" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read().strip()))" 2>/dev/null || echo '""')
AFTERSHOCK_MAG_TYPE_ESCAPED=$(echo "$AFTERSHOCK_MAG_TYPE" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read().strip()))" 2>/dev/null || echo '""')

cat > /tmp/${TASK}_result.json << EOF
{
    "task": "$TASK",
    "task_start": $TASK_START,
    "initial_event_count": $INITIAL_EVENT_COUNT,
    "current_event_count": ${CURRENT_EVENT_COUNT:-0},
    "aftershock_exists": $([ "${AFTERSHOCK_EXISTS:-0}" -gt 0 ] 2>/dev/null && echo "true" || echo "false"),
    "aftershock_event_type": $AFTERSHOCK_EVENT_TYPE_ESCAPED,
    "aftershock_type_correct": $AFTERSHOCK_TYPE_CORRECT,
    "aftershock_has_mwmb": $AFTERSHOCK_HAS_MWMB,
    "aftershock_mag_type": $AFTERSHOCK_MAG_TYPE_ESCAPED,
    "bulletin_exists": $BULLETIN_EXISTS,
    "bulletin_size": $BULLETIN_SIZE,
    "bulletin_has_mainshock": $BULLETIN_HAS_MAINSHOCK,
    "bulletin_has_aftershock": $BULLETIN_HAS_AFTERSHOCK,
    "bulletin_has_magnitudes": $BULLETIN_HAS_MAGNITUDES
}
EOF

echo "Result written to /tmp/${TASK}_result.json"
cat /tmp/${TASK}_result.json
echo "=== Export complete ==="
