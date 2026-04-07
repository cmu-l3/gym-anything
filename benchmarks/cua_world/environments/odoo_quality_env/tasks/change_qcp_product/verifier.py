#!/usr/bin/env python3
"""
Verifier for change_qcp_product task.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_change_qcp_product(traj, env_info, task_info):
    """
    Verify that the agent changed the Quality Control Point product correctly.
    
    Scoring:
    - QCP Exists (original ID): 15 pts
    - Product is 'Office Chair': 50 pts
    - Old product 'Acoustic Bloc Screens' removed: 20 pts
    - Name and Test Type preserved: 15 pts
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result file
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
            
    if result.get("error"):
        return {"passed": False, "score": 0, "feedback": f"Verification error: {result['error']}"}

    score = 0
    feedback_parts = []
    
    # 1. Check Existence (15 pts)
    if result.get("qcp_exists"):
        score += 15
        feedback_parts.append("QCP record found")
    else:
        feedback_parts.append("QCP record deleted or ID changed")
        return {"passed": False, "score": 0, "feedback": "Critical: The Quality Control Point record was deleted."}

    # 2. Check Product Change (50 pts)
    if result.get("correct_product_associated"):
        score += 50
        feedback_parts.append("Correct product (Office Chair) selected")
    else:
        feedback_parts.append("Office Chair NOT selected")

    # 3. Check Old Product Removal (20 pts)
    if result.get("old_product_removed"):
        score += 20
        feedback_parts.append("Old product removed")
    else:
        feedback_parts.append("Old product (Acoustic Bloc Screens) still present")

    # 4. Check Preservation of Fields (15 pts)
    fields_ok = True
    if not result.get("name_unchanged"):
        feedback_parts.append("QCP Name was changed (should remain 'Visual Inspection - Incoming Screens')")
        fields_ok = False
    if not result.get("test_type_unchanged"):
        feedback_parts.append("Test Type was changed")
        fields_ok = False
        
    if fields_ok:
        score += 15
        feedback_parts.append("Other fields preserved")
    else:
        score += 5 # Partial credit if they only messed up one, but simplified here

    passed = (score >= 85) # Requires existence + new product + removal + fields ok
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }