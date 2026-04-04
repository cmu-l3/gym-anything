#!/bin/bash
echo "=== Exporting Configure Dashboard Properties Result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# -----------------------------------------------------------------------
# 1. Query Database for Dashboard Properties
# -----------------------------------------------------------------------
# We expect ID=1. We fetch name, description, public, alias.
# Using python to fetch and format as JSON to handle special chars/newlines safely.

cat > /tmp/fetch_db_result.py << 'PYEOF'
import subprocess
import json
import sys

def db_query(sql):
    cmd = ['docker', 'exec', 'emoncms-db', 'mysql', '-u', 'emoncms', '-pemoncms', 'emoncms', '-N', '-e', sql]
    res = subprocess.run(cmd, capture_output=True, text=True)
    return res.stdout.strip()

try:
    # Fetch fields individually to avoid delimiter parsing issues
    name = db_query("SELECT name FROM dashboard WHERE id=1")
    description = db_query("SELECT description FROM dashboard WHERE id=1")
    public = db_query("SELECT public FROM dashboard WHERE id=1")
    alias = db_query("SELECT alias FROM dashboard WHERE id=1")
    
    result = {
        "db_name": name,
        "db_description": description,
        "db_public": public,
        "db_alias": alias
    }
    print(json.dumps(result))
except Exception as e:
    print(json.dumps({"error": str(e)}))
PYEOF

DB_RESULT_JSON=$(python3 /tmp/fetch_db_result.py)

# -----------------------------------------------------------------------
# 2. Verify Public HTTP Access
# -----------------------------------------------------------------------
# Try to access the dashboard without logging in (using curl without cookies)
# URL: http://localhost/dashboard/view?id=1
# OR if alias is set: http://localhost/oakwood-plaza (if mod_rewrite active) or http://localhost/dashboard/view?id=oakwood-plaza

# Test 1: Direct ID access
HTTP_CODE_ID=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost/dashboard/view?id=1")

# Test 2: Alias access (if alias matches expectation)
# We won't strictly enforce alias access via curl here, checking the DB alias + ID access is sufficient evidence 
# that public access works, but checking the alias URL is a good bonus signal.
ALIAS_URL="http://localhost/oakwood-plaza"
HTTP_CODE_ALIAS=$(curl -s -o /dev/null -w "%{http_code}" "$ALIAS_URL")

# Check content to ensure it's not the login page
CONTENT_CHECK=$(curl -s "http://localhost/dashboard/view?id=1" | grep -i "Oakwood Plaza" || echo "")
if [ -n "$CONTENT_CHECK" ]; then
    PUBLIC_CONTENT_VISIBLE="true"
else
    PUBLIC_CONTENT_VISIBLE="false"
fi

# -----------------------------------------------------------------------
# 3. Compile Final JSON
# -----------------------------------------------------------------------

# Helper to merge JSONs
cat > /tmp/merge_results.py << 'PYEOF'
import json
import sys

db_json = sys.argv[1]
extras = {
    "http_code_id": sys.argv[2],
    "http_code_alias": sys.argv[3],
    "public_content_visible": sys.argv[4] == "true",
    "task_start": int(sys.argv[5]),
    "task_end": int(sys.argv[6]),
    "screenshot_path": "/tmp/task_final.png"
}

try:
    data = json.loads(db_json)
    data.update(extras)
    print(json.dumps(data, indent=2))
except Exception as e:
    print(json.dumps({"error": str(e)}))
PYEOF

# Create final result file
python3 /tmp/merge_results.py \
    "$DB_RESULT_JSON" \
    "$HTTP_CODE_ID" \
    "$HTTP_CODE_ALIAS" \
    "$PUBLIC_CONTENT_VISIBLE" \
    "$TASK_START" \
    "$TASK_END" \
    > /tmp/task_result.json

# Prepare for export (fix permissions)
chmod 666 /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="