#!/usr/bin/env python3
"""
Verifier for add_medication_dictionary_entry task.

Uses a hybrid verification strategy:
1. Programmatic: Checks FreeMED MySQL database for count changes and specific keyword presence in new rows.
2. VLM: Samples trajectory frames to ensure the agent used the web UI to enter the data (prevents SQL injection gaming).
"""

import os
import json
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_add_medication(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Framework error: copy_from_env not available."}

    # Extract metadata expectations
    metadata = task_info.get('metadata', {})
    expected_brand = metadata.get('expected_brand', 'Wegovy').lower()
    expected_generic = metadata.get('expected_generic', 'semaglutide').lower()
    expected_ndc_parts = metadata.get('expected_ndc_parts', ['00169', '4505', '14'])

    # 1. READ PROGRAMMATIC EXPORT
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            db_result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to read database result: {e}")
        db_result = {}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    initial_count = int(db_result.get("initial_count", 0))
    current_count = int(db_result.get("current_count", 0))
    target_match = db_result.get("target_match", "").lower()
    recent_rows = db_result.get("recent_rows", "").lower()

    # 2. EVALUATE DATABASE METRICS
    score = 0
    feedback = []
    
    # Check if a new record was added
    new_record_added = current_count > initial_count
    if new_record_added:
        score += 15
        feedback.append(f"DB count increased ({initial_count} -> {current_count}).")
    else:
        feedback.append("DB count did not increase.")

    # Check if Wegovy/semaglutide was found
    db_text = target_match if target_match else recent_rows
    
    found_name = expected_brand in db_text or expected_generic in db_text
    if found_name:
        score += 25
        feedback.append("Found 'Wegovy'/'semaglutide' in database.")
    else:
        feedback.append("Did not find medication name in database.")

    # Check for NDC parts
    found_ndc = all(part in db_text for part in expected_ndc_parts)
    if found_ndc:
        score += 20
        feedback.append("Found expected NDC code in database.")
    else:
        feedback.append("Did not find expected NDC code.")

    # 3. VLM TRAJECTORY VERIFICATION (Anti-Gaming & UI confirmation)
    try:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
        frames = sample_trajectory_frames(traj, n=4)
        final = get_final_screenshot(traj)
        images = frames + [final] if final else frames
    except ImportError:
        images = []
        logger.warning("Could not import gym_anything.vlm utilities.")

    vlm_score = 0
    query_vlm = env_info.get("query_vlm")
    
    if query_vlm and images:
        prompt = """Analyze these sequential screenshots of a user interacting with an Electronic Medical Record (EMR) system.
The goal is to add a new medication ('Wegovy', NDC 00169-4505-14) to the system's drug dictionary/formulary.

Verify the following:
1. Did the user navigate to a Medication, Drug, or Formulary maintenance screen?
2. Is there evidence of the user typing 'Wegovy' or 'semaglutide' into form fields?
3. Did the user attempt to save or submit the form?

Return ONLY a valid JSON object exactly like this, with boolean values:
{
    "navigated_to_module": true/false,
    "entered_details": true/false,
    "saved_form": true/false
}"""
        
        try:
            vlm_response = query_vlm(prompt=prompt, images=images)
            vlm_data = vlm_response.get("parsed", {})
            if not isinstance(vlm_data, dict):
                import json as json_lib
                # Fallback if the parser missed it but it's in the text
                text = vlm_response.get("response", "")
                start = text.find('{')
                end = text.rfind('}') + 1
                if start >= 0 and end > start:
                    vlm_data = json_lib.loads(text[start:end])
                else:
                    vlm_data = {}

            if vlm_data.get("navigated_to_module"):
                vlm_score += 10
                feedback.append("VLM: Navigated to maintenance module.")
            if vlm_data.get("entered_details"):
                vlm_score += 20
                feedback.append("VLM: Entered medication details in UI.")
            if vlm_data.get("saved_form"):
                vlm_score += 10
                feedback.append("VLM: Attempted to save form.")
        except Exception as e:
            logger.error(f"VLM verification failed: {e}")
            feedback.append(f"VLM error: {str(e)[:50]}")
    else:
        feedback.append("VLM validation skipped (tools unavailable).")
        # Give grace points if DB perfectly matches but VLM failed to run
        if found_name and found_ndc and new_record_added:
            vlm_score += 40 

    score += vlm_score

    # 4. FINAL DECISION
    # Must have used the UI to enter the details AND the DB record must exist
    key_criteria_met = new_record_added and found_name and (vlm_score >= 20)
    passed = score >= 70 and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "details": {
            "initial_db_count": initial_count,
            "final_db_count": current_count,
            "found_name_in_db": found_name,
            "found_ndc_in_db": found_ndc,
            "vlm_score": vlm_score
        }
    }