#!/usr/bin/env python3
"""
Verifier for configure_lead_monitoring_panel task.

This task evaluates the agent's ability to navigate the configuration screens 
to create a new lab test type with associated analytes, and then order that 
custom panel for a patient, followed by scheduling an appointment.

Scoring breakdown (100 points total):
  - 25 pts: Lab test type 'LEAD_OCC' created and active
  - 25 pts: At least 3 associated criteria/analytes configured
  - 10 pts: Analyte names or codes match the expected lead panel keywords
  - 25 pts: Lab request explicitly ordered for patient Bonifacio Caput using LEAD_OCC
  - 15 pts: Follow-up appointment scheduled for Bonifacio Caput within 14-30 days

Pass threshold: score >= 60 AND lab_type_found = True
"""

import json
import logging
import os
import tempfile

logger = logging.getLogger(__name__)

def verify_configure_lead_monitoring_panel(traj, env_info, task_info):
    """Verify the creation and assignment of the lead exposure monitoring panel."""
    copy_from_env = env_info.get('copy_from_env')
    
    score = 0
    feedback_parts = []
    
    # --- Copy result JSON from VM ---
    result = {}
    try:
        with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as tmp:
            local_path = tmp.name
        copy_from_env('/tmp/configure_lead_monitoring_panel_result.json', local_path)
        with open(local_path) as f:
            result = json.load(f)
        os.unlink(local_path)
    except Exception as e:
        logger.error(f"Failed to retrieve result JSON: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Could not retrieve result file from VM: {e}"
        }

    # --- CRITICAL CHECK: Correct patient ---
    target_id = result.get('target_patient_id', 0)
    if not target_id or target_id == 0:
        return {
            "passed": False,
            "score": 0,
            "feedback": "CRITICAL: Patient Bonifacio Caput not found — setup may have failed."
        }

    target_name = result.get('target_patient_name', '')
    if 'bonifacio' not in target_name.lower() or 'caput' not in target_name.lower():
        return {
            "passed": False,
            "score": 0,
            "feedback": f"CRITICAL: Wrong patient target. Expected Bonifacio Caput, got: {target_name}"
        }

    # --- Criterion 1: Lab Test Type created (25 pts) ---
    lab_type_found = result.get('lab_type_found', False)
    lab_type_active = result.get('lab_type_active', False)
    
    if lab_type_found and lab_type_active:
        score += 25
        feedback_parts.append("Lab test type 'LEAD_OCC' created and marked active")
    elif lab_type_found:
        score += 15
        feedback_parts.append("Lab test type 'LEAD_OCC' created but NOT marked active")
    else:
        feedback_parts.append("MISSING: Lab test type 'LEAD_OCC' not created")

    # --- Criterion 2: Analytes configured (25 pts) ---
    criteria_count = result.get('criteria_count', 0)
    try:
        criteria_count = int(criteria_count)
    except (ValueError, TypeError):
        criteria_count = 0
        
    if criteria_count >= 3:
        score += 25
        feedback_parts.append(f"{criteria_count} analytes configured for panel")
    elif criteria_count == 2:
        score += 15
        feedback_parts.append("Only 2 analytes configured (minimum 3 required for full credit)")
    elif criteria_count == 1:
        score += 8
        feedback_parts.append("Only 1 analyte configured")
    else:
        feedback_parts.append("MISSING: No analytes (criteria) configured for the panel")

    # --- Criterion 3: Analyte quality (10 pts) ---
    criteria_names = result.get('criteria_names', '').lower()
    quality_score = 0
    if criteria_count > 0:
        # Keywords matched to check clinical accuracy
        keywords = [('lead', 'bll'), ('zinc', 'zpp'), ('protoporphyrin', 'fep'), ('hemoglobin', 'hgb')]
        matches = 0
        for kw_tuple in keywords:
            if any(kw in criteria_names for kw in kw_tuple):
                matches += 1
        
        if matches >= 3:
            quality_score = 10
        elif matches == 2:
            quality_score = 6
        elif matches == 1:
            quality_score = 3
            
        score += quality_score
        feedback_parts.append(f"Analyte naming quality: {matches}/4 core concepts matched")

    # --- Criterion 4: Lab Request for Bonifacio (25 pts) ---
    lab_request_found = result.get('lab_request_found', False)
    if lab_request_found:
        score += 25
        feedback_parts.append("Lab request created for Bonifacio using the LEAD_OCC panel")
    else:
        feedback_parts.append("MISSING: Lab request not found for Bonifacio using the new LEAD_OCC panel")

    # --- Criterion 5: Follow-up Appointment (15 pts) ---
    appt_found = result.get('appt_found', False)
    appt_days = result.get('appt_days_from_today', 0)
    try:
        appt_days = int(appt_days)
    except (ValueError, TypeError):
        appt_days = 0

    if appt_found:
        if 14 <= appt_days <= 30:
            score += 15
            feedback_parts.append(f"Follow-up appointment optimally scheduled ({appt_days} days from today)")
        elif 7 <= appt_days <= 45:
            score += 8
            feedback_parts.append(f"Follow-up appointment scheduled but outside 14-30 day window ({appt_days} days from today)")
        else:
            score += 5
            feedback_parts.append(f"Follow-up appointment scheduled but timing is poor ({appt_days} days from today)")
    else:
        feedback_parts.append("MISSING: Follow-up appointment not scheduled for Bonifacio")

    # Calculate final pass/fail
    passed = score >= 60 and lab_type_found
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }