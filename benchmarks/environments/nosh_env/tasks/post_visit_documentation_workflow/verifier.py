#!/usr/bin/env python3
"""
Verifier for post_visit_documentation_workflow task in NOSH ChartingSystem.

Patient: Chloe Rafferty (pid=31), DOB: 2001-04-18, female.
Agent must complete 6 post-visit documentation tasks in NOSH.

Scoring (100 points total):
- Encounter created (today, Office Visit):              15 pts
- Vitals recorded (weight 134, height 65, BP 112/72,
                   pulse 74, temp 99.1):                20 pts
- Medical problem J06.9 added:                          15 pts
- Penicillin allergy recorded:                          15 pts
- Azithromycin prescription:                            20 pts
- Follow-up appointment on 2026-07-08:                  15 pts

Pass threshold: 70 points (at least 5 of 6 subtasks)
"""

import json
import os
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

RESULT_PATH = "/tmp/post_visit_documentation_workflow_result.json"


def _approx_equal(val_str, expected, tolerance):
    """Check if a string numeric value is within tolerance of expected."""
    try:
        val = float(str(val_str).strip())
        return abs(val - expected) <= tolerance
    except (ValueError, TypeError):
        return False


def verify_post_visit_documentation_workflow(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    expected_pid = metadata.get('patient_pid', 31)

    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix='.json') as tmp:
            tmp_path = tmp.name
        try:
            copy_from_env(RESULT_PATH, tmp_path)
            with open(tmp_path, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(tmp_path):
                os.unlink(tmp_path)
    except Exception as e:
        logger.error(f"Failed to copy/parse result: {e}")
        return {"passed": False, "score": 0, "feedback": f"Could not read result file: {e}"}

    # Verify correct patient
    patient_pid = result.get('patient_pid', 0)
    if patient_pid != expected_pid:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Wrong patient — expected pid={expected_pid}, got {patient_pid}"
        }

    score = 0
    feedback_parts = []

    # ---- Criterion 1: Encounter created (15 pts) ----
    try:
        enc = result.get('encounter', {})
        if enc.get('today_encounter') or enc.get('new_encounter'):
            score += 15
            feedback_parts.append("PASS: Encounter created")
        else:
            feedback_parts.append("FAIL: No new encounter found")
    except Exception as e:
        feedback_parts.append(f"ERROR encounter: {e}")

    # ---- Criterion 2: Vitals recorded (20 pts) ----
    try:
        vit = result.get('vitals', {})
        if vit.get('new_vitals'):
            vitals_score = 0
            vitals_feedback = []
            exp_v = metadata.get('expected_vitals', {})

            if _approx_equal(vit.get('weight'), exp_v.get('weight', 134), 5):
                vitals_score += 4
                vitals_feedback.append("weight OK")
            else:
                vitals_feedback.append(f"weight {vit.get('weight')} (expected ~134)")

            if _approx_equal(vit.get('height'), exp_v.get('height', 65), 3):
                vitals_score += 4
                vitals_feedback.append("height OK")
            else:
                vitals_feedback.append(f"height {vit.get('height')} (expected ~65)")

            if _approx_equal(vit.get('bp_systolic'), exp_v.get('bp_systolic', 112), 10):
                vitals_score += 4
                vitals_feedback.append("BP sys OK")
            else:
                vitals_feedback.append(f"BP sys {vit.get('bp_systolic')} (expected ~112)")

            if _approx_equal(vit.get('bp_diastolic'), exp_v.get('bp_diastolic', 72), 10):
                vitals_score += 4
                vitals_feedback.append("BP dia OK")
            else:
                vitals_feedback.append(f"BP dia {vit.get('bp_diastolic')} (expected ~72)")

            if _approx_equal(vit.get('pulse'), exp_v.get('pulse', 74), 5):
                vitals_score += 4
                vitals_feedback.append("pulse OK")
            else:
                vitals_feedback.append(f"pulse {vit.get('pulse')} (expected ~74)")

            score += vitals_score
            if vitals_score >= 12:
                feedback_parts.append(f"PASS: Vitals recorded correctly ({vitals_score}/20: {', '.join(vitals_feedback)})")
            elif vitals_score > 0:
                feedback_parts.append(f"PARTIAL: Vitals partially correct ({vitals_score}/20: {', '.join(vitals_feedback)})")
            else:
                feedback_parts.append(f"FAIL: Vitals recorded but values incorrect ({', '.join(vitals_feedback)})")
        else:
            feedback_parts.append("FAIL: No vitals recorded")
    except Exception as e:
        feedback_parts.append(f"ERROR vitals: {e}")

    # ---- Criterion 3: Medical problem J06.9 (15 pts) ----
    try:
        prob = result.get('problem', {})
        if prob.get('j069_found'):
            score += 15
            feedback_parts.append("PASS: J06.9 medical problem added")
        elif prob.get('new_problem'):
            score += 7
            feedback_parts.append(f"PARTIAL: Medical problem added but not J06.9 (got: {prob.get('latest_name', 'unknown')})")
        else:
            feedback_parts.append("FAIL: No medical problem added")
    except Exception as e:
        feedback_parts.append(f"ERROR problem: {e}")

    # ---- Criterion 4: Penicillin allergy (15 pts) ----
    try:
        allergy = result.get('allergy', {})
        if allergy.get('penicillin_found'):
            score += 15
            feedback_parts.append("PASS: Penicillin allergy recorded")
        elif allergy.get('new_allergy'):
            score += 7
            feedback_parts.append(f"PARTIAL: Allergy added but not penicillin (got: {allergy.get('latest_allergen', 'unknown')})")
        else:
            feedback_parts.append("FAIL: No allergy recorded")
    except Exception as e:
        feedback_parts.append(f"ERROR allergy: {e}")

    # ---- Criterion 5: Azithromycin prescription (20 pts) ----
    try:
        rx = result.get('rx', {})
        if rx.get('azithromycin_found'):
            score += 20
            dosage = rx.get('dosage', '')
            feedback_parts.append(f"PASS: Azithromycin prescribed (dosage: {dosage})")
        elif rx.get('new_rx'):
            score += 7
            feedback_parts.append(f"PARTIAL: Medication prescribed but not azithromycin (got: {rx.get('latest_drug', 'unknown')})")
        else:
            feedback_parts.append("FAIL: No prescription recorded")
    except Exception as e:
        feedback_parts.append(f"ERROR rx: {e}")

    # ---- Criterion 6: Follow-up appointment 2026-07-08 (15 pts) ----
    try:
        apt = result.get('appointment', {})
        if apt.get('jul08_found'):
            score += 15
            feedback_parts.append("PASS: Follow-up appointment scheduled for 2026-07-08")
        elif apt.get('new_appointment'):
            score += 7
            feedback_parts.append(f"PARTIAL: Appointment scheduled but not on 2026-07-08 (got: {apt.get('latest_start', 'unknown')})")
        else:
            feedback_parts.append("FAIL: No follow-up appointment scheduled")
    except Exception as e:
        feedback_parts.append(f"ERROR appointment: {e}")

    passed = score >= 70
    feedback = " | ".join(feedback_parts)
    logger.info(f"Score: {score}/100, Passed: {passed}")

    return {
        "passed": passed,
        "score": score,
        "feedback": feedback
    }


if __name__ == "__main__":
    import shutil

    mock_result = {
        "task_start": 1700000000,
        "patient_pid": 31,
        "encounter": {"init_count": 0, "curr_count": 1, "new_encounter": True, "today_encounter": True},
        "vitals": {"init_count": 0, "curr_count": 1, "new_vitals": True,
                   "weight": "134", "height": "65", "bp_systolic": "112", "bp_diastolic": "72",
                   "pulse": "74", "temperature": "99.1"},
        "problem": {"init_count": 0, "curr_count": 1, "new_problem": True,
                    "j069_found": True, "latest_name": "Acute upper respiratory infection"},
        "allergy": {"init_count": 0, "curr_count": 1, "new_allergy": True,
                    "penicillin_found": True, "latest_allergen": "Penicillin"},
        "rx": {"init_count": 0, "curr_count": 1, "new_rx": True,
               "azithromycin_found": True, "dosage": "500mg", "latest_drug": "Azithromycin"},
        "appointment": {"init_count": 0, "curr_count": 1, "new_appointment": True,
                        "jul08_found": True, "latest_start": "2026-07-08 10:00:00"}
    }

    tmp = tempfile.NamedTemporaryFile(mode='w', suffix='.json', delete=False)
    json.dump(mock_result, tmp)
    tmp.close()

    def mock_copy(src, dst):
        shutil.copy(tmp.name, dst)

    result = verify_post_visit_documentation_workflow(
        traj={},
        env_info={'copy_from_env': mock_copy},
        task_info={'metadata': {'patient_pid': 31}}
    )
    print(f"Score: {result['score']}/100, Passed: {result['passed']}")
    print(f"Feedback: {result['feedback']}")
    os.unlink(tmp.name)
