#!/bin/bash
# Export script for Register Worker task
# - Queries DB for the new worker
# - Checks timestamps
# - exports JSON result

set -e
echo "=== Exporting Register Worker Result ==="

source /workspace/scripts/task_utils.sh

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Get task start time
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_worker_count.txt 2>/dev/null || echo "0")

# 3. Query Database for Result
# We look for the most recently created Worker that matches the name loosely
echo "Querying database for 'Marie Dupont'..."

# Fetch details of the matching worker (if any)
# We select ID, Name, Born_At, and Created_At epoch
DB_RESULT=$(ekylibre_db_query "
SELECT 
    id, 
    name, 
    born_at::text, 
    EXTRACT(EPOCH FROM created_at)::bigint 
FROM products 
WHERE type = 'Worker' 
  AND name ILIKE '%Marie%' 
  AND name ILIKE '%Dupont%' 
ORDER BY created_at DESC 
LIMIT 1;
" 2>/dev/null || echo "")

# Fetch final total count
FINAL_COUNT=$(ekylibre_db_query "SELECT COUNT(*) FROM products WHERE type = 'Worker';" 2>/dev/null || echo "0")

# Parse DB Result (format: id|name|born_at|created_at_epoch)
WORKER_FOUND="false"
WORKER_ID=""
WORKER_NAME=""
WORKER_DOB=""
WORKER_CREATED_AT="0"

if [ -n "$DB_RESULT" ]; then
    WORKER_FOUND="true"
    WORKER_ID=$(echo "$DB_RESULT" | cut -d'|' -f1)
    WORKER_NAME=$(echo "$DB_RESULT" | cut -d'|' -f2)
    WORKER_DOB=$(echo "$DB_RESULT" | cut -d'|' -f3)
    WORKER_CREATED_AT=$(echo "$DB_RESULT" | cut -d'|' -f4)
fi

# 4. Check if creation happened DURING the task
CREATED_DURING_TASK="false"
if [ "$WORKER_CREATED_AT" -ge "$TASK_START" ]; then
    CREATED_DURING_TASK="true"
fi

# 5. Check if count actually increased
COUNT_INCREASED="false"
if [ "$FINAL_COUNT" -gt "$INITIAL_COUNT" ]; then
    COUNT_INCREASED="true"
fi

# 6. Generate JSON Result
# Using a temp file and moving it to avoid permission issues
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "worker_found": $WORKER_FOUND,
    "worker_id": "$WORKER_ID",
    "worker_name": "$WORKER_NAME",
    "worker_dob": "$WORKER_DOB",
    "worker_created_at": $WORKER_CREATED_AT,
    "task_start_time": $TASK_START,
    "created_during_task": $CREATED_DURING_TASK,
    "initial_count": $INITIAL_COUNT,
    "final_count": $FINAL_COUNT,
    "count_increased": $COUNT_INCREASED,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location with lenient permissions
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="