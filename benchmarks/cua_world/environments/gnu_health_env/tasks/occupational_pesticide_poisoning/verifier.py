#!/usr/bin/env python3
"""
Verifier for occupational_pesticide_poisoning task.

This task assesses if the agent can accurately chart an occupational toxic exposure,
requiring targeted diagnosis coding, specific toxidrome vitals (bradycardia),
formulary navigation (Atropine), lab ordering, and appointment scheduling.

Scoring breakdown (100 points total):
  - 20 pts: T60.x Diagnosis (Toxic effect of organophosphate)
  - 20 pts: Clinical evaluation with Heart Rate <= 60 bpm
  - 20 pts: Atropine prescription
  - 20 pts: >= 2 Lab orders
  - 20 pts: Appointment scheduled 1 to 5 days from today

Pass threshold: score >= 70
"""

import json
import logging
import os
import tempfile

logger = logging.getLogger(__name__)


def check_ui_interaction(traj, env_info):
    """
    Anti-gaming check: Ensure the agent interacted with the UI,
    rather than injecting raw SQL via python_interpreter tool.
    """
    # Simple heuristic: if the agent used VNC mouse/keyboard actions.
    ui_actions = 0
    for action in traj:
        if 'action_type' in action and action['action_type'] in ['mouse_move', 'mouse_click', 'keyboard_type', 'keyboard_key']:
            ui_actions += 1
    return ui_actions > 5


def verify_occupational_pesticide_poisoning(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Verifier error: copy_from_env missing"}

    score = 0
    feedback_parts = []
    subscores = {}

    try:
        with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as tmp:
            local_path = tmp.name
        copy_from_env('/tmp/occupational_pesticide_poisoning_result.json', local_path)
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

    # Anti-gaming: Ensure UI was used
    if not check_ui_interaction(traj, env_info):
        return {
            "passed": False,
            "score": 0,
            "feedback": "Anti-gaming failure: Insufficient UI interaction detected. Raw database injection is not allowed."
        }

    target_id = result.get('target_patient_id', 0)
    if not target_id or target_id == 0:
        return {"passed": False, "score": 0, "feedback": "CRITICAL: Patient John Zenon not found."}
        
    target_name = result.get('target_patient_name', '')
    if 'john' not in target_name.lower():
        return {"passed": False, "score": 0, "feedback": f"CRITICAL: Wrong patient. Expected John Zenon, got: {target_name}"}

    # 1. T60.x Diagnosis
    t60_found = result.get('t60_found', False)
    t60_active = result.get('t60_active', False)
    t60_code = result.get('t60_code', 'none')
    any_new_disease = int(result.get('any_new_disease_count', 0))

    if t60_found and t60_active:
        score += 20
        subscores['diagnosis'] = 20
        feedback_parts.append(f"Diagnosis correct: {t60_code} (active)")
    elif t60_found:
        score += 15
        subscores['diagnosis'] = 15
        feedback_parts.append(f"Diagnosis {t60_code} found but not marked active")
    elif any_new_disease > 0:
        score += 5
        subscores['diagnosis'] = 5
        feedback_parts.append("A diagnosis was added but not a T60 organophosphate code")
    else:
        subscores['diagnosis'] = 0
        feedback_parts.append("MISSING: No organophosphate toxicity diagnosis (T60) found")

    # 2. Evaluation with Bradycardia
    eval_found = result.get('evaluation_found', False)
    eval_hr_str = result.get('evaluation_heart_rate', 'null')
    
    if eval_found:
        try:
            hr_val = float(eval_hr_str)
            if hr_val <= 60:
                score += 20
                subscores['vitals'] = 20
                feedback_parts.append(f"Bradycardia documented (HR={hr_val})")
            else:
                score += 10
                subscores['vitals'] = 10
                feedback_parts.append(f"Evaluation found but HR={hr_val} is not <= 60 (cholinergic toxidrome missed)")
        except ValueError:
            score += 5
            subscores['vitals'] = 5
            feedback_parts.append(f"Evaluation found but HR '{eval_hr_str}' is invalid")
    else:
        subscores['vitals'] = 0
        feedback_parts.append("MISSING: No clinical evaluation documented")

    # 3. Atropine Antidote
    presc_found = result.get('prescription_found', False)
    atropine_found = result.get('atropine_found', False)
    
    if atropine_found:
        score += 20
        subscores['antidote'] = 20
        feedback_parts.append(f"Atropine antidote prescribed")
    elif presc_found:
        score += 5
        subscores['antidote'] = 5
        feedback_parts.append(f"Prescription created but Atropine missing")
    else:
        subscores['antidote'] = 0
        feedback_parts.append("MISSING: No Atropine antidote prescribed")

    # 4. Toxicity Labs (>= 2)
    lab_count = int(result.get('new_lab_count', 0))
    if lab_count >= 2:
        score += 20
        subscores['labs'] = 20
        feedback_parts.append(f"Sufficient lab orders ({lab_count})")
    elif lab_count == 1:
        score += 10
        subscores['labs'] = 10
        feedback_parts.append(f"Only 1 lab ordered (minimum 2 expected)")
    else:
        subscores['labs'] = 0
        feedback_parts.append("MISSING: No laboratory orders placed")

    # 5. Follow-up (1-5 days)
    appt_found = result.get('appointment_found', False)
    appt_days_str = result.get('appointment_days_diff', 'null')
    
    if appt_found:
        try:
            days = int(float(appt_days_str))
            if 1 <= days <= 5:
                score += 20
                subscores['followup'] = 20
                feedback_parts.append(f"Follow-up scheduled correctly in {days} days")
            else:
                score += 10
                subscores['followup'] = 10
                feedback_parts.append(f"Follow-up scheduled but in {days} days (expected 1-5 days)")
        except ValueError:
            score += 5
            subscores['followup'] = 5
            feedback_parts.append("Follow-up appointment found but date could not be parsed")
    else:
        subscores['followup'] = 0
        feedback_parts.append("MISSING: No follow-up appointment scheduled")

    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores
    }