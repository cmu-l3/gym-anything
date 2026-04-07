#!/bin/bash
echo "=== Exporting task results ==="
source /workspace/scripts/task_utils.sh

# Take final state screenshot
take_screenshot /tmp/task_phantom_final.png

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Authenticate with API to get current state
ac_login
PHANTOM_DATA=$(ac_api GET "/users" | jq -c '.[] | select(.email != null and (.email | contains("@external-vendor.net")))' 2>/dev/null)

PHANTOM_EXISTS="false"
PHANTOM_CARD="null"
PHANTOM_COMPANY="null"

if [ -n "$PHANTOM_DATA" ] && [ "$PHANTOM_DATA" != "null" ]; then
    PHANTOM_EXISTS="true"
    # Extract values, handling both null literal and missing fields
    PHANTOM_CARD=$(echo "$PHANTOM_DATA" | jq -r '.cardNumber // "null"')
    PHANTOM_COMPANY=$(echo "$PHANTOM_DATA" | jq -r '.company // "null"')
fi

# Check for the extracted card file
EXTRACTED_CARD=""
FILE_EXISTS="false"
FILE_MTIME="0"

if [ -f "/home/ga/compromised_card.txt" ]; then
    FILE_EXISTS="true"
    # Read and sanitize the extracted card
    EXTRACTED_CARD=$(cat "/home/ga/compromised_card.txt" | tr -d '\n\r' | sed 's/"/\\"/g' | sed 's/\\//g')
    FILE_MTIME=$(stat -c %Y "/home/ga/compromised_card.txt" 2>/dev/null || echo "0")
fi

# Retrieve the hidden ground truth
GROUND_TRUTH=$(sudo cat /var/lib/app/ground_truth/phantom_card.txt 2>/dev/null || echo "MISSING")

# Create JSON result securely
TEMP_JSON=$(mktemp)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "phantom_exists": $PHANTOM_EXISTS,
    "phantom_card": "$PHANTOM_CARD",
    "phantom_company": "$PHANTOM_COMPANY",
    "file_exists": $FILE_EXISTS,
    "file_mtime": $FILE_MTIME,
    "extracted_card": "$EXTRACTED_CARD",
    "ground_truth_card": "$GROUND_TRUTH"
}
EOF

# Move to standard readable location
sudo mv "$TEMP_JSON" /tmp/task_result.json
sudo chmod 666 /tmp/task_result.json

echo "Result saved to /tmp/task_result.json:"
cat /tmp/task_result.json
echo "=== Export complete ==="