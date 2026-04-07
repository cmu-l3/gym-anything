#!/usr/bin/env python3
"""Verifier for model_agrivoltaic_system_gui task.

Validates the SAM project file configuration programmatically, checking
capacity, spatial constraints (GCR, clearance), and bifacial tracking settings.
Also uses VLM on trajectory to verify UI interaction.
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VLM_PROMPT = """You are verifying an agent's completion of an agrivoltaic solar design task in NREL SAM.
Look at the trajectory frames of the agent interacting with the GUI.

Verify whether the agent performed the following actions in the UI:
1. Did the agent navigate the 'System Design' page?
2. Did the agent modify Ground Coverage Ratio (GCR)?
3. Did the agent modify the Ground clearance height?
4. Did the agent set the Array type to 1-Axis Tracking?

Respond with a JSON object containing:
{
    "navigated_system_design": true/false,
    "modified_gcr": true/false,
    "modified_clearance": true/false,
    "set_tracking": true/false,
    "confidence": "low"/"medium"/"high"
}
"""

def verify_agrivoltaic_system(traj, env_info, task_info):
    """Verify agrivoltaic system was configured correctly.
    
    Scoring: 100 points max
    - File exists & modified: 20
    - DC size ~2000 kW: 15
    - GCR = 0.20: 20
    - Clearance = 3.0: 15
    - Tracking Mode = 1 (1-Axis): 10
    - Bifacial Module: 10
    - VLM UI Verification: 10
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_capacity_min = metadata.get('expected_capacity_min', 1800)
    expected_capacity_max = metadata.get('expected_capacity_max', 2200)
    expected_gcr = metadata.get('expected_gcr', 0.20)
    expected_clearance = metadata.get('expected_clearance', 3.0)
    expected_tracking_mode = metadata.get('expected_tracking_mode', 1)

    # Read exported JSON
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
    
    # 1. Check file creation/modification (Anti-gaming) (20 pts)
    file_exists = result.get('file_exists') is True or str(result.get('file_exists')).lower() == 'true'
    file_modified = result.get('file_modified') is True or str(result.get('file_modified')).lower() == 'true'
    
    if file_exists and file_modified:
        score += 20
        feedback_parts.append("✅ Project file saved")
    elif file_exists:
        score += 5
        feedback_parts.append("❌ File exists but wasn't modified during task")
    else:
        feedback_parts.append("❌ agrivoltaic.sam file not found")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}
        
    # Extract values
    sys_cap = float(result.get('system_capacity', 0))
    gcr = float(result.get('gcr', -1))
    clearance = float(result.get('clearance_height', -1))
    tracking = float(result.get('tracking_mode', -1))
    is_bifacial = result.get('is_bifacial') is True
    
    # 2. Check System Capacity (15 pts)
    if expected_capacity_min <= sys_cap <= expected_capacity_max:
        score += 15
        feedback_parts.append(f"✅ Capacity {sys_cap:.0f} kW")
    else:
        feedback_parts.append(f"❌ Capacity {sys_cap:.0f} kW (expected ~2000)")
        
    # 3. Check GCR (20 pts)
    if abs(gcr - expected_gcr) < 0.02:
        score += 20
        feedback_parts.append(f"✅ GCR {gcr}")
    else:
        feedback_parts.append(f"❌ GCR {gcr} (expected {expected_gcr})")
        
    # 4. Check Ground Clearance (15 pts)
    if abs(clearance - expected_clearance) < 0.2:
        score += 15
        feedback_parts.append(f"✅ Clearance {clearance}m")
    else:
        feedback_parts.append(f"❌ Clearance {clearance}m (expected {expected_clearance})")
        
    # 5. Check Tracking Mode (10 pts)
    if tracking == expected_tracking_mode:
        score += 10
        feedback_parts.append("✅ 1-Axis Tracking")
    else:
        feedback_parts.append(f"❌ Tracking Mode {tracking} (expected {expected_tracking_mode})")
        
    # 6. Check Bifacial (10 pts)
    if is_bifacial:
        score += 10
        feedback_parts.append("✅ Bifaciality enabled")
    else:
        feedback_parts.append("❌ Bifaciality not detected")

    # 7. VLM Trajectory Verification (10 pts)
    # This prevents users from just dropping a perfectly configured file via a hidden script 
    # instead of doing GUI work.
    try:
        frames = sample_trajectory_frames(traj, n=5)
        if frames:
            vlm_res = query_vlm(images=frames, prompt=VLM_PROMPT)
            if vlm_res.get("success"):
                parsed = vlm_res.get("parsed", {})
                ui_actions = sum([
                    parsed.get("navigated_system_design", False),
                    parsed.get("modified_gcr", False),
                    parsed.get("modified_clearance", False),
                    parsed.get("set_tracking", False)
                ])
                # Award up to 10 points based on UI actions seen
                ui_score = min(10, int((ui_actions / 3.0) * 10))
                score += ui_score
                feedback_parts.append(f"UI Evidence Score: {ui_score}/10")
            else:
                feedback_parts.append("VLM query failed, skipping UI evidence points")
    except Exception as e:
        logger.warning(f"VLM verification error: {e}")
        feedback_parts.append("UI evidence check skipped")
        
    # Key criteria MUST be met to pass
    gcr_ok = abs(gcr - expected_gcr) < 0.02
    clearance_ok = abs(clearance - expected_clearance) < 0.2
    
    passed = score >= 75 and file_modified and gcr_ok and clearance_ok
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }