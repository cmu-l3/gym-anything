#!/bin/bash
echo "=== Exporting csv_batch_to_hl7_transformation result ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end.png

# 1. Check if output files exist inside the container
# We copy them out to analyze content
mkdir -p /tmp/verification_output
docker cp nextgen-connect:/tmp/hl7_output/. /tmp/verification_output/ 2>/dev/null || true

OUTPUT_FILE_COUNT=$(find /tmp/verification_output -name "*.hl7" | wc -l)
echo "Found $OUTPUT_FILE_COUNT HL7 output files."

# 2. Extract content from the first generated HL7 file for validation
FIRST_HL7_FILE=$(find /tmp/verification_output -name "*.hl7" | head -1)
SAMPLE_CONTENT=""
if [ -n "$FIRST_HL7_FILE" ]; then
    SAMPLE_CONTENT=$(cat "$FIRST_HL7_FILE")
fi

# 3. Check Channel Configuration via DB
# We need to verify:
# - Channel exists
# - Source is File Reader
# - Batch processing is enabled
# - Data type is Delimited
# - Destination is File Writer

CHANNEL_ID=""
CHANNEL_NAME=""
IS_BATCH="false"
IS_CSV="false"
IS_FILE_READER="false"

# Get the most recently modified channel
LATEST_CHANNEL=$(query_postgres "SELECT id, name, channel FROM channel ORDER BY revision DESC LIMIT 1;" 2>/dev/null || true)

if [ -n "$LATEST_CHANNEL" ]; then
    CHANNEL_ID=$(echo "$LATEST_CHANNEL" | cut -d'|' -f1)
    CHANNEL_NAME=$(echo "$LATEST_CHANNEL" | cut -d'|' -f2)
    CHANNEL_XML=$(echo "$LATEST_CHANNEL" | cut -d'|' -f3-)

    # Check for File Reader
    if echo "$CHANNEL_XML" | grep -qi "com.mirth.connect.connectors.file.FileReceiverProperties"; then
        IS_FILE_READER="true"
    fi

    # Check for Batch Processing enabled
    # Look for <processBatch>true</processBatch> inside properties
    if echo "$CHANNEL_XML" | grep -qi "<processBatch>true</processBatch>"; then
        IS_BATCH="true"
    fi

    # Check for Delimited Text data type (CSV)
    # Look for DelimitedDataTypeProperties
    if echo "$CHANNEL_XML" | grep -qi "DelimitedDataTypeProperties"; then
        IS_CSV="true"
    fi
fi

# 4. Check if channel was deployed
CHANNEL_DEPLOYED="false"
if [ -n "$CHANNEL_ID" ]; then
    DEPLOY_COUNT=$(query_postgres "SELECT COUNT(*) FROM d_channels WHERE channel_id='$CHANNEL_ID';" 2>/dev/null || echo "0")
    if [ "$DEPLOY_COUNT" -gt 0 ]; then
        CHANNEL_DEPLOYED="true"
    fi
fi

# 5. Create JSON Result
# We need to escape the sample content for JSON
SAFE_SAMPLE=$(echo "$SAMPLE_CONTENT" | jq -R '.')

JSON_CONTENT=$(cat <<EOF
{
    "output_file_count": $OUTPUT_FILE_COUNT,
    "channel_found": $([ -n "$CHANNEL_ID" ] && echo "true" || echo "false"),
    "channel_name": "$CHANNEL_NAME",
    "config_is_file_reader": $IS_FILE_READER,
    "config_is_batch": $IS_BATCH,
    "config_is_csv": $IS_CSV,
    "channel_deployed": $CHANNEL_DEPLOYED,
    "sample_hl7_content": $SAFE_SAMPLE,
    "timestamp": "$(date -Iseconds)"
}
EOF
)

write_result_json "/tmp/csv_batch_result.json" "$JSON_CONTENT"

# Cleanup
rm -rf /tmp/verification_output

echo "Result saved to /tmp/csv_batch_result.json"
cat /tmp/csv_batch_result.json
echo "=== Export complete ==="