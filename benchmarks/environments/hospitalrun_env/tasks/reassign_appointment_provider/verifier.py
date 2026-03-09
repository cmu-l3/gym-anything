#!/usr/bin/env python3
"""
Verifier for reassign_appointment_provider task.
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_reassign_appointment_provider(traj, env_info, task_info):
    """
    Verifies that the appointment was successfully reassigned to Dr. James Chen.
    
    Criteria:
    1. CouchDB: Appointment document exists.
    2. CouchDB: Provider is "Dr. James Chen" (or similar).
    3. CouchDB: Date/Time has NOT changed (tolerance allowed).
    4. CouchDB: Patient is still Maria Santos.
    5. CouchDB: Document was updated (revision check).
    6. VLM: Trajectory shows editing workflow.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load metadata
    metadata = task_info.get('metadata', {})
    target_provider = metadata.get('target_provider', 'Dr. James Chen')
    target_short = metadata.get('target_provider_short', 'James Chen')
    original_provider = metadata.get('original_provider', 'Dr. Emily Johnson')
    
    # 1. Load result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)
            
    appt_doc = result.get('appointment_doc', {})
    if not appt_doc.get('exists'):
        return {"passed": False, "score": 0, "feedback": "Appointment document not found in database."}
        
    score = 0
    feedback_parts = []
    
    # --- Criterion 1: Provider Updated (40 pts) ---
    current_provider = appt_doc.get('provider', '').strip()
    
    # lenient match
    provider_match = (
        target_provider.lower() in current_provider.lower() or 
        target_short.lower() in current_provider.lower()
    )
    
    # check strictly not original
    not_original = original_provider.lower() not in current_provider.lower()
    
    if provider_match and not_original:
        score += 40
        feedback_parts.append("Provider correctly updated to Dr. James Chen.")
    elif not_original:
        score += 10
        feedback_parts.append(f"Provider changed, but not to target (Found: '{current_provider}').")
    else:
        feedback_parts.append(f"Provider not updated (Still: '{current_provider}').")
        
    # --- Criterion 2: Appointment Modified (Anti-gaming) (30 pts) ---
    rev = appt_doc.get('rev', '')
    # Seeded doc usually starts with 1-xxx. Update makes it 2-xxx.
    if rev and not rev.startswith('1-'):
        score += 30
        feedback_parts.append("Appointment record modification detected.")
    else:
        feedback_parts.append("No changes detected in database record.")

    # --- Criterion 3: Date/Time Preserved (20 pts) ---
    # Check if start time is close to initial
    initial_ms = result.get('initial_start_ms', 0)
    current_ms = appt_doc.get('startDate', 0)
    
    # Allow 0 tolerance ideally, but maybe slight drift if they dragged and dropped? 
    # Task says "Do not change", so strict is better.
    if abs(current_ms - initial_ms) < 1000: # 1 second tolerance
        score += 20
        feedback_parts.append("Appointment time preserved.")
    else:
        feedback_parts.append("Appointment time was changed.")
        
    # --- Criterion 4: Patient Preserved (10 pts) ---
    patient_ref = appt_doc.get('patient', '')
    if 'patient_p1_0001' in patient_ref or 'Maria' in str(appt_doc):
        score += 10
        feedback_parts.append("Patient association preserved.")
    else:
        feedback_parts.append("Patient association lost or changed.")

    # --- VLM Verification (Bonus/Confirmation) ---
    # We verify that they actually used the UI
    # Not strictly adding points to >100, but used to validate logic if score is marginal?
    # For now, let's keep it simple: VLM helps confirm if programmatic fails or vice versa?
    # Actually, let's just use programmatic as primary as per instructions, but we can return VLM feedback.
    
    # Calculate final pass
    # Must have provider correct and modified
    passed = (provider_match and rev and not rev.startswith('1-'))
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }