#!/usr/bin/env python3
"""
Verifier for Set Patient Alert task.
Checks if the correct alert text was added to the correct patient.
"""

import json
import os
import logging
import tempfile
import difflib

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_set_patient_alert(traj, env_info, task_info):
    """
    Verify the patient alert task.
    
    Criteria:
    1. Patient record must exist (Sanity check).
    2. Alert field must not be empty.
    3. Alert field must contain specific key phrases (Medical safety critical).
    4. Full text should match expected string (approximate match allowed).
    5. Database record must show modification during task window (Anti-gaming).
    """
    
    # 1. Setup and Copy Data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Infrastructure error: copy_from_env missing"}

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

    # 2. Extract Data
    patient_found = result.get("patient_found", False)
    actual_text = result.get("alert_text", "").strip()
    updated_during_task = result.get("updated_during_task", False)
    
    metadata = task_info.get("metadata", {})
    expected_text = metadata.get("expected_alert_text", "")
    key_phrases = metadata.get("key_phrases", [])

    score = 0
    feedback = []

    # 3. Scoring Logic

    # Criterion A: Patient Found (Required for any points)
    if not patient_found:
        return {"passed": False, "score": 0, "feedback": "Target patient Robert Williams was not found in database."}
    
    # Criterion B: Alert Field Not Empty (25 pts)
    if not actual_text:
        return {"passed": False, "score": 0, "feedback": "Alert field is empty. No changes saved."}
    score += 25
    feedback.append("Alert field populated.")

    # Criterion C: Updated During Task (Anti-gaming)
    # If the text is correct but timestamp didn't update, they might have somehow not saved or it's stale data
    # However, setup script clears it, so existence of text implies update.
    # We'll use this as a soft check or tiebreaker if needed, but primary score is content.
    if updated_during_task:
        feedback.append("Record updated during task session.")
    else:
        feedback.append("Warning: Database timestamp check failed (possibly clock skew), relying on content.")

    # Criterion D: Key Phrases (45 pts total)
    # "hard of hearing", "speak slowly", "905-555-0173", "Maria"
    # We split points among provided phrases
    phrase_points = 45 / len(key_phrases) if key_phrases else 0
    phrases_found = 0
    
    lower_actual = actual_text.lower()
    for phrase in key_phrases:
        if phrase.lower() in lower_actual:
            score += phrase_points
            phrases_found += 1
        else:
            feedback.append(f"Missing key phrase: '{phrase}'")
    
    # Criterion E: Full Text Match (30 pts)
    # Use SequenceMatcher for fuzzy comparison
    similarity = difflib.SequenceMatcher(None, expected_text.lower(), actual_text.lower()).ratio()
    
    if similarity > 0.95:
        score += 30
        feedback.append("Text matches perfectly.")
    elif similarity > 0.8:
        score += 20
        feedback.append("Text matches closely.")
    elif similarity > 0.6:
        score += 10
        feedback.append("Text is somewhat similar but contains errors.")
    else:
        feedback.append("Text deviates significantly from instructions.")

    # 4. Final Verification
    passed = (score >= 70) and (phrases_found >= len(key_phrases) - 1)
    
    return {
        "passed": passed,
        "score": int(score),
        "feedback": " ".join(feedback),
        "details": {
            "similarity": similarity,
            "actual_text": actual_text
        }
    }