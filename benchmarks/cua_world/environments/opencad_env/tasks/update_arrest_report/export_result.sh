#!/bin/bash
echo "=== Exporting update_arrest_report result ==="

source /workspace/scripts/task_utils.sh

# Capture final visual state
take_screenshot /tmp/task_final.png

# Retrieve the specific report ID we are tracking
TARGET_ID=$(cat /tmp/target_report_id.txt 2>/dev/null)

if [ -z "$TARGET_ID" ]; then
    echo "ERROR: Target report ID lost. Attempting to recover by name..."
    TARGET_ID=$(opencad_db_query "SELECT a.id FROM ncic_arrests a JOIN ncic_names n ON a.name_id = n.id WHERE n.name='Elena Fisher' ORDER BY a.id DESC LIMIT 1")
fi

echo "Inspecting Report ID: $TARGET_ID"

REPORT_FOUND="false"
CURRENT_CHARGES=""
CURRENT_NARRATIVE=""
CURRENT_NAME=""

if [ -n "$TARGET_ID" ]; then
    # Check if the record still exists
    EXISTS_CHECK=$(opencad_db_query "SELECT id FROM ncic_arrests WHERE id='$TARGET_ID'")

    if [ -n "$EXISTS_CHECK" ]; then
        REPORT_FOUND="true"

        # Get current values
        # We use json_escape for safe JSON formatting later
        CURRENT_CHARGES=$(opencad_db_query "SELECT arrest_reason FROM ncic_arrests WHERE id='$TARGET_ID'")
        CURRENT_NARRATIVE=$(opencad_db_query "SELECT narrative FROM ncic_arrests WHERE id='$TARGET_ID'")
        CURRENT_NAME=$(opencad_db_query "SELECT n.name FROM ncic_arrests a JOIN ncic_names n ON a.name_id = n.id WHERE a.id='$TARGET_ID'")
    fi
fi

# Determine if content matches expectations
# We do this logic in python verifier usually, but we extract the raw data here.

# Create result JSON
# Note: We escape strings to prevent JSON syntax errors
SAFE_CHARGES=$(json_escape "$CURRENT_CHARGES")
SAFE_NARRATIVE=$(json_escape "$CURRENT_NARRATIVE")
SAFE_NAME=$(json_escape "$CURRENT_NAME")

cat > /tmp/update_arrest_result.json << EOF
{
    "report_found": $REPORT_FOUND,
    "report_id": "${TARGET_ID}",
    "current_charges": "${SAFE_CHARGES}",
    "current_narrative": "${SAFE_NARRATIVE}",
    "current_name": "${SAFE_NAME}",
    "timestamp": "$(date -Iseconds)"
}
EOF

# Safe copy to accessible location
safe_write_result "$(cat /tmp/update_arrest_result.json)" /tmp/task_result.json

echo "Result exported:"
cat /tmp/task_result.json
echo "=== Export complete ==="