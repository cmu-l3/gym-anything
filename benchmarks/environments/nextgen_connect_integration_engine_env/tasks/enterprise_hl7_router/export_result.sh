#!/bin/bash
echo "=== Exporting enterprise_hl7_router task result ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_entrouter.png

# Get initial and current channel counts
INITIAL=$(cat /tmp/initial_entrouter_channel_count 2>/dev/null || echo "0")
CURRENT=$(get_channel_count)

echo "Initial channel count: $INITIAL"
echo "Current channel count: $CURRENT"

# Locate the three channels
FACADE_EXISTS="false"
FACADE_ID=""
FACADE_NAME=""
FACADE_STATUS="unknown"
FACADE_PORT=""
FACADE_HAS_JS_TRANSFORMER="false"
FACADE_HAS_CHANNEL_WRITERS=0
FACADE_HAS_DLQ_WRITER="false"

LAB_EXISTS="false"
LAB_ID=""
LAB_NAME=""
LAB_STATUS="unknown"
LAB_HAS_DB_WRITER="false"

ADT_EXISTS="false"
ADT_ID=""
ADT_NAME=""
ADT_STATUS="unknown"
ADT_HAS_DB_WRITER="false"

# Find Enterprise Router (facade)
FACADE_DATA=$(query_postgres "SELECT id, name FROM channel WHERE LOWER(name) LIKE '%enterprise%' OR (LOWER(name) LIKE '%router%' AND LOWER(name) LIKE '%hl7%') OR LOWER(name) LIKE '%facade%';" 2>/dev/null || true)
if [ -n "$FACADE_DATA" ]; then
    FACADE_EXISTS="true"
    FACADE_ID=$(echo "$FACADE_DATA" | head -1 | cut -d'|' -f1)
    FACADE_NAME=$(echo "$FACADE_DATA" | head -1 | cut -d'|' -f2)
    echo "Found facade channel: $FACADE_NAME (ID: $FACADE_ID)"
fi

# Find Lab Results Processor
LAB_DATA=$(query_postgres "SELECT id, name FROM channel WHERE LOWER(name) LIKE '%lab%result%' OR LOWER(name) LIKE '%lab.*processor%' OR (LOWER(name) LIKE '%lab%' AND LOWER(name) LIKE '%inbox%');" 2>/dev/null || true)
if [ -n "$LAB_DATA" ]; then
    LAB_EXISTS="true"
    LAB_ID=$(echo "$LAB_DATA" | head -1 | cut -d'|' -f1)
    LAB_NAME=$(echo "$LAB_DATA" | head -1 | cut -d'|' -f2)
    echo "Found lab channel: $LAB_NAME (ID: $LAB_ID)"
fi

# Find ADT Event Handler
ADT_DATA=$(query_postgres "SELECT id, name FROM channel WHERE (LOWER(name) LIKE '%adt%' AND (LOWER(name) LIKE '%event%' OR LOWER(name) LIKE '%handler%' OR LOWER(name) LIKE '%processor%' OR LOWER(name) LIKE '%inbox%'));" 2>/dev/null || true)
if [ -n "$ADT_DATA" ]; then
    ADT_EXISTS="true"
    ADT_ID=$(echo "$ADT_DATA" | head -1 | cut -d'|' -f1)
    ADT_NAME=$(echo "$ADT_DATA" | head -1 | cut -d'|' -f2)
    echo "Found ADT channel: $ADT_NAME (ID: $ADT_ID)"
fi

# If we created enough channels but couldn't find by name, use newest ones
if [ "$CURRENT" -gt "$INITIAL" ]; then
    NEW_COUNT=$((CURRENT - INITIAL))
    echo "$NEW_COUNT new channels created"
    ALL_NEW=$(query_postgres "SELECT id, name FROM channel ORDER BY revision DESC LIMIT $NEW_COUNT;" 2>/dev/null || true)

    if [ "$FACADE_EXISTS" = "false" ] && [ -n "$ALL_NEW" ]; then
        FACADE_ID=$(echo "$ALL_NEW" | head -1 | cut -d'|' -f1)
        FACADE_NAME=$(echo "$ALL_NEW" | head -1 | cut -d'|' -f2)
        FACADE_EXISTS="true"
    fi
    if [ "$LAB_EXISTS" = "false" ] && [ -n "$ALL_NEW" ] && [ "$NEW_COUNT" -ge 2 ]; then
        LAB_ID=$(echo "$ALL_NEW" | sed -n '2p' | cut -d'|' -f1)
        LAB_NAME=$(echo "$ALL_NEW" | sed -n '2p' | cut -d'|' -f2)
        LAB_EXISTS="true"
    fi
    if [ "$ADT_EXISTS" = "false" ] && [ -n "$ALL_NEW" ] && [ "$NEW_COUNT" -ge 3 ]; then
        ADT_ID=$(echo "$ALL_NEW" | sed -n '3p' | cut -d'|' -f1)
        ADT_NAME=$(echo "$ALL_NEW" | sed -n '3p' | cut -d'|' -f2)
        ADT_EXISTS="true"
    fi
fi

# Analyze facade channel XML
if [ -n "$FACADE_ID" ]; then
    FACADE_XML=$(query_postgres "SELECT channel FROM channel WHERE id='$FACADE_ID';" 2>/dev/null || true)

    FACADE_PORT=$(echo "$FACADE_XML" | python3 -c "
import sys, re
xml = sys.stdin.read()
m = re.search(r'<port>(\d+)</port>', xml)
if m: print(m.group(1))
else: print('')
" 2>/dev/null || true)

    # Check for JavaScript transformer with MSH field extraction
    if echo "$FACADE_XML" | grep -qi "JAVASCRIPT\|MSH.*3\|sendingApp\|messageType\|channelMap"; then
        FACADE_HAS_JS_TRANSFORMER="true"
    fi

    # Count Channel Writer destinations
    FACADE_HAS_CHANNEL_WRITERS=$(echo "$FACADE_XML" | python3 -c "
import sys, re
xml = sys.stdin.read()
count = len(re.findall(r'ChannelDispatcherProperties|channelDispatcher', xml, re.IGNORECASE))
print(count)
" 2>/dev/null || echo "0")

    # Check for DLQ database writer
    if echo "$FACADE_XML" | grep -qi "dead_letter_queue\|DatabaseDispatcher\|dlq"; then
        FACADE_HAS_DLQ_WRITER="true"
    fi

    DEPLOYED_CHECK=$(query_postgres "SELECT COUNT(*) FROM d_channels WHERE channel_id='$FACADE_ID';" 2>/dev/null || echo "0")
    if [ "$DEPLOYED_CHECK" -gt 0 ] 2>/dev/null; then
        FACADE_STATUS="deployed"
    fi
    API_STATUS=$(get_channel_status_api "$FACADE_ID" 2>/dev/null || echo "UNKNOWN")
    if [ "$API_STATUS" != "UNKNOWN" ] && [ -n "$API_STATUS" ]; then
        FACADE_STATUS="$API_STATUS"
    fi
fi

# Analyze lab channel
if [ -n "$LAB_ID" ]; then
    LAB_XML=$(query_postgres "SELECT channel FROM channel WHERE id='$LAB_ID';" 2>/dev/null || true)
    if echo "$LAB_XML" | grep -qi "DatabaseDispatcher\|lab_results_inbox"; then
        LAB_HAS_DB_WRITER="true"
    fi

    DEPLOYED_CHECK=$(query_postgres "SELECT COUNT(*) FROM d_channels WHERE channel_id='$LAB_ID';" 2>/dev/null || echo "0")
    if [ "$DEPLOYED_CHECK" -gt 0 ] 2>/dev/null; then
        LAB_STATUS="deployed"
    fi
    API_STATUS=$(get_channel_status_api "$LAB_ID" 2>/dev/null || echo "UNKNOWN")
    if [ "$API_STATUS" != "UNKNOWN" ] && [ -n "$API_STATUS" ]; then
        LAB_STATUS="$API_STATUS"
    fi
fi

# Analyze ADT channel
if [ -n "$ADT_ID" ]; then
    ADT_XML=$(query_postgres "SELECT channel FROM channel WHERE id='$ADT_ID';" 2>/dev/null || true)
    if echo "$ADT_XML" | grep -qi "DatabaseDispatcher\|adt_events_inbox"; then
        ADT_HAS_DB_WRITER="true"
    fi

    DEPLOYED_CHECK=$(query_postgres "SELECT COUNT(*) FROM d_channels WHERE channel_id='$ADT_ID';" 2>/dev/null || echo "0")
    if [ "$DEPLOYED_CHECK" -gt 0 ] 2>/dev/null; then
        ADT_STATUS="deployed"
    fi
    API_STATUS=$(get_channel_status_api "$ADT_ID" 2>/dev/null || echo "UNKNOWN")
    if [ "$API_STATUS" != "UNKNOWN" ] && [ -n "$API_STATUS" ]; then
        ADT_STATUS="$API_STATUS"
    fi
fi

# Check database tables
ROUTING_RULES_EXISTS="false"
ROUTING_RULES_COUNT=0
DLQ_EXISTS="false"
LAB_INBOX_EXISTS="false"
ADT_INBOX_EXISTS="false"

RR_CHECK=$(query_postgres "SELECT COUNT(*) FROM information_schema.tables WHERE table_name='routing_rules';" 2>/dev/null || echo "0")
if [ "$RR_CHECK" -gt 0 ] 2>/dev/null; then
    ROUTING_RULES_EXISTS="true"
    ROUTING_RULES_COUNT=$(query_postgres "SELECT COUNT(*) FROM routing_rules;" 2>/dev/null || echo "0")
fi

DLQ_CHECK=$(query_postgres "SELECT COUNT(*) FROM information_schema.tables WHERE table_name='dead_letter_queue';" 2>/dev/null || echo "0")
[ "$DLQ_CHECK" -gt 0 ] 2>/dev/null && DLQ_EXISTS="true"

LAB_CHECK=$(query_postgres "SELECT COUNT(*) FROM information_schema.tables WHERE table_name='lab_results_inbox';" 2>/dev/null || echo "0")
[ "$LAB_CHECK" -gt 0 ] 2>/dev/null && LAB_INBOX_EXISTS="true"

ADT_CHECK=$(query_postgres "SELECT COUNT(*) FROM information_schema.tables WHERE table_name='adt_events_inbox';" 2>/dev/null || echo "0")
[ "$ADT_CHECK" -gt 0 ] 2>/dev/null && ADT_INBOX_EXISTS="true"

echo "Facade: $FACADE_NAME (port: $FACADE_PORT, status: $FACADE_STATUS)"
echo "  JS transformer: $FACADE_HAS_JS_TRANSFORMER, Channel writers: $FACADE_HAS_CHANNEL_WRITERS, DLQ writer: $FACADE_HAS_DLQ_WRITER"
echo "Lab Processor: $LAB_NAME (status: $LAB_STATUS, DB writer: $LAB_HAS_DB_WRITER)"
echo "ADT Handler: $ADT_NAME (status: $ADT_STATUS, DB writer: $ADT_HAS_DB_WRITER)"
echo "routing_rules: $ROUTING_RULES_EXISTS ($ROUTING_RULES_COUNT rows), DLQ: $DLQ_EXISTS, lab_inbox: $LAB_INBOX_EXISTS, adt_inbox: $ADT_INBOX_EXISTS"

JSON_CONTENT=$(cat <<EOF
{
    "initial_count": $INITIAL,
    "current_count": $CURRENT,
    "facade_exists": $FACADE_EXISTS,
    "facade_id": "$FACADE_ID",
    "facade_name": "$FACADE_NAME",
    "facade_status": "$FACADE_STATUS",
    "facade_port": "$FACADE_PORT",
    "facade_has_js_transformer": $FACADE_HAS_JS_TRANSFORMER,
    "facade_channel_writer_count": $FACADE_HAS_CHANNEL_WRITERS,
    "facade_has_dlq_writer": $FACADE_HAS_DLQ_WRITER,
    "lab_channel_exists": $LAB_EXISTS,
    "lab_channel_id": "$LAB_ID",
    "lab_channel_name": "$LAB_NAME",
    "lab_channel_status": "$LAB_STATUS",
    "lab_has_db_writer": $LAB_HAS_DB_WRITER,
    "adt_channel_exists": $ADT_EXISTS,
    "adt_channel_id": "$ADT_ID",
    "adt_channel_name": "$ADT_NAME",
    "adt_channel_status": "$ADT_STATUS",
    "adt_has_db_writer": $ADT_HAS_DB_WRITER,
    "routing_rules_exists": $ROUTING_RULES_EXISTS,
    "routing_rules_count": $ROUTING_RULES_COUNT,
    "dlq_table_exists": $DLQ_EXISTS,
    "lab_inbox_exists": $LAB_INBOX_EXISTS,
    "adt_inbox_exists": $ADT_INBOX_EXISTS,
    "timestamp": "$(date -Iseconds)"
}
EOF
)

write_result_json "/tmp/enterprise_hl7_router_result.json" "$JSON_CONTENT"

echo "Result saved to /tmp/enterprise_hl7_router_result.json"
cat /tmp/enterprise_hl7_router_result.json
echo "=== Export complete ==="
