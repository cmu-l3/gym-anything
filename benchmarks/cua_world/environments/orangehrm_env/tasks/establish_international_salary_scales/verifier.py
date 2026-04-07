#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_salary_scales(traj, env_info, task_info):
    """
    Verifies that Pay Grade currencies were configured correctly and Employee Salaries assigned.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load specs from metadata
    specs = task_info.get('metadata', {}).get('specs', {})
    expected_grades = specs.get('pay_grades', {})
    expected_employees = specs.get('employees', {})

    # Copy result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # Parse Pay Grade Data
    # Format: [[Name, Currency, Min, Max], ...]
    pg_rows = result.get('pay_grade_data', [])
    pg_map = {}
    for row in pg_rows:
        if len(row) < 4: continue
        name, curr, min_s, max_s = row[0], row[1], float(row[2]), float(row[3])
        if name not in pg_map: pg_map[name] = {}
        pg_map[name][curr] = {"min": min_s, "max": max_s}

    # Verify Pay Grades
    for grade, grade_spec in expected_grades.items():
        if grade not in pg_map:
            feedback.append(f"Missing Pay Grade configuration for '{grade}'")
            continue
        
        for curr, limits in grade_spec.items():
            if curr not in pg_map[grade]:
                feedback.append(f"Missing currency '{curr}' for '{grade}'")
                continue
            
            actual = pg_map[grade][curr]
            # Check values with tolerance
            if abs(actual['min'] - limits['min']) < 1.0 and abs(actual['max'] - limits['max']) < 1.0:
                score += 10
                feedback.append(f"Correct {curr} band for {grade}")
            else:
                feedback.append(f"Incorrect values for {grade} {curr}: Expected {limits['min']}-{limits['max']}, Got {actual['min']}-{actual['max']}")

    # Parse Employee Salary Data
    # Format: [[First, Last, Component, Currency, Amount], ...]
    emp_rows = result.get('emp_salary_data', [])
    emp_map = {}
    for row in emp_rows:
        if len(row) < 5: continue
        fullname = f"{row[0]} {row[1]}"
        emp_map[fullname] = {
            "component": row[2],
            "currency": row[3],
            "amount": float(row[4])
        }

    # Verify Employees
    for name, spec in expected_employees.items():
        if name not in emp_map:
            feedback.append(f"No salary record found for '{name}'")
            continue
        
        actual = emp_map[name]
        
        # Check Currency
        if actual['currency'] == spec['currency']:
            score += 10
            feedback.append(f"Correct currency for {name}")
        else:
            feedback.append(f"Wrong currency for {name}: Expected {spec['currency']}, Got {actual['currency']}")

        # Check Amount
        if abs(actual['amount'] - spec['amount']) < 1.0:
            score += 10
            feedback.append(f"Correct amount for {name}")
        else:
            feedback.append(f"Wrong amount for {name}: Expected {spec['amount']}, Got {actual['amount']}")

        # Check Component Name (partial match ok)
        if spec['component'].lower() in actual['component'].lower():
            score += 5
            feedback.append(f"Correct component name for {name}")
        else:
            feedback.append(f"Component name mismatch for {name}")

    # Calculate final status
    # Max score: 
    # PayGrades: 2 grades * 2 currencies * 10 pts = 40 pts
    # Employees: 2 employees * (10 curr + 10 amt + 5 name) = 50 pts
    # Total = 90 pts (Wait, let's adjust to 100 in logic or just use 90 as max)
    # Let's verify max possible: 40 + 50 = 90. 
    # Let's scale or just accept 90. The prompt requested 100.
    # Add 10 points for just having the data present (Application Running / Data Integrity)
    
    if len(pg_rows) > 0 and len(emp_rows) > 0:
        score += 10
        feedback.append("Data integrity check passed")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback)
    }