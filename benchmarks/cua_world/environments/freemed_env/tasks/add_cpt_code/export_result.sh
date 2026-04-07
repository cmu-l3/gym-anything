#!/bin/bash
echo "=== Exporting add_cpt_code result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_cpt_end.png

# Get current CPT count for anti-gaming verification
CURRENT_COUNT=$(freemed_query "SELECT COUNT(*) FROM cpt" 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_cpt_count.txt 2>/dev/null || echo "0")

echo "CPT count: initial=$INITIAL_COUNT, current=$CURRENT_COUNT"

# Query for the specific CPT code added
# FreeMED query utility handles direct MySQL connection using -N -e 
CPT_DATA=$(freemed_query "SELECT id, cptcode, cptnameint, cptnameext FROM cpt WHERE cptcode='99214' ORDER BY id DESC LIMIT 1" 2>/dev/null)

CPT_FOUND="false"
CPT_ID=""
CPT_CODE=""
CPT_NAME_INT=""
CPT_NAME_EXT=""

if [ -n "$CPT_DATA" ]; then
    CPT_FOUND="true"
    CPT_ID=$(echo "$CPT_DATA" | cut -f1)
    CPT_CODE=$(echo "$CPT_DATA" | cut -f2)
    CPT_NAME_INT=$(echo "$CPT_DATA" | cut -f3)
    CPT_NAME_EXT=$(echo "$CPT_DATA" | cut -f4)
    echo "CPT found: ID=$CPT_ID, Code='$CPT_CODE', IntName='$CPT_NAME_INT', ExtName='$CPT_NAME_EXT'"
else
    echo "CPT code '99214' NOT found in database."
fi

# Escape special characters for JSON format
CPT_NAME_INT_ESC=$(echo "$CPT_NAME_INT" | sed 's/"/\\"/g' | sed 's/\\/\\\\/g')
CPT_NAME_EXT_ESC=$(echo "$CPT_NAME_EXT" | sed 's/"/\\"/g' | sed 's/\\/\\\\/g')

# Create JSON result using a temporary file for atomic writing and permission handling
TEMP_JSON=$(mktemp /tmp/add_cpt_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "initial_cpt_count": ${INITIAL_COUNT:-0},
    "current_cpt_count": ${CURRENT_COUNT:-0},
    "cpt_found": $CPT_FOUND,
    "cpt": {
        "id": "$CPT_ID",
        "code": "$CPT_CODE",
        "internal_name": "$CPT_NAME_INT_ESC",
        "external_name": "$CPT_NAME_EXT_ESC"
    },
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Move temp file to final location setting correct ownership/permissions
rm -f /tmp/add_cpt_result.json 2>/dev/null || sudo rm -f /tmp/add_cpt_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/add_cpt_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/add_cpt_result.json
chmod 666 /tmp/add_cpt_result.json 2>/dev/null || sudo chmod 666 /tmp/add_cpt_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
cat /tmp/add_cpt_result.json
echo ""
echo "=== Export Complete ==="