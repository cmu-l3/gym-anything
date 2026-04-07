#!/bin/bash
# Export results for oracle_xml_data_export task
# Validates XML structure, file existence, and PL/SQL function status

set -e

echo "=== Exporting Oracle XML Data Export Results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final_screenshot.png

# Get task start time for timestamp validation
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# Use Python for robust XML parsing and DB querying
python3 << 'PYEOF'
import oracledb
import json
import os
import xml.etree.ElementTree as ET
import datetime

result = {
    "org_file_exists": False,
    "org_file_valid_xml": False,
    "org_root_tag": "",
    "org_dept_count": 0,
    "org_emp_count": 0,
    "org_attributes_ok": False,
    "org_file_created_during_task": False,
    
    "comp_file_exists": False,
    "comp_file_valid_xml": False,
    "comp_root_tag": "",
    "comp_job_count": 0,
    "comp_fields_ok": False,
    "comp_file_created_during_task": False,
    
    "function_exists": False,
    "function_status": "INVALID",
    "function_test_result": "N/A",
    "function_test_emp_count": 0,
    
    "timestamp": datetime.datetime.now().isoformat()
}

task_start_ts = float(os.environ.get("TASK_START", 0))

def check_file_timestamp(filepath):
    try:
        mtime = os.path.getmtime(filepath)
        return mtime > task_start_ts
    except OSError:
        return False

# --- 1. Validate Organization Structure XML ---
org_path = "/home/ga/Desktop/org_structure.xml"
if os.path.exists(org_path):
    result["org_file_exists"] = True
    result["org_file_created_during_task"] = check_file_timestamp(org_path)
    
    try:
        # Check size first
        if os.path.getsize(org_path) > 100:
            tree = ET.parse(org_path)
            root = tree.getroot()
            result["org_root_tag"] = root.tag
            result["org_file_valid_xml"] = True
            
            # Count departments and employees
            depts = root.findall(".//department")
            result["org_dept_count"] = len(depts)
            
            emps = root.findall(".//employee")
            result["org_emp_count"] = len(emps)
            
            # Check structure of first dept/emp
            if depts:
                d = depts[0]
                has_id = 'id' in d.attrib
                has_name = d.find('name') is not None
                has_mgr = d.find('manager_name') is not None
                
                # Check employee fields
                emp_attrs_ok = False
                dept_emps = d.findall(".//employee")
                if dept_emps:
                    e = dept_emps[0]
                    e_fields = ['first_name', 'last_name', 'email', 'job_id', 'salary']
                    emp_attrs_ok = all(e.find(f) is not None for f in e_fields)
                
                result["org_attributes_ok"] = has_id and has_name and has_mgr and emp_attrs_ok
    except ET.ParseError as e:
        result["org_xml_error"] = str(e)
    except Exception as e:
        result["org_error"] = str(e)

# --- 2. Validate Compensation Feed XML ---
comp_path = "/home/ga/Desktop/compensation_feed.xml"
if os.path.exists(comp_path):
    result["comp_file_exists"] = True
    result["comp_file_created_during_task"] = check_file_timestamp(comp_path)
    
    try:
        if os.path.getsize(comp_path) > 100:
            tree = ET.parse(comp_path)
            root = tree.getroot()
            result["comp_root_tag"] = root.tag
            result["comp_file_valid_xml"] = True
            
            jobs = root.findall(".//job")
            result["comp_job_count"] = len(jobs)
            
            if jobs:
                j = jobs[0]
                req_fields = ['title', 'min_salary', 'max_salary', 'employee_count', 'avg_actual_salary', 'total_payroll']
                result["comp_fields_ok"] = all(j.find(f) is not None for f in req_fields) and 'id' in j.attrib
    except ET.ParseError as e:
        result["comp_xml_error"] = str(e)
    except Exception as e:
        result["comp_error"] = str(e)

# --- 3. Validate PL/SQL Function ---
try:
    conn = oracledb.connect(user="hr", password="hr123", dsn="localhost:1521/XEPDB1")
    cursor = conn.cursor()
    
    # Check status
    cursor.execute("SELECT status FROM user_objects WHERE object_name = 'GENERATE_DEPT_XML' AND object_type = 'FUNCTION'")
    row = cursor.fetchone()
    if row:
        result["function_exists"] = True
        result["function_status"] = row[0]
    
    # Test function execution (Dept 60 = IT, has 5 employees)
    if result["function_status"] == "VALID":
        try:
            cursor.execute("SELECT generate_dept_xml(60).getStringVal() FROM dual")
            xml_out = cursor.fetchone()[0]
            if xml_out:
                result["function_test_result"] = "SUCCESS"
                # Parse returned XML fragment
                try:
                    # XMLType might return just the fragment, wrap in root for parsing
                    xml_str = f"<root>{xml_out}</root>"
                    f_root = ET.fromstring(xml_str)
                    
                    # Depending on how they wrote it, it might be <department>... or just content
                    # If they followed instructions, it returns a <department> element
                    dept_el = f_root.find("department")
                    if dept_el is not None:
                        result["function_test_emp_count"] = len(dept_el.findall(".//employee"))
                    else:
                        # Maybe root is department
                        if f_root.tag == "department" or (len(f_root) > 0 and f_root[0].tag == "department"):
                             result["function_test_emp_count"] = len(f_root.findall(".//employee"))
                except Exception as xml_e:
                    result["function_test_parsing_error"] = str(xml_e)
        except Exception as exec_e:
            result["function_test_result"] = f"EXECUTION ERROR: {str(exec_e)}"
            
    cursor.close()
    conn.close()

except Exception as e:
    result["db_error"] = str(e)

# Save result
with open("/tmp/oracle_xml_export_result.json", "w") as f:
    json.dump(result, f, indent=2)

print("Export complete.")
PYEOF

# Echo content for debugging logs
echo "Result JSON content:"
cat /tmp/oracle_xml_export_result.json

echo "=== Export Complete ==="