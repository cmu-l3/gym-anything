#!/bin/bash
echo "=== Exporting event_screening_false_detection_cleanup result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true
TASK="event_screening_false_detection_cleanup"

TASK_START=$(cat /tmp/${TASK}_start_ts 2>/dev/null || echo "0")
INITIAL_EVENT_COUNT=$(cat /tmp/${TASK}_initial_event_count 2>/dev/null || echo "4")

# Take final screenshot
take_screenshot /tmp/${TASK}_end_screenshot.png 2>/dev/null || true

# ─── 1. Count remaining events ──────────────────────────────────────────────

CURRENT_EVENT_COUNT=$(mysql -u sysop -psysop seiscomp -N -B -e \
    "SELECT COUNT(*) FROM Event" 2>/dev/null || echo "0")
echo "Current event count: $CURRENT_EVENT_COUNT (was $INITIAL_EVENT_COUNT)"

# ─── 2. Check if false events were removed ──────────────────────────────────

FALSE_1_EXISTS=$(mysql -u sysop -psysop seiscomp -N -B -e \
    "SELECT COUNT(*) FROM Origin WHERE ABS(latitude_value - 5.0) < 1.0 AND ABS(longitude_value - 170.5) < 1.0" \
    2>/dev/null || echo "0")
FALSE_2_EXISTS=$(mysql -u sysop -psysop seiscomp -N -B -e \
    "SELECT COUNT(*) FROM Origin WHERE ABS(latitude_value - (-45.0)) < 1.0 AND ABS(longitude_value - (-175.0)) < 1.0" \
    2>/dev/null || echo "0")
FALSE_3_EXISTS=$(mysql -u sysop -psysop seiscomp -N -B -e \
    "SELECT COUNT(*) FROM Origin WHERE ABS(latitude_value - 65.0) < 1.0 AND ABS(longitude_value - (-30.5)) < 1.0" \
    2>/dev/null || echo "0")

FALSE_EVENTS_REMAINING=0
[ "${FALSE_1_EXISTS:-0}" -gt 0 ] 2>/dev/null && FALSE_EVENTS_REMAINING=$((FALSE_EVENTS_REMAINING + 1))
[ "${FALSE_2_EXISTS:-0}" -gt 0 ] 2>/dev/null && FALSE_EVENTS_REMAINING=$((FALSE_EVENTS_REMAINING + 1))
[ "${FALSE_3_EXISTS:-0}" -gt 0 ] 2>/dev/null && FALSE_EVENTS_REMAINING=$((FALSE_EVENTS_REMAINING + 1))

echo "False events remaining: $FALSE_EVENTS_REMAINING"
echo "  mid-Pacific (5.0, 170.5): $FALSE_1_EXISTS"
echo "  South Pacific (-45.0, -175.0): $FALSE_2_EXISTS"
echo "  North Atlantic (65.0, -30.5): $FALSE_3_EXISTS"

# ─── 3. Check if real event is still present ────────────────────────────────

REAL_EVENT_EXISTS=$(mysql -u sysop -psysop seiscomp -N -B -e \
    "SELECT COUNT(*) FROM Origin WHERE ABS(latitude_value - 37.5) < 2.0 AND ABS(longitude_value - 137.3) < 2.0" \
    2>/dev/null || echo "0")
echo "Real event (Noto M7.5) still present: $REAL_EVENT_EXISTS"

REAL_EVENT_PRESERVED="false"
[ "${REAL_EVENT_EXISTS:-0}" -gt 0 ] 2>/dev/null && REAL_EVENT_PRESERVED="true"

# ─── 4. Check bulletin file ─────────────────────────────────────────────────

BULLETIN_FILE="/home/ga/Desktop/verified_events.txt"
BULLETIN_EXISTS="false"
BULLETIN_SIZE=0
BULLETIN_HAS_REAL_EVENT="false"
BULLETIN_HAS_FALSE_EVENTS="false"

if [ -f "$BULLETIN_FILE" ]; then
    BULLETIN_EXISTS="true"
    BULLETIN_SIZE=$(wc -c < "$BULLETIN_FILE" 2>/dev/null || echo "0")
    CONTENT=$(cat "$BULLETIN_FILE" 2>/dev/null || echo "")

    # Check for real event indicators
    if echo "$CONTENT" | grep -qiE "(7\.5|Noto|37\.(2|4|5)|137\.(2|3))"; then
        BULLETIN_HAS_REAL_EVENT="true"
    fi

    # Check if bulletin incorrectly includes false events
    if echo "$CONTENT" | grep -qiE "(170\.5|175\.0|\-45\.|\-30\.5|mid-Pacific|South Pacific|North Atlantic|false.detect)"; then
        BULLETIN_HAS_FALSE_EVENTS="true"
    fi
fi
echo "Bulletin: exists=$BULLETIN_EXISTS size=$BULLETIN_SIZE real=$BULLETIN_HAS_REAL_EVENT false=$BULLETIN_HAS_FALSE_EVENTS"

# ─── 5. Write result JSON ───────────────────────────────────────────────────

cat > /tmp/${TASK}_result.json << EOF
{
    "task": "$TASK",
    "task_start": $TASK_START,
    "initial_event_count": $INITIAL_EVENT_COUNT,
    "current_event_count": ${CURRENT_EVENT_COUNT:-0},
    "false_events_remaining": $FALSE_EVENTS_REMAINING,
    "false_1_mid_pacific": $([ "${FALSE_1_EXISTS:-0}" -gt 0 ] 2>/dev/null && echo "true" || echo "false"),
    "false_2_south_pacific": $([ "${FALSE_2_EXISTS:-0}" -gt 0 ] 2>/dev/null && echo "true" || echo "false"),
    "false_3_north_atlantic": $([ "${FALSE_3_EXISTS:-0}" -gt 0 ] 2>/dev/null && echo "true" || echo "false"),
    "real_event_preserved": $REAL_EVENT_PRESERVED,
    "bulletin_exists": $BULLETIN_EXISTS,
    "bulletin_size": $BULLETIN_SIZE,
    "bulletin_has_real_event": $BULLETIN_HAS_REAL_EVENT,
    "bulletin_has_false_events": $BULLETIN_HAS_FALSE_EVENTS
}
EOF

echo "Result written to /tmp/${TASK}_result.json"
cat /tmp/${TASK}_result.json
echo "=== Export complete ==="
