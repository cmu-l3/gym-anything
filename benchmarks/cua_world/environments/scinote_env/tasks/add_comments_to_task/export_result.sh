#!/bin/bash
echo "=== Exporting add_comments_to_task result ==="

source /workspace/scripts/task_utils.sh

# Capture final state screenshot
take_screenshot /tmp/task_end_screenshot.png

# Function to safely dump all recent table rows into a text file
# We look back 1 hour to easily catch the task duration without time sync issues
dump_table_text() {
    local table=$1
    local exists=$(scinote_db_query "SELECT EXISTS (SELECT FROM information_schema.tables WHERE table_schema = 'public' AND table_name = '${table}');" | tr -d '[:space:]' | grep -i "t" || echo "f")
    if [ "$exists" = "t" ]; then
        scinote_db_query "SELECT * FROM ${table} WHERE created_at >= NOW() - INTERVAL '1 hour';" 2>/dev/null > "/tmp/table_dump_${table}.txt"
    fi
}

echo "Querying database for recent inputs..."

# We dump any table that might reasonably hold comment/activity/result text
dump_table_text "comments"
dump_table_text "activities"
dump_table_text "notes"
dump_table_text "results"
dump_table_text "step_texts"
dump_table_text "my_modules"

# Use python to safely merge everything into one JSON string
# This approach is immune to SQL json_agg parsing errors or schema variations
python3 -c '
import json
import glob
from datetime import datetime

text_dump = ""
for file in glob.glob("/tmp/table_dump_*.txt"):
    try:
        with open(file, "r", errors="replace") as f:
            text_dump += f.read() + "\n"
    except Exception:
        pass

result = {
    "text_dump": text_dump,
    "export_timestamp": datetime.now().isoformat()
}

with open("/tmp/add_comments_result.json", "w") as f:
    json.dump(result, f)
'

chmod 666 /tmp/add_comments_result.json
echo "Result saved to /tmp/add_comments_result.json"
echo "=== Export complete ==="