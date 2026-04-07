#!/bin/bash
echo "=== Exporting Task Results ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Capture final screenshot
take_screenshot /tmp/task_final.png

# 1. Check Channel Existence
CHANNEL_NAME="NK1_to_JSON"
CHANNEL_ID=$(get_channel_id "$CHANNEL_NAME")
CHANNEL_EXISTS="false"
CHANNEL_STATUS="UNKNOWN"
PORT_6661_OPEN="false"

if [ -n "$CHANNEL_ID" ]; then
    CHANNEL_EXISTS="true"
    CHANNEL_STATUS=$(get_channel_status_api "$CHANNEL_ID")
fi

# 2. Check if Port 6661 is open (listening)
if netstat -tuln | grep -q ":6661 "; then
    PORT_6661_OPEN="true"
fi

# 3. Check Output Files
# We look for any JSON files created in the output directory
OUTPUT_DIR="/home/ga/json_out"
FILE_COUNT=$(ls -1 "$OUTPUT_DIR"/*.json 2>/dev/null | wc -l)
LATEST_FILE=$(ls -t "$OUTPUT_DIR"/*.json 2>/dev/null | head -n1)

SAMPLE_OUTPUT_CONTENT=""
if [ -n "$LATEST_FILE" ]; then
    SAMPLE_OUTPUT_CONTENT=$(cat "$LATEST_FILE" | head -c 1000) # Cap size
fi

# 4. Check if agent ran the sample test (using the provided sample data)
# The sample patient ID is PT89455
SAMPLE_TEST_FILE="$OUTPUT_DIR/PT89455_contacts.json"
SAMPLE_TEST_EXISTS="false"
if [ -f "$SAMPLE_TEST_FILE" ]; then
    SAMPLE_TEST_EXISTS="true"
fi

# Create JSON result
# Note: Verification mainly happens in verifier.py via active probe,
# but this export provides static evidence.
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "channel_exists": $CHANNEL_EXISTS,
    "channel_id": "$CHANNEL_ID",
    "channel_status": "$CHANNEL_STATUS",
    "port_6661_open": $PORT_6661_OPEN,
    "output_file_count": $FILE_COUNT,
    "sample_test_file_exists": $SAMPLE_TEST_EXISTS,
    "latest_file_content": $(echo "$SAMPLE_OUTPUT_CONTENT" | jq -R -s '.')
}
EOF

# Save result with permissions
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Exported result to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="