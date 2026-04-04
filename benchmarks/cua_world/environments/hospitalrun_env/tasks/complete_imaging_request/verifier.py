#!/usr/bin/env python3
"""
Verifier for complete_imaging_request task.
Verifies that the imaging request was completed with radiological findings in CouchDB.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_complete_imaging_request(traj, env_info, task_info):
    """
    Verify the imaging request completion.
    
    Criteria:
    1. Document status is 'Completed' (30 pts)
    2. Result text is present and sufficient length (15 pts)
    3. Result text contains clinical keywords (15 pts)
    4. Document was modified during task (anti-gaming) (15 pts)
    5. Correct patient/document association (10 pts)
    6. VLM Trajectory shows workflow (15 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load metadata
    metadata = task_info.get('metadata', {})
    expected_terms = metadata.get('expected_result_terms', [])
    min_length = metadata.get('min_result_length', 20)

    # Copy result file
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

    score = 0
    feedback_parts = []
    
    # ─── Check 1: Document Existence ────────────────────────────────────────
    if not result.get('doc_found', False):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Imaging document not found in database."
        }

    # ─── Check 2: Status (30 pts) ───────────────────────────────────────────
    status = result.get('status', '')
    if status == 'Completed':
        score += 30
        feedback_parts.append("Status changed to Completed")
    else:
        feedback_parts.append(f"Status is '{status}' (expected 'Completed')")

    # ─── Check 3: Result Content (30 pts total) ─────────────────────────────
    result_text = result.get('result_text', '').strip()
    
    # Length check (15 pts)
    if len(result_text) >= min_length:
        score += 15
        feedback_parts.append("Result text present")
    else:
        feedback_parts.append(f"Result text too short ({len(result_text)} chars)")

    # Keywords check (15 pts)
    lower_text = result_text.lower()
    found_terms = [t for t in expected_terms if t.lower() in lower_text]
    if len(found_terms) >= 3:
        score += 15
        feedback_parts.append(f"Clinical terms found: {len(found_terms)}")
    elif len(found_terms) >= 1:
        score += 5
        feedback_parts.append(f"Few clinical terms found: {len(found_terms)}")
    else:
        feedback_parts.append("No expected clinical terms found")

    # ─── Check 4: Modification/Anti-Gaming (15 pts) ─────────────────────────
    if result.get('is_modified', False):
        score += 15
        feedback_parts.append("Document modified during task")
    else:
        feedback_parts.append("Document NOT modified (revisions match)")

    # ─── Check 5: Patient Association (10 pts) ──────────────────────────────
    # HospitalRun usually stores the ID directly or wrapping object
    patient_ref = result.get('patient_ref', '')
    if 'patient_p1_0000001' in str(patient_ref):
        score += 10
        feedback_parts.append("Correct patient linked")
    else:
        feedback_parts.append("Incorrect patient linkage")

    # ─── Check 6: VLM Trajectory Verification (Placeholder 15 pts) ──────────
    # Since we can't run VLM here without the model, we give partial credit if
    # the programmatic checks pass, assuming the agent must have used the UI.
    # In a full production env, we would query the VLM here.
    if score >= 60:
        score += 0  # Placeholder: usually VLM adds 15 pts
        # If the text was entered and status changed, UI usage is implied
        pass 
    
    # Final check
    passed = (score >= 60) and (status == 'Completed')
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }