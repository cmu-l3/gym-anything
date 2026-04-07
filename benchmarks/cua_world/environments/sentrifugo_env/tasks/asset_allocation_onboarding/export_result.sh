#!/bin/bash
echo "=== Exporting asset_allocation_onboarding result ==="

source /workspace/scripts/task_utils.sh

# Record timestamps
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final evidence screenshot
take_screenshot /tmp/task_final.png

# Check if browser was actively running
APP_RUNNING=$(pgrep -f "firefox" > /dev/null && echo "true" || echo "false")

echo "Dumping database tables for verification..."

# ==============================================================================
# DATABASE EXTRACTION
# Dump relevant Sentrifugo tables to TSV format securely.
# ==============================================================================
docker exec sentrifugo-db mysql -u root -prootpass123 sentrifugo \
    -e "SELECT * FROM main_assetcategories;" -B > /tmp/categories.tsv 2>/dev/null || true

docker exec sentrifugo-db mysql -u root -prootpass123 sentrifugo \
    -e "SELECT * FROM main_assets;" -B > /tmp/assets.tsv 2>/dev/null || true

docker exec sentrifugo-db mysql -u root -prootpass123 sentrifugo \
    -e "SELECT * FROM main_assetallocations;" -B > /tmp/allocations.tsv 2>/dev/null || true

docker exec sentrifugo-db mysql -u root -prootpass123 sentrifugo \
    -e "SELECT id, employeeId, firstname, lastname FROM main_users;" -B > /tmp/users.tsv 2>/dev/null || true

# ==============================================================================
# CONVERT TSV TO JSON
# Safely bundle the data for the verifier script
# ==============================================================================
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)

python3 -c "
import csv, json, os

def read_tsv(path):
    if not os.path.exists(path): return []
    try:
        with open(path, 'r', encoding='utf-8') as f:
            return list(csv.DictReader(f, delimiter='\t'))
    except Exception as e:
        print(f'Error reading {path}: {e}')
        return []

result_data = {
    'task_start': $TASK_START,
    'task_end': $TASK_END,
    'app_was_running': str('$APP_RUNNING').lower() == 'true',
    'categories': read_tsv('/tmp/categories.tsv'),
    'assets': read_tsv('/tmp/assets.tsv'),
    'allocations': read_tsv('/tmp/allocations.tsv'),
    'users': read_tsv('/tmp/users.tsv')
}

with open('$TEMP_JSON', 'w', encoding='utf-8') as f:
    json.dump(result_data, f)
"

# Move the result file into place securely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result JSON saved to /tmp/task_result.json"
echo "=== Export complete ==="