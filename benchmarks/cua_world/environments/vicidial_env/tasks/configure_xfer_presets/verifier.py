#!/usr/bin/env python3
"""
Verifier for configure_xfer_presets task.
Checks if the correct transfer presets were added to the Vicidial database.
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_xfer_presets(traj, env_info, task_info):
    """
    Verifies that 3 specific transfer presets exist in the database.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load expected values from metadata
    metadata = task_info.get('metadata', {})
    expected_presets = metadata.get('presets', [])
    
    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Scoring variables
    score = 0
    max_score = 100
    feedback_parts = []
    
    # Database Results
    actual_presets = result.get('final_presets', [])
    initial_count = int(result.get('initial_count', 0))
    final_count = len(actual_presets)
    
    # Check 1: Preset Count (10 pts)
    # Anti-gaming: Ensure count increased from initial (which was 0)
    if final_count == 3:
        score += 10
        feedback_parts.append("Correct number of presets found (3).")
    elif final_count > 0:
        score += 5
        feedback_parts.append(f"Found {final_count} presets (expected 3).")
    else:
        feedback_parts.append("No presets found for SALESTEAM.")
        
    if final_count > initial_count:
        score += 7 # Anti-gaming points
        feedback_parts.append("Presets were created during task.")
    else:
        feedback_parts.append("No new presets created.")

    # Check 2: Verify specific presets (65 pts total)
    # Structure matching dictionary by name for easy lookup
    actual_map = {p['preset_name']: p for p in actual_presets}
    
    for expected in expected_presets:
        name = expected['name']
        if name in actual_map:
            score += 8 # Name exists
            actual = actual_map[name]
            
            # Number check (8 pts)
            if actual['preset_number'] == expected['number']:
                score += 8
            else:
                feedback_parts.append(f"{name}: Wrong number ({actual['preset_number']})")

            # DTMF check (variable pts based on complexity)
            # Normalize empty strings for comparison
            exp_dtmf = expected['dtmf']
            act_dtmf = actual.get('preset_dtmf', '')
            if act_dtmf is None: act_dtmf = ""
            
            if str(act_dtmf).strip() == str(exp_dtmf).strip():
                score += 4 if name == "SpanishSupport" else 5
            else:
                feedback_parts.append(f"{name}: Wrong DTMF ('{act_dtmf}')")

            # Hide Number check (2 pts each -> 6 total)
            if actual.get('preset_hide_number') == expected['hide']:
                score += 2
        else:
            feedback_parts.append(f"Missing preset: {name}")

    # Check 3: VLM Verification (18 pts)
    # We want to see the agent navigating the admin interface
    frames = sample_trajectory_frames(traj, n=5)
    final_screen = get_final_screenshot(traj)
    
    vlm_prompt = """
    You are verifying a Vicidial configuration task.
    Look at these screenshots of the agent's workflow.
    
    1. Did the agent access the Vicidial Admin Interface? (Look for green/white tabular interface)
    2. Did the agent view the 'Sales Team Outbound' campaign settings?
    3. Did the agent interact with form fields?
    
    Return JSON: {"admin_accessed": bool, "campaign_viewed": bool, "form_interaction": bool}
    """
    
    vlm_score = 0
    try:
        vlm_res = query_vlm(images=frames + [final_screen], prompt=vlm_prompt)
        parsed = vlm_res.get('parsed', {})
        
        if parsed.get('admin_accessed'): vlm_score += 5
        if parsed.get('campaign_viewed'): vlm_score += 8
        if parsed.get('form_interaction'): vlm_score += 5
        
        score += vlm_score
        feedback_parts.append(f"VLM Verification: {vlm_score}/18")
    except Exception as e:
        logger.warning(f"VLM check failed: {e}")
        # Fallback: grant partial points if DB checks passed perfectly
        if score >= 70:
            score += 10
            feedback_parts.append("VLM skipped (system error), verified via DB.")

    # Final tally
    passed = score >= 70 and final_count == 3
    
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts)
    }