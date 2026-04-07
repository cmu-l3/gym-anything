#!/usr/bin/env python3
"""
Verifier for archive_departing_employee task.

Verification Strategy:
1. Database Check (Primary):
   - Walter Horton must exist in the database (not deleted).
   - Walter Horton's 'active' field must be False.
   - Active employee count should have decreased by exactly 1.
2. VLM Check (Secondary):
   - Final screenshot should NOT show Walter Horton in the Kanban/List view.
"""

import json
import logging
import os
import tempfile
from typing import Dict, Any

# Import VLM utils provided by the framework
try:
    from vlm_utils import query_vlm, get_final_screenshot
except ImportError:
    # Fallback for local testing
    def query_vlm(*args, **kwargs): return {"success": False, "error": "ImportError"}
    def get_final_screenshot(*args, **kwargs): return None

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_archive_departing_employee(traj, env_info, task_info):
    """
    Verify that Walter Horton was correctly archived in Odoo.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # ----------------------------------------------------------------
    # 1. Retrieve Result JSON from Environment
    # ----------------------------------------------------------------
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # ----------------------------------------------------------------
    # 2. Evaluate Database Criteria
    # ----------------------------------------------------------------
    score = 0
    feedback_parts = []
    
    walter_exists = result.get('walter_exists_in_db', False)
    walter_active = result.get('walter_active', True)
    initial_count = result.get('initial_active_count', 0)
    final_count = result.get('final_active_count', 0)
    
    # Criterion 1: Employee is Archived (50 pts)
    # Must exist AND be inactive
    if walter_exists and not walter_active:
        score += 50
        feedback_parts.append("Walter Horton is correctly archived.")
    elif walter_exists and walter_active:
        feedback_parts.append("Walter Horton is still active (failed to archive).")
    elif not walter_exists:
        feedback_parts.append("Walter Horton record was DELETED instead of archived.")

    # Criterion 2: Record Preservation (15 pts)
    # The record must still exist in the DB (even if deleted, we can't give points for preservation)
    if walter_exists:
        score += 15
        feedback_parts.append("Employee record preserved in database.")
    else:
        feedback_parts.append("Employee record was permanently removed from database.")

    # Criterion 3: Collateral Damage Check (20 pts)
    # Count should decrease by exactly 1
    diff = initial_count - final_count
    if diff == 1:
        score += 20
        feedback_parts.append("Active employee count decreased by exactly 1.")
    elif diff == 0:
        feedback_parts.append("No change in active employee count.")
    else:
        feedback_parts.append(f"Active employee count changed by {diff} (expected 1).")

    # ----------------------------------------------------------------
    # 3. VLM Verification (15 pts)
    # ----------------------------------------------------------------
    # Only verify visually if primary task was at least attempted
    vlm_success = False
    if score >= 50:
        final_screenshot = get_final_screenshot(traj)
        if final_screenshot:
            prompt = """
            You are verifying an Odoo HR task. The goal was to archive (hide) employee "Walter Horton".
            Look at this screenshot of the Employee Directory.
            
            1. Is the "Employees" page visible?
            2. Do you see a card or list item for "Walter Horton"?
            
            If he is archived, he should NOT be visible in the default view.
            
            Respond in JSON:
            {
                "page_visible": true/false,
                "walter_visible": true/false,
                "reasoning": "..."
            }
            """
            vlm_response = query_vlm(prompt=prompt, image=final_screenshot)
            
            if vlm_response.get('success'):
                parsed = vlm_response.get('parsed', {})
                # We want page_visible=True and walter_visible=False
                if parsed.get('page_visible') and not parsed.get('walter_visible'):
                    score += 15
                    vlm_success = True
                    feedback_parts.append("Visual verification passed: Walter Horton is not visible.")
                elif parsed.get('walter_visible'):
                    feedback_parts.append("Visual verification failed: Walter Horton is still visible on screen.")
                else:
                    feedback_parts.append("Visual verification inconclusive.")
    
    # ----------------------------------------------------------------
    # 4. Final Result
    # ----------------------------------------------------------------
    passed = (score >= 70)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "walter_exists": walter_exists,
            "walter_active": walter_active,
            "count_diff": diff,
            "vlm_success": vlm_success
        }
    }