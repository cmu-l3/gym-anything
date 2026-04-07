#!/bin/bash
# Export script for IoT ETL Task
# Verifies database objects, runs functional tests against the agent's package, and checks file output.

set -e
echo "=== Exporting IoT ETL Results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end.png

# --- 1. Python Validation Script ---
# We use Python to connect and run complex verification logic
python3 << 'PYEOF'
import oracledb
import json
import os
import csv

# Initialize result dictionary
result = {
    "objects_exist": False,
    "package_valid": False,
    "function_pipelined": False,
    "type_attributes_correct": False,
    "test_valid_row": {"success": False, "temp_c": None, "low_batt": None},
    "test_error_row": {"success": False, "error_logged": False},
    "file_exists": False,
    "file_row_count": 0,
    "file_headers": [],
    "db_error": None
}

try:
    conn = oracledb.connect(user="hr", password="hr123", dsn="localhost:1521/XEPDB1")
    cursor = conn.cursor()

    # --- Check Objects Existence & Validity ---
    cursor.execute("""
        SELECT object_name, object_type, status 
        FROM user_objects 
        WHERE object_name IN ('PKG_IOT_ETL', 'T_IOT_METRIC', 'T_IOT_METRIC_TAB')
    """)
    objects = {row[0]: {'type': row[1], 'status': row[2]} for row in cursor.fetchall()}
    
    if 'PKG_IOT_ETL' in objects and 'T_IOT_METRIC' in objects:
        result["objects_exist"] = True
        # Check package body validity
        cursor.execute("SELECT status FROM user_objects WHERE object_name = 'PKG_IOT_ETL' AND object_type = 'PACKAGE BODY'")
        row = cursor.fetchone()
        if row and row[0] == 'VALID':
            result["package_valid"] = True

    # --- Check Pipelined Keyword in Source ---
    cursor.execute("""
        SELECT count(*) FROM user_source 
        WHERE name = 'PKG_IOT_ETL' 
        AND upper(text) LIKE '%PIPELINED%'
    """)
    if cursor.fetchone()[0] > 0:
        result["function_pipelined"] = True

    # --- Check Type Attributes ---
    if 'T_IOT_METRIC' in objects:
        cursor.execute("""
            SELECT attr_name 
            FROM user_type_attrs 
            WHERE type_name = 'T_IOT_METRIC'
        """)
        attrs = [r[0] for r in cursor.fetchall()]
        required = ['TEMP_CELSIUS', 'IS_LOW_BATTERY', 'SENSOR_ID']
        if all(req in attrs for req in required):
            result["type_attributes_correct"] = True

    # --- Functional Test 1: Valid Row Transformation ---
    # We call the agent's function with a manually constructed cursor
    try:
        cursor.execute("""
            SELECT temp_celsius, is_low_battery 
            FROM TABLE(pkg_iot_etl.stream_metrics(
                CURSOR(SELECT 1 as log_id, 'TEST|2024-01-01T12:00:00|212|10|OK' as raw_payload FROM DUAL)
            ))
        """)
        row = cursor.fetchone()
        if row:
            result["test_valid_row"]["success"] = True
            result["test_valid_row"]["temp_c"] = row[0] # Expect 100
            result["test_valid_row"]["low_batt"] = row[1] # Expect 'Y' (10 < 20)
    except Exception as e:
        result["test_valid_row"]["error"] = str(e)

    # --- Functional Test 2: Error Handling ---
    # Verify it doesn't crash and logs error
    try:
        # Clear errors first
        cursor.execute("DELETE FROM iot_parse_errors WHERE log_id = 99999")
        
        # Call with bad data
        cursor.execute("""
            SELECT count(*) 
            FROM TABLE(pkg_iot_etl.stream_metrics(
                CURSOR(SELECT 99999 as log_id, 'TEST|BAD_DATE|ERR|10|OK' as raw_payload FROM DUAL)
            ))
        """)
        count = cursor.fetchone()[0] # Should be 0 rows returned
        
        # Check error table
        cursor.execute("SELECT count(*) FROM iot_parse_errors WHERE log_id = 99999")
        err_count = cursor.fetchone()[0]
        
        if count == 0 and err_count == 1:
            result["test_error_row"]["success"] = True
            result["test_error_row"]["error_logged"] = True
    except Exception as e:
        result["test_error_row"]["error"] = str(e)

    conn.close()

except Exception as e:
    result["db_error"] = str(e)

# --- File Check ---
file_path = "/home/ga/Desktop/parsed_metrics.csv"
if os.path.exists(file_path):
    result["file_exists"] = True
    try:
        with open(file_path, 'r') as f:
            lines = f.readlines()
            result["file_row_count"] = len(lines)
            if len(lines) > 0:
                result["file_headers"] = lines[0].strip().split(',')
    except:
        pass

# Save Result
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)

PYEOF

# Fix permissions
chmod 666 /tmp/task_result.json

echo "Export complete. Result saved to /tmp/task_result.json"
cat /tmp/task_result.json