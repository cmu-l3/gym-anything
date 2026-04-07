#!/bin/bash
echo "=== Exporting Task Result ==="

source /workspace/scripts/task_utils.sh

# 1. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 2. Gather Data
EMP_NUMBER=$(cat /tmp/target_emp_number.txt 2>/dev/null || echo "0")
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

if [ "$EMP_NUMBER" == "0" ]; then
    # Fallback lookup if tmp file lost
    EMP_NUMBER=$(get_employee_empnum "James" "Anderson")
fi

# Check Profile Picture
# Returns 1 if record exists, 0 otherwise
PHOTO_EXISTS=$(orangehrm_db_query "SELECT COUNT(*) FROM hs_hr_emp_picture WHERE emp_number = $EMP_NUMBER;" 2>/dev/null | tr -d '[:space:]')
if [ -z "$PHOTO_EXISTS" ]; then PHOTO_EXISTS="0"; fi

# Check Attachments
# We get a raw list of filename|description pairs
ATTACHMENTS_RAW=$(orangehrm_db_query "SELECT eattach_filename, eattach_desc FROM hs_hr_emp_attachment WHERE emp_number = $EMP_NUMBER;" 2>/dev/null)

# 3. Build JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)

# Use python to construct safe JSON from the raw DB output
python3 -c "
import json
import sys

emp_num = '$EMP_NUMBER'
photo_exists = '$PHOTO_EXISTS' == '1'
raw_attachments = \"\"\"$ATTACHMENTS_RAW\"\"\"

attachments_list = []
if raw_attachments.strip():
    for line in raw_attachments.strip().split('\n'):
        parts = line.split('\t')
        if len(parts) >= 1:
            fname = parts[0]
            desc = parts[1] if len(parts) > 1 else ''
            attachments_list.append({'filename': fname, 'description': desc})

result = {
    'emp_number': emp_num,
    'photo_uploaded': photo_exists,
    'attachments': attachments_list,
    'screenshot_path': '/tmp/task_final.png'
}

with open('$TEMP_JSON', 'w') as f:
    json.dump(result, f)
"

# 4. Finalize Export
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "=== Export Complete ==="
cat /tmp/task_result.json