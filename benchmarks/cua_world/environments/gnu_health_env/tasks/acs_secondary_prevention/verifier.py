#!/usr/bin/env python3
"""
Verifier for acs_secondary_prevention task.

This is a hard task requiring the agent to independently navigate multiple EHR
modules to implement an evidence-based secondary prevention protocol for MI.

Scoring breakdown (100 points total):
  - 20 pts: Cardiac Diagnosis (I21 or I25) active
  - 20 pts: Secondary Prevention Rx (>=2 of: Antiplatelet, Statin, Beta-blocker)
  - 20 pts: Lipid Monitoring Labs (>= 2 lipid-related labs)
  - 20 pts: Lifestyle counseling (smoking cessation or diet)
  - 20 pts: Follow-up appointment scheduled within 21-35 days

Pass threshold: score >= 70
"""

import json
import logging
import os
import tempfile
from datetime import datetime

logger = logging.getLogger(__name__)


def verify_acs_secondary_prevention(traj, env_info, task_info):
    """Verify acute coronary syndrome secondary prevention protocol for Roberto Carlos."""
    copy_from_env = env_info.get('copy_from_env')

    score = 0
    feedback_parts = []
    subscores = {}

    # --- Copy result JSON from VM ---
    result = {}
    try:
        with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as tmp:
            local_path = tmp.name
        copy_from_env('/tmp/acs_secondary_prevention_result.json', local_path)
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
            "feedback": "CRITICAL: Patient Roberto Carlos not found — setup may have failed.",
            "subscores": {}
        }

    # --- Criterion 1: Cardiac Diagnosis (20 pts) ---
    cardiac_found = result.get('cardiac_found', False)
    cardiac_active = result.get('cardiac_active', False)
    cardiac_code = result.get('cardiac_code', 'none')
    any_new_disease = result.get('any_new_disease_count', 0)

    if cardiac_found and cardiac_active:
        score += 20
        subscores['cardiac_diagnosis'] = 20
        feedback_parts.append(f"Cardiac diagnosis documented: ICD-10 {cardiac_code} (active)")
    elif cardiac_found:
        score += 15
        subscores['cardiac_diagnosis'] = 15
        feedback_parts.append(f"Cardiac diagnosis {cardiac_code} found but not marked active")
    elif any_new_disease > 0:
        score += 5
        subscores['cardiac_diagnosis'] = 5
        feedback_parts.append(f"A diagnosis was added but not a correct cardiac code (expected I21.x or I25.x)")
    else:
        subscores['cardiac_diagnosis'] = 0
        feedback_parts.append("MISSING: No cardiac diagnosis documented for Roberto Carlos")

    # --- Criterion 2: Secondary Prevention Rx (20 pts) ---
    has_ap = result.get('has_antiplatelet', False)
    has_stat = result.get('has_statin', False)
    has_bb = result.get('has_betablocker', False)
    
    rx_classes = sum([has_ap, has_stat, has_bb])
    
    if rx_classes >= 2:
        score += 20
        subscores['secondary_prevention_rx'] = 20
        feedback_parts.append(f"Secondary prevention Rx complete ({rx_classes}/3 recommended classes prescribed)")
    elif rx_classes == 1:
        score += 10
        subscores['secondary_prevention_rx'] = 10
        feedback_parts.append(f"Partial secondary prevention Rx: only 1 class prescribed (need >= 2 of antiplatelet, statin, beta-blocker)")
    else:
        subscores['secondary_prevention_rx'] = 0
        feedback_parts.append("MISSING: No secondary prevention medications prescribed")

    # --- Criterion 3: Lipid Monitoring Labs (20 pts) ---
    new_lipid_labs = result.get('new_lipid_labs_count', 0)
    
    if new_lipid_labs >= 2:
        score += 20
        subscores['lipid_labs'] = 20
        feedback_parts.append(f"Baseline lipid monitoring labs ordered (count: {new_lipid_labs})")
    elif new_lipid_labs == 1:
        score += 10
        subscores['lipid_labs'] = 10
        feedback_parts.append("Partial lab orders: 1 lipid lab ordered, >= 2 expected for comprehensive profile")
    else:
        subscores['lipid_labs'] = 0
        feedback_parts.append("MISSING: No lipid/cholesterol laboratory tests ordered")

    # --- Criterion 4: Lifestyle counseling (20 pts) ---
    lifestyle_found = result.get('lifestyle_found', False)
    has_smoking = result.get('lifestyle_has_smoking', False)
    has_diet = result.get('lifestyle_has_diet', False)

    if lifestyle_found and (has_smoking or has_diet):
        score += 20
        subscores['lifestyle_counseling'] = 20
        topics = []
        if has_smoking: topics.append("smoking cessation")
        if has_diet: topics.append("cardiac diet")
        feedback_parts.append(f"Lifestyle counseling documented: {' and '.join(topics)}")
    elif lifestyle_found:
        score += 10
        subscores['lifestyle_counseling'] = 10
        feedback_parts.append("Lifestyle record created but did not specifically mention smoking cessation or cardiac diet")
    else:
        subscores['lifestyle_counseling'] = 0
        feedback_parts.append("MISSING: No lifestyle or dietary counseling documented")

    # --- Criterion 5: Follow-up Appointment (20 pts) ---
    appt_found = result.get('appt_found', False)
    appt_date_str = result.get('appt_date', 'null')
    task_start_str = result.get('task_start_date', 'null')
    
    if appt_found and appt_date_str != 'null' and task_start_str != 'null':
        try:
            appt_dt = datetime.strptime(appt_date_str, "%Y-%m-%d")
            start_dt = datetime.strptime(task_start_str, "%Y-%m-%d")
            diff_days = (appt_dt - start_dt).days
            
            if 21 <= diff_days <= 35:
                score += 20
                subscores['followup_appointment'] = 20
                feedback_parts.append(f"Follow-up scheduled correctly in {diff_days} days (target: 21-35 days)")
            elif diff_days > 0:
                score += 10
                subscores['followup_appointment'] = 10
                feedback_parts.append(f"Follow-up scheduled in {diff_days} days (outside 21-35 day window)")
            else:
                subscores['followup_appointment'] = 0
                feedback_parts.append(f"Follow-up scheduled in past ({diff_days} days)")
        except ValueError:
            score += 5
            subscores['followup_appointment'] = 5
            feedback_parts.append(f"Appointment scheduled but date parsing failed ({appt_date_str})")
    elif appt_found:
        score += 5
        subscores['followup_appointment'] = 5
        feedback_parts.append("Appointment record created but lacks valid date")
    else:
        subscores['followup_appointment'] = 0
        feedback_parts.append("MISSING: No cardiology follow-up appointment scheduled")

    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback_parts),
        "subscores": subscores
    }