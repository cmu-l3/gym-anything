#!/bin/bash
echo "=== Exporting clinical_data_audit result ==="

source /workspace/scripts/task_utils.sh

# Capture final UI state
take_screenshot /tmp/task_final.png

# 1. Locate and Extract Findings File
FINDINGS_PATH="/home/ga/Documents/audit_findings.txt"
FILE_EXISTS="false"
FILE_CONTENT=""

if [ -f "$FINDINGS_PATH" ]; then
    FILE_EXISTS="true"
    # Safely extract text content, limiting to 2000 chars to avoid buffer bloat
    FILE_CONTENT=$(head -c 2000 "$FINDINGS_PATH" | jq -R -s '.')
else
    FILE_CONTENT='""'
fi

# 2. Database Status Check (Has DM-101 Baseline Assessment been locked?)
DM_STUDY_ID=$(oc_query "SELECT study_id FROM study WHERE unique_identifier = 'DM-TRIAL-2024' LIMIT 1" 2>/dev/null)
DM101_SS_ID=$(oc_query "SELECT study_subject_id FROM study_subject WHERE label = 'DM-101' AND study_id = $DM_STUDY_ID LIMIT 1" 2>/dev/null)
# Status 7 = Locked, Status 5 = Stopped/Frozen. Check current state:
EVENT_STATUS=$(oc_query "SELECT status_id FROM study_event WHERE study_subject_id = $DM101_SS_ID ORDER BY study_event_id DESC LIMIT 1" 2>/dev/null)

# 3. Anti-gaming check (Did the agent just use PSQL?)
PSQL_USED="false"
if grep -qi "psql\|docker exec\|docker.*psql" /home/ga/.bash_history 2>/dev/null; then
    PSQL_USED="true"
fi

# 4. Generate the export JSON
TEMP_JSON=$(mktemp /tmp/audit_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "file_exists": $FILE_EXISTS,
    "file_content": $FILE_CONTENT,
    "event_status_id": ${EVENT_STATUS:-0},
    "psql_used": $PSQL_USED,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move safely into position
rm -f /tmp/clinical_data_audit_result.json 2>/dev/null || sudo rm -f /tmp/clinical_data_audit_result.json
cp "$TEMP_JSON" /tmp/clinical_data_audit_result.json
chmod 666 /tmp/clinical_data_audit_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/clinical_data_audit_result.json"
cat /tmp/clinical_data_audit_result.json
echo "=== Export complete ==="