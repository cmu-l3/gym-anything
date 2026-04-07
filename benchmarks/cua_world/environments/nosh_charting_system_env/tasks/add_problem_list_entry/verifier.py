#!/usr/bin/env python3
"""
Verifier for add_problem_list_entry task in NOSH ChartingSystem.

Verifies:
1. Database: A new issue record exists for the correct patient.
2. Content: The issue text contains "Hypertension".
3. Code: The ICD code is "I10".
4. Date: The onset date is "2024-08-15".
5. Status: The issue is active (not resolved).
6. VLM: Trajectory shows interaction with the chart/issues list.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_add_problem_list_entry(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load metadata
    metadata = task_info.get('metadata', {})
    expected_text = metadata.get('expected_condition_text', 'Essential Hypertension')
    expected_code = metadata.get('expected_icd_code', 'I10')
    expected_date = metadata.get('expected_onset_date', '2024-08-15')

    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # --- CRITERION 1: Record Existence (20 pts) ---
    found_record = result.get('found_record')
    initial_count = result.get('initial_issue_count', 0)
    current_count = result.get('current_issue_count', 0)
    
    record_exists = False
    if found_record and isinstance(found_record, dict):
        record_exists = True
        score += 20
        feedback_parts.append("New problem list entry found in database.")
    elif current_count > initial_count:
        # Partial credit if count increased but query missed specific text
        score += 10
        feedback_parts.append(f"Issue count increased ({initial_count}->{current_count}), but specific record match failed.")
    else:
        feedback_parts.append("No new issue record found.")
        # If no record, we can't verify details, so mostly fail here
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    # --- CRITERION 2: Content Matching (20 pts) ---
    issue_text = found_record.get('issue', '') or ''
    if 'hypertension' in issue_text.lower():
        score += 20
        feedback_parts.append(f"Condition text correct ('{issue_text}').")
    else:
        feedback_parts.append(f"Condition text incorrect. Expected 'Hypertension', got '{issue_text}'.")

    # --- CRITERION 3: ICD Code (15 pts) ---
    icd_code = found_record.get('icd', '') or ''
    # Loose match to handle potential formatting like "I10 "
    if expected_code.lower() in icd_code.lower():
        score += 15
        feedback_parts.append(f"ICD code correct ('{icd_code}').")
    else:
        feedback_parts.append(f"ICD code mismatch. Expected '{expected_code}', got '{icd_code}'.")

    # --- CRITERION 4: Onset Date (15 pts) ---
    date_active = found_record.get('date_active', '')
    if str(date_active) == expected_date:
        score += 15
        feedback_parts.append(f"Onset date correct ({date_active}).")
    else:
        feedback_parts.append(f"Onset date mismatch. Expected {expected_date}, got {date_active}.")

    # --- CRITERION 5: Status (10 pts) ---
    # In NOSH, active issues usually have NULL in date_inactive
    date_inactive = found_record.get('date_inactive')
    if date_inactive is None or str(date_inactive) == "" or str(date_inactive) == "0000-00-00":
        score += 10
        feedback_parts.append("Status is Active.")
    else:
        feedback_parts.append(f"Status appears inactive (Date Resolved: {date_inactive}).")

    # --- CRITERION 6: VLM Verification (20 pts) ---
    # Verify the agent actually used the UI
    frames = sample_trajectory_frames(traj, n=4)
    final_screen = get_final_screenshot(traj)
    
    vlm_prompt = """
    Review this sequence of screenshots from an EHR (NOSH).
    The user is supposed to:
    1. Open a patient chart.
    2. Navigate to the "Issues" or "Problem List" section.
    3. Add a diagnosis of "Essential Hypertension" (ICD-10: I10).
    
    Do you see evidence of:
    - A patient chart being open?
    - The "Issues" or "Problem List" interface?
    - A form being filled out or the "Hypertension" entry appearing?
    
    Answer JSON: {"evidence_found": bool, "confidence": float}
    """
    
    # Default to passing VLM if code is perfect, but this adds robustness
    vlm_score = 0
    try:
        vlm_result = query_vlm(images=frames + [final_screen], prompt=vlm_prompt)
        parsed = vlm_result.get('parsed', {})
        if parsed.get('evidence_found', False):
            vlm_score = 20
            feedback_parts.append("Visual evidence of workflow confirmed.")
        else:
            feedback_parts.append("Visual evidence of workflow unclear.")
    except Exception as e:
        logger.warning(f"VLM check failed: {e}")
        # Fallback: if database score is high, assume pass
        if score >= 60:
            vlm_score = 20
    
    score += vlm_score

    # Final Verdict
    # Pass threshold: 60 (Requires at least record existence + some details)
    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }