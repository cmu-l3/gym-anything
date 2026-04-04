#!/bin/bash
set -e
echo "=== Exporting task results ==="

source /workspace/scripts/task_utils.sh

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Extract Data from Database using Python for clean JSON formatting
# We run this INSIDE the container to access the DB directly
cat > /tmp/extract_data.py << 'PYEOF'
import json
import pymysql
import os
import sys

try:
    # Connect to DB
    conn = pymysql.connect(
        host='librehealth-db',
        user='libreehr',
        password='s3cret',
        db='libreehr',
        cursorclass=pymysql.cursors.DictCursor
    )
    
    result_data = {
        "record_found": False,
        "provider_number": None,
        "group_number": None,
        "provider_id": None,
        "insurance_company_id": None,
        "record_id": 0,
        "provider_username": None,
        "insurance_name": None,
        "error": None
    }

    with conn.cursor() as cursor:
        # Get IDs for verification context
        cursor.execute("SELECT id FROM users WHERE username='admin'")
        admin_row = cursor.fetchone()
        admin_id = admin_row['id'] if admin_row else -1

        cursor.execute("SELECT id FROM insurance_companies WHERE name LIKE '%Blue Cross Blue Shield%' LIMIT 1")
        bcbs_row = cursor.fetchone()
        bcbs_id = bcbs_row['id'] if bcbs_row else -1

        # Query the specific record we expect
        # We look for the most recently added record for this pair
        query = """
            SELECT in_num.*, u.username, ic.name as insurance_name
            FROM insurance_numbers in_num
            JOIN users u ON in_num.provider_id = u.id
            JOIN insurance_companies ic ON in_num.insurance_company_id = ic.id
            WHERE in_num.provider_id = %s 
            AND in_num.insurance_company_id = %s
            ORDER BY in_num.id DESC LIMIT 1
        """
        cursor.execute(query, (admin_id, bcbs_id))
        row = cursor.fetchone()

        if row:
            result_data["record_found"] = True
            result_data["record_id"] = row["id"]
            result_data["provider_number"] = row["provider_number"]
            result_data["group_number"] = row["group_number"]
            result_data["provider_id"] = row["provider_id"]
            result_data["insurance_company_id"] = row["insurance_company_id"]
            result_data["provider_username"] = row["username"]
            result_data["insurance_name"] = row["insurance_name"]

    print(json.dumps(result_data))

except Exception as e:
    print(json.dumps({"error": str(e)}))
finally:
    if 'conn' in locals() and conn:
        conn.close()
PYEOF

# Run the extraction script
python3 /tmp/extract_data.py > /tmp/db_result.json

# 3. Add timestamp info for anti-gaming
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_MAX_ID=$(cat /tmp/initial_max_id.txt 2>/dev/null || echo "0")

# Create final combined JSON
jq -n \
    --slurpfile db /tmp/db_result.json \
    --arg start_time "$TASK_START" \
    --arg init_max_id "$INITIAL_MAX_ID" \
    '{
        db_state: $db[0],
        task_meta: {
            start_time: $start_time,
            initial_max_id: $init_max_id
        }
    }' > /tmp/task_result.json

# Clean up
rm -f /tmp/extract_data.py /tmp/db_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="