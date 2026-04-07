#!/usr/bin/env python3
"""
Verifier for add_billing_modifier task in FreeMED.

Multi-signal verification:
1. Programmatic database checks (delta row count, code match, description match)
2. Anti-gaming check (spoofed patient table entries)
3. VLM trajectory check (menu navigation visible)
"""

import os
import json
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def build_vlm_prompt():
    return """Examine these screenshots from an agent's trajectory interacting with FreeMED.
The task was to navigate to the "Modifiers" module (typically located under the 'Support Data' or 'System' menu) and add a billing modifier code.

Look for the following visual evidence:
1. Did the agent navigate to a "Modifiers" or "Billing" configuration module?
2. Did the agent open or fill out a form for adding a new modifier?

Return a JSON object with these keys:
{
    "navigated_to_modifiers": true/false,
    "filled_modifier_form": true/false,
    "confidence": "high/medium/low",
    "reasoning": "Brief explanation of what you see"
}
"""

def verify_add_billing_modifier(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_code = metadata.get('expected_code', '95')
    expected_keywords = metadata.get('expected_keywords', ['Telemedicine', 'Synchronous'])

    # 1. Fetch JSON result exported from the container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/add_billing_modifier_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to read result JSON: {e}")
        return {"passed": False, "score": 0, "feedback": f"Could not read task results: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []

    initial_count = result.get('initial_count', 0)
    current_count = result.get('current_count', 0)
    new_rows = result.get('new_rows', [])
    spoofed_patient_count = result.get('spoofed_patient_count', 0)

    # ANTI-GAMING CHECK
    if spoofed_patient_count > 0:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "ANTI-GAMING TRIGGERED: Detected attempt to insert target values into the Patient table instead of Modifiers."
        }

    # Database Evaluation
    if current_count > initial_count:
        score += 10
        feedback_parts.append(f"Row count increased ({initial_count} -> {current_count})")
    else:
        feedback_parts.append("FAIL: No new rows added to the modifier table.")

    code_found = False
    desc_found = False

    for row in new_rows:
        # Check all values in the row to make it column-agnostic
        row_values = [str(v).strip().lower() for v in row.values() if v is not None]
        
        # Exact match for the code "95"
        if any(v == expected_code for v in row_values):
            code_found = True
        
        # Substring match for description keywords
        if any(any(kw.lower() in v for kw in expected_keywords) for v in row_values):
            desc_found = True

        if code_found and desc_found:
            break

    if code_found:
        score += 25
        feedback_parts.append(f"Code '{expected_code}' successfully stored")
    else:
        feedback_parts.append(f"Code '{expected_code}' NOT found in new rows")

    if desc_found:
        score += 25
        feedback_parts.append("Description 'Telemedicine' successfully stored")
    else:
        feedback_parts.append("Description 'Telemedicine' NOT found in new rows")

    # VLM Evaluation (Trajectory Verification)
    vlm_feedback = "VLM check failed/skipped"
    try:
        # Attempt to import frame sampling
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
        frames = sample_trajectory_frames(traj, n=4)
        final = get_final_screenshot(traj)
        if final and final not in frames:
            frames.append(final)
        
        if frames and env_info.get('query_vlm'):
            query_vlm = env_info.get('query_vlm')
            vlm_response = query_vlm(
                images=frames,
                prompt=build_vlm_prompt()
            )
            
            if vlm_response and "parsed" in vlm_response:
                parsed = vlm_response["parsed"]
                navigated = parsed.get("navigated_to_modifiers", False)
                filled = parsed.get("filled_modifier_form", False)
                
                if navigated:
                    score += 20
                    feedback_parts.append("VLM confirms navigation to Modifiers module")
                else:
                    feedback_parts.append("VLM did not observe navigation to Modifiers module")
                    
                if filled:
                    score += 20
                    feedback_parts.append("VLM confirms modifier form interaction")
                else:
                    feedback_parts.append("VLM did not observe modifier form interaction")
            else:
                feedback_parts.append("VLM response missing parsed data")
    except Exception as e:
        logger.warning(f"VLM verification error: {e}")
        feedback_parts.append("VLM verification skipped (error or missing imports)")
        # Grant partial VLM points if DB is perfectly correct to avoid failing due to VLM API issues
        if code_found and desc_found:
            score += 40 
            feedback_parts.append("Granted VLM points via DB fallback")

    passed = (score >= 80 and code_found)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }