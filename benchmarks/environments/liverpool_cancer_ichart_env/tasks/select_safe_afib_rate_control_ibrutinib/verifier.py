#!/usr/bin/env python3
"""
Verifier for select_safe_afib_rate_control_ibrutinib task.

Criteria:
1. File Existence & Anti-gaming (20 pts): File created during task.
2. Content Accuracy (40 pts): Correct colors for Verapamil, Diltiazem, Bisoprolol.
3. Conclusion (20 pts): Bisoprolol identified as safe.
4. VLM Trajectory (20 pts): Visual evidence of app usage and lookups.
"""

import json
import tempfile
import os
import logging
import re
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_ibrutinib_afib_safety(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_colors = metadata.get('expected_colors', {})
    
    score = 0
    feedback_parts = []
    
    # ============================
    # 1. Retrieve & Validate File
    # ============================
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/sdcard/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve result: {str(e)}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    content = result_data.get("file_content", "")
    file_created = result_data.get("file_created_during_task", False)
    
    if not result_data.get("file_exists"):
        return {"passed": False, "score": 0, "feedback": "Output file /sdcard/ibrutinib_afib_safety.txt not found."}
        
    if not file_created:
        feedback_parts.append("WARNING: File not modified during task (anti-gaming check failed).")
        # We allow checking content but cap score or fail based on strictness. 
        # Here we penalize heavily.
        score = 0
    else:
        score += 20
        feedback_parts.append("File created successfully.")

    # ============================
    # 2. Analyze Content (60 pts total possible)
    # ============================
    content_lower = content.lower()
    
    # Check Drug Colors (10 pts each)
    # Verapamil: Red/Orange
    if "verapamil" in content_lower:
        if "red" in content_lower or "orange" in content_lower:
            score += 15
            feedback_parts.append("Verapamil interaction identified correctly (Red/Orange).")
        else:
            feedback_parts.append("Verapamil color incorrect.")
    else:
        feedback_parts.append("Verapamil not found in report.")

    # Diltiazem: Red/Orange
    if "diltiazem" in content_lower:
        if "red" in content_lower or "orange" in content_lower:
            score += 15
            feedback_parts.append("Diltiazem interaction identified correctly (Red/Orange).")
        else:
            feedback_parts.append("Diltiazem color incorrect.")
    else:
        feedback_parts.append("Diltiazem not found in report.")

    # Bisoprolol: Green
    if "bisoprolol" in content_lower:
        if "green" in content_lower:
            score += 10
            feedback_parts.append("Bisoprolol interaction identified correctly (Green).")
        else:
            feedback_parts.append("Bisoprolol color incorrect.")
    else:
        feedback_parts.append("Bisoprolol not found in report.")

    # Check Safe Option Conclusion (20 pts)
    # Look for "Safe Option: Bisoprolol" or similar
    safe_match = re.search(r"safe.*bisoprolol", content_lower)
    if safe_match:
        score += 20
        feedback_parts.append("Safe option correctly identified as Bisoprolol.")
    else:
        feedback_parts.append("Did not explicitly identify Bisoprolol as the safe option.")

    # ============================
    # 3. VLM Trajectory Verification (20 pts)
    # ============================
    # Sample frames to prove work was done
    frames = sample_trajectory_frames(traj, n=6)
    
    vlm_prompt = """
    You are verifying an agent's workflow in the 'Liverpool Cancer iChart' app.
    The goal was to check 'Ibrutinib' against 'Verapamil', 'Diltiazem', and 'Bisoprolol'.
    
    Look at the sequence of images and answer:
    1. Did the agent select 'Ibrutinib' in the cancer drug list?
    2. Did the agent navigate to co-medications?
    3. Can you see any interaction results (traffic light colors) for the requested drugs?
    4. Did the agent seem to perform the task rather than just writing the file?
    
    Return JSON:
    {
        "ibrutinib_selected": true/false,
        "results_viewed": true/false,
        "workflow_valid": true/false
    }
    """
    
    try:
        vlm_result = query_vlm(images=frames, prompt=vlm_prompt)
        parsed = vlm_result.get("parsed", {})
        
        if parsed.get("workflow_valid", False) or parsed.get("results_viewed", False):
            score += 20
            feedback_parts.append("VLM verified valid workflow.")
        else:
            feedback_parts.append("VLM could not verify workflow (no interaction screens seen).")
            
    except Exception as e:
        logger.warning(f"VLM verification failed: {e}")
        # Fallback: if text result is perfect, we give partial credit for VLM to avoid false negatives on error
        if score >= 60:
            score += 10
            feedback_parts.append("VLM skipped, partial credit granted based on result accuracy.")

    # ============================
    # Final Scoring
    # ============================
    passed = score >= 80
    
    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " | ".join(feedback_parts)
    }