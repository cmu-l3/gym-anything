#!/usr/bin/env python3
"""
Verifier for Batch Classify Quarry Blasts task.

VERIFICATION METRICS:
1. Programmatic DB Check: Target events updated correctly (type, certainty, description)
2. Programmatic Anti-gaming Check: Control event (Noto) left untouched
3. VLM Verification: Analyzes trajectory to ensure agent typed commands/scripts (not a bypass)
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VLM_PROCESS_PROMPT = """You are evaluating an AI agent performing a database batch update task on a Linux system.
The agent was asked to update seismic events in a specific geographic box to 'quarry blast' using either SQL or a Python script.

Look at the trajectory frames (ordered chronologically).
Please assess:
1. Did the agent use a terminal window?
2. Is there evidence of the agent typing SQL commands (e.g., using `mysql`), writing a script, or actively querying the database?
3. Did the agent make meaningful progress toward modifying database records?

Respond in JSON format:
{
    "used_terminal": true/false,
    "executed_commands_or_script": true/false,
    "meaningful_progress": true/false,
    "confidence": "high/medium/low",
    "reasoning": "Brief explanation of what the agent did in the frames"
}
"""

def verify_batch_classify_quarry_blasts(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_type = metadata.get('expected_type', 'quarry blast')
    expected_certainty = metadata.get('expected_certainty', 'known')
    expected_description = metadata.get('expected_description', 'Biak Mine Verification')
    expected_target_count = metadata.get('expected_target_count', 5)

    # 1. Retrieve the exported JSON from the container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load exported results: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    target_events = result.get("target_events", [])
    control_events = result.get("control_events", [])

    # 2. Check Target Events (Biak zone)
    if len(target_events) == 0:
        feedback_parts.append("CRITICAL: No target events found in the target geographic box.")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}
    
    type_matches = sum(1 for e in target_events if e.get("type") == expected_type)
    certainty_matches = sum(1 for e in target_events if e.get("certainty") == expected_certainty)
    desc_matches = sum(1 for e in target_events if e.get("description") == expected_description)
    total_found = len(target_events)

    # Score Type (30 pts)
    if type_matches == expected_target_count:
        score += 30
        feedback_parts.append("All target event types updated to 'quarry blast'")
    else:
        feedback_parts.append(f"Target types updated: {type_matches}/{total_found}")
        score += int(30 * (type_matches / expected_target_count))

    # Score Certainty (20 pts)
    if certainty_matches == expected_target_count:
        score += 20
        feedback_parts.append("All target certainties updated to 'known'")
    else:
        feedback_parts.append(f"Target certainties updated: {certainty_matches}/{total_found}")
        score += int(20 * (certainty_matches / expected_target_count))

    # Score Description (20 pts)
    if desc_matches == expected_target_count:
        score += 20
        feedback_parts.append("All target descriptions correctly added")
    else:
        feedback_parts.append(f"Target descriptions added: {desc_matches}/{total_found}")
        score += int(20 * (desc_matches / expected_target_count))

    # 3. Check Control Event (Noto earthquake)
    safety_violation = False
    if control_events:
        # Control event should NOT have the quarry blast properties
        control = control_events[0]
        if control.get("type") == expected_type or control.get("certainty") == expected_certainty:
            safety_violation = True
            feedback_parts.append("FAIL: Control event (Noto) was accidentally modified!")
        else:
            score += 10
            feedback_parts.append("Control event preserved successfully")
    else:
        feedback_parts.append("Warning: Control event not found in database")

    # 4. VLM Trajectory Verification (20 pts)
    vlm_score = 0
    query_vlm = env_info.get("query_vlm")
    if query_vlm and traj:
        from gym_anything.vlm import sample_trajectory_frames
        frames = sample_trajectory_frames(traj, n=4)
        
        try:
            vlm_response = query_vlm(images=frames, prompt=VLM_PROCESS_PROMPT)
            if vlm_response and vlm_response.get("success"):
                parsed = vlm_response.get("parsed", {})
                if parsed.get("executed_commands_or_script", False) and parsed.get("meaningful_progress", False):
                    vlm_score = 20
                    feedback_parts.append("VLM confirmed process execution via terminal/scripts")
                else:
                    feedback_parts.append("VLM did not observe clear terminal interaction")
            else:
                feedback_parts.append("VLM query failed or returned no data")
                vlm_score = 10 # Grace score if VLM is completely broken
        except Exception as e:
            logger.warning(f"VLM exception: {e}")
            vlm_score = 10
    else:
        # Fallback if VLM isn't configured
        vlm_score = 20
        feedback_parts.append("VLM verification skipped (not available)")
    
    score += vlm_score

    # 5. Final Calculation
    # Must get the classification right and not violate the safety check
    key_criteria_met = (type_matches == expected_target_count) and not safety_violation
    passed = score >= 80 and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }