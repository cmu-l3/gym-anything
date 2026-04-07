#!/bin/bash
echo "=== Exporting Talent Acquisition Pipeline Result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# 1. Check Job Titles 
# (These tables are standard Sentrifugo HR core tables)
JT_BIOMASS=$(sentrifugo_db_query "SELECT COUNT(*) FROM main_jobtitles WHERE jobtitlename LIKE '%Biomass%' AND isactive=1;" | tr -d '[:space:]')
JT_SAFETY=$(sentrifugo_db_query "SELECT COUNT(*) FROM main_jobtitles WHERE jobtitlename LIKE '%Safety Inspector%' AND isactive=1;" | tr -d '[:space:]')

# 2. Dump entire DB to make schema-agnostic text searches for Talent Acquisition module additions
docker exec sentrifugo-db mysqldump -u root -prootpass123 sentrifugo --no-create-info --skip-extended-insert > /tmp/db_dump.sql 2>/dev/null

IR_PHONE=$(grep -ci "Initial Phone Screen" /tmp/db_dump.sql || echo "0")
IR_TECH=$(grep -ci "Technical Plant Assessment" /tmp/db_dump.sql || echo "0")
IR_MANAGER=$(grep -ci "Plant Manager Interview" /tmp/db_dump.sql || echo "0")

# 3. DB hints for Requisitions (not definitive enough to capture department links, but good for partial credit fallback)
REQ_EVIDENCE_1=$(grep -i "Biomass" /tmp/db_dump.sql | grep -c "2" || echo "0")
REQ_EVIDENCE_2=$(grep -i "Safety Inspector" /tmp/db_dump.sql | grep -c "3" || echo "0")

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "job_title_biomass_count": ${JT_BIOMASS:-0},
    "job_title_safety_count": ${JT_SAFETY:-0},
    "ir_phone_found": ${IR_PHONE:-0},
    "ir_tech_found": ${IR_TECH:-0},
    "ir_manager_found": ${IR_MANAGER:-0},
    "req_evidence_1": ${REQ_EVIDENCE_1:-0},
    "req_evidence_2": ${REQ_EVIDENCE_2:-0},
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="