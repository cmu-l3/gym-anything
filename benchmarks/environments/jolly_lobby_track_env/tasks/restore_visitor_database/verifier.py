#!/usr/bin/env python3
"""
Verifier for restore_visitor_database task.
"""

import json
import tempfile
import os
import logging
import time
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_restore_visitor_database(traj, env_info, task_info):
    """
    Verify that the database was restored.
    
    Criteria:
    1. Active database file size matches backup size (primary technical check).
    2. Active database was modified after task start (anti-gaming).
    3. Confirmation file exists with correct text (user compliance).
    4. VLM: Final screenshot shows visitor records in the list (visual proof).
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result JSON
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
    feedback_parts = []
    
    # 1. Database File Check (40 points)
    db_restored = result.get('db_restored_heuristic', False)
    db_size = result.get('db_size', 0)
    backup_size = result.get('backup_size', 0)
    
    if db_restored:
        score += 40
        feedback_parts.append(f"Database file restored successfully (Size: {db_size} bytes)")
    else:
        feedback_parts.append(f"Database file size ({db_size}) does not match expected restored size ({backup_size})")

    # 2. Modification Check (10 points)
    task_start = result.get('task_start', 0)
    db_mtime = result.get('db_mtime', 0)
    
    if db_mtime > task_start:
        score += 10
        feedback_parts.append("Database modified during task")
    else:
        feedback_parts.append("Database file not modified")

    # 3. Confirmation File (20 points)
    confirm_exists = result.get('confirmation_exists', False)
    confirm_content = result.get('confirmation_content', "").lower()
    
    if confirm_exists:
        score += 10
        if "successfully" in confirm_content or "restored" in confirm_content:
            score += 10
            feedback_parts.append("Confirmation file valid")
        else:
            feedback_parts.append("Confirmation file exists but content mismatch")
    else:
        feedback_parts.append("Confirmation file missing")

    # 4. VLM Verification (30 points)
    # Check if UI shows records
    final_screenshot = get_final_screenshot(traj)
    if final_screenshot:
        # Prompt for VLM
        prompt = """
        Analyze this screenshot of the 'Jolly Lobby Track' software.
        1. Look for the visitor list or log grid.
        2. Are there visitor rows/records visible in the grid? (Look for names, dates, or filled rows).
        3. Or is the list completely empty/blank?
        
        Answer JSON: {"records_visible": true/false, "description": "..."}
        """
        
        try:
            vlm_response = query_vlm(images=[final_screenshot], prompt=prompt)
            parsed = vlm_response.get('parsed', {})
            records_visible = parsed.get('records_visible', False)
            
            if records_visible:
                score += 30
                feedback_parts.append("Visual verification passed: Records visible")
            else:
                feedback_parts.append("Visual verification failed: No records visible in UI")
        except Exception as e:
            logger.warning(f"VLM check failed: {e}")
            # Fallback points if DB check passed strongly
            if db_restored:
                score += 15
                feedback_parts.append("VLM check skipped (error), partial credit based on file check")
    else:
        feedback_parts.append("No screenshot available for visual verification")

    # Final Pass/Fail
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }