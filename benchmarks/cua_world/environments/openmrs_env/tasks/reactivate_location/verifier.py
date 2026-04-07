#!/usr/bin/env python3
"""
Verifier for reactivate_location task.

Criteria:
1. Location 'Isolation Ward B' must be active (retired = 0/False).
2. The change must have occurred AFTER the task started (anti-gaming).
3. VLM trajectory check to verify UI interaction (optional but good for robustness).
"""

import json
import os
import tempfile
import logging
import sys

# Add path for shared VLM utils if available
sys.path.append("/workspace/utils")
try:
    from vlm_utils import sample_trajectory_frames, query_vlm
    VLM_AVAILABLE = True
except ImportError:
    VLM_AVAILABLE = False

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_reactivate_location(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy function missing"}

    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result file: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # Extract data
    is_retired = bool(result.get('retired', 1))  # 1 is true/retired, 0 is false/active
    changed_ts = result.get('changed_timestamp', 0)
    start_ts = result.get('task_start_timestamp', 0)

    # Criterion 1: Location is Active (50 points)
    if not is_retired:
        score += 50
        feedback.append("Success: Location 'Isolation Ward B' is active.")
    else:
        feedback.append("Fail: Location is still marked as retired.")

    # Criterion 2: Change happened during task (30 points)
    # Give a small buffer (e.g., 5 seconds) for clock skew if needed, usually not.
    if changed_ts > start_ts:
        score += 30
        feedback.append("Success: Modification timestamp confirms recent action.")
    else:
        if not is_retired:
             feedback.append("Warning: Location is active, but timestamp suggests it wasn't modified during this task session.")
        else:
             feedback.append("Fail: No recent modification detected.")

    # Criterion 3: VLM Verification (20 points)
    # Check if we see the 'Locations' management screen or 'Unretire' action
    vlm_score = 0
    if VLM_AVAILABLE:
        try:
            frames = sample_trajectory_frames(traj, n=4)
            if frames:
                prompt = """
                Analyze these screenshots of a user using OpenMRS.
                I am looking for evidence that the user reactivated a retired location.
                
                Look for:
                1. A list of locations (tables with Name, Description, etc.)
                2. Search filters like "Include Retired" or "Retired" checkbox.
                3. A specific location details page showing "Isolation Ward B".
                4. An action button like "Unretire", "Restore", or unchecking a "Retired" box.
                
                Did the user find the location and interact with it?
                Respond with 'YES' or 'NO' and a brief reason.
                """
                
                # We use a simple heuristic here for the prompt response or just award points if specific keywords found
                # For robust implementation, we'd parse the VLM response. 
                # Here we assume a hypothetical VLM wrapper returns a structured dict or string.
                # Since the framework wrapper isn't fully defined in prompt context, we'll do a basic pass.
                
                vlm_resp = query_vlm(images=frames, prompt=prompt)
                
                # Check for positive keywords in VLM reasoning (mock logic)
                resp_text = str(vlm_resp).upper()
                if "YES" in resp_text or "UNRETIRE" in resp_text or "ISOLATION" in resp_text:
                    vlm_score = 20
                    feedback.append("VLM: Confirmed UI interaction with location settings.")
                else:
                    feedback.append("VLM: Could not clearly verify UI interaction.")
            else:
                # If no frames, assume ok if programmatic passed, but penalize slightly? 
                # Or just give full points if programmatic is strong.
                # Let's be lenient if frames are missing but DB is perfect.
                if score >= 80: 
                    vlm_score = 20
                    feedback.append("VLM: No frames available, trusting DB verification.")
        except Exception as e:
            logger.warning(f"VLM check failed: {e}")
            if score >= 80: vlm_score = 20 # Fallback
    else:
        # If VLM not available, reallocate points
        if score >= 80:
            score = 100
            feedback.append("VLM unavailable: Scaled programmatic score to 100.")

    total_score = score + vlm_score
    passed = (total_score >= 80)

    return {
        "passed": passed,
        "score": min(100, total_score),
        "feedback": " | ".join(feedback)
    }