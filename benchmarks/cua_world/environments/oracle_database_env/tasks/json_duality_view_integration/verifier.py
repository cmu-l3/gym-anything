#!/usr/bin/env python3
"""
Verifier for json_duality_view_integration task.

Scoring Criteria (100 pts):
- View 'DEPT_EMP_DV' exists: 20 pts
- View is VALID: 10 pts
- View definition contains 'JSON': 10 pts (Basic check for duality syntax)
- Dept 300 exists in relational table: 15 pts (Proves insertion worked)
- Dept 300 Name is 'Cloud Operations': 10 pts (Proves update worked)
- Emp 3001 exists: 10 pts
- Emp 3001 Email is 'SGUPTA_CLOUD': 10 pts (Proves nested update worked)
- Emp 3002 exists: 5 pts
- Export file exists and is valid JSON: 5 pts
- Export file content matches expected Dept ID: 5 pts

Pass Threshold: 65 pts
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_json_duality(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    # Copy result file
    with tempfile.TemporaryDirectory() as tmpdir:
        result_path = os.path.join(tmpdir, "json_duality_result.json")
        try:
            copy_from_env("/tmp/json_duality_result.json", result_path)
            if not os.path.exists(result_path):
                return {"passed": False, "score": 0, "feedback": "Result file not found."}
            
            with open(result_path, "r") as f:
                result = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Error loading result: {e}"}

    score = 0
    feedback = []

    # 1. View Existence (20)
    if result.get("view_exists"):
        score += 20
        feedback.append("View DEPT_EMP_DV exists (+20)")
    else:
        feedback.append("View DEPT_EMP_DV not found (0)")

    # 2. View Status (10)
    if result.get("view_status") == "VALID":
        score += 10
        feedback.append("View is VALID (+10)")
    elif result.get("view_exists"):
        feedback.append(f"View exists but status is {result.get('view_status')} (0)")

    # 3. View Definition Check (10)
    # Duality views usually have 'JSON' keyword in their text or are in user_json_duality_views
    view_text = result.get("view_text", "").upper()
    is_duality = result.get("is_duality_view", False)
    if is_duality or "JSON" in view_text:
        score += 10
        feedback.append("View definition indicates JSON Duality (+10)")
    else:
        feedback.append("View definition does not look like a JSON Duality View (0)")

    # 4. Dept 300 Existence (15)
    if result.get("dept_300_exists"):
        score += 15
        feedback.append("Department 300 created in table (+15)")
    else:
        feedback.append("Department 300 not found in relational table (0)")

    # 5. Dept Name Update (10)
    dept_name = result.get("dept_300_name", "")
    if dept_name == "Cloud Operations":
        score += 10
        feedback.append("Department name updated correctly to 'Cloud Operations' (+10)")
    elif dept_name == "Cloud Infrastructure":
        feedback.append("Department name is 'Cloud Infrastructure' - Update step skipped? (0)")
    else:
        feedback.append(f"Department name mismatch: found '{dept_name}' (0)")

    # 6. Emp 3001 Existence (10)
    if result.get("emp_3001_exists"):
        score += 10
        feedback.append("Employee 3001 created in table (+10)")
    else:
        feedback.append("Employee 3001 not found (0)")

    # 7. Emp 3001 Update (10)
    emp_email = result.get("emp_3001_email", "")
    if emp_email == "SGUPTA_CLOUD":
        score += 10
        feedback.append("Employee email updated correctly to 'SGUPTA_CLOUD' (+10)")
    elif emp_email == "SGUPTA":
        feedback.append("Employee email is 'SGUPTA' - Update step skipped? (0)")
    else:
        feedback.append(f"Employee email mismatch: found '{emp_email}' (0)")

    # 8. Emp 3002 Existence (5)
    if result.get("emp_3002_exists"):
        score += 5
        feedback.append("Employee 3002 created in table (+5)")
    else:
        feedback.append("Employee 3002 not found (0)")

    # 9. File Existence (5)
    if result.get("file_exists") and result.get("file_content_valid"):
        score += 5
        feedback.append("Export file exists and is valid JSON (+5)")
    else:
        feedback.append("Export file missing or invalid (0)")

    # 10. File Content (5)
    if result.get("file_matches_id"):
        score += 5
        feedback.append("Export file contains correct Department ID (+5)")

    return {
        "passed": score >= 65,
        "score": score,
        "feedback": "; ".join(feedback)
    }