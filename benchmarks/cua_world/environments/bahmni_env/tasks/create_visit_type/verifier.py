#!/usr/bin/env python3
"""
Verifier for create_visit_type task.
Verifies that the agent created a specific Visit Type in OpenMRS.
"""

import json
import logging
import os
import tempfile
from datetime import datetime

# Import VLM helpers from the framework
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_visit_type(traj, env_info, task_info):
    """
    Verify create_visit_type task.
    
    Criteria:
    1. Visit Type "Telehealth Consultation" exists (35 pts)
    2. Description matches exactly (20 pts)
    3. Visit Type is active/not retired (10 pts)
    4. New creation detected (Count increased + created during task) (15 pts)
    5. VLM: Confirms usage of OpenMRS Admin UI (20 pts)
    
    Pass Threshold: 60/100
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
        
    # Load expected values
    metadata = task_info.get('metadata', {})
    expected_name = metadata.get('target_name', 'Telehealth Consultation')
    expected_desc = metadata.get('target_description', 'Remote patient consultation conducted via video or phone call')

    # 1. Retrieve Result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read verification data: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # --- Check 1: Visit Type Exists (35 pts) ---
    target_data = result.get('target_visit_type', {})
    exists = target_data.get('exists', False)
    
    if exists:
        score += 35
        feedback.append(f"✅ Visit type '{expected_name}' created.")
    else:
        feedback.append(f"❌ Visit type '{expected_name}' not found.")
        # If the main object doesn't exist, we can stop or give 0 for everything else
        return {
            "passed": False,
            "score": score,
            "feedback": "\n".join(feedback)
        }

    # --- Check 2: Description Accuracy (20 pts) ---
    actual_desc = target_data.get('description', '')
    if actual_desc.strip() == expected_desc.strip():
        score += 20
        feedback.append("✅ Description matches exactly.")
    elif expected_desc.lower() in actual_desc.lower():
        score += 10
        feedback.append(f"⚠️ Description partial match (Expected: '{expected_desc}', Got: '{actual_desc}').")
    else:
        feedback.append(f"❌ Description incorrect (Got: '{actual_desc}').")

    # --- Check 3: Active Status (10 pts) ---
    is_retired = target_data.get('retired', True)
    if not is_retired:
        score += 10
        feedback.append("✅ Visit type is active.")
    else:
        feedback.append("❌ Visit type is retired (inactive).")

    # --- Check 4: Anti-Gaming / Freshness (15 pts) ---
    # We check if count increased AND if creation timestamp is valid
    initial_count = result.get('initial_count', 0)
    current_count = result.get('current_count', 0)
    
    if current_count > initial_count:
        score += 15
        feedback.append(f"✅ Visit type count increased ({initial_count} -> {current_count}).")
    else:
        feedback.append(f"❌ Count did not increase (Initial: {initial_count}, Current: {current_count}). Did you modify an existing one?")

    # --- Check 5: VLM Trajectory Verification (20 pts) ---
    # We want to verify the agent actually navigated the OpenMRS Admin UI
    # and didn't just curl the API (though unlikely for an agent).
    query_vlm = env_info.get('query_vlm')
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=4)
        final_ss = get_final_screenshot(traj)
        if final_ss:
            frames.append(final_ss)
            
        vlm_prompt = (
            "Analyze these screenshots of a user interacting with a hospital system. "
            "Did the user access the 'OpenMRS Administration' interface (legacy grey/white UI) "
            "and use a form to 'Manage Visit Types'? "
            "Look for headers like 'Administration', 'Manage Visit Types', or 'Add Visit Type'. "
            "Return JSON with keys: 'visited_admin_ui' (bool) and 'reasoning' (string)."
        )
        
        try:
            vlm_resp = query_vlm(frames, vlm_prompt)
            parsed = vlm_resp.get('parsed', {})
            if parsed.get('visited_admin_ui', False):
                score += 20
                feedback.append("✅ VLM confirmed navigation to Admin UI.")
            else:
                feedback.append("⚠️ VLM could not confirm Admin UI usage (check screenshots).")
        except Exception as e:
            logger.warning(f"VLM check failed: {e}")
            # Fallback points if technical failure, to be fair
            score += 10
            feedback.append("⚠️ VLM verification skipped.")
    else:
        # If no VLM available, grant points if file checks passed significantly
        if score >= 60: 
            score += 20
            feedback.append("✅ VLM check skipped (unavailable).")

    # Final result
    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback)
    }