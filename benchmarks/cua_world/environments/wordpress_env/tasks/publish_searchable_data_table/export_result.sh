#!/bin/bash
# Export script for publish_searchable_data_table task

echo "=== Exporting task result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

cd /var/www/html/wordpress

# 1. Check if TablePress is active
TP_ACTIVE="false"
if wp plugin is-active tablepress --allow-root 2>/dev/null; then
    TP_ACTIVE="true"
fi

# 2. Check if a table was imported by inspecting wp_posts for tablepress_table type
TABLE_EXISTS="false"
DATA_AUTHENTIC="false"
TABLE_ID=$(wp_db_query "SELECT ID FROM wp_posts WHERE post_type='tablepress_table' AND post_status='publish' ORDER BY ID DESC LIMIT 1")

if [ -n "$TABLE_ID" ]; then
    TABLE_EXISTS="true"
    # Check if the authentic NASA data keyword ("Aachen") exists in the JSON payload of the table
    TABLE_CONTENT=$(wp_db_query "SELECT post_content FROM wp_posts WHERE ID=$TABLE_ID")
    if echo "$TABLE_CONTENT" | grep -qi "Aachen"; then
        DATA_AUTHENTIC="true"
    fi
fi

# 3. Check for the target blog post
POST_FOUND="false"
POST_ID=""
POST_CONTENT=""
SHORTCODE_EMBEDDED="false"

EXPECTED_TITLE="Historical Meteorite Landings Database"
POST_ID=$(wp_db_query "SELECT ID FROM wp_posts WHERE LOWER(TRIM(post_title)) = LOWER(TRIM('$EXPECTED_TITLE')) AND post_type='post' AND post_status='publish' ORDER BY ID DESC LIMIT 1")

if [ -n "$POST_ID" ]; then
    POST_FOUND="true"
    POST_CONTENT=$(wp_db_query "SELECT post_content FROM wp_posts WHERE ID=$POST_ID")
fi

# 4. Check timestamps to prevent gaming
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
POST_CREATED_AFTER_START="false"

if [ "$POST_FOUND" = "true" ]; then
    POST_DATE=$(wp_db_query "SELECT UNIX_TIMESTAMP(post_date) FROM wp_posts WHERE ID=$POST_ID")
    if [ -n "$POST_DATE" ] && [ "$POST_DATE" -ge "$TASK_START" ]; then
        POST_CREATED_AFTER_START="true"
    fi
fi

# Use Python to safely generate the result JSON
python3 - <<EOF
import json

result = {
    "tablepress_active": "$TP_ACTIVE" == "true",
    "table_exists": "$TABLE_EXISTS" == "true",
    "data_authentic": "$DATA_AUTHENTIC" == "true",
    "post_found": "$POST_FOUND" == "true",
    "post_created_after_start": "$POST_CREATED_AFTER_START" == "true",
    "post_content": """$POST_CONTENT""",
    "task_start_time": int("$TASK_START") if "$TASK_START".isdigit() else 0
}

with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=4)
EOF

chmod 666 /tmp/task_result.json
echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json

echo "=== Export complete ==="