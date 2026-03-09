#!/usr/bin/env python3
"""
Verifier for multi_feature_encounter task.

Task: For Robert MacPherson (DOB: September 17, 1948):
  1. Record blood pressure 158/92 mmHg in measurements
  2. Prescribe Ramipril 10mg OD
  3. Resolve/complete the open tickler about annual labs

Scoring (100 points total):
  - Criterion 1: Blood pressure measurement recorded               — 30 pts
    (Bonus: +10 if value is approximately 158/92)
  - Criterion 2: Ramipril prescription added and active            — 30 pts
  - Criterion 3: Open tickler resolved/completed                   — 30 pts
  - Criterion 4: Ramipril 10mg dose confirmed                      — 10 pts

Pass threshold: 70 points
Wrong-target guard: If data belongs to wrong patient, score = 0.
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)


def verify_multi_feature_encounter(traj, env_info, task_info):
    """
    Verify that BP was recorded, Ramipril prescribed, and tickler resolved
    for Robert MacPherson.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    metadata = task_info.get('metadata', {})
    expected_fname = metadata.get('patient_fname', 'Robert')
    expected_lname = metadata.get('patient_lname', 'MacPherson')

    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp.close()
        try:
            copy_from_env('/tmp/multi_feature_encounter_result.json', tmp.name)
            with open(tmp.name, 'r') as f:
                result = json.load(f)
        finally:
            try:
                os.unlink(tmp.name)
            except Exception:
                pass
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found — export script may not have run"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error reading result: {e}"}

    score = 0
    feedback_parts = []
    subscores = {}

    # Wrong-target guard
    if result.get('patient_fname') != expected_fname or result.get('patient_lname') != expected_lname:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Wrong target: expected {expected_fname} {expected_lname}"
        }

    new_measurements = result.get('new_measurement_count', 0)
    has_bp = result.get('has_bp_measurement', False)
    bp_correct = result.get('bp_value_approx_correct', False)

    # Criterion 1: Blood pressure recorded (30 pts, +10 bonus if correct value)
    try:
        if has_bp:
            score += 30
            subscores['bp_recorded'] = True
            bp_val = result.get('bp_value', '')
            if bp_correct:
                score += 10
                subscores['bp_value_correct'] = True
                feedback_parts.append(f"BP recorded and value approximately correct ({bp_val})")
            else:
                subscores['bp_value_correct'] = False
                feedback_parts.append(f"BP recorded ({bp_val}) but value may not be 158/92")
        elif new_measurements >= 2:
            # Multiple measurements added — likely includes BP (may be stored as two rows)
            score += 20
            subscores['bp_recorded'] = 'inferred'
            feedback_parts.append("Multiple measurements added (BP likely recorded but type name may differ)")
        elif new_measurements >= 1:
            score += 10
            subscores['bp_recorded'] = 'partial'
            feedback_parts.append("A measurement was added but BP not confirmed")
        else:
            subscores['bp_recorded'] = False
            feedback_parts.append("No blood pressure measurement found")
    except Exception as e:
        feedback_parts.append(f"BP check error: {e}")

    # Criterion 2: Ramipril active prescription (30 pts)
    try:
        if result.get('ramipril_active', False):
            score += 30
            subscores['ramipril_prescribed'] = True
            feedback_parts.append("Ramipril prescription added and active")
        elif result.get('ramipril_found', False):
            score += 15
            subscores['ramipril_prescribed'] = 'found_archived'
            feedback_parts.append("Ramipril found but appears to be archived")
        elif result.get('new_drug_count', 0) >= 1:
            score += 15
            subscores['ramipril_prescribed'] = 'different_drug'
            feedback_parts.append("A medication was prescribed but Ramipril not confirmed by name")
        else:
            subscores['ramipril_prescribed'] = False
            feedback_parts.append("Ramipril not found as active prescription")
    except Exception as e:
        feedback_parts.append(f"Ramipril check error: {e}")

    # Criterion 3: Tickler resolved/completed (30 pts)
    try:
        tickler_resolved = result.get('tickler_resolved', False)
        init_status = result.get('tickler_initial_status', 'A')
        curr_status = result.get('tickler_current_status', 'A')

        if tickler_resolved:
            score += 30
            subscores['tickler_resolved'] = True
            feedback_parts.append(f"Tickler resolved (status: {init_status} → {curr_status or 'deleted'})")
        elif curr_status and curr_status.strip() == init_status.strip():
            subscores['tickler_resolved'] = False
            feedback_parts.append(f"Tickler still open (status unchanged: {curr_status})")
        else:
            subscores['tickler_resolved'] = False
            feedback_parts.append("Tickler not resolved")
    except Exception as e:
        feedback_parts.append(f"Tickler check error: {e}")

    # Criterion 4: Ramipril 10mg dose correct (10 pts)
    try:
        if result.get('ramipril_dose_10mg', False):
            score += 10
            subscores['ramipril_dose'] = True
            feedback_parts.append("Ramipril 10mg dose confirmed")
        elif result.get('ramipril_active', False):
            subscores['ramipril_dose'] = False
            feedback_parts.append("Ramipril active but 10mg not confirmed in dosage field")
        else:
            subscores['ramipril_dose'] = False
    except Exception as e:
        feedback_parts.append(f"Ramipril dose check error: {e}")

    passed = score >= 70

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts) or "No criteria met",
        "subscores": subscores
    }
