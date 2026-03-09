#!/usr/bin/env python3
"""
Verifier for create_volume_with_pim task.

Verification Logic:
1. Volume Creation: File exists, correct timestamp, reasonable size.
2. Security (PIM): 
   - MUST mount with Password + PIM=10.
   - MUST NOT mount with Password + Default PIM (this proves PIM was set).
3. Data Integrity: File exists inside volume and checksum matches.
4. Cleanup: Volume dismounted at end.
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_volume_with_pim(traj, env_info, task_info):
    """
    Verify creation of VeraCrypt volume with custom PIM.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load Result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # 2. Scoring Logic
    score = 0
    feedback_parts = []
    
    # Check 1: Volume Exists (15 pts)
    if result.get('volume_exists'):
        score += 15
        feedback_parts.append("Volume file exists")
    else:
        feedback_parts.append("Volume file missing")
        return {"passed": False, "score": 0, "feedback": "Volume file not found"}

    # Check 2: Created During Task (10 pts)
    if result.get('created_during_task'):
        score += 10
        feedback_parts.append("Created during task")
    else:
        feedback_parts.append("File timestamp invalid (pre-existing?)")

    # Check 3: Mounts with PIM=10 (25 pts)
    if result.get('mount_pim10_success'):
        score += 25
        feedback_parts.append("Mounts with PIM=10")
    else:
        feedback_parts.append("Failed to mount with PIM=10 (Wrong password or PIM?)")

    # Check 4: Rejects Default PIM (20 pts) - CRITICAL ANTI-GAMING
    if not result.get('mount_default_success') and result.get('mount_pim10_success'):
        # Only award if it ALSO mounted with PIM 10 (otherwise it might just be a wrong password for both)
        score += 20
        feedback_parts.append("Correctly requires PIM")
    elif result.get('mount_default_success'):
        feedback_parts.append("FAILED: Volume mounts with default PIM (PIM was not set!)")
    
    # Check 5: File Content (25 pts total)
    if result.get('file_inside_found'):
        score += 20
        if result.get('file_content_match'):
            score += 5
            feedback_parts.append("Document inside matches")
        else:
            feedback_parts.append("Document content mismatch")
    else:
        feedback_parts.append("Document missing from volume")

    # Check 6: Dismounted (5 pts)
    if not result.get('final_is_mounted'):
        score += 5
        feedback_parts.append("Volume dismounted")
    else:
        feedback_parts.append("Volume left mounted")

    # 3. VLM Verification (Trajectory check for PIM UI)
    # This is a supplemental check to verify the UI interaction
    frames = sample_trajectory_frames(traj, n=5)
    final_img = get_final_screenshot(traj)
    
    vlm_score = 0
    if query_vlm and frames:
        prompt = """
        Review these screenshots of a user creating a VeraCrypt volume.
        I am looking for evidence that they set the 'PIM' (Personal Iterations Multiplier).
        
        Look for:
        1. The 'Volume Password' screen.
        2. A checkbox 'Use PIM' being checked.
        3. A 'Volume PIM' field with the value '10'.
        
        Did the user interact with PIM settings?
        Response JSON: {"pim_interaction_visible": bool, "reason": str}
        """
        
        # We only check the trajectory frames, not the final one (which is likely desktop)
        vlm_resp = query_vlm(images=frames, prompt=prompt)
        
        if vlm_resp.get('success'):
            parsed = vlm_resp.get('parsed', {})
            if parsed.get('pim_interaction_visible'):
                # Add a bonus or verify it aligns
                logger.info(f"VLM confirmed PIM interaction: {parsed.get('reason')}")
            else:
                logger.info("VLM did not clearly see PIM interaction (this is okay if programmatic check passes)")

    # 4. Final Determination
    # Must mount with PIM 10 AND NOT mount with default PIM
    pim_verified = result.get('mount_pim10_success') and not result.get('mount_default_success')
    file_verified = result.get('file_inside_found')
    
    passed = (score >= 70) and pim_verified and file_verified

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }