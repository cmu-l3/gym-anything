#!/usr/bin/env python3
"""
Verifier for update_imaging_indication task.

Checks:
1. Imaging document for Gregory Peck exists.
2. Notes field has been updated to "Rule out Pneumonia".
3. Document revision has changed (proving an edit occurred).
4. Critical fields (Imaging Type, Patient) are preserved.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_update_imaging_indication(traj, env_info, task_info):
    """
    Verify the imaging request update.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load metadata
    metadata = task_info.get('metadata', {})
    target_notes = metadata.get('target_notes', "Rule out Pneumonia").lower()
    
    # 1. Retrieve Result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 2. Check Document Existence (10 pts)
    if not result.get('doc_exists'):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Imaging request document not found. It may have been deleted."
        }
    score += 10
    feedback_parts.append("Document exists")

    # 3. Check Modification (Revision Change) (20 pts)
    # The agent must actually SAVE the document, generating a new rev
    initial_rev = result.get('initial_rev', '')
    current_rev = result.get('current_rev', '')
    
    if not initial_rev or not current_rev:
        feedback_parts.append("Could not verify revision change (missing data)")
    elif initial_rev == current_rev:
        feedback_parts.append("Document revision unchanged - Agent did not save changes")
    else:
        score += 20
        feedback_parts.append("Document was modified/saved")

    # 4. Check Content: Notes (50 pts)
    # Allow some flexibility (case insensitive, whitespace)
    actual_notes = result.get('notes', '').strip().lower()
    
    if target_notes in actual_notes:
        score += 50
        feedback_parts.append(f"Notes updated correctly ('{result.get('notes')}')")
    else:
        feedback_parts.append(f"Notes incorrect. Expected '{metadata.get('target_notes')}', got '{result.get('notes')}'")

    # 5. Check Content: Data Preservation (20 pts)
    # Ensure they didn't change the patient or the procedure type
    # Patient ID should be patient_p1_gregory
    # Imaging Type should be "Chest X-ray"
    
    actual_patient = result.get('patient_id', '')
    actual_type = result.get('imaging_type', '')
    
    preservation_score = 0
    if "gregory" in actual_patient.lower():
        preservation_score += 10
    else:
        feedback_parts.append(f"Wrong patient linked: {actual_patient}")
        
    if "chest x-ray" in actual_type.lower() or "chest xray" in actual_type.lower():
        preservation_score += 10
    else:
        feedback_parts.append(f"Wrong imaging type: {actual_type}")
        
    score += preservation_score
    if preservation_score == 20:
        feedback_parts.append("Data integrity preserved")

    # 6. Final Pass Determination
    # Must have updated notes AND saved the doc (rev changed)
    passed = (target_notes in actual_notes) and (initial_rev != current_rev) and (score >= 80)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }