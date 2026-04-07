#!/bin/bash
# Export script for PL/SQL SQL Injection Remediation
# Runs internal verification tests (functional & security) and exports results

set -e

echo "=== Exporting SQL Injection Remediation Results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/final_state.png

# Path for output
RESULT_JSON="/tmp/task_result.json"
OUTPUT_SQL_FILE="/home/ga/Desktop/secure_reporting.sql"

# Check if output file exists
FILE_EXISTS=false
if [ -f "$OUTPUT_SQL_FILE" ]; then
    FILE_EXISTS=true
fi

# --- Run Internal Verification Script (Python) ---
# We run this INSIDE the container context via a heredoc passed to python3
# This script connects to DB, runs tests (attacks), and inspects the package source.

cat > /tmp/verify_internal.py << 'PYEOF'
import oracledb
import json
import re
import os

results = {
    "package_valid": False,
    "search_functional": False,
    "search_secure": False,
    "sort_functional": False,
    "sort_secure": False,
    "source_checks": {
        "using_clause": False,
        "dbms_assert": False,
        "explicit_whitelist": False
    },
    "file_exported": False,
    "errors": []
}

try:
    # 1. Connect to DB
    conn = oracledb.connect(user="hr", password="hr123", dsn="localhost:1521/XEPDB1")
    cursor = conn.cursor()

    # 2. Check Package Validity
    cursor.execute("SELECT status FROM user_objects WHERE object_name = 'HR_LEGACY_REPORTING' AND object_type = 'PACKAGE BODY'")
    row = cursor.fetchone()
    if row and row[0] == 'VALID':
        results["package_valid"] = True
    else:
        results["errors"].append(f"Package status is {row[0] if row else 'MISSING'}")

    if results["package_valid"]:
        # 3. Test SEARCH_EMPLOYEES (Functionality)
        # Search for 'King', expect 'King' (Steven and Janette)
        try:
            out_cur = conn.cursor()
            cursor.callproc("hr_legacy_reporting.search_employees", ["King", out_cur])
            rows = out_cur.fetchall()
            # Expect 2 rows (Steven King, Janette King)
            if len(rows) == 2:
                results["search_functional"] = True
            else:
                results["errors"].append(f"Search functional fail: Expected 2 rows for 'King', got {len(rows)}")
        except Exception as e:
            results["errors"].append(f"Search functional error: {str(e)}")

        # 4. Test SEARCH_EMPLOYEES (Security - Injection)
        # Attack: ' OR '1'='1
        # If vulnerable: returns ALL 107 rows
        # If fixed (bind var): searches for literal string "' OR '1'='1", returns 0 rows
        try:
            out_cur = conn.cursor()
            cursor.callproc("hr_legacy_reporting.search_employees", ["' OR '1'='1", out_cur])
            rows = out_cur.fetchall()
            if len(rows) == 0:
                results["search_secure"] = True
            else:
                results["errors"].append(f"Search INSECURE: Injection payload returned {len(rows)} rows (expected 0)")
        except Exception as e:
            results["errors"].append(f"Search security check error: {str(e)}")

        # 5. Test RANK_DEPARTMENTS (Functionality)
        # Sort by department_name
        try:
            out_cur = conn.cursor()
            cursor.callproc("hr_legacy_reporting.rank_departments", ["department_name", out_cur])
            rows = out_cur.fetchall()
            if len(rows) > 0:
                # Basic check: is the first one 'Administration' (ID 10)? Or 'Accounting'?
                # 'Accounting' (ID 110) comes before 'Administration' (ID 10) alphabetically? No.
                # Let's just check it didn't crash and returned rows.
                results["sort_functional"] = True
                
                # Check for "lazy fix" (ORDER BY :1) which suppresses sorting
                # If they used bind var for order by, output won't be sorted by name.
                # Default order is usually ID. 
                # ID order: 10 (Admin), 20 (Marketing)...
                # Name order: Accounting, Administration...
                first_dept_name = rows[0][1] # department_name is 2nd col
                # If valid sort, first might be 'Accounting' or 'Administration' depending on data
                # Let's rely on the security check + source check for the lazy fix detection
        except Exception as e:
            results["errors"].append(f"Sort functional error: {str(e)}")

        # 6. Test RANK_DEPARTMENTS (Security - Injection)
        # Attack: invalid column name or SQL injection
        # Payload: "department_id, (SELECT 1 FROM DUAL)" -> Invalid column name if sanitized
        try:
            out_cur = conn.cursor()
            cursor.callproc("hr_legacy_reporting.rank_departments", ["department_id DESC", out_cur])
            # If they used simple_sql_name, 'department_id DESC' might fail (it allows simple names only).
            # If they used a whitelist, 'department_id DESC' might fail if not in list.
            # Let's try a pure injection: "department_id UNION SELECT..."
            
            payload = "department_id" # This should work
            
            # Now bad payload
            bad_payload = "department_id invalid_syntax" 
            try:
                cursor.callproc("hr_legacy_reporting.rank_departments", [bad_payload, out_cur])
                # If this runs without error, it MIGHT be vulnerable if it executed `ORDER BY department_id invalid_syntax`
                # But that is invalid SQL, so it should crash the SQL engine.
                # If they used DBMS_ASSERT.SIMPLE_SQL_NAME, it raises ORA-44003.
                # If they used Whitelist, it falls to ELSE and probably raises error or does default.
                
                # If it didn't raise an exception, investigate why.
                # Maybe they quoted it? `ORDER BY 'payload'` -> valid SQL, but constant sort.
                pass
            except oracledb.DatabaseError as e:
                error_obj = e.args[0]
                # ORA-44003: invalid SQL name (DBMS_ASSERT)
                # ORA-009xx: SQL syntax error (Vulnerable but crashed DB engine)
                # Custom error (Whitelist)
                
                # To distinguish ORA-44003 (Secure) from ORA-00933 (Vulnerable, passed string to SQL engine),
                # we need to know the error code.
                if 'ORA-44003' in str(error_obj) or 'ORA-44004' in str(error_obj):
                     results["sort_secure"] = True # DBMS_ASSERT caught it
                elif 'ORA-20' in str(error_obj): # Custom user exception (likely whitelist)
                     results["sort_secure"] = True
                else:
                    # ORA-00933 means the string reached the SQL engine -> VULNERABLE (mostly)
                    # OR they are using bind variable for order by (ORDER BY :1), which is invalid for functionality but secure.
                    results["errors"].append(f"Sort verification raised: {str(error_obj)}")
        except Exception as e:
             results["errors"].append(f"Sort security check error: {str(e)}")

    # 7. Get Package Source for Static Analysis
    cursor.execute("SELECT text FROM user_source WHERE name = 'HR_LEGACY_REPORTING' AND type = 'PACKAGE BODY' ORDER BY line")
    source_lines = [row[0] for row in cursor.fetchall()]
    source_text = "".join(source_lines).upper()

    # Check for USING clause (Bind variable indicator) in SEARCH
    if "USING" in source_text and "LIKE" in source_text:
        results["source_checks"]["using_clause"] = True

    # Check for DBMS_ASSERT in RANK
    if "DBMS_ASSERT" in source_text:
        results["source_checks"]["dbms_assert"] = True
    
    # Check for Whitelist logic (CASE or IF checking column names)
    if "CASE" in source_text or ("IF" in source_text and "DEPARTMENT_ID" in source_text):
        results["source_checks"]["explicit_whitelist"] = True
        
    # Check for "lazy fix" (ORDER BY :bind)
    # Pattern: ORDER BY\s*:\w+ or ORDER BY\s*variables
    # Hard to regex perfectly, but if they lack DBMS_ASSERT/Whitelist and have USING in rank, it's suspicious.
    
    conn.close()

except Exception as e:
    results["errors"].append(f"Fatal error: {str(e)}")

# Check file existence check passed from bash
if os.path.exists('/home/ga/Desktop/secure_reporting.sql'):
    results["file_exported"] = True

with open('/tmp/task_result.json', 'w') as f:
    json.dump(results, f, indent=4)
PYEOF

# Run the python script
python3 /tmp/verify_internal.py

echo "Internal verification complete. JSON result generated."
cat /tmp/task_result.json