#!/bin/bash
set -e
echo "=== Exporting Bulk Import Results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# 1. Capture final screenshot
take_screenshot /tmp/task_final.png

# 2. Get task timing
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 3. Query the database for risks created during the task
# We fetch Title, Description, Threats, Vulnerabilities for all non-deleted risks
# We filter for the expected titles in the Python verifier, but we dump relevant recent data here.
# Note: 'created' is a datetime, we check if it's recent or if the ID is high.
# For robustness, we'll dump all non-deleted risks and let Python filter.

echo "Dumping risk data..."
docker exec eramba-db mysql -u eramba -peramba_db_pass eramba -N -e \
    "SELECT title, description, threats, vulnerabilities, created, modified FROM risks WHERE deleted=0 ORDER BY created DESC;" \
    > /tmp/risks_dump.tsv 2>/dev/null || true

# 4. Get current risk count
FINAL_COUNT=$(docker exec eramba-db mysql -u eramba -peramba_db_pass eramba -N -e "SELECT COUNT(*) FROM risks WHERE deleted=0;" 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_risk_count.txt 2>/dev/null || echo "0")

# 5. Construct JSON result
# We use python to safely construct JSON from the TSV dump to avoid escaping issues in bash
python3 -c "
import json
import csv
import sys
import time
from datetime import datetime

risks = []
try:
    with open('/tmp/risks_dump.tsv', 'r') as f:
        # MySQL -N output is tab-separated
        reader = csv.reader(f, delimiter='\t')
        for row in reader:
            if len(row) >= 6:
                risks.append({
                    'title': row[0],
                    'description': row[1],
                    'threats': row[2],
                    'vulnerabilities': row[3],
                    'created': row[4],
                    'modified': row[5]
                })
except Exception as e:
    print(f'Error reading TSV: {e}', file=sys.stderr)

result = {
    'task_start': $TASK_START,
    'task_end': $TASK_END,
    'initial_count': int('$INITIAL_COUNT'),
    'final_count': int('$FINAL_COUNT'),
    'risks': risks,
    'screenshot_path': '/tmp/task_final.png'
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
"

# 6. Secure the output file
chmod 666 /tmp/task_result.json

echo "=== Export Complete ==="
cat /tmp/task_result.json