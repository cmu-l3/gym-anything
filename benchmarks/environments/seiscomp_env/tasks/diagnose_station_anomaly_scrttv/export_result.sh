#!/bin/bash
echo "=== Exporting diagnose_station_anomaly_scrttv result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true
TASK="diagnose_station_anomaly_scrttv"
TARGET_STATION="KWP"

TASK_START=$(cat /tmp/${TASK}_start_ts 2>/dev/null || echo "0")
INITIAL_BINDING_COUNT=$(cat /tmp/${TASK}_initial_binding_count 2>/dev/null || echo "5")

# Take final screenshot
take_screenshot /tmp/${TASK}_end_screenshot.png 2>/dev/null || true

# ─── 1. Check if KWP bindings were removed ────────────────────────────────

KWP_KEY="$SEISCOMP_ROOT/etc/key/station_GE_KWP"
KWP_HAS_SCAUTOPICK="false"
KWP_HAS_SCAMP="false"
KWP_KEY_EXISTS="false"

if [ -f "$KWP_KEY" ]; then
    KWP_KEY_EXISTS="true"
    grep -qi "scautopick" "$KWP_KEY" 2>/dev/null && KWP_HAS_SCAUTOPICK="true"
    grep -qi "scamp" "$KWP_KEY" 2>/dev/null && KWP_HAS_SCAMP="true"
fi

echo "KWP key file exists: $KWP_KEY_EXISTS"
echo "KWP has scautopick: $KWP_HAS_SCAUTOPICK"
echo "KWP has scamp: $KWP_HAS_SCAMP"

# ─── 2. Check that other stations still have bindings ──────────────────────

OTHER_STATIONS_WITH_BINDINGS=0
for STA in TOLI GSI SANI BKB; do
    KEY_FILE="$SEISCOMP_ROOT/etc/key/station_GE_${STA}"
    if [ -f "$KEY_FILE" ] && grep -qi "scautopick" "$KEY_FILE" 2>/dev/null; then
        OTHER_STATIONS_WITH_BINDINGS=$((OTHER_STATIONS_WITH_BINDINGS + 1))
    fi
done
echo "Other stations with scautopick bindings: $OTHER_STATIONS_WITH_BINDINGS (should be 4)"

# ─── 3. Check the anomaly report file ─────────────────────────────────────

REPORT_FILE="/home/ga/Desktop/station_anomaly_report.txt"
REPORT_EXISTS="false"
REPORT_MENTIONS_KWP="false"
REPORT_HAS_SYMPTOMS="false"
REPORT_HAS_ACTION="false"
REPORT_SIZE=0
REPORT_CONTENT=""

if [ -f "$REPORT_FILE" ]; then
    REPORT_EXISTS="true"
    REPORT_SIZE=$(wc -c < "$REPORT_FILE" 2>/dev/null || echo "0")

    # Read the report content (first 2000 chars)
    REPORT_CONTENT=$(head -c 2000 "$REPORT_FILE" 2>/dev/null || echo "")

    # Check if report mentions the target station KWP
    if echo "$REPORT_CONTENT" | grep -qi "KWP"; then
        REPORT_MENTIONS_KWP="true"
    fi

    # Check if report describes symptoms (noise, gap, spike, anomal, corrupt, bad, unreliable)
    if echo "$REPORT_CONTENT" | grep -qiE "(noise|gap|spike|anomal|corrupt|bad|unreliable|timing|quality|irregular|glitch|artifact|discontinuit|malfunction)"; then
        REPORT_HAS_SYMPTOMS="true"
    fi

    # Check if report describes corrective action (disabl|remov|unbind|deactivat|exclud|stop)
    if echo "$REPORT_CONTENT" | grep -qiE "(disabl|remov|unbind|deactivat|exclud|stop|took.*(out|off)|turned.*(off))"; then
        REPORT_HAS_ACTION="true"
    fi
fi

echo "Report exists: $REPORT_EXISTS (size=$REPORT_SIZE)"
echo "Report mentions KWP: $REPORT_MENTIONS_KWP"
echo "Report describes symptoms: $REPORT_HAS_SYMPTOMS"
echo "Report describes action: $REPORT_HAS_ACTION"

# ─── 4. Check if a wrong station was disabled instead ──────────────────────

WRONG_STATION_DISABLED="false"
for STA in TOLI GSI SANI BKB; do
    KEY_FILE="$SEISCOMP_ROOT/etc/key/station_GE_${STA}"
    if [ ! -f "$KEY_FILE" ] || ! grep -qi "scautopick" "$KEY_FILE" 2>/dev/null; then
        WRONG_STATION_DISABLED="true"
        echo "WARNING: GE.$STA binding was removed (wrong station)"
    fi
done

# ─── 5. Write result JSON ─────────────────────────────────────────────────

# Escape report content for JSON
REPORT_ESCAPED=$(echo "$REPORT_CONTENT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')

cat > /tmp/${TASK}_result.json << EOF
{
    "task": "$TASK",
    "task_start": $TASK_START,
    "initial_binding_count": $INITIAL_BINDING_COUNT,
    "kwp_key_exists": $KWP_KEY_EXISTS,
    "kwp_has_scautopick": $KWP_HAS_SCAUTOPICK,
    "kwp_has_scamp": $KWP_HAS_SCAMP,
    "other_stations_with_bindings": $OTHER_STATIONS_WITH_BINDINGS,
    "wrong_station_disabled": $WRONG_STATION_DISABLED,
    "report_exists": $REPORT_EXISTS,
    "report_size": $REPORT_SIZE,
    "report_mentions_kwp": $REPORT_MENTIONS_KWP,
    "report_has_symptoms": $REPORT_HAS_SYMPTOMS,
    "report_has_action": $REPORT_HAS_ACTION,
    "report_content": $REPORT_ESCAPED
}
EOF

echo "Result written to /tmp/${TASK}_result.json"
cat /tmp/${TASK}_result.json
echo "=== Export complete ==="
