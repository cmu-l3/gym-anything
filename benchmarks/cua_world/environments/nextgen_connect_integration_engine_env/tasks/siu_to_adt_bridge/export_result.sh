#!/bin/bash
echo "=== Exporting siu_to_adt_bridge task result ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_siubridge.png

# Get initial and current channel counts
INITIAL=$(cat /tmp/initial_siubridge_channel_count 2>/dev/null || echo "0")
CURRENT=$(get_channel_count)

echo "Initial channel count: $INITIAL"
echo "Current channel count: $CURRENT"

# Locate both channels
SIU_CHANNEL_EXISTS="false"
SIU_CHANNEL_ID=""
SIU_CHANNEL_NAME=""
SIU_CHANNEL_STATUS="unknown"
SIU_LISTEN_PORT=""
SIU_HAS_JS_TRANSFORMER="false"
SIU_HAS_CHANNEL_WRITER="false"

ADT_CHANNEL_EXISTS="false"
ADT_CHANNEL_ID=""
ADT_CHANNEL_NAME=""
ADT_CHANNEL_STATUS="unknown"
ADT_HAS_DB_WRITER="false"

# Find SIU channel
SIU_DATA=$(query_postgres "SELECT id, name FROM channel WHERE LOWER(name) LIKE '%siu%' OR (LOWER(name) LIKE '%intake%' AND LOWER(name) LIKE '%channel%') OR LOWER(name) LIKE '%schedule%intake%';" 2>/dev/null || true)
if [ -n "$SIU_DATA" ]; then
    SIU_CHANNEL_EXISTS="true"
    SIU_CHANNEL_ID=$(echo "$SIU_DATA" | head -1 | cut -d'|' -f1)
    SIU_CHANNEL_NAME=$(echo "$SIU_DATA" | head -1 | cut -d'|' -f2)
    echo "Found SIU channel: $SIU_CHANNEL_NAME (ID: $SIU_CHANNEL_ID)"
fi

# Find ADT processor channel
ADT_DATA=$(query_postgres "SELECT id, name FROM channel WHERE LOWER(name) LIKE '%pre-reg%' OR LOWER(name) LIKE '%prereg%' OR (LOWER(name) LIKE '%adt%' AND LOWER(name) LIKE '%processor%') OR (LOWER(name) LIKE '%adt%' AND LOWER(name) LIKE '%registration%');" 2>/dev/null || true)
if [ -n "$ADT_DATA" ]; then
    ADT_CHANNEL_EXISTS="true"
    ADT_CHANNEL_ID=$(echo "$ADT_DATA" | head -1 | cut -d'|' -f1)
    ADT_CHANNEL_NAME=$(echo "$ADT_DATA" | head -1 | cut -d'|' -f2)
    echo "Found ADT channel: $ADT_CHANNEL_NAME (ID: $ADT_CHANNEL_ID)"
fi

# Fallback: look at newest channels if we have enough new ones
if [ "$CURRENT" -gt "$INITIAL" ]; then
    NEW_CHANNELS=$(query_postgres "SELECT id, name FROM channel ORDER BY revision DESC LIMIT $((CURRENT - INITIAL));" 2>/dev/null || true)
    echo "New channels created: $((CURRENT - INITIAL))"
    echo "New channels: $NEW_CHANNELS"

    # If we found 2 new channels and one has channel-writer, use them
    if [ "$SIU_CHANNEL_EXISTS" = "false" ] && [ -n "$NEW_CHANNELS" ]; then
        SIU_CHANNEL_ID=$(echo "$NEW_CHANNELS" | head -1 | cut -d'|' -f1)
        SIU_CHANNEL_NAME=$(echo "$NEW_CHANNELS" | head -1 | cut -d'|' -f2)
        SIU_CHANNEL_EXISTS="true"
    fi
    if [ "$ADT_CHANNEL_EXISTS" = "false" ] && [ -n "$NEW_CHANNELS" ]; then
        ADT_LINE=$(echo "$NEW_CHANNELS" | sed -n '2p')
        if [ -n "$ADT_LINE" ]; then
            ADT_CHANNEL_ID=$(echo "$ADT_LINE" | cut -d'|' -f1)
            ADT_CHANNEL_NAME=$(echo "$ADT_LINE" | cut -d'|' -f2)
            ADT_CHANNEL_EXISTS="true"
        fi
    fi
fi

# Analyze SIU channel
if [ -n "$SIU_CHANNEL_ID" ]; then
    SIU_XML=$(query_postgres "SELECT channel FROM channel WHERE id='$SIU_CHANNEL_ID';" 2>/dev/null || true)

    SIU_LISTEN_PORT=$(echo "$SIU_XML" | python3 -c "
import sys, re
xml = sys.stdin.read()
m = re.search(r'<port>(\d+)</port>', xml)
if m: print(m.group(1))
else: print('')
" 2>/dev/null || true)

    # Check for JavaScript transformer with SIU/SCH field mapping
    if echo "$SIU_XML" | grep -qi "JAVASCRIPT\|SIU\|SCH\|ADT.*A04\|transformedADT\|channelMap"; then
        SIU_HAS_JS_TRANSFORMER="true"
    fi

    # Check for Channel Writer destination
    if echo "$SIU_XML" | grep -qi "ChannelDispatcherProperties\|channelDispatcher\|Channel Writer\|channel.*writer"; then
        SIU_HAS_CHANNEL_WRITER="true"
    fi

    DEPLOYED_CHECK=$(query_postgres "SELECT COUNT(*) FROM d_channels WHERE channel_id='$SIU_CHANNEL_ID';" 2>/dev/null || echo "0")
    if [ "$DEPLOYED_CHECK" -gt 0 ] 2>/dev/null; then
        SIU_CHANNEL_STATUS="deployed"
    fi
    API_STATUS=$(get_channel_status_api "$SIU_CHANNEL_ID" 2>/dev/null || echo "UNKNOWN")
    if [ "$API_STATUS" != "UNKNOWN" ] && [ -n "$API_STATUS" ]; then
        SIU_CHANNEL_STATUS="$API_STATUS"
    fi
fi

# Analyze ADT channel
if [ -n "$ADT_CHANNEL_ID" ]; then
    ADT_XML=$(query_postgres "SELECT channel FROM channel WHERE id='$ADT_CHANNEL_ID';" 2>/dev/null || true)

    if echo "$ADT_XML" | grep -qi "DatabaseDispatcher\|scheduling_preregistrations\|jdbc:postgresql"; then
        ADT_HAS_DB_WRITER="true"
    fi

    DEPLOYED_CHECK=$(query_postgres "SELECT COUNT(*) FROM d_channels WHERE channel_id='$ADT_CHANNEL_ID';" 2>/dev/null || echo "0")
    if [ "$DEPLOYED_CHECK" -gt 0 ] 2>/dev/null; then
        ADT_CHANNEL_STATUS="deployed"
    fi
    API_STATUS=$(get_channel_status_api "$ADT_CHANNEL_ID" 2>/dev/null || echo "UNKNOWN")
    if [ "$API_STATUS" != "UNKNOWN" ] && [ -n "$API_STATUS" ]; then
        ADT_CHANNEL_STATUS="$API_STATUS"
    fi
fi

# Check scheduling_preregistrations table
PREREG_TABLE_EXISTS="false"
PREREG_ROW_COUNT=0

PREREG_CHECK=$(query_postgres "SELECT COUNT(*) FROM information_schema.tables WHERE table_name='scheduling_preregistrations';" 2>/dev/null || echo "0")
if [ "$PREREG_CHECK" -gt 0 ] 2>/dev/null; then
    PREREG_TABLE_EXISTS="true"
    PREREG_ROW_COUNT=$(query_postgres "SELECT COUNT(*) FROM scheduling_preregistrations;" 2>/dev/null || echo "0")
fi

echo "SIU channel: $SIU_CHANNEL_NAME (port: $SIU_LISTEN_PORT, status: $SIU_CHANNEL_STATUS)"
echo "  JS transformer: $SIU_HAS_JS_TRANSFORMER, Channel writer: $SIU_HAS_CHANNEL_WRITER"
echo "ADT channel: $ADT_CHANNEL_NAME (status: $ADT_CHANNEL_STATUS)"
echo "  DB writer: $ADT_HAS_DB_WRITER"
echo "scheduling_preregistrations: $PREREG_TABLE_EXISTS ($PREREG_ROW_COUNT rows)"

JSON_CONTENT=$(cat <<EOF
{
    "initial_count": $INITIAL,
    "current_count": $CURRENT,
    "siu_channel_exists": $SIU_CHANNEL_EXISTS,
    "siu_channel_id": "$SIU_CHANNEL_ID",
    "siu_channel_name": "$SIU_CHANNEL_NAME",
    "siu_channel_status": "$SIU_CHANNEL_STATUS",
    "siu_listen_port": "$SIU_LISTEN_PORT",
    "siu_has_js_transformer": $SIU_HAS_JS_TRANSFORMER,
    "siu_has_channel_writer": $SIU_HAS_CHANNEL_WRITER,
    "adt_channel_exists": $ADT_CHANNEL_EXISTS,
    "adt_channel_id": "$ADT_CHANNEL_ID",
    "adt_channel_name": "$ADT_CHANNEL_NAME",
    "adt_channel_status": "$ADT_CHANNEL_STATUS",
    "adt_has_db_writer": $ADT_HAS_DB_WRITER,
    "prereg_table_exists": $PREREG_TABLE_EXISTS,
    "prereg_row_count": $PREREG_ROW_COUNT,
    "timestamp": "$(date -Iseconds)"
}
EOF
)

write_result_json "/tmp/siu_to_adt_bridge_result.json" "$JSON_CONTENT"

echo "Result saved to /tmp/siu_to_adt_bridge_result.json"
cat /tmp/siu_to_adt_bridge_result.json
echo "=== Export complete ==="
