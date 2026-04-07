#!/usr/bin/env python3
"""
Verifier for record_occupational_rads task.

Scoring breakdown (100 points total):
  - 20 pts: J68.x (RADS/Toxic inhalation) diagnosis active
  - 20 pts: Clinical evaluation with HR >= 100 bpm and at least 1 other vitals field
  - 20 pts: Dual pharmacotherapy (Bronchodilator + Corticosteroid, 10 pts each)
  - 20 pts: >= 2 lab orders
  - 20 pts: Follow-up appointment in 7-14 days

Pass threshold: score >= 70
"""

import json
import logging
import os
import tempfile

logger = logging.getLogger(__name__)

def verify_record_occupational_rads(traj, env_info, task_info):
    """Verify occupational health protocol documentation."""
    copy_from_env = env_info.get('copy_from_env')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Verifier error: copy_from_env not available."}

    score = 0
    feedback_parts = []
    
    try:
        with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as tmp:
            local_path = tmp.name
        copy_from_env('/tmp/record_occupational_rads_result.json', local_path)
        with open(local_path) as f:
            result = json.load(f)
        os.unlink(local_path)
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Could not read exported JSON data: {e}"
        }

    target_id = result.get('target_patient_id', 0)
    if not target_id or target_id == 0:
        return {
            "passed": False,
            "score": 0,
            "feedback": "CRITICAL: Target patient Bonifacio Caput not found."
        }

    # --- Criterion 1: J68 Diagnosis (20 pts) ---
    j68_found = result.get('j68_found', False)
    j68_active = result.get('j68_active', False)
    j68_code = result.get('j68_code', '')
    any_jcode_found = result.get('any_jcode_found', False)
    any_jcode = result.get('any_jcode', '')

    if j68_found and j68_active:
        score += 20
        feedback_parts.append(f"Diagnosis: J68 code correctly documented and active ({j68_code})")
    elif j68_found:
        score += 15
        feedback_parts.append(f"Diagnosis: J68 documented but not marked active ({j68_code})")
    elif any_jcode_found:
        score += 10
        feedback_parts.append(f"Diagnosis: Respiratory J-code used ({any_jcode}), but expected J68 for toxic inhalation")
    else:
        feedback_parts.append("Diagnosis: MISSING. No J68.x (Toxic Inhalation) code found")

    # --- Criterion 2: Clinical Evaluation (20 pts) ---
    eval_found = result.get('eval_found', False)
    hr_str = result.get('eval_hr', 'null')
    temp_str = result.get('eval_temp', 'null')
    rr_str = result.get('eval_rr', 'null')
    sys_str = result.get('eval_sys', 'null')

    if eval_found:
        try:
            hr = float(hr_str) if hr_str != 'null' else 0
        except ValueError:
            hr = 0
        
        has_tachycardia = hr >= 100
        has_other_vitals = any(v != 'null' and v != '' for v in [temp_str, rr_str, sys_str])
        
        if has_tachycardia and has_other_vitals:
            score += 20
            feedback_parts.append(f"Evaluation: Documented tachycardia ({hr} bpm) and additional vitals")
        elif has_tachycardia:
            score += 15
            feedback_parts.append(f"Evaluation: Documented tachycardia ({hr} bpm), but missing additional vital signs")
        elif hr > 0:
            score += 10
            feedback_parts.append(f"Evaluation: Documented HR ({hr} bpm) but not reflecting tachycardia criteria (>=100)")
        elif has_other_vitals:
            score += 8
            feedback_parts.append("Evaluation: Documented some vitals, but missing heart rate entirely")
        else:
            score += 5
            feedback_parts.append("Evaluation: Created empty evaluation lacking acute vitals")
    else:
        feedback_parts.append("Evaluation: MISSING. No clinical evaluation documented")

    # --- Criterion 3: Dual Pharmacotherapy (20 pts) ---
    broncho_found = result.get('broncho_found', False)
    broncho_name = result.get('broncho_name', 'none')
    steroid_found = result.get('steroid_found', False)
    steroid_name = result.get('steroid_name', 'none')

    if broncho_found and steroid_found:
        score += 20
        feedback_parts.append(f"Pharmacotherapy: Dual regimen prescribed ({broncho_name} AND {steroid_name})")
    elif broncho_found:
        score += 10
        feedback_parts.append(f"Pharmacotherapy: Prescribed bronchodilator ({broncho_name}) but missing corticosteroid")
    elif steroid_found:
        score += 10
        feedback_parts.append(f"Pharmacotherapy: Prescribed corticosteroid ({steroid_name}) but missing bronchodilator")
    else:
        feedback_parts.append("Pharmacotherapy: MISSING. Neither bronchodilator nor corticosteroid prescribed")

    # --- Criterion 4: Laboratory Orders >= 2 (20 pts) ---
    lab_count = result.get('new_lab_count', 0)
    lab_types = result.get('new_lab_types', '')

    if lab_count >= 2:
        score += 20
        feedback_parts.append(f"Labs: Ordered {lab_count} test(s) ({lab_types})")
    elif lab_count == 1:
        score += 10
        feedback_parts.append(f"Labs: Ordered only 1 test ({lab_types}) - expected at least 2 for baseline")
    else:
        feedback_parts.append("Labs: MISSING. No laboratory tests ordered")

    # --- Criterion 5: Follow-up Appointment (20 pts) ---
    appt_found = result.get('appt_found', False)
    days_diff = result.get('appt_days_diff', 0)

    if appt_found:
        if 7 <= days_diff <= 14:
            score += 20
            feedback_parts.append(f"Follow-up: Scheduled perfectly within 7-14 days ({days_diff} days from today)")
        elif days_diff > 0:
            score += 10
            feedback_parts.append(f"Follow-up: Scheduled but outside ideal 7-14 day window ({days_diff} days from today)")
        else:
            score += 5
            feedback_parts.append(f"Follow-up: Scheduled appointment but date logic is flawed ({days_diff} days)")
    else:
        feedback_parts.append("Follow-up: MISSING. No follow-up appointment scheduled")

    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }