#!/usr/bin/env python3
"""
Verifier for allergy_drug_conflict_resolution task in NOSH ChartingSystem.

Scenario: Medication safety audit. 4 patients have drug allergies.
3 have active allergy-drug conflicts; 1 has allergy but no conflict (noise).

Agent must:
1. Discover the 3 conflicting patients
2. Discontinue (inactivate) the contraindicated medication
3. Prescribe an alternative medication
4. Create an encounter note for each

Scoring (100 points total):
Per conflicting patient (×3):
  - Conflicting drug discontinued:          20 pts each = 60 pts
  - Safe alternative prescribed:            10 pts each = 30 pts
- Encounter created for at least 2 patients: 10 pts

Pass threshold: 60 points (at least 3 conflicting drugs discontinued)
"""

import json
import os
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

RESULT_PATH = "/tmp/allergy_drug_conflict_resolution_result.json"


def verify_allergy_drug_conflict_resolution(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

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

    score = 0
    feedback_parts = []
    patients = result.get('patients', {})

    conflict_patients = [
        ('32', 'Marcus Odom', 'TMP-SMX'),
        ('33', 'Patricia Fenn', 'Amoxicillin'),
        ('34', 'Theodore Ashe', 'Codeine Phosphate'),
    ]

    encounter_count = 0

    for pid_key, name, drug in conflict_patients:
        try:
            p = patients.get(pid_key, {})

            # Criterion: conflicting drug discontinued (20 pts)
            discontinued = (
                p.get('conflicting_drug_inactive') or
                p.get('conflicting_drug_removed') or
                (p.get('init_active_rx', 1) > p.get('curr_active_rx', 1))
            )
            if discontinued:
                score += 20
                feedback_parts.append(f"PASS: {name} (pid {pid_key}) — {drug} discontinued")
            else:
                feedback_parts.append(f"FAIL: {name} (pid {pid_key}) — {drug} still active")

            # Criterion: alternative prescribed (10 pts)
            if p.get('alternative_prescribed'):
                score += 10
                alt = p.get('alternative_drug', 'unknown')
                feedback_parts.append(f"PASS: {name} — alternative prescribed: {alt}")
            else:
                feedback_parts.append(f"FAIL: {name} — no safe alternative prescribed")

            if p.get('new_encounter'):
                encounter_count += 1

        except Exception as e:
            feedback_parts.append(f"ERROR checking pid {pid_key}: {e}")

    # Encounter bonus: 10 pts if encounters created for at least 2 patients
    try:
        if encounter_count >= 3:
            score += 10
            feedback_parts.append(f"PASS: Encounter notes created for all 3 patients")
        elif encounter_count >= 2:
            score += 10
            feedback_parts.append(f"PASS: Encounter notes created for {encounter_count}/3 patients")
        elif encounter_count >= 1:
            score += 5
            feedback_parts.append(f"PARTIAL: Encounter notes created for {encounter_count}/3 patients")
        else:
            feedback_parts.append("FAIL: No encounter notes created")
    except Exception as e:
        feedback_parts.append(f"ERROR checking encounters: {e}")

    passed = score >= 60
    feedback = " | ".join(feedback_parts)
    logger.info(f"Score: {score}/100, Passed: {passed}")

    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": {
            "encounters_created": encounter_count,
        }
    }


if __name__ == "__main__":
    import shutil

    mock_result = {
        "task_start": 1700000000,
        "patients": {
            "32": {"name": "Marcus Odom", "allergy": "Sulfonamides",
                   "conflict_drug": "TMP-SMX",
                   "init_active_rx": 1, "curr_active_rx": 1,
                   "init_total_rx": 1, "curr_total_rx": 2,
                   "conflicting_drug_inactive": True, "conflicting_drug_removed": False,
                   "alternative_prescribed": True, "alternative_drug": "Nitrofurantoin",
                   "init_enc_count": 0, "curr_enc_count": 1, "new_encounter": True},
            "33": {"name": "Patricia Fenn", "allergy": "Penicillin",
                   "conflict_drug": "Amoxicillin",
                   "init_active_rx": 1, "curr_active_rx": 0,
                   "init_total_rx": 1, "curr_total_rx": 2,
                   "conflicting_drug_inactive": False, "conflicting_drug_removed": True,
                   "alternative_prescribed": True, "alternative_drug": "Azithromycin",
                   "init_enc_count": 0, "curr_enc_count": 1, "new_encounter": True},
            "34": {"name": "Theodore Ashe", "allergy": "Codeine",
                   "conflict_drug": "Codeine Phosphate",
                   "init_active_rx": 1, "curr_active_rx": 1,
                   "init_total_rx": 1, "curr_total_rx": 1,
                   "conflicting_drug_inactive": False, "conflicting_drug_removed": False,
                   "alternative_prescribed": False, "alternative_drug": "",
                   "init_enc_count": 0, "curr_enc_count": 0, "new_encounter": False}
        },
        "noise_pid35": {"name": "Nancy Briggs", "allergy": "Latex",
                        "metformin_still_active": True}
    }

    tmp = tempfile.NamedTemporaryFile(mode='w', suffix='.json', delete=False)
    json.dump(mock_result, tmp)
    tmp.close()

    def mock_copy(src, dst):
        shutil.copy(tmp.name, dst)

    result = verify_allergy_drug_conflict_resolution(
        traj={}, env_info={'copy_from_env': mock_copy}, task_info={}
    )
    print(f"Score: {result['score']}/100, Passed: {result['passed']}")
    print(f"Feedback: {result['feedback']}")
    os.unlink(tmp.name)
