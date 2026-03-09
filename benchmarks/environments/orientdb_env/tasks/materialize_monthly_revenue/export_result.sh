#!/bin/bash
set -e
echo "=== Exporting materialize_monthly_revenue results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
take_screenshot /tmp/task_final.png

# Capture OrientDB Schema and Data for Verification
echo "Extracting database state..."

# 1. Get Schema (Classes and Indexes)
SCHEMA_JSON=$(curl -s -u "root:GymAnything123!" "http://localhost:2480/database/demodb")

# 2. Get the content of the new MonthlyStats class
# We select all fields
MONTHLY_STATS_JSON=$(orientdb_sql "demodb" "SELECT Year, Month, TotalRevenue, OrderCount FROM MonthlyStats")

# 3. Get the raw source data (Orders) so the verifier can calculate ground truth
# We fetch all paid orders to verify the aggregation locally
SOURCE_DATA_JSON=$(orientdb_sql "demodb" "SELECT Date, Price, Status FROM Orders WHERE Status='paid'")

# Combine into one JSON file
python3 -c "
import json
import sys

try:
    schema = json.loads('''$SCHEMA_JSON''')
    stats = json.loads('''$MONTHLY_STATS_JSON''')
    source = json.loads('''$SOURCE_DATA_JSON''')
    
    result = {
        'schema': schema,
        'monthly_stats': stats.get('result', []),
        'source_data': source.get('result', []),
        'task_start': $TASK_START,
        'task_end': $TASK_END,
        'screenshot_exists': True
    }
    
    with open('/tmp/task_result.json', 'w') as f:
        json.dump(result, f, indent=2)
        
except Exception as e:
    print(f'Error processing JSON: {e}')
    # Fallback empty result
    with open('/tmp/task_result.json', 'w') as f:
        json.dump({'error': str(e)}, f)
"

# Set permissions
chmod 666 /tmp/task_result.json

echo "Export complete. Result saved to /tmp/task_result.json"