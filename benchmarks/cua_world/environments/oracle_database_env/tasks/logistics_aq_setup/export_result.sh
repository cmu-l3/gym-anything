#!/bin/bash
# Export script for Logistics AQ Setup
# Verifies AQ objects, message contents, and output file

set -e
echo "=== Exporting Logistics AQ Results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Use Python inside the container logic to perform complex object/data verification
# We'll use the pre-installed python3 and oracledb (if available) or SQL queries parsed by python.
# Since the environment has python3 and oracledb installed via setup_oracle.sh:

python3 << 'PYEOF'
import oracledb
import json
import os
import sys

result = {
    "privileges_granted": False,
    "type_exists": False,
    "type_attributes": [],
    "queue_table_exists": False,
    "queue_exists": False,
    "queue_enabled": False,
    "procedure_exists": False,
    "procedure_status": "UNKNOWN",
    "message_count": 0,
    "messages_verified": {}, # Key: OrderID, Value: Customer
    "output_file_exists": False,
    "output_file_content": "",
    "errors": []
}

try:
    # Connect as SYSTEM to check privileges (optional) or just check functionality via HR
    # We will connect as HR to verify objects and data.
    conn = oracledb.connect(user="hr", password="hr123", dsn="localhost:1521/XEPDB1")
    cursor = conn.cursor()

    # 1. Check Privileges (Indirectly checked by ability to use AQ, but let's query USER_TAB_PRIVS/ROLE_PRIVS)
    # Actually, simpler to just check if objects exist.

    # 2. Check Object Type
    try:
        cursor.execute("SELECT attr_name, attr_type_name FROM user_type_attrs WHERE type_name = 'ORDER_EVENT_T'")
        attrs = cursor.fetchall()
        if attrs:
            result["type_exists"] = True
            result["type_attributes"] = [f"{r[0]}:{r[1]}" for r in attrs]
    except Exception as e:
        result["errors"].append(f"Type check error: {str(e)}")

    # 3. Check Queue Table
    try:
        cursor.execute("SELECT queue_table FROM user_queue_tables WHERE queue_table = 'ORDER_EVT_QT'")
        if cursor.fetchone():
            result["queue_table_exists"] = True
    except Exception as e:
        result["errors"].append(f"Queue Table check error: {str(e)}")

    # 4. Check Queue
    try:
        cursor.execute("SELECT name, enqueue_enabled, dequeue_enabled FROM user_queues WHERE name = 'ORDER_EVT_Q'")
        row = cursor.fetchone()
        if row:
            result["queue_exists"] = True
            if row[1] == 'YES':
                result["queue_enabled"] = True
    except Exception as e:
        result["errors"].append(f"Queue check error: {str(e)}")

    # 5. Check Procedure
    try:
        cursor.execute("SELECT status FROM user_objects WHERE object_name = 'ENQUEUE_ORDER' AND object_type = 'PROCEDURE'")
        row = cursor.fetchone()
        if row:
            result["procedure_exists"] = True
            result["procedure_status"] = row[0]
    except Exception as e:
        result["errors"].append(f"Procedure check error: {str(e)}")

    # 6. Check Messages (Content)
    # We need to query the AQ view. The view name is usually AQ$<QUEUE_TABLE_NAME>
    # Note: Accessing object attributes in SQL requires alias.
    try:
        # Check count
        cursor.execute("SELECT COUNT(*) FROM AQ$ORDER_EVT_QT")
        result["message_count"] = cursor.fetchone()[0]

        # Check specific data (Order 1001 and 1004)
        # We assume the payload column is 'user_data' (standard) and attributes are as defined.
        cursor.execute("""
            SELECT t.user_data.ORDER_ID, t.user_data.CUSTOMER_CODE 
            FROM AQ$ORDER_EVT_QT t 
            WHERE t.user_data.ORDER_ID IN (1001, 1004)
        """)
        for row in cursor.fetchall():
            o_id = str(row[0])
            cust = str(row[1])
            result["messages_verified"][o_id] = cust

    except Exception as e:
        result["errors"].append(f"Message data check error: {str(e)}")
        # Fallback: try raw query if object access fails
        try:
            cursor.execute("SELECT COUNT(*) FROM ORDER_EVT_QT") # Underlying table
            # This counts rows, but verifying content is harder without object types working in SQL
        except:
            pass

    conn.close()

except Exception as e:
    result["errors"].append(f"DB Connection error: {str(e)}")

# 7. Check output file
file_path = "/home/ga/Desktop/queue_dump.txt"
if os.path.exists(file_path):
    result["output_file_exists"] = True
    try:
        with open(file_path, "r") as f:
            result["output_file_content"] = f.read(500) # First 500 chars
    except Exception as e:
        result["errors"].append(f"File read error: {str(e)}")

# Save result
with open("/tmp/logistics_aq_result.json", "w") as f:
    json.dump(result, f, indent=2)

PYEOF

# Ensure the result file permissions are open for the host to copy
chmod 644 /tmp/logistics_aq_result.json 2>/dev/null || true

cat /tmp/logistics_aq_result.json
echo "=== Export Complete ==="