#!/bin/bash
# Export script for Segment + Scheduled Report task

echo "=== Exporting Segment Scheduled Report Result ==="
source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_final_screenshot.png

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# ── Baseline values ───────────────────────────────────────────────────────
INITIAL_SEG_COUNT=$(cat /tmp/initial_segment_count 2>/dev/null || echo "0")
INITIAL_REP_COUNT=$(cat /tmp/initial_report_count 2>/dev/null || echo "0")
INITIAL_SEG_IDS=$(cat /tmp/initial_segment_ids 2>/dev/null || echo "")
INITIAL_REP_IDS=$(cat /tmp/initial_report_ids 2>/dev/null || echo "")

# ── Current state ─────────────────────────────────────────────────────────
CURRENT_SEG_COUNT=$(matomo_query "SELECT COUNT(*) FROM matomo_segment WHERE deleted=0" 2>/dev/null || echo "0")
CURRENT_REP_COUNT=$(matomo_query "SELECT COUNT(*) FROM matomo_report WHERE deleted=0" 2>/dev/null || echo "0")

echo "Segments: initial=$INITIAL_SEG_COUNT, current=$CURRENT_SEG_COUNT"
echo "Reports:  initial=$INITIAL_REP_COUNT, current=$CURRENT_REP_COUNT"

# ── Debug: Show all segments ──────────────────────────────────────────────
echo ""
echo "=== DEBUG: Segments in database ==="
matomo_query_verbose "SELECT idsegment, name, definition, login, deleted FROM matomo_segment ORDER BY idsegment DESC LIMIT 5" 2>/dev/null
echo "=== END DEBUG ==="

# ── Debug: Show all reports ───────────────────────────────────────────────
echo ""
echo "=== DEBUG: Reports in database ==="
matomo_query_verbose "SELECT idreport, idsite, login, description, idsegment, period, type, parameters, deleted FROM matomo_report ORDER BY idreport DESC LIMIT 5" 2>/dev/null
echo "=== END DEBUG ==="
echo ""

# ── Find new segments (created after task start) ──────────────────────────
# New = ID not in the initial list
NEW_SEG_DATA=$(matomo_query "SELECT idsegment, name, definition, login, enable_all_users, enable_only_idsite
    FROM matomo_segment
    WHERE deleted=0
    ORDER BY idsegment DESC LIMIT 3" 2>/dev/null)

SEGMENT_FOUND="false"
SEG_ID=""
SEG_NAME=""
SEG_DEFINITION=""
SEG_LOGIN=""

if [ -n "$NEW_SEG_DATA" ]; then
    # Try to find a new segment (ID not in initial list)
    while IFS=$'\t' read -r sid sname sdef slogin senable ssite; do
        if [ -z "$INITIAL_SEG_IDS" ] || ! echo ",$INITIAL_SEG_IDS," | grep -q ",$sid,"; then
            SEGMENT_FOUND="true"
            SEG_ID="$sid"
            SEG_NAME="$sname"
            SEG_DEFINITION="$sdef"
            SEG_LOGIN="$slogin"
            break
        fi
    done <<< "$NEW_SEG_DATA"
fi

echo "Segment found: $SEGMENT_FOUND (ID=$SEG_ID, name=$SEG_NAME)"
[ -n "$SEG_DEFINITION" ] && echo "Definition: $SEG_DEFINITION"

# ── Find new reports ──────────────────────────────────────────────────────
NEW_REP_DATA=$(matomo_query "SELECT idreport, idsite, login, description, idsegment, period, hour, type, parameters
    FROM matomo_report
    WHERE deleted=0
    ORDER BY idreport DESC LIMIT 3" 2>/dev/null)

REPORT_FOUND="false"
REP_ID=""
REP_IDSITE=""
REP_LOGIN=""
REP_DESCRIPTION=""
REP_IDSEGMENT=""
REP_PERIOD=""
REP_HOUR=""
REP_TYPE=""
REP_PARAMETERS=""

if [ -n "$NEW_REP_DATA" ]; then
    while IFS=$'\t' read -r rid rsite rlogin rdesc rseg rperiod rhour rtype rparams; do
        if [ -z "$INITIAL_REP_IDS" ] || ! echo ",$INITIAL_REP_IDS," | grep -q ",$rid,"; then
            REPORT_FOUND="true"
            REP_ID="$rid"
            REP_IDSITE="$rsite"
            REP_LOGIN="$rlogin"
            REP_DESCRIPTION="$rdesc"
            REP_IDSEGMENT="$rseg"
            REP_PERIOD="$rperiod"
            REP_HOUR="$rhour"
            REP_TYPE="$rtype"
            REP_PARAMETERS="$rparams"
            break
        fi
    done <<< "$NEW_REP_DATA"
fi

echo "Report found: $REPORT_FOUND (ID=$REP_ID, period=$REP_PERIOD, idsegment=$REP_IDSEGMENT)"
[ -n "$REP_PARAMETERS" ] && echo "Parameters snippet: ${REP_PARAMETERS:0:200}"

# ── Escape for JSON ───────────────────────────────────────────────────────
escape_json() {
    echo "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

SEG_NAME_ESC=$(escape_json "$SEG_NAME")
SEG_DEF_ESC=$(escape_json "$SEG_DEFINITION")
REP_DESC_ESC=$(escape_json "$REP_DESCRIPTION")
REP_PARAMS_ESC=$(escape_json "$REP_PARAMETERS")

# ── Check if target email appears in report parameters ────────────────────
TARGET_EMAIL="analytics@marketingteam.test"
EMAIL_IN_PARAMS="false"
if echo "$REP_PARAMETERS" | grep -qi "$TARGET_EMAIL"; then
    EMAIL_IN_PARAMS="true"
fi

# ── Write result JSON ─────────────────────────────────────────────────────
TEMP_JSON=$(mktemp /tmp/segment_scheduled_report_result.XXXXXX.json)
cat > "$TEMP_JSON" << JSONEOF
{
    "task_start_timestamp": $TASK_START,
    "task_end_timestamp": $TASK_END,
    "initial_segment_count": ${INITIAL_SEG_COUNT:-0},
    "current_segment_count": ${CURRENT_SEG_COUNT:-0},
    "initial_report_count": ${INITIAL_REP_COUNT:-0},
    "current_report_count": ${CURRENT_REP_COUNT:-0},
    "initial_segment_ids": "$(escape_json "$INITIAL_SEG_IDS")",
    "initial_report_ids": "$(escape_json "$INITIAL_REP_IDS")",
    "segment": {
        "found": $SEGMENT_FOUND,
        "idsegment": "${SEG_ID}",
        "name": "${SEG_NAME_ESC}",
        "definition": "${SEG_DEF_ESC}",
        "login": "${SEG_LOGIN}"
    },
    "report": {
        "found": $REPORT_FOUND,
        "idreport": "${REP_ID}",
        "idsite": "${REP_IDSITE}",
        "idsegment": "${REP_IDSEGMENT}",
        "period": "${REP_PERIOD}",
        "hour": "${REP_HOUR}",
        "type": "${REP_TYPE}",
        "description": "${REP_DESC_ESC}",
        "parameters": "${REP_PARAMS_ESC}",
        "email_in_params": $EMAIL_IN_PARAMS
    },
    "export_timestamp": "$(date -Iseconds)"
}
JSONEOF

rm -f /tmp/segment_scheduled_report_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/segment_scheduled_report_result.json
chmod 666 /tmp/segment_scheduled_report_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Result JSON saved to /tmp/segment_scheduled_report_result.json"
cat /tmp/segment_scheduled_report_result.json

echo ""
echo "=== Export Complete ==="
