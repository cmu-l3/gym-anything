#!/bin/bash
echo "=== Exporting create_faq_entries results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot as evidence
take_screenshot /tmp/create_faq_final.png

# Read initial states
INITIAL_FAQ_COUNT=$(cat /tmp/initial_faq_count.txt 2>/dev/null || echo "0")
INITIAL_MAX_ID=$(cat /tmp/initial_max_id.txt 2>/dev/null || echo "0")
TASK_START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Get current FAQ count
CURRENT_FAQ_COUNT=$(vtiger_db_query "SELECT COUNT(*) FROM vtiger_faq f JOIN vtiger_crmentity c ON f.id=c.crmid WHERE c.deleted=0" | tr -d '[:space:]')

# Export FAQ data securely to avoid newline/quote escaping issues
# We use TO_BASE64 to safely transport text fields
echo "Exporting FAQ data from database..."
vtiger_db_query "SELECT f.id, TO_BASE64(f.question), TO_BASE64(f.faq_answer), TO_BASE64(f.status), TO_BASE64(f.category), c.smownerid FROM vtiger_faq f JOIN vtiger_crmentity c ON f.id=c.crmid WHERE c.deleted=0" > /tmp/faqs_b64.tsv

# Convert to JSON using Python
python3 << 'PYEOF'
import base64
import json
import sys
import os

faqs = []
try:
    with open('/tmp/faqs_b64.tsv', 'r') as f:
        for line in f:
            parts = line.strip('\n').split('\t')
            if len(parts) >= 6:
                faqs.append({
                    'id': int(parts[0]) if parts[0].isdigit() else 0,
                    'question': base64.b64decode(parts[1]).decode('utf-8', 'ignore') if parts[1] != 'NULL' else '',
                    'answer': base64.b64decode(parts[2]).decode('utf-8', 'ignore') if parts[2] != 'NULL' else '',
                    'status': base64.b64decode(parts[3]).decode('utf-8', 'ignore') if parts[3] != 'NULL' else '',
                    'category': base64.b64decode(parts[4]).decode('utf-8', 'ignore') if parts[4] != 'NULL' else '',
                    'smownerid': int(parts[5]) if parts[5].isdigit() else 0
                })
except Exception as e:
    print(f"Error processing base64 data: {e}")

# Read initial states passed from bash
try:
    with open('/tmp/initial_faq_count.txt', 'r') as f:
        initial_count = int(f.read().strip())
except:
    initial_count = 0

try:
    with open('/tmp/initial_max_id.txt', 'r') as f:
        initial_max_id = int(f.read().strip())
except:
    initial_max_id = 0

try:
    with open('/tmp/task_start_time.txt', 'r') as f:
        task_start_time = int(f.read().strip())
except:
    task_start_time = 0

# Get current count
current_count = int(os.environ.get('CURRENT_FAQ_COUNT', 0))

result = {
    'initial_count': initial_count,
    'current_count': current_count,
    'initial_max_id': initial_max_id,
    'task_start_time': task_start_time,
    'faqs': faqs
}

with open('/tmp/create_faq_result.json', 'w') as f:
    json.dump(result, f, indent=2)
PYEOF

# Clean up temporary tsv
rm -f /tmp/faqs_b64.tsv

echo "Result JSON saved to /tmp/create_faq_result.json"
cat /tmp/create_faq_result.json
echo "=== create_faq_entries export complete ==="