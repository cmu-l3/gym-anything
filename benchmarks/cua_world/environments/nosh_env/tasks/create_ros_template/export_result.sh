#!/bin/bash
echo "=== Exporting Task Results ==="

# Source timestamp
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# ==============================================================================
# VERIFICATION: Database Content Check
# ==============================================================================
# We dump the database again and search for the template and its contents.
# This is robust against schema changes as we look for the data presence.

echo "Dumping database for verification..."
docker exec nosh-db mysqldump -uroot -prootpassword nosh > /tmp/nosh_final_dump.sql 2>/dev/null

# 1. Check if template name exists
if grep -i "Cardio_Consult" /tmp/nosh_final_dump.sql > /dev/null; then
    TEMPLATE_EXISTS="true"
else
    TEMPLATE_EXISTS="false"
fi

# 2. Extract the specific line(s) containing the template to check for content
# This reduces false positives from other tables
grep -i "Cardio_Consult" /tmp/nosh_final_dump.sql > /tmp/template_record.txt || true

# 3. Check for required symptom keywords in the template record
FATIGUE_FOUND="false"
CHEST_PAIN_FOUND="false"
PALPITATIONS_FOUND="false"
EDEMA_FOUND="false"
SOB_FOUND="false"

if grep -i "Fatigue" /tmp/template_record.txt > /dev/null; then FATIGUE_FOUND="true"; fi
if grep -i "Chest.*pain" /tmp/template_record.txt > /dev/null; then CHEST_PAIN_FOUND="true"; fi
if grep -i "Palpitations" /tmp/template_record.txt > /dev/null; then PALPITATIONS_FOUND="true"; fi
if grep -i "Edema" /tmp/template_record.txt > /dev/null; then EDEMA_FOUND="true"; fi
if grep -iE "Shortness.*breath|Dyspnea|SOB" /tmp/template_record.txt > /dev/null; then SOB_FOUND="true"; fi

# 4. Check if it's a NEW record (wasn't in initial dump)
if grep -i "Cardio_Consult" /tmp/initial_template_check.txt > /dev/null; then
    IS_NEW_RECORD="false"
else
    IS_NEW_RECORD="true"
fi

# ==============================================================================
# JSON EXPORT
# ==============================================================================
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "template_exists": $TEMPLATE_EXISTS,
    "is_new_record": $IS_NEW_RECORD,
    "items_found": {
        "fatigue": $FATIGUE_FOUND,
        "chest_pain": $CHEST_PAIN_FOUND,
        "palpitations": $PALPITATIONS_FOUND,
        "edema": $EDEMA_FOUND,
        "shortness_of_breath": $SOB_FOUND
    },
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location with permissions
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Results exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="