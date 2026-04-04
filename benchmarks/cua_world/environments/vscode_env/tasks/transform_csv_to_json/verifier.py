#!/usr/bin/env python3
"""
Verifier for CSV to JSON transformation task
Checks that flat CSV was correctly transformed to nested JSON structure
"""

import sys
import os
import logging
import tempfile
import json
import csv
from pathlib import Path
from typing import Dict, Any, Tuple, List

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_csv_to_json_transformation(traj, env_info, task_info):
    """
    Verify that CSV was correctly transformed to nested JSON structure.
    
    Success criteria (all must pass for data integrity):
    1. JSON file exists and is valid JSON
    2. Has correct nested structure (departments -> employees -> roles)
    3. All CSV rows are accounted for in JSON (no data loss)
    4. Employees with multiple roles are correctly grouped
    5. Department names are preserved exactly (including those with commas)
    6. Employee data is properly trimmed and normalized
    
    Returns:
        dict with keys: passed, score, feedback
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "❌ Copy function not available"
        }
    
    temp_dir = tempfile.mkdtemp(prefix='csv_json_verify_')
    
    try:
        # Copy files from container
        csv_path = Path(temp_dir) / "employee_access.csv"
        json_path = Path(temp_dir) / "access_control.json"
        
        try:
            copy_from_env("/home/ga/workspace/data_migration/employee_access.csv", str(csv_path))
        except Exception as e:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"❌ Failed to copy CSV file: {str(e)}"
            }
        
        try:
            copy_from_env("/home/ga/workspace/data_migration/access_control.json", str(json_path))
        except Exception as e:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"❌ Failed to copy JSON file: {str(e)}"
            }
        
        feedback_parts = []
        
        # Criterion 1: Check JSON file exists and has content
        if not json_path.exists():
            return {
                "passed": False,
                "score": 0,
                "feedback": "❌ Output JSON file (access_control.json) not found"
            }
        
        if json_path.stat().st_size == 0:
            return {
                "passed": False,
                "score": 0,
                "feedback": "❌ Output JSON file is empty"
            }
        
        feedback_parts.append("✅ JSON file exists")
        
        # Criterion 2: Parse JSON and validate it's valid JSON
        try:
            with open(json_path, 'r', encoding='utf-8') as f:
                output_data = json.load(f)
            feedback_parts.append("✅ JSON is valid")
        except json.JSONDecodeError as e:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"❌ Invalid JSON format: {str(e)}"
            }
        except Exception as e:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"❌ Error reading JSON: {str(e)}"
            }
        
        # Criterion 3: Check structure - should have "departments" key
        if "departments" not in output_data:
            return {
                "passed": False,
                "score": 0,
                "feedback": "❌ Missing 'departments' key in JSON root. Expected structure: {\"departments\": {...}}"
            }
        
        departments = output_data["departments"]
        if not isinstance(departments, dict):
            return {
                "passed": False,
                "score": 0,
                "feedback": "❌ 'departments' should be an object/dict, not a list or other type"
            }
        
        feedback_parts.append("✅ Correct root structure")
        
        # Parse CSV to get expected data
        csv_data = []
        try:
            with open(csv_path, 'r', encoding='utf-8') as f:
                reader = csv.DictReader(f)
                for row in reader:
                    csv_data.append({
                        'department': row['department'].strip(),
                        'employee_id': row['employee_id'].strip(),
                        'employee_name': row['employee_name'].strip(),
                        'role': row['role'].strip()
                    })
        except Exception as e:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"❌ Error reading CSV file: {str(e)}"
            }
        
        if len(csv_data) == 0:
            return {
                "passed": False,
                "score": 0,
                "feedback": "❌ CSV file is empty or unreadable"
            }
        
        total_csv_rows = len(csv_data)
        
        # Build expected structure from CSV
        expected_departments = {}
        for row in csv_data:
            dept = row['department']
            emp_id = row['employee_id']
            emp_name = row['employee_name']
            role = row['role']
            
            if dept not in expected_departments:
                expected_departments[dept] = {}
            
            if emp_id not in expected_departments[dept]:
                expected_departments[dept][emp_id] = {
                    'name': emp_name,
                    'roles': []
                }
            
            # Add role if not already present (avoid duplicates)
            if role not in expected_departments[dept][emp_id]['roles']:
                expected_departments[dept][emp_id]['roles'].append(role)
        
        # Criterion 4: Verify all departments are present
        expected_dept_names = set(expected_departments.keys())
        actual_dept_names = set(departments.keys())
        
        if expected_dept_names != actual_dept_names:
            missing = expected_dept_names - actual_dept_names
            extra = actual_dept_names - expected_dept_names
            error_msg = []
            if missing:
                error_msg.append(f"Missing departments: {missing}")
            if extra:
                error_msg.append(f"Extra departments: {extra}")
            return {
                "passed": False,
                "score": 0,
                "feedback": "❌ Department mismatch. " + " | ".join(error_msg)
            }
        
        feedback_parts.append(f"✅ All {len(expected_dept_names)} departments present")
        
        # Criterion 5: Verify each department's structure and employees
        total_json_entries = 0
        employees_with_multiple_roles = 0
        unique_employees = 0
        
        for dept_name, dept_data in departments.items():
            # Check for 'employees' key
            if 'employees' not in dept_data:
                return {
                    "passed": False,
                    "score": 0,
                    "feedback": f"❌ Department '{dept_name}' missing 'employees' key. Expected structure: {{\"employees\": [...]}}"
                }
            
            employees_list = dept_data['employees']
            if not isinstance(employees_list, list):
                return {
                    "passed": False,
                    "score": 0,
                    "feedback": f"❌ Department '{dept_name}' employees should be a list/array"
                }
            
            # Build map of employees in JSON
            json_employees = {}
            for emp in employees_list:
                if not isinstance(emp, dict):
                    return {
                        "passed": False,
                        "score": 0,
                        "feedback": f"❌ Employee entry in '{dept_name}' should be an object"
                    }
                
                if 'id' not in emp:
                    return {
                        "passed": False,
                        "score": 0,
                        "feedback": f"❌ Employee in '{dept_name}' missing 'id' field"
                    }
                
                json_employees[emp['id']] = emp
            
            # Compare with expected
            expected_employees = expected_departments[dept_name]
            
            if set(json_employees.keys()) != set(expected_employees.keys()):
                missing = set(expected_employees.keys()) - set(json_employees.keys())
                extra = set(json_employees.keys()) - set(expected_employees.keys())
                error_msg = []
                if missing:
                    error_msg.append(f"missing employee IDs: {missing}")
                if extra:
                    error_msg.append(f"extra employee IDs: {extra}")
                return {
                    "passed": False,
                    "score": 0,
                    "feedback": f"❌ Employee mismatch in department '{dept_name}': " + ", ".join(error_msg)
                }
            
            # Verify each employee's data
            for emp_id, expected_emp in expected_employees.items():
                json_emp = json_employees[emp_id]
                
                # Check 'name' field exists
                if 'name' not in json_emp:
                    return {
                        "passed": False,
                        "score": 0,
                        "feedback": f"❌ Employee {emp_id} in '{dept_name}' missing 'name' field"
                    }
                
                # Check name matches (case-sensitive, but trimmed)
                json_name = str(json_emp['name']).strip()
                expected_name = expected_emp['name'].strip()
                
                if json_name != expected_name:
                    return {
                        "passed": False,
                        "score": 0,
                        "feedback": f"❌ Name mismatch for {emp_id}: expected '{expected_name}', got '{json_name}'"
                    }
                
                # Check 'roles' field exists and is a list
                if 'roles' not in json_emp:
                    return {
                        "passed": False,
                        "score": 0,
                        "feedback": f"❌ Employee {emp_id} in '{dept_name}' missing 'roles' field"
                    }
                
                if not isinstance(json_emp['roles'], list):
                    return {
                        "passed": False,
                        "score": 0,
                        "feedback": f"❌ Employee {emp_id} 'roles' should be an array/list"
                    }
                
                # Check roles match (order-independent)
                expected_roles = set(expected_emp['roles'])
                json_roles = set(str(r).strip() for r in json_emp['roles'])
                
                if expected_roles != json_roles:
                    return {
                        "passed": False,
                        "score": 0,
                        "feedback": f"❌ Roles mismatch for {emp_id} ({json_name}): expected {expected_roles}, got {json_roles}"
                    }
                
                # Count entries and multi-role employees
                role_count = len(json_emp['roles'])
                total_json_entries += role_count
                unique_employees += 1
                
                if role_count > 1:
                    employees_with_multiple_roles += 1
        
        # Criterion 6: Verify total count matches (all CSV rows accounted for)
        if total_json_entries != total_csv_rows:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"❌ Data loss detected: {total_csv_rows} CSV rows vs {total_json_entries} JSON role entries. All CSV rows must be preserved."
            }
        
        feedback_parts.append(f"✅ All {total_csv_rows} CSV rows preserved in JSON")
        
        # Criterion 7: Check that multi-role employees were properly grouped
        # From the CSV, we expect exactly 4 employees with multiple roles:
        # E001 (2 roles), E006 (2 roles), E009 (2 roles), E010 (2 roles)
        expected_multi_role_count = 4
        
        if employees_with_multiple_roles != expected_multi_role_count:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"❌ Role grouping incorrect: expected {expected_multi_role_count} employees with multiple roles, found {employees_with_multiple_roles}. Employees with same ID should have roles grouped in array."
            }
        
        feedback_parts.append(f"✅ {employees_with_multiple_roles} multi-role employees correctly grouped")
        
        # Criterion 8: Verify department with comma was handled correctly
        dept_with_comma = "Sales, Marketing"
        if dept_with_comma not in departments:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"❌ Department name with comma not preserved: expected '{dept_with_comma}'"
            }
        
        feedback_parts.append("✅ Department names with commas handled correctly")
        
        # All checks passed!
        feedback_parts.append(f"✅ {unique_employees} unique employees across {len(expected_dept_names)} departments")
        
        return {
            "passed": True,
            "score": 100,
            "feedback": " | ".join(feedback_parts)
        }
        
    except Exception as e:
        logger.exception("Verification error")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"❌ Verification exception: {str(e)}"
        }
    
    finally:
        # Cleanup temp directory
        import shutil
        if os.path.exists(temp_dir):
            shutil.rmtree(temp_dir, ignore_errors=True)
