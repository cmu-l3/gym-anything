#!/bin/bash
# Export script for Data Cleansing Regex task
# Validates the CLEAN_EMPLOYEES table structure and content using Python

set -e

echo "=== Exporting Data Cleansing Results ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_final.png

# Path to the report file the agent should create
REPORT_PATH="/home/ga/Desktop/data_cleansing_report.txt"

# Run Python validation script inside the container context
# This script connects to DB, checks the table, and outputs a JSON result
python3 << 'PYEOF'
import oracledb
import json
import os
import re

result = {
    "table_exists": False,
    "row_count": 0,
    "columns_correct": False,
    "column_types": {},
    "data_validation": {
        "valid_phones": 0,
        "valid_emails": 0,
        "valid_salaries": 0,
        "valid_dates": 0,
        "clean_names": 0,
        "clean_titles": 0,
        "standard_depts": 0,
        "unique_ids": 0
    },
    "spot_checks": {
        "id_42": False,
        "id_88": False,
        "id_99": False
    },
    "report_file_exists": False,
    "report_file_content": ""
}

try:
    # Connect to DB
    conn = oracledb.connect(user="hr", password="hr123", dsn="localhost:1521/XEPDB1")
    cursor = conn.cursor()

    # 1. Check Table Existence
    cursor.execute("SELECT COUNT(*) FROM user_tables WHERE table_name = 'CLEAN_EMPLOYEES'")
    if cursor.fetchone()[0] > 0:
        result["table_exists"] = True
        
        # 2. Check Row Count
        cursor.execute("SELECT COUNT(*) FROM clean_employees")
        result["row_count"] = cursor.fetchone()[0]
        
        # 3. Check Column Structure
        expected_cols = {
            "EMPLOYEE_ID": "NUMBER",
            "FIRST_NAME": "VARCHAR2",
            "LAST_NAME": "VARCHAR2",
            "EMAIL": "VARCHAR2",
            "PHONE_NUMBER": "VARCHAR2",
            "SALARY": "NUMBER",
            "HIRE_DATE": "DATE",
            "JOB_TITLE": "VARCHAR2",
            "DEPARTMENT_NAME": "VARCHAR2"
        }
        
        cursor.execute("SELECT column_name, data_type FROM user_tab_columns WHERE table_name = 'CLEAN_EMPLOYEES'")
        found_cols = {row[0]: row[1] for row in cursor.fetchall()}
        result["column_types"] = found_cols
        
        cols_ok = True
        for col, dtype in expected_cols.items():
            if col not in found_cols or found_cols[col] != dtype:
                cols_ok = False
        result["columns_correct"] = cols_ok

        # 4. Data Validation (Fetch all rows)
        if cols_ok:
            cursor.execute("SELECT * FROM clean_employees")
            # Get col indices
            desc = [d[0] for d in cursor.description]
            idx = {name: i for i, name in enumerate(desc)}
            
            rows = cursor.fetchall()
            
            ids = set()
            depts = set()
            
            for row in rows:
                # Extract values
                r_id = row[idx["EMPLOYEE_ID"]]
                r_fname = row[idx["FIRST_NAME"]]
                r_lname = row[idx["LAST_NAME"]]
                r_email = row[idx["EMAIL"]]
                r_phone = row[idx["PHONE_NUMBER"]]
                r_sal = row[idx["SALARY"]]
                r_date = row[idx["HIRE_DATE"]]
                r_job = row[idx["JOB_TITLE"]]
                r_dept = row[idx["DEPARTMENT_NAME"]]
                
                # Check ID Uniqueness
                if r_id is not None:
                    ids.add(r_id)
                
                # Check Phone (XXX-XXX-XXXX)
                if r_phone and re.match(r"^\d{3}-\d{3}-\d{4}$", r_phone):
                    result["data_validation"]["valid_phones"] += 1
                    
                # Check Email (lowercase, no space, has @)
                if r_email and r_email == r_email.lower() and " " not in r_email and "@" in r_email:
                    result["data_validation"]["valid_emails"] += 1
                
                # Check Salary (positive number)
                if r_sal is not None and r_sal > 0:
                    result["data_validation"]["valid_salaries"] += 1
                    
                # Check Date (not null)
                if r_date is not None:
                    result["data_validation"]["valid_dates"] += 1
                    
                # Check Names (trimmed)
                if r_fname and r_lname and r_fname.strip() == r_fname and r_lname.strip() == r_lname:
                    result["data_validation"]["clean_names"] += 1
                    
                # Check Job Titles (no abbreviations)
                bad_abbr = r"(^|\s)(Sr\.|Jr\.|Mgr|Engr|Mktg|Asst\.|Dir\.|VP)(\s|$|,)"
                if r_job and not re.search(bad_abbr, r_job, re.IGNORECASE):
                    result["data_validation"]["clean_titles"] += 1
                    
                # Collect depts
                if r_dept:
                    depts.add(r_dept)
                    
                # Spot Checks
                if r_id == 42:
                    if r_fname == "John" and r_lname == "Doe" and r_phone == "555-123-4567":
                        result["spot_checks"]["id_42"] = True
                if r_id == 88:
                    if r_fname == "Jane" and r_lname == "Smith" and r_sal == 92500:
                        result["spot_checks"]["id_88"] = True
                if r_id == 99:
                    if "@unknown.com" in (r_email or ""):
                        result["spot_checks"]["id_99"] = True
                        
            result["data_validation"]["unique_ids"] = len(ids)
            result["data_validation"]["standard_depts"] = len(depts) # Should be low (<10)

except Exception as e:
    result["error"] = str(e)

# Check Report File
report_path = "/home/ga/Desktop/data_cleansing_report.txt"
if os.path.exists(report_path):
    result["report_file_exists"] = True
    try:
        with open(report_path, 'r') as f:
            result["report_file_content"] = f.read(500)
    except:
        pass

# Save Result
with open("/tmp/data_cleansing_result.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

PYEOF

# Copy result to task result path expected by verifier
cp /tmp/data_cleansing_result.json /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "=== Export Complete ==="
cat /tmp/task_result.json