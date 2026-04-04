#!/bin/bash
echo "=== Exporting transform_hl7_format task result ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end.png

# Get initial and current channel counts
INITIAL=$(cat /tmp/initial_transformer_channel_count 2>/dev/null || echo "0")
CURRENT=$(get_channel_count)

echo "Initial channel count: $INITIAL"
echo "Current channel count: $CURRENT"

# Check for transformer channel
TRANSFORMER_EXISTS="false"
CHANNEL_ID=""
CHANNEL_NAME=""
HAS_TRANSFORMER="false"
OUTPUT_FORMAT=""

# Query for channels with "transformer" or "transform" in the name
TRANSFORMER_QUERY="SELECT id, name FROM channel WHERE LOWER(name) LIKE '%transform%';"
TRANSFORMER_DATA=$(query_postgres "$TRANSFORMER_QUERY" 2>/dev/null || true)

if [ -n "$TRANSFORMER_DATA" ]; then
    TRANSFORMER_EXISTS="true"
    CHANNEL_ID=$(echo "$TRANSFORMER_DATA" | head -1 | cut -d'|' -f1)
    CHANNEL_NAME=$(echo "$TRANSFORMER_DATA" | head -1 | cut -d'|' -f2)
    echo "Found transformer channel: $CHANNEL_NAME (ID: $CHANNEL_ID)"

    # Check channel XML for transformer elements
    CHANNEL_XML=$(query_postgres "SELECT channel FROM channel WHERE id='$CHANNEL_ID';" 2>/dev/null || true)
    if echo "$CHANNEL_XML" | grep -qi "transformer.*element\|JavaScript\|SerializerFactory\|msg\.\|XML"; then
        HAS_TRANSFORMER="true"
    fi

    # Try to detect output format from channel config
    if echo "$CHANNEL_XML" | grep -qi "outboundDataType.*XML\|HL7V2.*XML\|toXML\|xml"; then
        OUTPUT_FORMAT="XML"
    fi
fi

# If exact match not found, check for any new channel
if [ "$TRANSFORMER_EXISTS" = "false" ] && [ "$CURRENT" -gt "$INITIAL" ]; then
    echo "New channel detected, checking if it's a transformer..."
    LATEST_CHANNEL="SELECT id, name FROM channel ORDER BY id DESC LIMIT 1;"
    LATEST_DATA=$(query_postgres "$LATEST_CHANNEL" 2>/dev/null || true)

    if [ -n "$LATEST_DATA" ]; then
        TRANSFORMER_EXISTS="true"
        CHANNEL_ID=$(echo "$LATEST_DATA" | head -1 | cut -d'|' -f1)
        CHANNEL_NAME=$(echo "$LATEST_DATA" | head -1 | cut -d'|' -f2)
        echo "Found latest channel: $CHANNEL_NAME (ID: $CHANNEL_ID)"
        HAS_TRANSFORMER="possible"
    fi
fi

# Check for transformed output files - both on host and in docker container
TRANSFORMED_OUTPUT="false"
# Check host filesystem
if [ -d "/home/ga/transformer_output" ]; then
    HOST_COUNT=$(ls -1 /home/ga/transformer_output/ 2>/dev/null | wc -l || echo "0")
    if [ "$HOST_COUNT" -gt 0 ] 2>/dev/null; then
        TRANSFORMED_OUTPUT="true"
        echo "Found $HOST_COUNT output file(s) on host"
    fi
fi
# Check docker container
DOCKER_COUNT=$(docker exec nextgen-connect ls /home/ga/transformer_output/ 2>/dev/null | wc -l || echo "0")
if [ "$DOCKER_COUNT" -gt 0 ] 2>/dev/null; then
    TRANSFORMED_OUTPUT="true"
    echo "Found $DOCKER_COUNT output file(s) in docker container"
fi

# Detect output format from files
if [ "$TRANSFORMED_OUTPUT" = "true" ]; then
    # Check if output files are XML
    SAMPLE_FILE=""
    if [ -d "/home/ga/transformer_output" ]; then
        SAMPLE_FILE=$(ls /home/ga/transformer_output/ 2>/dev/null | head -1)
        if [ -n "$SAMPLE_FILE" ]; then
            FIRST_CHAR=$(head -c 1 "/home/ga/transformer_output/$SAMPLE_FILE" 2>/dev/null || true)
            if [ "$FIRST_CHAR" = "<" ]; then
                OUTPUT_FORMAT="XML"
            fi
        fi
    fi
fi

# Create JSON result
JSON_CONTENT=$(cat <<EOF
{
    "initial_count": $INITIAL,
    "current_count": $CURRENT,
    "transformer_exists": $TRANSFORMER_EXISTS,
    "channel_id": "$CHANNEL_ID",
    "channel_name": "$CHANNEL_NAME",
    "has_transformer": "$HAS_TRANSFORMER",
    "output_format": "$OUTPUT_FORMAT",
    "transformed_output": $TRANSFORMED_OUTPUT,
    "timestamp": "$(date -Iseconds)"
}
EOF
)

# Write result with permission handling
write_result_json "/tmp/transform_hl7_format_result.json" "$JSON_CONTENT"

echo "Result saved to /tmp/transform_hl7_format_result.json"
cat /tmp/transform_hl7_format_result.json
echo "=== Export complete ==="
