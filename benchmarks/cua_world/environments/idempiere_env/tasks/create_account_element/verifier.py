#!/usr/bin/env python3
"""
Verifier for create_account_element task.

Verifies that:
1. The account record exists in the database.
2. The account attributes (Name, Type, Sign, Summary) are correct.
3. The record was created during the task execution (timestamp check).
4. Uses VLM to verify the UI state as a backup/context check.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import get_final_screenshot, sample_trajectory_frames

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_account_element(traj, env_info, task_info):
    """
    Verify the creation of Account 76500.
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_value = metadata.get('expected_value', '76500')
    expected_name = metadata.get('expected_name', 'Social Media Advertising')
    expected_type = metadata.get('expected_type', 'E') # E = Expense
    expected_sign = metadata.get('expected_sign', 'N') # N = Natural
    expected_summary = metadata.get('expected_summary', 'N')

    score = 0
    max_score = 100
    feedback_parts = []
    
    # ================================================================
    # 1. DATABASE VERIFICATION (Primary)
    # ================================================================
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

    # Criterion 1: Record Exists (25 pts)
    if result.get('found', False):
        score += 25
        feedback_parts.append(f"Account {expected_value} created in database")
    else:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Account {expected_value} NOT found in database. Critical failure.",
            "details": result
        }

    # Criterion 2: Correct Name (20 pts)
    actual_name = result.get('name', '')
    if actual_name == expected_name:
        score += 20
        feedback_parts.append("Name is correct")
    else:
        feedback_parts.append(f"Name mismatch: expected '{expected_name}', got '{actual_name}'")

    # Criterion 3: Correct Account Type (20 pts)
    actual_type = result.get('account_type', '')
    if actual_type == expected_type:
        score += 20
        feedback_parts.append("Account Type is correct (Expense)")
    else:
        feedback_parts.append(f"Account Type mismatch: expected '{expected_type}', got '{actual_type}'")

    # Criterion 4: Correct Account Sign (10 pts)
    actual_sign = result.get('account_sign', '')
    if actual_sign == expected_sign:
        score += 10
        feedback_parts.append("Account Sign is correct (Natural)")
    else:
        feedback_parts.append(f"Account Sign mismatch: expected '{expected_sign}', got '{actual_sign}'")

    # Criterion 5: Is Summary (5 pts)
    actual_summary = result.get('is_summary', '')
    if actual_summary == expected_summary:
        score += 5
        feedback_parts.append("Summary flag is correct")
    else:
        feedback_parts.append(f"Summary flag mismatch: expected '{expected_summary}', got '{actual_summary}'")

    # Criterion 6: Description Check (10 pts)
    actual_desc = result.get('description', '').lower()
    if "social media" in actual_desc:
        score += 10
        feedback_parts.append("Description contains valid keywords")
    else:
        feedback_parts.append("Description is missing or irrelevant")

    # Criterion 7: Anti-Gaming / Timestamp (10 pts)
    if result.get('created_during_task', False):
        score += 10
        feedback_parts.append("Record created during task session")
    else:
        feedback_parts.append("WARNING: Record timestamp indicates it was pre-existing or created before task start")

    # ================================================================
    # 2. VLM VERIFICATION (Secondary/Backup)
    # ================================================================
    # We check if the final screen looks like the Account Element window
    if query_vlm:
        final_screen = get_final_screenshot(traj)
        if final_screen:
            prompt = """
            Analyze this screenshot of the iDempiere ERP system.
            1. Is the "Account Element" or "Element Value" window visible?
            2. Is there a record form showing "Social Media Advertising" or "76500"?
            3. Are there success notifications or status bars indicating a saved record?
            
            Return JSON:
            {
                "window_visible": bool,
                "record_visible": bool,
                "confidence": "low|medium|high"
            }
            """
            vlm_res = query_vlm(prompt=prompt, image=final_screen)
            if vlm_res.get('success'):
                parsed = vlm_res.get('parsed', {})
                if parsed.get('record_visible'):
                    # Bonus validation or tie-breaker if DB query was ambiguous (unlikely here)
                    feedback_parts.append("(VLM confirmed record visibility)")

    # ================================================================
    # SCORING & DECISION
    # ================================================================
    
    # Pass threshold: 65 points AND record must exist (which is checked at start)
    passed = (score >= 65)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }