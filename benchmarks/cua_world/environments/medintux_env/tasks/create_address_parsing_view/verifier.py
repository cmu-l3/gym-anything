#!/usr/bin/env python3
"""
Verifier for create_address_parsing_view task.

Verifies:
1. SQL View existence and structure.
2. Logic correctness via dynamic data injection (performed in export_result.sh).
3. CSV output file existence.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_address_parsing_view(traj, env_info, task_info):
    """
    Verify the SQL View creation and address parsing logic.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result JSON from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    # 1. View Exists (20 pts)
    if result.get('view_exists', False):
        score += 20
        feedback_parts.append("SQL View created successfully")
    else:
        feedback_parts.append("SQL View 'vue_adresse_parsed' NOT found")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # 2. Columns Correct (20 pts)
    if result.get('columns_correct', False):
        score += 20
        feedback_parts.append("View columns appear correct")
    else:
        feedback_parts.append("View columns missing required fields (num_voie, nom_voie)")

    # 3. Logic Correct via Injection Test (50 pts)
    # This is the most critical part: did the parsing actually work on new data?
    logic_correct = result.get('logic_correct', False)
    test_case = result.get('test_case', {})
    
    if logic_correct:
        score += 50
        feedback_parts.append("Address parsing logic verified with test data")
    else:
        actual_num = test_case.get('actual_num', 'NULL')
        actual_voie = test_case.get('actual_voie', 'NULL')
        expected_num = test_case.get('expected_num', '')
        feedback_parts.append(f"Parsing logic failed on test case. Expected '{expected_num}' but got '{actual_num}'")

    # 4. CSV Export (10 pts)
    if result.get('csv_exists', False) and result.get('csv_size', 0) > 10:
        score += 10
        feedback_parts.append("CSV export file created")
    else:
        feedback_parts.append("CSV export file missing or empty")

    passed = (score >= 70 and logic_correct)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": result
    }