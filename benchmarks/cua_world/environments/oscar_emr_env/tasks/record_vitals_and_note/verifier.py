#!/usr/bin/env python3
"""
Verifier for record_vitals_and_note task.

Task: Record vital signs (BP 118/76, Weight 63 kg, Height 167 cm) and write
an encounter note for patient Maria Santos (DOB: April 27, 1994).

Scoring (100 points total):
  - Criterion 1: At least one new measurement recorded (any vital sign)     — 20 pts
  - Criterion 2: Blood pressure measurement recorded                          — 25 pts
  - Criterion 3: Weight AND height measurements recorded                      — 25 pts
  - Criterion 4: Encounter note created with clinical content                 — 30 pts

Pass threshold: 70 points
Wrong-target guard: If no data found for Maria Santos, score = 0.
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)


def verify_record_vitals_and_note(traj, env_info, task_info):
    """
    Verify that vital signs and an encounter note were recorded for Maria Santos.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    metadata = task_info.get('metadata', {})
    expected_fname = metadata.get('patient_fname', 'Maria')
    expected_lname = metadata.get('patient_lname', 'Santos')

    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp.close()
        try:
            copy_from_env('/tmp/record_vitals_and_note_result.json', tmp.name)
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

    # Wrong-target guard: confirm we have data for the expected patient
    if result.get('patient_fname') != expected_fname or result.get('patient_lname') != expected_lname:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Wrong target: expected {expected_fname} {expected_lname}"
        }

    new_measurements = result.get('new_measurement_count', 0)
    has_bp = result.get('has_bp_measurement', False)
    has_weight = result.get('has_weight_measurement', False)
    has_height = result.get('has_height_measurement', False)
    new_notes = result.get('new_note_count', 0)
    note_has_content = result.get('note_has_content', False)
    note_has_annual = result.get('note_has_annual_physical', False)

    # Criterion 1: At least one new measurement recorded (20 pts)
    try:
        if new_measurements >= 1:
            score += 20
            subscores['any_measurement'] = True
            feedback_parts.append(f"Vitals recorded ({new_measurements} measurements)")
        else:
            subscores['any_measurement'] = False
            feedback_parts.append("No new measurements found")
    except Exception as e:
        feedback_parts.append(f"Measurement check error: {e}")

    # Criterion 2: Blood pressure measurement (25 pts)
    try:
        if has_bp:
            score += 25
            subscores['bp_recorded'] = True
            bp_val = result.get('bp_value', '')
            feedback_parts.append(f"BP recorded ({bp_val})")
        else:
            # Also check: if 3+ measurements were recorded, likely includes BP
            # (some OSCAR versions store BP as two separate rows)
            if new_measurements >= 3:
                score += 15
                subscores['bp_recorded'] = 'inferred'
                feedback_parts.append("BP likely recorded (3+ vitals detected, BP column name may differ)")
            else:
                subscores['bp_recorded'] = False
                feedback_parts.append("Blood pressure not detected in measurements")
    except Exception as e:
        feedback_parts.append(f"BP check error: {e}")

    # Criterion 3: Weight AND height measured (25 pts; 12 pts for just one)
    try:
        if has_weight and has_height:
            score += 25
            subscores['weight_height'] = True
            feedback_parts.append("Weight and height both recorded")
        elif has_weight or has_height:
            score += 12
            subscores['weight_height'] = 'partial'
            which = 'weight' if has_weight else 'height'
            feedback_parts.append(f"Only {which} recorded (missing the other)")
        else:
            # If many measurements recorded overall, give partial credit
            if new_measurements >= 2:
                score += 10
                subscores['weight_height'] = 'inferred'
                feedback_parts.append("Multiple measurements recorded but weight/height column names may differ")
            else:
                subscores['weight_height'] = False
                feedback_parts.append("Weight and height not detected")
    except Exception as e:
        feedback_parts.append(f"Weight/height check error: {e}")

    # Criterion 4: Encounter note created with clinical content (30 pts)
    try:
        if new_notes >= 1 and note_has_content:
            pts = 30 if note_has_annual else 20
            score += pts
            subscores['encounter_note'] = True
            detail = "with annual physical context" if note_has_annual else "with clinical content"
            feedback_parts.append(f"Encounter note created {detail}")
        elif new_notes >= 1:
            score += 10
            subscores['encounter_note'] = 'minimal'
            feedback_parts.append("Encounter note created but content may be minimal")
        else:
            subscores['encounter_note'] = False
            feedback_parts.append("No encounter note found")
    except Exception as e:
        feedback_parts.append(f"Note check error: {e}")

    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts) or "No criteria met",
        "subscores": subscores
    }
