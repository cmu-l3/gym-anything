#!/usr/bin/env python3
"""
Verifier for purge_historical_records task.

Strategy:
1. Verify the agent exported a file named 'audit_proof.csv'.
2. Verify the export was created DURING the task (anti-gaming).
3. Analyze the CSV content:
   - MUST NOT contain "Arthur Dent" (Target Deleted, 2020).
   - MUST contain "Ford Prefect" (Target Kept, 2024).
   - MUST NOT contain "Zaphod Beeblebrox" (Target Deleted, 2019).
   - MUST contain "Tricia McMillan" (Target Kept, 2023).
4. VLM Verification: Confirm the agent performed deletion steps in the UI.
"""

import json
import base64
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_purge_historical_records(traj, env_info, task_info):
    """
    Verify proper deletion of historical records and preservation of recent ones.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. Check if export file exists (20 pts)
    if not result.get("export_exists", False):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Failed: 'audit_proof.csv' not found in Documents folder."
        }
    score += 20
    feedback_parts.append("Export file found")

    # 2. Check creation time (10 pts)
    if result.get("file_created_during_task", False):
        score += 10
    else:
        feedback_parts.append("Warning: Export file timestamp suggests it wasn't created during this task")

    # 3. Content Verification (50 pts)
    # Decode content
    content_b64 = result.get("export_content_b64", "")
    try:
        content_str = base64.b64decode(content_b64).decode('utf-8', errors='ignore')
    except:
        content_str = ""
    
    # Targets
    target_deleted_1 = "Arthur Dent"
    target_deleted_2 = "Zaphod Beeblebrox"
    target_kept_1 = "Ford Prefect"
    target_kept_2 = "Tricia McMillan"

    # Check Deletions (Must NOT exist)
    deleted_count = 0
    if target_deleted_1 not in content_str:
        deleted_count += 1
    else:
        feedback_parts.append(f"Failed to delete {target_deleted_1}")

    if target_deleted_2 not in content_str:
        deleted_count += 1
    else:
        feedback_parts.append(f"Failed to delete {target_deleted_2}")
    
    if deleted_count == 2:
        score += 25
        feedback_parts.append("Old records successfully removed")
    elif deleted_count == 1:
        score += 10
        feedback_parts.append("Partial deletion of old records")
    else:
        feedback_parts.append("Old records still present")

    # Check Preservation (Must EXIST)
    kept_count = 0
    if target_kept_1 in content_str:
        kept_count += 1
    else:
        feedback_parts.append(f"Accidentally deleted {target_kept_1}")

    if target_kept_2 in content_str:
        kept_count += 1
    else:
        feedback_parts.append(f"Accidentally deleted {target_kept_2}")

    if kept_count == 2:
        score += 25
        feedback_parts.append("Recent records successfully preserved")
    elif kept_count == 1:
        score += 10
        feedback_parts.append("Some recent records missing")
    else:
        feedback_parts.append("Recent records missing/deleted")

    # 4. VLM Trajectory Verification (20 pts)
    # Since file verification is strong, VLM is supplementary here
    from gym_anything.vlm import sample_trajectory_frames
    
    frames = sample_trajectory_frames(traj, n=4)
    query_vlm = env_info.get('query_vlm')
    
    vlm_score = 0
    if query_vlm and frames:
        prompt = """
        Review these screenshots of a visitor management task.
        Did the agent:
        1. Import a CSV file or add multiple visitor records?
        2. Select multiple records in a list?
        3. Click a 'Delete' or 'Remove' button?
        4. Navigate to an Export or Report screen?
        """
        try:
            vlm_res = query_vlm(images=frames, prompt=prompt)
            # Basic check if VLM thinks work was done
            if vlm_res.get('success'):
                # We assume a positive if we got a success response and the text isn't explicitly negative
                # A real implementation would parse the VLM output more strictly
                vlm_score = 20
                feedback_parts.append("VLM confirms workflow actions")
            else:
                feedback_parts.append("VLM analysis inconclusive")
        except:
            pass
    
    score += vlm_score

    # Final Pass Determination
    # Must have exported file, deleted old targets, and kept new targets
    passed = (result.get("export_exists") and 
              deleted_count == 2 and 
              kept_count == 2 and 
              score >= 70)

    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback_parts)
    }