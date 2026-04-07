#!/usr/bin/env python3
"""
Verifier for occupational_rabies_pep task.

This task evaluates the documentation of an occupational zoonotic exposure.

Scoring breakdown (100 points total):
  - 20 pts: Dog bite diagnosis (W54.x) documented and active.
  - 20 pts: Rabies exposure (Z20.3) documented and active.
  - 20 pts: Amoxicillin prescription.
  - 20 pts: Tetanus prophylaxis (prescription or vaccination).
  - 20 pts: At least 3 new appointments scheduled for PEP.

Pass threshold: score >= 80 (must complete at least 4 of 5 components)
"""

import json
import logging
import os
import tempfile

logger = logging.getLogger(__name__)

def verify_occupational_rabies_pep(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    
    score = 0
    feedback_parts = []
    subscores = {}

    try:
        with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as tmp:
            local_path = tmp.name
        copy_from_env('/tmp/occupational_rabies_pep_result.json', local_path)
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

    # CRITICAL CHECK: Correct patient target
    target_id = result.get('target_patient_id', 0)
    target_name = result.get('target_patient_name', '').lower()
    
    if not target_id or target_id == 0 or 'john' not in target_name or 'zenon' not in target_name:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"CRITICAL: Wrong or missing patient target. Expected John Zenon, got: {target_name}",
            "subscores": {}
        }

    # Criterion 1: W54 Animal Bite
    w54_found = result.get('w54_found', False)
    w54_active = result.get('w54_active', False)
    w54_code = result.get('w54_code', 'none')
    
    if w54_found and w54_active:
        score += 20
        subscores['bite_diagnosis'] = 20
        feedback_parts.append(f"Animal bite documented: {w54_code} (active)")
    elif w54_found:
        score += 15
        subscores['bite_diagnosis'] = 15
        feedback_parts.append(f"Animal bite {w54_code} found but not marked active")
    else:
        subscores['bite_diagnosis'] = 0
        feedback_parts.append("MISSING: No animal bite diagnosis (W54.x) found")

    # Criterion 2: Z20.3 Rabies Exposure
    z20_found = result.get('z20_found', False)
    z20_active = result.get('z20_active', False)
    z20_code = result.get('z20_code', 'none')
    
    if z20_found and z20_active:
        score += 20
        subscores['rabies_exposure'] = 20
        feedback_parts.append(f"Rabies exposure documented: {z20_code} (active)")
    elif z20_found:
        score += 15
        subscores['rabies_exposure'] = 15
        feedback_parts.append(f"Rabies exposure {z20_code} found but not marked active")
    else:
        subscores['rabies_exposure'] = 0
        feedback_parts.append("MISSING: No Rabies exposure diagnosis (Z20.3) found")

    # Criterion 3: Amoxicillin Prophylaxis
    amox_found = result.get('amox_found', False)
    amox_name = result.get('amox_name', 'none')
    
    if amox_found:
        score += 20
        subscores['antibiotic_prophylaxis'] = 20
        feedback_parts.append(f"Antibiotic prophylaxis prescribed: {amox_name}")
    else:
        subscores['antibiotic_prophylaxis'] = 0
        feedback_parts.append("MISSING: No Amoxicillin prescription found")

    # Criterion 4: Tetanus Prophylaxis
    tet_found = result.get('tet_found', False)
    tet_source = result.get('tet_source', 'none')
    tet_name = result.get('tet_name', 'none')
    
    if tet_found:
        score += 20
        subscores['tetanus_prophylaxis'] = 20
        feedback_parts.append(f"Tetanus prophylaxis documented via {tet_source}: {tet_name}")
    else:
        subscores['tetanus_prophylaxis'] = 0
        feedback_parts.append("MISSING: No Tetanus prescription or vaccination found")

    # Criterion 5: PEP Appointments Scheduled (exactly 3 required)
    appt_count = result.get('new_appt_count', 0)
    try:
        appt_count = int(appt_count)
    except (ValueError, TypeError):
        appt_count = 0
        
    if appt_count >= 3:
        score += 20
        subscores['pep_appointments'] = 20
        feedback_parts.append(f"PEP schedule complete: {appt_count} appointments created")
    elif appt_count > 0:
        score += int(appt_count * 6)
        subscores['pep_appointments'] = int(appt_count * 6)
        feedback_parts.append(f"Incomplete PEP schedule: only {appt_count} appointments created (expected 3)")
    else:
        subscores['pep_appointments'] = 0
        feedback_parts.append("MISSING: No follow-up appointments scheduled for vaccine series")

    # Pass threshold evaluation
    passed = score >= 80

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores
    }