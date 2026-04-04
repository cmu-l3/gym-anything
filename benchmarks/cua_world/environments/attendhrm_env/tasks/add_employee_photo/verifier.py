#!/usr/bin/env python3
"""
Verifier for add_employee_photo task in AttendHRM.

Verification Strategy:
1. Primary: Check database result (exported via JSON) to confirm 'Sarah Connor' has a non-empty photo BLOB.
2. Secondary: VLM analysis of trajectory to confirm UI interaction with the "Photograph" tab and file picker.
3. Anti-gaming: Ensure DB change happened (blob size > 0).

Scores:
- 40 pts: Database confirmation (Photo blob exists and is > 1KB)
- 40 pts: VLM visual confirmation of upload process/result
- 20 pts: Application state (App running, clean exit)
"""

import json
import tempfile
import os
import logging
import sys

# Add parent directory for shared utilities if needed
# sys.path.insert(0, str(Path(__file__).parent.parent))

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_add_employee_photo(traj, env_info, task_info):
    """
    Verify that the employee photo was uploaded.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    feedback_parts = []
    score = 0
    max_score = 100

    # ================================================================
    # 1. Read Result JSON from Guest
    # ================================================================
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    
    try:
        # Path is fixed in export_result.ps1
        copy_from_env("C:\\workspace\\task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to read task result: {e}")
        return {"passed": False, "score": 0, "feedback": "Failed to retrieve task result from environment."}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # ================================================================
    # 2. Database Verification (40 points)
    # ================================================================
    blob_size = result.get('photo_blob_size_bytes', 0)
    # The generated red square bitmap is small but > 0 bytes. 
    # A 200x200 BMP is roughly 120KB (200*200*3 + header).
    # We set a loose threshold of 1KB to differentiate from empty/null.
    
    if blob_size > 1000:
        score += 40
        feedback_parts.append(f"Database confirmed photo storage ({blob_size} bytes).")
    elif blob_size > 0:
        score += 20
        feedback_parts.append(f"Database has data but size is small ({blob_size} bytes).")
    else:
        feedback_parts.append("Database shows NO photo data for employee.")

    # ================================================================
    # 3. App State Verification (20 points)
    # ================================================================
    if result.get('app_was_running', False):
        score += 20
        feedback_parts.append("AttendHRM was running.")
    else:
        feedback_parts.append("AttendHRM was NOT running at end of task.")

    # ================================================================
    # 4. VLM Verification (40 points)
    # ================================================================
    # Use VLM to check if the agent actually navigated the UI.
    # We look for "Sarah Connor" and "Photograph" tab in trajectory frames.
    
    from gym_anything.vlm import sample_trajectory_frames, query_vlm, get_final_screenshot
    
    frames = sample_trajectory_frames(traj, n=4)
    final_shot = get_final_screenshot(traj)
    
    if frames and final_shot:
        vlm_prompt = """
        You are verifying an agent's task to upload a photo for employee "Sarah Connor" in AttendHRM.
        
        Analyze these screenshots. Look for:
        1. An employee named "Sarah Connor" being selected or edited.
        2. The "Photograph" tab or section being active.
        3. A file selection dialog (Windows Explorer style) selecting a .bmp file.
        4. A photo (likely a red square with text "Sarah") appearing in the profile slot.
        
        Return JSON:
        {
            "employee_visible": true/false,
            "photo_tab_accessed": true/false,
            "file_dialog_seen": true/false,
            "new_photo_visible": true/false,
            "reasoning": "string"
        }
        """
        
        # We pass the frames to the VLM
        vlm_resp = query_vlm(prompt=vlm_prompt, images=frames + [final_shot])
        
        if vlm_resp and vlm_resp.get('success'):
            parsed = vlm_resp.get('parsed', {})
            
            vlm_score = 0
            if parsed.get('employee_visible'): vlm_score += 10
            if parsed.get('photo_tab_accessed'): vlm_score += 10
            if parsed.get('new_photo_visible'): vlm_score += 20
            
            score += vlm_score
            feedback_parts.append(f"Visual verification score: {vlm_score}/40.")
            feedback_parts.append(f"VLM reasoning: {parsed.get('reasoning', 'None')}")
        else:
            # If VLM fails, we give partial credit if DB check passed strongly
            if blob_size > 1000:
                score += 20
                feedback_parts.append("VLM unavailable, awarded partial visual credit based on DB success.")
    else:
         feedback_parts.append("No screenshots available for VLM verification.")

    # ================================================================
    # Final Result
    # ================================================================
    passed = score >= 80  # Requires DB success + some visual evidence or app state
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }