#!/bin/bash
echo "=== Exporting adt_census_lab_validation_pipeline result ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# 1. Take final screenshot
take_screenshot /tmp/task_end_adt_pipeline.png

# 2. Read initial and current channel counts
INITIAL=$(cat /tmp/initial_adt_pipeline_channel_count 2>/dev/null || echo "0")
CURRENT=$(get_channel_count)
echo "Initial channel count: $INITIAL, Current: $CURRENT"

# ── Helper: send MLLP message and capture response ──────────────────────────
send_mllp_capture() {
    local file="$1"
    local port="$2"
    if [ ! -f "$file" ]; then
        echo "NO_FILE"
        return
    fi
    local response_hex
    response_hex=$( (printf '\x0b'; cat "$file"; printf '\x1c\x0d') | timeout 10 nc localhost "$port" 2>/dev/null | xxd -p | tr -d '\n')
    if [ -n "$response_hex" ]; then
        echo "$response_hex" | xxd -r -p 2>/dev/null
    else
        echo "NO_RESPONSE"
    fi
}

# Escape a string for safe JSON embedding
json_escape() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    s=$(printf '%s' "$s" | tr '\n' ' ' | tr '\r' ' ' | tr '\t' ' ' | sed 's/  */ /g; s/^ *//; s/ *$//')
    printf '%s' "$s"
}

# ── 3. Find channels by name ────────────────────────────────────────────────

# ADT_Census_Manager
CENSUS_EXISTS="false"
CENSUS_ID=""
CENSUS_NAME=""
CENSUS_STATUS="unknown"
CENSUS_PORT=""

CENSUS_DATA=$(query_postgres "SELECT id, name FROM channel WHERE LOWER(name) LIKE '%census%' OR (LOWER(name) LIKE '%adt%' AND LOWER(name) LIKE '%manager%');" 2>/dev/null || true)
if [ -n "$CENSUS_DATA" ]; then
    CENSUS_EXISTS="true"
    CENSUS_ID=$(echo "$CENSUS_DATA" | head -1 | cut -d'|' -f1)
    CENSUS_NAME=$(echo "$CENSUS_DATA" | head -1 | cut -d'|' -f2)
    echo "Found census channel: $CENSUS_NAME ($CENSUS_ID)"
fi

# Lab_Results_Validator
VALIDATOR_EXISTS="false"
VALIDATOR_ID=""
VALIDATOR_NAME=""
VALIDATOR_STATUS="unknown"
VALIDATOR_PORT=""
VALIDATOR_HAS_JS="false"
VALIDATOR_HAS_CHANNEL_WRITER="false"
VALIDATOR_HAS_DB_REJECT="false"

VALIDATOR_DATA=$(query_postgres "SELECT id, name FROM channel WHERE LOWER(name) LIKE '%lab%validat%' OR LOWER(name) LIKE '%result%validat%' OR (LOWER(name) LIKE '%lab%' AND LOWER(name) LIKE '%result%');" 2>/dev/null || true)
if [ -n "$VALIDATOR_DATA" ]; then
    VALIDATOR_EXISTS="true"
    VALIDATOR_ID=$(echo "$VALIDATOR_DATA" | head -1 | cut -d'|' -f1)
    VALIDATOR_NAME=$(echo "$VALIDATOR_DATA" | head -1 | cut -d'|' -f2)
    echo "Found validator channel: $VALIDATOR_NAME ($VALIDATOR_ID)"
fi

# Critical_Value_Processor
PROCESSOR_EXISTS="false"
PROCESSOR_ID=""
PROCESSOR_NAME=""
PROCESSOR_STATUS="unknown"
PROCESSOR_HAS_DB_WRITER="false"
PROCESSOR_HAS_FILE_WRITER="false"

PROCESSOR_DATA=$(query_postgres "SELECT id, name FROM channel WHERE LOWER(name) LIKE '%critical%value%' OR LOWER(name) LIKE '%critical%process%' OR LOWER(name) LIKE '%value%process%';" 2>/dev/null || true)
if [ -n "$PROCESSOR_DATA" ]; then
    PROCESSOR_EXISTS="true"
    PROCESSOR_ID=$(echo "$PROCESSOR_DATA" | head -1 | cut -d'|' -f1)
    PROCESSOR_NAME=$(echo "$PROCESSOR_DATA" | head -1 | cut -d'|' -f2)
    echo "Found processor channel: $PROCESSOR_NAME ($PROCESSOR_ID)"
fi

# Fallback: assign from newest channels if not all found by name
if [ "$CURRENT" -gt "$INITIAL" ]; then
    NEW_COUNT=$((CURRENT - INITIAL))
    ALL_NEW=$(query_postgres "SELECT id, name FROM channel ORDER BY revision DESC LIMIT $NEW_COUNT;" 2>/dev/null || true)

    if [ "$CENSUS_EXISTS" = "false" ] && [ -n "$ALL_NEW" ]; then
        CENSUS_ID=$(echo "$ALL_NEW" | head -1 | cut -d'|' -f1)
        CENSUS_NAME=$(echo "$ALL_NEW" | head -1 | cut -d'|' -f2)
        CENSUS_EXISTS="true"
    fi
    if [ "$VALIDATOR_EXISTS" = "false" ] && [ -n "$ALL_NEW" ] && [ "$NEW_COUNT" -ge 2 ]; then
        VALIDATOR_ID=$(echo "$ALL_NEW" | sed -n '2p' | cut -d'|' -f1)
        VALIDATOR_NAME=$(echo "$ALL_NEW" | sed -n '2p' | cut -d'|' -f2)
        VALIDATOR_EXISTS="true"
    fi
    if [ "$PROCESSOR_EXISTS" = "false" ] && [ -n "$ALL_NEW" ] && [ "$NEW_COUNT" -ge 3 ]; then
        PROCESSOR_ID=$(echo "$ALL_NEW" | sed -n '3p' | cut -d'|' -f1)
        PROCESSOR_NAME=$(echo "$ALL_NEW" | sed -n '3p' | cut -d'|' -f2)
        PROCESSOR_EXISTS="true"
    fi
fi

# ── 4. Analyze channel XML ──────────────────────────────────────────────────

# Census channel
if [ -n "$CENSUS_ID" ]; then
    CENSUS_XML=$(query_postgres "SELECT channel FROM channel WHERE id='$CENSUS_ID';" 2>/dev/null || true)
    CENSUS_PORT=$(echo "$CENSUS_XML" | python3 -c "
import sys, re
xml = sys.stdin.read()
m = re.search(r'<port>(\d+)</port>', xml)
if m: print(m.group(1))
else: print('')
" 2>/dev/null || true)

    DEPLOYED_CHECK=$(query_postgres "SELECT COUNT(*) FROM d_channels WHERE channel_id='$CENSUS_ID';" 2>/dev/null || echo "0")
    if [ "$DEPLOYED_CHECK" -gt 0 ] 2>/dev/null; then
        CENSUS_STATUS="deployed"
    fi
    API_STATUS=$(get_channel_status_api "$CENSUS_ID" 2>/dev/null || echo "UNKNOWN")
    if [ "$API_STATUS" != "UNKNOWN" ] && [ -n "$API_STATUS" ]; then
        CENSUS_STATUS="$API_STATUS"
    fi
fi

# Validator channel
if [ -n "$VALIDATOR_ID" ]; then
    VALIDATOR_XML=$(query_postgres "SELECT channel FROM channel WHERE id='$VALIDATOR_ID';" 2>/dev/null || true)
    VALIDATOR_PORT=$(echo "$VALIDATOR_XML" | python3 -c "
import sys, re
xml = sys.stdin.read()
m = re.search(r'<port>(\d+)</port>', xml)
if m: print(m.group(1))
else: print('')
" 2>/dev/null || true)

    # Check for JavaScript transformer with DB lookup
    if echo "$VALIDATOR_XML" | grep -qi "JAVASCRIPT\|DatabaseConnectionFactory\|active_census\|channelMap"; then
        VALIDATOR_HAS_JS="true"
    fi

    # Check for Channel Writer destination
    if echo "$VALIDATOR_XML" | grep -qi "ChannelDispatcherProperties\|channelDispatcher"; then
        VALIDATOR_HAS_CHANNEL_WRITER="true"
    fi

    # Check for DB Writer for rejected messages
    if echo "$VALIDATOR_XML" | grep -qi "rejected_results\|DatabaseDispatcher"; then
        VALIDATOR_HAS_DB_REJECT="true"
    fi

    DEPLOYED_CHECK=$(query_postgres "SELECT COUNT(*) FROM d_channels WHERE channel_id='$VALIDATOR_ID';" 2>/dev/null || echo "0")
    if [ "$DEPLOYED_CHECK" -gt 0 ] 2>/dev/null; then
        VALIDATOR_STATUS="deployed"
    fi
    API_STATUS=$(get_channel_status_api "$VALIDATOR_ID" 2>/dev/null || echo "UNKNOWN")
    if [ "$API_STATUS" != "UNKNOWN" ] && [ -n "$API_STATUS" ]; then
        VALIDATOR_STATUS="$API_STATUS"
    fi
fi

# Processor channel
if [ -n "$PROCESSOR_ID" ]; then
    PROCESSOR_XML=$(query_postgres "SELECT channel FROM channel WHERE id='$PROCESSOR_ID';" 2>/dev/null || true)

    if echo "$PROCESSOR_XML" | grep -qi "DatabaseDispatcher\|lab_results"; then
        PROCESSOR_HAS_DB_WRITER="true"
    fi
    if echo "$PROCESSOR_XML" | grep -qi "FileDispatcher\|critical_alerts"; then
        PROCESSOR_HAS_FILE_WRITER="true"
    fi

    DEPLOYED_CHECK=$(query_postgres "SELECT COUNT(*) FROM d_channels WHERE channel_id='$PROCESSOR_ID';" 2>/dev/null || echo "0")
    if [ "$DEPLOYED_CHECK" -gt 0 ] 2>/dev/null; then
        PROCESSOR_STATUS="deployed"
    fi
    API_STATUS=$(get_channel_status_api "$PROCESSOR_ID" 2>/dev/null || echo "UNKNOWN")
    if [ "$API_STATUS" != "UNKNOWN" ] && [ -n "$API_STATUS" ]; then
        PROCESSOR_STATUS="$API_STATUS"
    fi
fi

echo "Census: $CENSUS_NAME (port:$CENSUS_PORT, status:$CENSUS_STATUS)"
echo "Validator: $VALIDATOR_NAME (port:$VALIDATOR_PORT, js:$VALIDATOR_HAS_JS, cw:$VALIDATOR_HAS_CHANNEL_WRITER, status:$VALIDATOR_STATUS)"
echo "Processor: $PROCESSOR_NAME (db:$PROCESSOR_HAS_DB_WRITER, file:$PROCESSOR_HAS_FILE_WRITER, status:$PROCESSOR_STATUS)"

# ── 5. Functional test: send MLLP messages in order ─────────────────────────

# Step 1: Send ADT A01 (admit patient) to census channel
echo "Sending ADT A01 admit to port 6661..."
ACK_ADT=$(send_mllp_capture /home/ga/sample_adt_a01_admit.hl7 6661)
echo "ADT ACK: $ACK_ADT"

# Wait for census processing
sleep 8

# Step 2: Send ORU messages to validator channel
echo "Sending critical ORU (MRN-3001) to port 6662..."
ACK_ORU_CRITICAL=$(send_mllp_capture /home/ga/sample_oru_critical.hl7 6662)
echo "Critical ORU ACK: $ACK_ORU_CRITICAL"
sleep 3

echo "Sending unknown ORU (MRN-9999) to port 6662..."
ACK_ORU_UNKNOWN=$(send_mllp_capture /home/ga/sample_oru_unknown.hl7 6662)
echo "Unknown ORU response: $ACK_ORU_UNKNOWN"
sleep 3

echo "Sending normal ORU (MRN-3001) to port 6662..."
ACK_ORU_NORMAL=$(send_mllp_capture /home/ga/sample_oru_normal.hl7 6662)
echo "Normal ORU ACK: $ACK_ORU_NORMAL"

# Wait for all processing to complete
sleep 12

# ── 6. Query database tables ────────────────────────────────────────────────

# Table existence
CENSUS_TABLE_EXISTS="false"
LAB_TABLE_EXISTS="false"
ALERTS_TABLE_EXISTS="false"
REJECTED_TABLE_EXISTS="false"

CT_CHECK=$(query_postgres "SELECT COUNT(*) FROM information_schema.tables WHERE table_name='active_census';" 2>/dev/null || echo "0")
[ "$CT_CHECK" -gt 0 ] 2>/dev/null && CENSUS_TABLE_EXISTS="true"

LT_CHECK=$(query_postgres "SELECT COUNT(*) FROM information_schema.tables WHERE table_name='lab_results';" 2>/dev/null || echo "0")
[ "$LT_CHECK" -gt 0 ] 2>/dev/null && LAB_TABLE_EXISTS="true"

AT_CHECK=$(query_postgres "SELECT COUNT(*) FROM information_schema.tables WHERE table_name='critical_alerts';" 2>/dev/null || echo "0")
[ "$AT_CHECK" -gt 0 ] 2>/dev/null && ALERTS_TABLE_EXISTS="true"

RT_CHECK=$(query_postgres "SELECT COUNT(*) FROM information_schema.tables WHERE table_name='rejected_results';" 2>/dev/null || echo "0")
[ "$RT_CHECK" -gt 0 ] 2>/dev/null && REJECTED_TABLE_EXISTS="true"

echo "Tables: census=$CENSUS_TABLE_EXISTS lab=$LAB_TABLE_EXISTS alerts=$ALERTS_TABLE_EXISTS rejected=$REJECTED_TABLE_EXISTS"

# Census data
MRN3001_IN_CENSUS=0
MRN3001_CENSUS_STATUS=""
if [ "$CENSUS_TABLE_EXISTS" = "true" ]; then
    MRN3001_IN_CENSUS=$(query_postgres "SELECT COUNT(*) FROM active_census WHERE mrn='MRN-3001';" 2>/dev/null || echo "0")
    MRN3001_CENSUS_STATUS=$(query_postgres "SELECT status FROM active_census WHERE mrn='MRN-3001' LIMIT 1;" 2>/dev/null || echo "")
fi
echo "Census: MRN-3001 count=$MRN3001_IN_CENSUS status=$MRN3001_CENSUS_STATUS"

# Lab results data
MRN3001_IN_LAB=0
MRN9999_IN_LAB=0
if [ "$LAB_TABLE_EXISTS" = "true" ]; then
    MRN3001_IN_LAB=$(query_postgres "SELECT COUNT(*) FROM lab_results WHERE mrn='MRN-3001';" 2>/dev/null || echo "0")
    MRN9999_IN_LAB=$(query_postgres "SELECT COUNT(*) FROM lab_results WHERE mrn='MRN-9999';" 2>/dev/null || echo "0")
fi
echo "Lab results: MRN-3001=$MRN3001_IN_LAB MRN-9999=$MRN9999_IN_LAB"

# Critical alerts data
MRN3001_IN_ALERTS=0
ALERT_PHYSICIAN=""
ALERT_DEPARTMENT=""
if [ "$ALERTS_TABLE_EXISTS" = "true" ]; then
    MRN3001_IN_ALERTS=$(query_postgres "SELECT COUNT(*) FROM critical_alerts WHERE mrn='MRN-3001';" 2>/dev/null || echo "0")
    ALERT_PHYSICIAN=$(query_postgres "SELECT physician FROM critical_alerts WHERE mrn='MRN-3001' LIMIT 1;" 2>/dev/null || echo "")
    ALERT_DEPARTMENT=$(query_postgres "SELECT department FROM critical_alerts WHERE mrn='MRN-3001' LIMIT 1;" 2>/dev/null || echo "")
fi
echo "Critical alerts: MRN-3001=$MRN3001_IN_ALERTS physician=$ALERT_PHYSICIAN dept=$ALERT_DEPARTMENT"

# Rejected results data
MRN9999_IN_REJECTED=0
if [ "$REJECTED_TABLE_EXISTS" = "true" ]; then
    MRN9999_IN_REJECTED=$(query_postgres "SELECT COUNT(*) FROM rejected_results WHERE mrn='MRN-9999';" 2>/dev/null || echo "0")
fi
echo "Rejected: MRN-9999=$MRN9999_IN_REJECTED"

# ── 7. Check alert files ────────────────────────────────────────────────────

ALERT_FILE_COUNT=0
ALERT_FILE_CONTENT=""

# Check inside Docker container
ALERT_FILE_COUNT=$(docker exec nextgen-connect sh -c 'ls /tmp/critical_alerts/ 2>/dev/null | wc -l' 2>/dev/null || echo "0")
if [ "$ALERT_FILE_COUNT" -gt 0 ] 2>/dev/null; then
    ALERT_FILE_CONTENT=$(docker exec nextgen-connect sh -c 'cat /tmp/critical_alerts/* 2>/dev/null | head -200' 2>/dev/null || echo "")
fi
echo "Alert files: count=$ALERT_FILE_COUNT"

# ── 8. Write result JSON ────────────────────────────────────────────────────

ACK_ADT_ESCAPED=$(json_escape "$ACK_ADT")
ACK_ORU_CRITICAL_ESCAPED=$(json_escape "$ACK_ORU_CRITICAL")
ACK_ORU_UNKNOWN_ESCAPED=$(json_escape "$ACK_ORU_UNKNOWN")
ACK_ORU_NORMAL_ESCAPED=$(json_escape "$ACK_ORU_NORMAL")
ALERT_CONTENT_ESCAPED=$(json_escape "$ALERT_FILE_CONTENT")
ALERT_PHYSICIAN_ESCAPED=$(json_escape "$ALERT_PHYSICIAN")
ALERT_DEPARTMENT_ESCAPED=$(json_escape "$ALERT_DEPARTMENT")
MRN3001_STATUS_ESCAPED=$(json_escape "$MRN3001_CENSUS_STATUS")

JSON_CONTENT=$(cat <<EOF
{
    "initial_count": $INITIAL,
    "current_count": $CURRENT,
    "census_channel_exists": $CENSUS_EXISTS,
    "census_channel_id": "$CENSUS_ID",
    "census_channel_name": "$CENSUS_NAME",
    "census_channel_status": "$CENSUS_STATUS",
    "census_channel_port": "$CENSUS_PORT",
    "validator_channel_exists": $VALIDATOR_EXISTS,
    "validator_channel_id": "$VALIDATOR_ID",
    "validator_channel_name": "$VALIDATOR_NAME",
    "validator_channel_status": "$VALIDATOR_STATUS",
    "validator_channel_port": "$VALIDATOR_PORT",
    "validator_has_js_transformer": $VALIDATOR_HAS_JS,
    "validator_has_channel_writer": $VALIDATOR_HAS_CHANNEL_WRITER,
    "validator_has_db_reject": $VALIDATOR_HAS_DB_REJECT,
    "processor_channel_exists": $PROCESSOR_EXISTS,
    "processor_channel_id": "$PROCESSOR_ID",
    "processor_channel_name": "$PROCESSOR_NAME",
    "processor_channel_status": "$PROCESSOR_STATUS",
    "processor_has_db_writer": $PROCESSOR_HAS_DB_WRITER,
    "processor_has_file_writer": $PROCESSOR_HAS_FILE_WRITER,
    "census_table_exists": $CENSUS_TABLE_EXISTS,
    "lab_results_table_exists": $LAB_TABLE_EXISTS,
    "critical_alerts_table_exists": $ALERTS_TABLE_EXISTS,
    "rejected_results_table_exists": $REJECTED_TABLE_EXISTS,
    "mrn3001_in_census": $MRN3001_IN_CENSUS,
    "mrn3001_census_status": "$MRN3001_STATUS_ESCAPED",
    "mrn3001_in_lab_results": $MRN3001_IN_LAB,
    "mrn9999_in_lab_results": $MRN9999_IN_LAB,
    "mrn3001_in_critical_alerts": $MRN3001_IN_ALERTS,
    "mrn9999_in_rejected": $MRN9999_IN_REJECTED,
    "alert_physician": "$ALERT_PHYSICIAN_ESCAPED",
    "alert_department": "$ALERT_DEPARTMENT_ESCAPED",
    "alert_file_count": $ALERT_FILE_COUNT,
    "alert_file_content": "$ALERT_CONTENT_ESCAPED",
    "ack_adt_response": "$ACK_ADT_ESCAPED",
    "ack_oru_critical": "$ACK_ORU_CRITICAL_ESCAPED",
    "ack_oru_unknown": "$ACK_ORU_UNKNOWN_ESCAPED",
    "ack_oru_normal": "$ACK_ORU_NORMAL_ESCAPED",
    "timestamp": "$(date -Iseconds)"
}
EOF
)

write_result_json "/tmp/adt_census_pipeline_result.json" "$JSON_CONTENT"

echo "Result saved to /tmp/adt_census_pipeline_result.json"
cat /tmp/adt_census_pipeline_result.json
echo "=== Export complete ==="
