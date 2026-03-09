#!/bin/bash
echo "=== Exporting create_risk_exception results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Capture final screenshot
take_screenshot /tmp/task_final.png

# 2. Check Database for the created record
echo "Querying database for Risk Exception..."

# Create a temporary SQL file to handle complex quoting if needed, or just use -e
# We fetch specific columns to verify against expectations
# Note: Eramba schema conventions: tables are plural, 'created' is datetime
# We look for the specific title requested.

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)

# We use python to execute the DB query and format as JSON to avoid bash string parsing hell
cat > /tmp/query_eramba.py << 'PYEOF'
import subprocess
import json
import sys

def run_query(query):
    cmd = ["docker", "exec", "eramba-db", "mysql", "-u", "eramba", "-peramba_db_pass", "eramba", "-N", "-e", query]
    try:
        res = subprocess.check_output(cmd, stderr=subprocess.DEVNULL)
        return res.decode('utf-8').strip()
    except:
        return ""

# 1. Find the specific exception
query_exception = """
SELECT id, title, description, review_planned_date, created 
FROM risk_exceptions 
WHERE title LIKE '%Email Gateway Upgrade Delay%' 
  AND deleted = 0 
ORDER BY id DESC LIMIT 1;
"""
row = run_query(query_exception)

result = {
    "record_found": False,
    "title": "",
    "description": "",
    "review_date": "",
    "created_at": "",
    "associated_risk_found": False
}

if row:
    parts = row.split('\t')
    if len(parts) >= 5:
        result["record_found"] = True
        exception_id = parts[0]
        result["title"] = parts[1]
        result["description"] = parts[2]
        result["review_date"] = parts[3]
        result["created_at"] = parts[4]
        
        # 2. Check association (junction table usually risk_exceptions_risks or similar)
        # Try query for association
        query_assoc = f"""
        SELECT count(*) 
        FROM risk_exceptions_risks 
        WHERE risk_exception_id = {exception_id};
        """
        # Note: Table name is a guess based on CakePHP conventions (plural_plural). 
        # If that fails, we might just check if the risk ID is in a field.
        # Let's try a direct check on standard naming.
        assoc_count = run_query(query_assoc)
        if assoc_count and int(assoc_count) > 0:
             result["associated_risk_found"] = True
        else:
            # Fallback check: maybe it's stored in the risks table?
            pass

print(json.dumps(result))
PYEOF

# Execute the python script
python3 /tmp/query_eramba.py > "$TEMP_JSON"

# 3. Add other metadata to the JSON
# Read the python output
RECORD_FOUND=$(jq -r '.record_found' "$TEMP_JSON")

# Check initial vs final count
INITIAL_COUNT=$(cat /tmp/initial_exception_count.txt 2>/dev/null || echo "0")
FINAL_COUNT=$(docker exec eramba-db mysql -u eramba -peramba_db_pass eramba -N -e "SELECT COUNT(*) FROM risk_exceptions WHERE deleted=0;" 2>/dev/null || echo "0")
COUNT_DIFF=$((FINAL_COUNT - INITIAL_COUNT))

# Add these to the JSON
jq --argjson diff "$COUNT_DIFF" \
   --argjson start "$TASK_START" \
   --argjson end "$TASK_END" \
   '. + {count_diff: $diff, task_start: $start, task_end: $end}' \
   "$TEMP_JSON" > /tmp/task_result.json

# Cleanup
rm -f "$TEMP_JSON" /tmp/query_eramba.py

echo "Export complete. Result:"
cat /tmp/task_result.json