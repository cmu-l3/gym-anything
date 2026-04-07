#!/usr/bin/env python3
"""
Verifier for ot_ics_device_taxonomy_provisioning task.

Uses the DB and API dumps to check for the exact configurations requested.
Checks:
- Category 'Industrial-PLC' (15 pts)
- Category 'HVAC-Sensor' (15 pts)
- Vendor 'Siemens' (10 pts)
- Vendor 'Schneider-Electric' (10 pts)
- Template 'Siemens-S7-1500' with OID (25 pts)
- Template 'Schneider-HVAC-Monitor' with OID (25 pts)

Also utilizes VLM on trajectory frames to cross-verify UI interaction (anti-gaming).
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def _search_text(combined_text, target):
    """Simple case-insensitive string search in the data dump."""
    return target.lower() in combined_text.lower()


def verify_ot_ics_device_taxonomy_provisioning(traj, env_info, task_info):
    """Main verification logic using copy_from_env and VLM."""
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Framework error: copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    result_file = metadata.get('result_file', '/tmp/ot_ics_result.json')
    local_path = tempfile.NamedTemporaryFile(delete=False, suffix='.json').name

    # 1. Retrieve the exported data from the environment
    try:
        copy_from_env(result_file, local_path)
        with open(local_path, 'r') as f:
            data = json.load(f)
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Failed to retrieve or parse result file '{result_file}': {e}"
        }
    finally:
        if os.path.exists(local_path):
            os.unlink(local_path)

    # Combine DB and API data into a single searchable text blob
    db_dump = data.get("db_dump", "")
    api_dump = data.get("api_dump", "")
    combined_data = f"{db_dump}\n{api_dump}"
    
    score = 0
    feedback_parts = []
    
    # 2. Programmatic Verification (100 points total)

    # Criteria 1: Category 'Industrial-PLC' (15 pts)
    if _search_text(combined_data, "Industrial-PLC"):
        score += 15
        feedback_parts.append("PASS: Category 'Industrial-PLC' found (+15)")
    else:
        feedback_parts.append("FAIL: Category 'Industrial-PLC' not found (0/15)")

    # Criteria 2: Category 'HVAC-Sensor' (15 pts)
    if _search_text(combined_data, "HVAC-Sensor"):
        score += 15
        feedback_parts.append("PASS: Category 'HVAC-Sensor' found (+15)")
    else:
        feedback_parts.append("FAIL: Category 'HVAC-Sensor' not found (0/15)")

    # Criteria 3: Vendor 'Siemens' (10 pts)
    if _search_text(combined_data, "Siemens"):
        score += 10
        feedback_parts.append("PASS: Vendor 'Siemens' found (+10)")
    else:
        feedback_parts.append("FAIL: Vendor 'Siemens' not found (0/10)")

    # Criteria 4: Vendor 'Schneider-Electric' (10 pts)
    if _search_text(combined_data, "Schneider-Electric"):
        score += 10
        feedback_parts.append("PASS: Vendor 'Schneider-Electric' found (+10)")
    else:
        feedback_parts.append("FAIL: Vendor 'Schneider-Electric' not found (0/10)")

    # Criteria 5: Template 'Siemens-S7-1500' and OID '1.3.6.1.4.1.4329.1.1' (25 pts)
    # Note: OID is searched without leading dot to match safely
    has_siemens_tpl = _search_text(combined_data, "Siemens-S7-1500")
    has_siemens_oid = _search_text(combined_data, "1.3.6.1.4.1.4329.1.1")
    if has_siemens_tpl and has_siemens_oid:
        score += 25
        feedback_parts.append("PASS: Template 'Siemens-S7-1500' with correct OID found (+25)")
    elif has_siemens_tpl:
        score += 10  # Partial credit for template name without correct OID
        feedback_parts.append("PARTIAL: Template 'Siemens-S7-1500' found, but OID missing/wrong (+10/25)")
    else:
        feedback_parts.append("FAIL: Template 'Siemens-S7-1500' not found (0/25)")

    # Criteria 6: Template 'Schneider-HVAC-Monitor' and OID '1.3.6.1.4.1.3833.1.2' (25 pts)
    has_schneider_tpl = _search_text(combined_data, "Schneider-HVAC-Monitor")
    has_schneider_oid = _search_text(combined_data, "1.3.6.1.4.1.3833.1.2")
    if has_schneider_tpl and has_schneider_oid:
        score += 25
        feedback_parts.append("PASS: Template 'Schneider-HVAC-Monitor' with correct OID found (+25)")
    elif has_schneider_tpl:
        score += 10
        feedback_parts.append("PARTIAL: Template 'Schneider-HVAC-Monitor' found, but OID missing/wrong (+10/25)")
    else:
        feedback_parts.append("FAIL: Template 'Schneider-HVAC-Monitor' not found (0/25)")

    # 3. VLM Verification (Anti-Gaming Check)
    # We sample trajectory frames to prove the agent navigated the UI rather than just submitting API requests blindly.
    vlm_feedback = ""
    query_vlm = env_info.get('query_vlm')
    if query_vlm:
        try:
            from gym_anything.vlm import sample_trajectory_frames
            frames = sample_trajectory_frames(traj, n=4)
            if frames:
                prompt = (
                    "You are verifying an agent's completion of an IT monitoring configuration task. "
                    "Look at these chronological screenshots from the agent's interaction. "
                    "Did the agent at any point navigate to the 'Settings' -> 'Configuration' (or 'Device Templates'/'Device Categories') "
                    "screens in ManageEngine OpManager? "
                    "Respond with a JSON object containing a single boolean field 'taxonomy_ui_accessed'."
                )
                vlm_resp = query_vlm(prompt=prompt, images=frames)
                if vlm_resp.get("success"):
                    parsed = vlm_resp.get("parsed", {})
                    if parsed.get("taxonomy_ui_accessed", False):
                        vlm_feedback = " [VLM confirmed UI interaction]"
                    else:
                        vlm_feedback = " [VLM Warning: Did not observe Configuration UI interaction]"
        except Exception as e:
            logger.warning(f"VLM verification skipped or failed: {e}")

    # Final logic
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts) + vlm_feedback
    }