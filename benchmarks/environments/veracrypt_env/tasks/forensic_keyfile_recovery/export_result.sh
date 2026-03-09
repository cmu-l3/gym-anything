#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Exporting Forensic Keyfile Recovery Results ==="

# Paths
RECOVERED_FILE="/home/ga/recovered_data/prototype_specs.txt"
REPORT_FILE="/home/ga/recovered_data/keyfile_name.txt"
GROUND_TRUTH_DIR="/var/lib/app/ground_truth"

# 1. Check Recovered File
FILE_EXISTS="false"
FILE_HASH=""
if [ -f "$RECOVERED_FILE" ]; then
    FILE_EXISTS="true"
    FILE_HASH=$(md5sum "$RECOVERED_FILE" | awk '{print $1}')
fi

# 2. Check Keyfile Identification Report
REPORT_EXISTS="false"
REPORTED_KEYFILE=""
if [ -f "$REPORT_FILE" ]; then
    REPORT_EXISTS="true"
    # Read first line, trim whitespace
    REPORTED_KEYFILE=$(head -n 1 "$REPORT_FILE" | tr -d '[:space:]')
fi

# 3. Get Ground Truth Data (Safe to read now as task is over)
EXPECTED_HASH=$(cat "$GROUND_TRUTH_DIR/specs_hash.md5" 2>/dev/null || echo "")
ACTUAL_KEYFILE=$(cat "$GROUND_TRUTH_DIR/correct_keyfile.txt" 2>/dev/null || echo "")

# 4. Check if Volume is Mounted (Bonus signal)
VOLUME_MOUNTED="false"
MOUNT_LIST=$(veracrypt --text --list --non-interactive 2>&1 || echo "")
if echo "$MOUNT_LIST" | grep -q "design_specs.hc"; then
    VOLUME_MOUNTED="true"
fi

# 5. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 6. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "file_exists": $FILE_EXISTS,
    "file_hash": "$FILE_HASH",
    "expected_hash": "$EXPECTED_HASH",
    "report_exists": $REPORT_EXISTS,
    "reported_keyfile": "$REPORTED_KEYFILE",
    "actual_keyfile": "$ACTUAL_KEYFILE",
    "volume_mounted": $VOLUME_MOUNTED,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Save result with proper permissions
write_result_json "/tmp/task_result.json" "$(cat $TEMP_JSON)"
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json

echo "=== Export Complete ==="