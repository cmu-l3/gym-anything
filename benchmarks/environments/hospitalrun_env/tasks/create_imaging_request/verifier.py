#!/usr/bin/env python3
"""
Verifier for create_imaging_request task.
"""

import json
import logging
import tempfile
import os

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_imaging_request(traj, env_info, task_info):
    """
    Verifies that a new imaging request was created for Maria Santos with specific notes.
    """
    # 1. Setup access to result file
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_patient_name = metadata.get('patient_name', 'Maria Santos')
    expected_patient_segment = metadata.get('patient_id_segment', 'p1_0001')
    expected_type = metadata.get('imaging_type', 'X-ray')
    required_notes_snippets = metadata.get('required_notes', [])

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Analyze Data
    initial_ids = set(result.get('initial_imaging_ids', []))
    final_docs = result.get('final_imaging_docs', [])
    
    # Find NEW documents (those not in initial list)
    new_docs = [d for d in final_docs if d.get('_id') not in initial_ids]

    if not new_docs:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "No new imaging request documents were created."
        }

    # 3. Score the new documents
    # We look for at least one valid document
    best_score = 0
    feedback_details = []

    for doc in new_docs:
        score = 0
        doc_feedback = []
        
        # HospitalRun structure: fields might be at root or inside 'data'
        data = doc.get('data', doc)
        
        # Criterion 1: Created (Implicitly true if in new_docs)
        score += 20
        doc_feedback.append("Document created")

        # Criterion 2: Correct Patient
        # Patient field usually contains ID or Name
        patient_ref = data.get('patient', '')
        # Could be an object or string
        if isinstance(patient_ref, dict):
            patient_ref = str(patient_ref)
            
        if expected_patient_segment in patient_ref or expected_patient_name in patient_ref:
            score += 30
            doc_feedback.append("Correct patient linked")
        else:
            doc_feedback.append(f"Wrong patient (found: {patient_ref})")

        # Criterion 3: Imaging Type
        img_type = data.get('imagingType', '') or data.get('type', '')
        # Allow case-insensitive partial match
        if expected_type.lower() in img_type.lower():
            score += 20
            doc_feedback.append(f"Correct imaging type ({img_type})")
        else:
            doc_feedback.append(f"Incorrect imaging type: {img_type}")

        # Criterion 4: Notes
        notes = data.get('notes', '') or data.get('clinicalIndication', '') or data.get('description', '')
        notes_lower = notes.lower()
        
        snippets_found = 0
        for snippet in required_notes_snippets:
            if snippet.lower() in notes_lower:
                snippets_found += 1
        
        if snippets_found == len(required_notes_snippets):
            score += 30
            doc_feedback.append("Clinical notes match exactly")
        elif snippets_found > 0:
            partial_score = int(30 * (snippets_found / len(required_notes_snippets)))
            score += partial_score
            doc_feedback.append(f"Clinical notes partially match ({snippets_found}/{len(required_notes_snippets)})")
        else:
            doc_feedback.append("Clinical notes missing or incorrect")

        # Track best document
        if score > best_score:
            best_score = score
            feedback_details = doc_feedback

    # 4. Final Result
    passed = best_score >= 90  # Strict pass for medical records
    
    return {
        "passed": passed,
        "score": best_score,
        "feedback": f"Analysis of best matching request: {', '.join(feedback_details)}"
    }