#!/usr/bin/env python3
"""
Verifier for correct_personal_data_discrepancies task.

Verifies that:
1. Dario Rossi: DOB 1985-05-15, Married, Italian, Male
2. Mei Chen: DOB 1990-11-20, Single, Chinese, Female
3. Sven Olson: DOB 1982-03-10, Married, Swedish, License Exp 2027-05-20
"""

import json
import os
import tempfile
import logging
from typing import Dict, Any

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_correct_personal_data_discrepancies(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result JSON from container
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

    employees = result.get('employees', {})
    feedback_parts = []
    score = 0
    
    # Define targets and points
    # Total points: 100
    # Dario: 30 pts
    # Mei: 30 pts
    # Sven: 30 pts
    # Base/Anti-gaming: 10 pts (All employees found)

    targets = [
        {
            "key": "Dario Rossi",
            "checks": [
                ("dob", "1985-05-15", 10),
                ("marital_status", "Married", 5),
                ("nationality", "Italian", 5),
                ("gender", "1", 10) # 1=Male
            ]
        },
        {
            "key": "Mei Chen",
            "checks": [
                ("dob", "1990-11-20", 10),
                ("marital_status", "Single", 5),
                ("nationality", "Chinese", 5),
                ("gender", "2", 10) # 2=Female
            ]
        },
        {
            "key": "Sven Olson",
            "checks": [
                ("dob", "1982-03-10", 10),
                ("marital_status", "Married", 5),
                ("nationality", "Swedish", 5),
                ("license_exp", "2027-05-20", 10)
            ]
        }
    ]

    employees_found = 0
    
    for target in targets:
        name = target["key"]
        if name not in employees:
            feedback_parts.append(f"❌ {name}: Record not found")
            continue
        
        employees_found += 1
        record = employees[name]
        emp_score = 0
        emp_feedback = []
        
        for field, expected, points in target["checks"]:
            actual = str(record.get(field, "")).strip()
            # Normalize gender for feedback
            display_field = field
            
            if actual == expected:
                emp_score += points
                emp_feedback.append(f"✅ {field}")
            else:
                emp_feedback.append(f"❌ {field} (expected {expected}, got {actual})")
        
        score += emp_score
        feedback_parts.append(f"{name}: {', '.join(emp_feedback)}")

    # Anti-gaming: All 3 employees must exist
    if employees_found == 3:
        score += 10
        feedback_parts.append("✅ All employee records present")
    else:
        feedback_parts.append(f"⚠️ Only {employees_found}/3 records found")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }