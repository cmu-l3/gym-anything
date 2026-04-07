#!/bin/bash
echo "=== Exporting journal_event_update_scsendjournal result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final_state.png

# Retrieve setup variables
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
EVENT_ID=$(cat /tmp/expected_event_id.txt 2>/dev/null || echo "")

# Query database for the expected journal entries
# Since time conversions can be tricky, we just verify the records exist
# and use the valid_sender check as an anti-gaming mechanism.
EVNAME_COUNT=$(seiscomp_db_query "SELECT COUNT(*) FROM JournalEntry WHERE action='EvName' AND parameters LIKE '%2024 Noto Peninsula Earthquake%'" 2>/dev/null || echo "0")
echo "$EVNAME_COUNT" > /tmp/evname_count

EVALMODE_COUNT=$(seiscomp_db_query "SELECT COUNT(*) FROM JournalEntry WHERE action='EvPrefOrgEvalMode' AND parameters='MANUAL'" 2>/dev/null || echo "0")
echo "$EVALMODE_COUNT" > /tmp/evalmode_count

# Anti-gaming: Check if the entries have a valid sender (meaning they were sent via the messaging system, not a raw SQL insert)
VALID_SENDER_COUNT=$(seiscomp_db_query "SELECT COUNT(*) FROM JournalEntry WHERE (action='EvName' OR action='EvPrefOrgEvalMode') AND sender IS NOT NULL AND sender != ''" 2>/dev/null || echo "0")
echo "$VALID_SENDER_COUNT" > /tmp/valid_sender

# Package everything into JSON using Python to avoid bash string escaping issues
python3 << 'PYEOF'
import json
import os

# Safe report reading
report_path = '/home/ga/journal_report.txt'
report_content = ''
report_exists = os.path.exists(report_path)
if report_exists:
    try:
        with open(report_path, 'r', errors='replace') as f:
            report_content = f.read()
    except Exception as e:
        report_content = f"Error reading file: {e}"

def read_int_file(path):
    try:
        with open(path, 'r') as f:
            val = f.read().strip()
            return int(val) if val.isdigit() else 0
    except:
        return 0

def read_str_file(path):
    try:
        with open(path, 'r') as f:
            return f.read().strip()
    except:
        return ""

data = {
    "task_start": read_int_file('/tmp/task_start_time.txt'),
    "expected_event_id": read_str_file('/tmp/expected_event_id.txt'),
    "evname_count": read_int_file('/tmp/evname_count'),
    "evalmode_count": read_int_file('/tmp/evalmode_count'),
    "valid_sender_count": read_int_file('/tmp/valid_sender'),
    "report_exists": report_exists,
    "report_content": report_content,
    "screenshot_path": "/tmp/task_final_state.png"
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(data, f)
PYEOF

# Ensure permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result JSON written to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="