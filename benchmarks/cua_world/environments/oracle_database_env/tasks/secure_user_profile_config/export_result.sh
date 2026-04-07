#!/bin/bash
# Export results for secure_user_profile_config task

echo "=== Exporting Security Config Results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Use Python to extract structured data from Oracle
# We need to query DBA_PROFILES, DBA_USERS, and DBA_SOURCE
python3 << 'PYEOF'
import oracledb
import json
import os
import re

result = {
    "profile_exists": False,
    "profile_limits": {},
    "function_exists": False,
    "function_owner": "",
    "function_source": "",
    "hr_profile_assignment": "",
    "hr_account_status": "",
    "db_error": ""
}

try:
    # Connect as SYSTEM to view DBA views
    conn = oracledb.connect(user="system", password="OraclePassword123", dsn="localhost:1521/XEPDB1")
    cursor = conn.cursor()

    # 1. Check Profile Configuration
    cursor.execute("""
        SELECT resource_name, limit
        FROM dba_profiles
        WHERE profile = 'SECURE_DEV_PROFILE'
    """)
    rows = cursor.fetchall()
    if rows:
        result["profile_exists"] = True
        for row in rows:
            result["profile_limits"][row[0]] = row[1]

    # 2. Check Verification Function Existence and Source
    cursor.execute("""
        SELECT owner, name
        FROM dba_objects
        WHERE object_name = 'STRICT_PASS_VERIFY'
          AND object_type = 'FUNCTION'
    """)
    func_row = cursor.fetchone()
    if func_row:
        result["function_exists"] = True
        result["function_owner"] = func_row[0]
        
        # Get source code to verify logic
        cursor.execute("""
            SELECT text
            FROM dba_source
            WHERE name = 'STRICT_PASS_VERIFY'
              AND owner = :owner
            ORDER BY line
        """, owner=func_row[0])
        source_lines = [r[0] for r in cursor.fetchall()]
        result["function_source"] = "".join(source_lines)

    # 3. Check HR User Status
    cursor.execute("""
        SELECT profile, account_status
        FROM dba_users
        WHERE username = 'HR'
    """)
    user_row = cursor.fetchone()
    if user_row:
        result["hr_profile_assignment"] = user_row[0]
        result["hr_account_status"] = user_row[1]

    cursor.close()
    conn.close()

except Exception as e:
    result["db_error"] = str(e)

# Save result to file
with open("/tmp/security_config_result.json", "w") as f:
    json.dump(result, f, indent=2)

print("Export complete.")
PYEOF

# Fix permissions
sudo chmod 666 /tmp/security_config_result.json 2>/dev/null || true

echo "=== Export Script Finished ==="