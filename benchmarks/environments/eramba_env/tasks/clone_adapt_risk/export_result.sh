#!/bin/bash
echo "=== Exporting clone_adapt_risk results ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 1. Query the database for the NEW risk
# We fetch title, description, mitigation strategy, threats, vulnerabilities, created time
echo "Querying database for new risk..."
docker exec eramba-db mysql -u eramba -peramba_db_pass eramba -N -e \
    "SELECT title, description, risk_mitigation_strategy_id, threats, vulnerabilities, UNIX_timestamp(created), id \
     FROM risks \
     WHERE title='Phishing Attacks on Remote Contractors' AND deleted=0 \
     ORDER BY id DESC LIMIT 1;" > /tmp/new_risk_raw.txt

# 2. Query the database for the ORIGINAL risk (to ensure it wasn't modified/renamed)
echo "Querying database for original risk..."
docker exec eramba-db mysql -u eramba -peramba_db_pass eramba -N -e \
    "SELECT title, risk_mitigation_strategy_id \
     FROM risks \
     WHERE title='Phishing Attacks on Employees' AND deleted=0 \
     LIMIT 1;" > /tmp/original_risk_raw.txt

# 3. Read source risk details (captured in setup)
SOURCE_DETAILS=$(cat /tmp/source_risk_details.txt 2>/dev/null || echo "")

# 4. Parse New Risk Data
NEW_RISK_EXISTS="false"
NEW_TITLE=""
NEW_DESC=""
NEW_STRATEGY=""
NEW_THREATS=""
NEW_VULNS=""
NEW_CREATED="0"
NEW_ID=""

if [ -s /tmp/new_risk_raw.txt ]; then
    NEW_RISK_EXISTS="true"
    # Read tab-separated values. Note: Description/Threats might contain tabs/newlines, so we handle carefully
    # For robust parsing, we'll use python in the next step, but here we just flag existence
fi

# 5. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 6. Create JSON payload using Python for robust string handling
python3 -c "
import json
import os
import sys

def read_file(path):
    if os.path.exists(path):
        with open(path, 'r', encoding='utf-8', errors='ignore') as f:
            return f.read().strip()
    return ''

# Read raw DB output
new_risk_raw = read_file('/tmp/new_risk_raw.txt')
original_risk_raw = read_file('/tmp/original_risk_raw.txt')
source_details = read_file('/tmp/source_risk_details.txt')
task_start = int(${TASK_START})

result = {
    'task_start': task_start,
    'task_end': int(${TASK_END}),
    'new_risk_found': False,
    'new_risk': {},
    'original_risk_preserved': False,
    'cloning_verified': False
}

if new_risk_raw:
    parts = new_risk_raw.split('\t')
    if len(parts) >= 7:
        result['new_risk_found'] = True
        result['new_risk'] = {
            'title': parts[0],
            'description': parts[1],
            'strategy_id': int(parts[2]) if parts[2].isdigit() else 0,
            'threats': parts[3],
            'vulnerabilities': parts[4],
            'created_ts': int(parts[5]) if parts[5].isdigit() else 0,
            'id': parts[6]
        }
        
        # Verify cloning: Threats/Vulns should match source (approx check)
        # source_details format: threats\tvulnerabilities
        if source_details:
            src_parts = source_details.split('\t')
            if len(src_parts) >= 2:
                # loose check: threats from source should be in new risk
                if src_parts[0] in result['new_risk']['threats']:
                    result['cloning_verified'] = True

if original_risk_raw:
    # If original risk still exists with correct title
    result['original_risk_preserved'] = True

print(json.dumps(result, indent=2))
" > /tmp/task_result.json

# 7. Secure the result file
chmod 666 /tmp/task_result.json

echo "=== Export complete ==="
cat /tmp/task_result.json