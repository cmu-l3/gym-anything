#!/bin/bash
echo "=== Exporting employee_self_service_update result ==="
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

START_TIME=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# Perform DB queries for specific strings (handling both direct saves and pending approvals)

# Address
MATCH_ADDR=$(sentrifugo_db_root_query "SELECT COUNT(*) FROM main_useraddresses WHERE address1 LIKE '%8472 Redwood%';")
MATCH_ADDR_PEND=$(sentrifugo_db_root_query "SELECT COUNT(*) FROM main_userprofileupdates WHERE details LIKE '%8472 Redwood%';")

# Phone
MATCH_PHONE=$(sentrifugo_db_root_query "SELECT COUNT(*) FROM main_employeeemergencycontacts WHERE workphone LIKE '%206-555-8472%' OR homephone LIKE '%206-555-8472%' OR mobilephone LIKE '%206-555-8472%';")
MATCH_PHONE_PEND=$(sentrifugo_db_root_query "SELECT COUNT(*) FROM main_userprofileupdates WHERE details LIKE '%206-555-8472%';")

# Name (Dependent & Emergency Contact)
MATCH_NAME_DEP=$(sentrifugo_db_root_query "SELECT COUNT(*) FROM main_employeedependents WHERE dependentname LIKE '%Eleanor Vance-Kim%';")
MATCH_NAME_EMG=$(sentrifugo_db_root_query "SELECT COUNT(*) FROM main_employeeemergencycontacts WHERE contactname LIKE '%Eleanor Vance-Kim%';")
MATCH_NAME_PEND=$(sentrifugo_db_root_query "SELECT COUNT(*) FROM main_userprofileupdates WHERE details LIKE '%Eleanor Vance-Kim%';")

# Dump the entire DB for grep fallback (robustness against JSON blob formatting in pending table)
docker exec sentrifugo-db mysqldump -u root -prootpass123 sentrifugo > /tmp/sentrifugo_dump.sql
DUMP_ADDR=$(grep -i "8472 Redwood" /tmp/sentrifugo_dump.sql | wc -l)
DUMP_PHONE=$(grep -i "206-555-8472" /tmp/sentrifugo_dump.sql | wc -l)
DUMP_NAME=$(grep -i "Eleanor Vance-Kim" /tmp/sentrifugo_dump.sql | wc -l)

# File uploads
# Look for newly modified images in the uploads directory created AFTER the task started
UPLOAD_COUNT=$(find /var/www/html/sentrifugo/public/uploads -type f -newermt "@$START_TIME" 2>/dev/null | grep -iE '\.(jpg|jpeg|png|gif)$' | wc -l)

# Export to JSON format for the verifier
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "db": {
        "address": $((${MATCH_ADDR:-0} + ${MATCH_ADDR_PEND:-0})),
        "phone": $((${MATCH_PHONE:-0} + ${MATCH_PHONE_PEND:-0})),
        "dependent": $((${MATCH_NAME_DEP:-0})),
        "emergency_contact": $((${MATCH_NAME_EMG:-0})),
        "pending_name": $((${MATCH_NAME_PEND:-0}))
    },
    "dump": {
        "address": ${DUMP_ADDR:-0},
        "phone": ${DUMP_PHONE:-0},
        "name": ${DUMP_NAME:-0}
    },
    "uploads": {
        "new_images": ${UPLOAD_COUNT:-0}
    },
    "screenshot_path": "/tmp/task_end_screenshot.png"
}
EOF

# Move to final destination safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Export complete. Results saved to /tmp/task_result.json"