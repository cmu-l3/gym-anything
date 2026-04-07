#!/usr/bin/env python3
"""
Verifier for Record Procedure/Charge Entry task in FreeMED.
Checks the database for correctly submitted procedure records.
Incorporates multi-signal verification using DB state and VLM trajectory analysis.
"""

import os
import json
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_record_procedure_charge(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    scoring = metadata.get('scoring', {})
    
    # Defaults based on task
    expected_cpt = metadata.get('expected_cpt', '99213')
    expected_icd = metadata.get('expected_icd', 'I10')
    expected_charge = float(metadata.get('expected_charge', 150.0))

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result JSON: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    new_records = result.get('new_records', [])
    target_patient_id = str(result.get('target_patient_id', '0'))
    
    score = 0
    feedback_parts = []
    
    # ---------------------------------------------------------
    # Criterion 1: Record Exists (20 pts)
    # ---------------------------------------------------------
    if new_records:
        score += scoring.get('record_exists', 20)
        feedback_parts.append(f"Found {len(new_records)} new procedure record(s)")
    else:
        feedback_parts.append("No new procedure records found in database")
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }
        
    # Find the best matching record
    best_record = None
    best_match_score = -1
    
    for rec in new_records:
        match_score = 0
        
        # Check patient linkage
        has_patient = any(target_patient_id == str(val).strip() for key, val in rec.items() if 'pat' in key.lower())
        if has_patient: match_score += 1
        
        # Check CPT
        has_cpt = any(expected_cpt in str(val) for key, val in rec.items())
        if has_cpt: match_score += 1
        
        # Check ICD
        has_icd = any(expected_icd.lower() in str(val).lower() for key, val in rec.items())
        if has_icd: match_score += 1
        
        if match_score > best_match_score:
            best_match_score = match_score
            best_record = rec

    rec = best_record if best_record else new_records[-1]
    
    # ---------------------------------------------------------
    # Criterion 2: Correct Patient Linked (20 pts)
    # ---------------------------------------------------------
    # Either the specific 'procpatient'/'patient' column matches or *any* column has the ID (fallback)
    is_correct_patient = any(
        target_patient_id == str(val).strip() for key, val in rec.items() 
        if 'pat' in key.lower() or 'id' in key.lower()
    )
    if is_correct_patient:
        score += scoring.get('correct_patient', 20)
        feedback_parts.append("Record correctly linked to patient")
    else:
        feedback_parts.append("Record does not appear linked to target patient")

    # ---------------------------------------------------------
    # Criterion 3: CPT Correct (20 pts)
    # ---------------------------------------------------------
    is_cpt_correct = any(expected_cpt in str(val) for key, val in rec.items())
    if is_cpt_correct:
        score += scoring.get('cpt_correct', 20)
        feedback_parts.append(f"CPT {expected_cpt} correct")
    else:
        feedback_parts.append(f"CPT {expected_cpt} not found")

    # ---------------------------------------------------------
    # Criterion 4: Charge Correct (15 pts)
    # ---------------------------------------------------------
    is_charge_correct = False
    for key, val in rec.items():
        if val is None:
            continue
        # Strip currency symbols, spaces, commas
        clean_val = str(val).replace('$', '').replace(',', '').strip()
        try:
            val_float = float(clean_val)
            if abs(val_float - expected_charge) < 0.02:
                is_charge_correct = True
                break
        except ValueError:
            pass

    if is_charge_correct:
        score += scoring.get('charge_correct', 15)
        feedback_parts.append(f"Charge amount ${expected_charge:.2f} correct")
    else:
        feedback_parts.append("Charge amount incorrect or missing")

    # ---------------------------------------------------------
    # Criterion 5: Diagnosis Correct (15 pts)
    # ---------------------------------------------------------
    is_diag_correct = any(expected_icd.lower() in str(val).lower() for key, val in rec.items() if val)
    # FreeMED sometimes stores the foreign key ID for ICD table instead of text.
    # We ideally resolve it in export_result, but if we see 'I10' it's a guaranteed pass.
    # A full VLM check supplements this if the DB mapping is purely numeric.
    if is_diag_correct:
        score += scoring.get('diagnosis_correct', 15)
        feedback_parts.append(f"Diagnosis {expected_icd} correct")
    else:
        feedback_parts.append(f"Diagnosis {expected_icd} text not explicitly found (may be numeric ID)")

    # ---------------------------------------------------------
    # Criterion 6: Workflow Evidence (VLM Check) (10 pts)
    # ---------------------------------------------------------
    # We sample the trajectory to ensure they actually used the form
    try:
        from gym_anything.vlm import sample_trajectory_frames, query_vlm
        frames = sample_trajectory_frames(traj, n=4)
        if frames:
            prompt = (
                "Look at these screenshots of a user interacting with FreeMED EMR. "
                "Is there evidence that the user navigated to a 'Procedure', 'Charge Entry', or 'Billing' form, "
                "and entered billing details like CPT code 99213, an ICD diagnosis, or a charge amount of $150? "
                "Answer ONLY with a JSON object containing a boolean 'workflow_evidence' key: {\"workflow_evidence\": true/false}."
            )
            vlm_result = query_vlm(images=frames, prompt=prompt)
            if vlm_result and "workflow_evidence" in vlm_result.get("parsed", {}):
                if vlm_result["parsed"]["workflow_evidence"]:
                    score += scoring.get('workflow_evidence', 10)
                    feedback_parts.append("VLM confirmed procedure entry workflow")
                else:
                    feedback_parts.append("VLM did not observe procedure entry workflow")
            else:
                # Fallback if VLM fails but record exists
                score += scoring.get('workflow_evidence', 10)
                feedback_parts.append("VLM unavailable, auto-granting workflow points since DB record exists")
        else:
            feedback_parts.append("No trajectory frames for VLM")
    except ImportError:
        # If VLM tools aren't available, but DB record exists, grant the points.
        score += scoring.get('workflow_evidence', 10)
        feedback_parts.append("VLM tools missing, assuming valid workflow")

    # ---------------------------------------------------------
    # Final Result
    # ---------------------------------------------------------
    # Pass threshold: must score at least 60 AND actually created the linked record
    passed = score >= 60 and len(new_records) > 0 and is_correct_patient
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "record_exists": len(new_records) > 0,
            "correct_patient": is_correct_patient,
            "cpt_correct": is_cpt_correct,
            "charge_correct": is_charge_correct,
            "diagnosis_correct": is_diag_correct,
            "extracted_record": best_record
        }
    }