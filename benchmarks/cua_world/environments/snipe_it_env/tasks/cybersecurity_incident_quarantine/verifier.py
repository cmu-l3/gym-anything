#!/usr/bin/env python3
"""
Verifier for cybersecurity_incident_quarantine task.

Verification Strategy:
C1 (20 pts): 'Quarantined - Forensic Hold' status label created and is Undeployable.
C2, C3, C4 (15 pts each): Target assets checked in, assigned new status, and notes appended.
C5 (15 pts): Action logs confirm UI/API check-in was used (anti DB-edit gaming).
C6 (20 pts): Control group assets are completely untouched (MANDATORY TO PASS).
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_cybersecurity_incident_quarantine(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/quarantine_result.json", temp_file.name)
            with open(temp_file.name, 'r') as f:
                result = json.load(f)
        finally:
            os.path.exists(temp_file.name) and os.unlink(temp_file.name)
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found in VM."}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error reading result JSON: {e}"}

    score = 0
    feedback = []

    # --- C1: Status Label Verification ---
    label_id = result.get('label_id', '')
    label_undeployable = str(result.get('label_undeployable', '0'))

    if label_id and label_undeployable == '1':
        score += 20
        feedback.append("C1: Undeployable 'Quarantined - Forensic Hold' status created (+20)")
    elif label_id:
        feedback.append("C1: 'Quarantined - Forensic Hold' status created, but is NOT set to 'Undeployable' (+0)")
    else:
        feedback.append("C1: 'Quarantined - Forensic Hold' status not found (+0)")

    # --- C2, C3, C4: Target Asset Remediation ---
    targets = ['LPT-MKT-04', 'LPT-SALES-11', 'LPT-HR-02']
    targets_logged = 0

    for idx, t in enumerate(targets):
        c_name = f"C{idx+2}"
        data = result.get(t, {})
        
        if not data.get('found'):
            feedback.append(f"{c_name}: Target asset {t} not found in database (+0)")
            continue

        assigned = str(data.get('assigned_to', ''))
        status = str(data.get('status_id', ''))
        notes = data.get('notes', '')
        checkins = int(data.get('checkins', 0))

        # Empty, 0, or NULL means it's checked in.
        is_checked_in = assigned in ['0', 'NULL', '', 'None']
        is_quarantined = (status == str(label_id)) if label_id else False
        has_note = 'CS-8841' in notes.upper()

        if is_checked_in and is_quarantined and has_note:
            score += 15
            feedback.append(f"{c_name}: {t} fully remediated (checked-in, status updated, notes appended) (+15)")
        else:
            partial = 0
            if is_checked_in: partial += 5
            if is_quarantined: partial += 5
            if has_note: partial += 5
            score += partial
            
            missing = []
            if not is_checked_in: missing.append("not checked in")
            if not is_quarantined: missing.append("wrong status")
            if not has_note: missing.append("missing note")
            feedback.append(f"{c_name}: {t} partially remediated - {', '.join(missing)} (+{partial})")

        if checkins > 0: 
            targets_logged += 1

    # --- C5: Action Log Anti-Gaming ---
    if targets_logged == len(targets):
        score += 15
        feedback.append("C5: Action logs confirm standard check-in workflow used for all targets (+15)")
    elif targets_logged > 0:
        partial = targets_logged * 5
        score += partial
        feedback.append(f"C5: Action logs confirm check-in for {targets_logged}/3 targets (+{partial})")
    else:
        feedback.append("C5: No check-in action logs found (workflow bypassed or DB edited directly) (+0)")

    # --- C6: Control Asset Verification (Mandatory pass condition) ---
    controls = ['LPT-EXEC-01', 'LPT-DEV-09']
    controls_untouched = True
    
    for c in controls:
        data = result.get(c, {})
        if not data.get('found'):
            continue
        
        assigned = str(data.get('assigned_to', ''))
        status = str(data.get('status_id', ''))
        notes = data.get('notes', '')
        
        is_checked_in = assigned in ['0', 'NULL', '', 'None']
        is_quarantined = (status == str(label_id)) if label_id else False
        has_note = 'CS-8841' in notes.upper()

        if is_checked_in or is_quarantined or has_note:
            controls_untouched = False
            feedback.append(f"C6 Violation: Control asset {c} was improperly modified! (-20)")

    if controls_untouched:
        score += 20
        feedback.append("C6: Control assets correctly left untouched (+20)")

    # --- Final Evaluation ---
    # The agent must achieve at least 80 points AND not touch the control assets.
    passed = (score >= 80) and controls_untouched
    
    if not controls_untouched and score >= 80:
        feedback.append("CRITICAL FAILURE: Modifying control assets causes automatic task failure.")
        passed = False
    elif score == 0:
        feedback.append("DO-NOTHING: No verifiable actions were detected.")

    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback)
    }