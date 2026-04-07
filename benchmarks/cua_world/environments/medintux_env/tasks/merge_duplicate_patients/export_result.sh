#!/bin/bash
echo "=== Exporting task results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# GUIDs from setup
GUID_A="DUP-MERGE-AAA-001"
GUID_B="DUP-MERGE-BBB-002"

# 1. Check Audit Report
REPORT_PATH="/home/ga/merge_report.txt"
REPORT_EXISTS="false"
REPORT_CONTENT=""
FILE_CREATED_DURING_TASK="false"

if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_MTIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    if [ "$REPORT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    # Read first 1000 chars of report, escape quotes for JSON
    REPORT_CONTENT=$(head -c 1000 "$REPORT_PATH" | sed 's/"/\\"/g' | tr '\n' ' ')
fi

# 2. Database State Verification

# Count remaining DUPONT records with correct DOB
SURVIVOR_COUNT=$(mysql -u root DrTuxTest -N -e \
    "SELECT COUNT(*) FROM IndexNomPrenom WHERE FchGnrl_NomDos='DUPONT' AND FchGnrl_Prenom LIKE 'Marie%'" 2>/dev/null || echo 0)

# Check if specific GUIDs still exist
GUID_A_EXISTS=$(mysql -u root DrTuxTest -N -e "SELECT COUNT(*) FROM IndexNomPrenom WHERE FchGnrl_IDDos='$GUID_A'" 2>/dev/null)
GUID_B_EXISTS=$(mysql -u root DrTuxTest -N -e "SELECT COUNT(*) FROM IndexNomPrenom WHERE FchGnrl_IDDos='$GUID_B'" 2>/dev/null)

# Get details of the surviving record(s)
# We fetch relevant fields to verify merge quality
# JSON_OBJECT is not available in this old MySQL version usually, so we format manually
SURVIVOR_DATA=$(mysql -u root DrTuxTest -N -e \
    "SELECT CONCAT(FchPat_NomFille, '|', FchPat_Adresse, '|', FchPat_Ville, '|', FchPat_Tel1, '|', FchPat_NumSS) \
     FROM fchpat \
     WHERE FchPat_NomFille='DUPONT' AND FchPat_Nee='1967-04-12'" 2>/dev/null | head -1)

SURVIVOR_FIRSTNAME=$(mysql -u root DrTuxTest -N -e \
    "SELECT FchGnrl_Prenom FROM IndexNomPrenom \
     WHERE FchGnrl_NomDos='DUPONT' AND FchGnrl_IDDos IN (SELECT FchPat_GUID_Doss FROM fchpat WHERE FchPat_NomFille='DUPONT' AND FchPat_Nee='1967-04-12')" 2>/dev/null | head -1)

# App running check
APP_RUNNING=$(pgrep -f "Manager.exe" > /dev/null && echo "true" || echo "false")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "report_exists": $REPORT_EXISTS,
    "report_created_during_task": $FILE_CREATED_DURING_TASK,
    "report_content": "$REPORT_CONTENT",
    "survivor_count": $SURVIVOR_COUNT,
    "guid_a_exists": $GUID_A_EXISTS,
    "guid_b_exists": $GUID_B_EXISTS,
    "survivor_data_raw": "$SURVIVOR_DATA",
    "survivor_firstname": "$SURVIVOR_FIRSTNAME",
    "app_was_running": $APP_RUNNING
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="