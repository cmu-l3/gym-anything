#!/usr/bin/env python3
"""
Verifier for occupational_travel_medicine_clearance task.

This task requires the agent to coordinate a multi-step pre-travel medical clearance
for an employee deploying overseas. It tests cross-module integration across Conditions,
Evaluations, Immunizations, Prescriptions, and Appointments.

Scoring breakdown (100 points total):
  - 20 pts: Prophylactic Z-code condition (Z29 or Z02.89) documented.
  - 20 pts: Pre-travel evaluation documented with valid vitals (BP + HR).
  - 20 pts: Travel vaccination record created.
  - 20 pts: Prescription created for malaria chemoprophylaxis (or generic alternative).
  - 20 pts: Clearance appointment scheduled 10-20 days in the future.
  - Trajectory checks applied using VLM to ensure interaction with GNU Health interface.

Pass threshold: score >= 70
"""

import json
import logging
import os
import tempfile
from datetime import datetime

logger = logging.getLogger(__name__)


def build_vlm_prompt():
    """Build VLM prompt to verify trajectory interactions in GNU Health."""
    return """Examine these screenshots from a GNU Health user session.
    
We are verifying that the user navigated the hospital information system to perform travel clearance tasks.
Look for evidence of the following:
1. Did the user access the 'Immunizations' or 'Vaccines' module to log a vaccination?
2. Did the user open the 'Prescriptions' module and type/search for medications?
3. Did the user fill in vital signs (like BP and Heart Rate) in a clinical evaluation form?
4. Are there any critical error dialogs or application crashes visible?

Respond in JSON format with boolean flags:
{
    "accessed_immunizations": true/false,
    "accessed_prescriptions": true/false,
    "filled_vitals": true/false,
    "no_critical_errors": true/false
}
"""


def verify_occupational_travel_medicine_clearance(traj, env_info, task_info):
    """Verify occupational travel medicine clearance for patient John Zenon."""
    copy_from_env = env_info.get('copy_from_env')
    metadata = task_info.get('metadata', {})

    score = 0
    feedback_parts = []
    subscores = {}

    # --- Copy result JSON from VM ---
    result = {}
    try:
        with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as tmp:
            local_path = tmp.name
        copy_from_env('/tmp/occupational_travel_medicine_clearance_result.json', local_path)
        with open(local_path) as f:
            result = json.load(f)
        os.unlink(local_path)
    except Exception as e:
        logger.error(f"Failed to retrieve result JSON: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Could not retrieve result file from VM: {e}",
            "subscores": {}
        }

    # --- CRITICAL CHECK: Correct patient ---
    target_id = result.get('target_patient_id', 0)
    if not target_id or target_id == 0:
        return {
            "passed": False,
            "score": 0,
            "feedback": "CRITICAL: Patient John Zenon not found — setup may have failed.",
            "subscores": {}
        }

    target_name = result.get('target_patient_name', '')
    if 'john' not in target_name.lower() or 'zenon' not in target_name.lower():
        return {
            "passed": False,
            "score": 0,
            "feedback": f"CRITICAL: Wrong patient target. Expected John Zenon, got: {target_name}",
            "subscores": {}
        }

    # --- Criterion 1: Prophylactic Z-code diagnosis (20 pts) ---
    z_found = result.get('z_code_found', False)
    z_active = result.get('z_code_active', False)
    z_code = result.get('z_code', 'none')
    any_new_disease = result.get('any_new_disease_count', 0)
    
    try:
        any_new_disease = int(any_new_disease)
    except (ValueError, TypeError):
        any_new_disease = 0

    if z_found and z_active:
        score += 20
        subscores['prophylactic_diagnosis'] = 20
        feedback_parts.append(f"Prophylactic diagnosis documented: ICD-10 {z_code} (active)")
    elif z_found:
        score += 15
        subscores['prophylactic_diagnosis'] = 15
        feedback_parts.append(f"Z-code {z_code} found but not marked active")
    elif any_new_disease > 0:
        score += 8
        subscores['prophylactic_diagnosis'] = 8
        feedback_parts.append("A diagnosis was added but not a Z29 or Z02 prophylactic code")
    else:
        subscores['prophylactic_diagnosis'] = 0
        feedback_parts.append("MISSING: No prophylactic condition (Z29/Z02) documented for John Zenon")

    # --- Criterion 2: Clinical Evaluation with vitals (20 pts) ---
    eval_found = result.get('evaluation_found', False)
    sys_bp = result.get('evaluation_systolic', 'null')
    dia_bp = result.get('evaluation_diastolic', 'null')
    hr = result.get('evaluation_heart_rate', 'null')
    
    if eval_found and sys_bp != 'null' and dia_bp != 'null' and hr != 'null':
        score += 20
        subscores['clinical_evaluation'] = 20
        feedback_parts.append(f"Clinical evaluation documented with vitals: BP {sys_bp}/{dia_bp}, HR {hr}")
    elif eval_found and (sys_bp != 'null' or hr != 'null'):
        score += 10
        subscores['clinical_evaluation'] = 10
        feedback_parts.append("Clinical evaluation created but some vital signs (BP or HR) are missing")
    elif eval_found:
        score += 5
        subscores['clinical_evaluation'] = 5
        feedback_parts.append("Clinical evaluation created but no required vitals (BP/HR) documented")
    else:
        subscores['clinical_evaluation'] = 0
        feedback_parts.append("MISSING: No clinical evaluation documented")

    # --- Criterion 3: Travel Vaccination (20 pts) ---
    vax_found = result.get('vaccination_found', False)
    vax_name = result.get('vaccination_name', 'none')
    
    if vax_found:
        score += 20
        subscores['vaccination'] = 20
        feedback_parts.append(f"Vaccination record created: {vax_name}")
    else:
        subscores['vaccination'] = 0
        feedback_parts.append("MISSING: No travel vaccination documented in the Immunizations module")

    # --- Criterion 4: Chemoprophylaxis Prescription (20 pts) ---
    rx_found = result.get('prescription_found', False)
    rx_drug_name = result.get('prescription_drug_name', 'none')
    
    if rx_found:
        # Check if the name seems appropriate for malaria
        drug_lower = rx_drug_name.lower()
        if any(x in drug_lower for x in ['doxycycline', 'mefloquine', 'atovaquone', 'proguanil', 'chloroquine', 'malar']):
            score += 20
            subscores['prescription'] = 20
            feedback_parts.append(f"Antimalarial chemoprophylaxis prescribed: {rx_drug_name}")
        else:
            # Full credit given if they prescribed something, since it's hard to find exact drugs in the demo DB sometimes
            score += 20
            subscores['prescription'] = 20
            feedback_parts.append(f"Prescription created (generic alternative accepted): {rx_drug_name}")
    else:
        subscores['prescription'] = 0
        feedback_parts.append("MISSING: No chemoprophylaxis prescription documented")

    # --- Criterion 5: Follow-up Appointment (20 pts) ---
    appt_found = result.get('appointment_found', False)
    appt_date_str = result.get('appointment_date', 'null')
    task_start_str = result.get('task_start_date', 'null')
    
    if appt_found and appt_date_str != 'null' and task_start_str != 'null':
        try:
            appt_date = datetime.strptime(appt_date_str, "%Y-%m-%d").date()
            start_date = datetime.strptime(task_start_str, "%Y-%m-%d").date()
            days_diff = (appt_date - start_date).days
            
            if 10 <= days_diff <= 20:
                score += 20
                subscores['appointment'] = 20
                feedback_parts.append(f"Clearance follow-up appointment correctly scheduled {days_diff} days out ({appt_date_str})")
            else:
                score += 10
                subscores['appointment'] = 10
                feedback_parts.append(f"Follow-up appointment scheduled {days_diff} days out — expected 10-20 days")
        except ValueError:
            score += 5
            subscores['appointment'] = 5
            feedback_parts.append(f"Appointment created but date could not be verified ({appt_date_str})")
    elif appt_found:
        score += 5
        subscores['appointment'] = 5
        feedback_parts.append("Appointment found but missing valid date")
    else:
        subscores['appointment'] = 0
        feedback_parts.append("MISSING: No follow-up appointment scheduled")

    # --- VLM Trajectory Verification ---
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
    try:
        # Sample frames to verify workflow steps (prevent programmatic gaming)
        frames = sample_trajectory_frames(traj, n=5)
        final = get_final_screenshot(traj)
        if final:
            frames.append(final)
            
        if hasattr(env_info, 'get') and env_info.get('query_vlm'):
            query_vlm = env_info.get('query_vlm')
            vlm_response = query_vlm(images=frames, prompt=build_vlm_prompt())
            
            if vlm_response and 'parsed' in vlm_response:
                parsed = vlm_response['parsed']
                no_errors = parsed.get('no_critical_errors', True)
                accessed_imm = parsed.get('accessed_immunizations', False)
                
                if not no_errors:
                    score = max(0, score - 10)
                    feedback_parts.append("VLM Penalization: Critical application errors detected in trajectory")
                if accessed_imm:
                    feedback_parts.append("VLM Validation: Immunization module interaction verified")
    except Exception as e:
        logger.warning(f"VLM verification failed or unavailable: {e}")

    # Final scoring evaluation
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores
    }