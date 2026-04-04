#!/usr/bin/env python3
"""
Verifier for diabetic_care_gap_intervention task in NOSH ChartingSystem.

Scenario: Diabetes quality improvement audit.
5 patients have T2DM (E11.9). Pids 36, 37, 38 have care gaps (no flu vaccine + old encounter).
Pids 39, 40 are up to date (noise — should NOT get duplicate flu vaccines).

Agent must:
1. Identify the 3 patients with care gaps
2. Record influenza vaccine for each
3. Create encounter note for each

Scoring (100 points total):
Per care-gap patient (pids 36, 37, 38):
  - Flu vaccine recorded:    20 pts × 3 = 60 pts
  - Encounter note created:  10 pts × 3 = 30 pts
- All 3 flu vaccines given:  10 pts bonus

Pass threshold: 60 points (at least 3 flu vaccines administered)
"""

import json
import os
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

RESULT_PATH = "/tmp/diabetic_care_gap_intervention_result.json"


def verify_diabetic_care_gap_intervention(traj, env_info, task_info):
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

    flu_count = 0
    enc_count = 0

    care_gap_patients = [
        ('36', 'Sandra Pratt'),
        ('37', 'Gregory Holt'),
        ('38', 'Wendy Kaufman'),
    ]

    for pid_key, name in care_gap_patients:
        try:
            p = patients.get(pid_key, {})

            # Flu vaccine criterion (20 pts each)
            if p.get('flu_vaccine_added') or p.get('new_vaccine_added'):
                score += 20
                flu_count += 1
                vaccine_name = p.get('latest_vaccine_name', 'unknown')
                feedback_parts.append(f"PASS: Flu vaccine recorded for {name} (pid {pid_key}): {vaccine_name}")
            else:
                feedback_parts.append(f"FAIL: No flu vaccine recorded for {name} (pid {pid_key})")

            # Encounter criterion (10 pts each)
            if p.get('new_encounter'):
                score += 10
                enc_count += 1
                feedback_parts.append(f"PASS: Encounter note created for {name} (pid {pid_key})")
            else:
                feedback_parts.append(f"FAIL: No new encounter for {name} (pid {pid_key})")

        except Exception as e:
            feedback_parts.append(f"ERROR checking pid {pid_key}: {e}")

    # Bonus: all 3 flu vaccines given
    try:
        if flu_count >= 3:
            score += 10
            feedback_parts.append("BONUS: All 3 care-gap patients vaccinated (+10)")
    except Exception:
        pass

    passed = score >= 60
    feedback = " | ".join(feedback_parts)
    logger.info(f"Score: {score}/100, Passed: {passed}")

    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": {
            "flu_vaccines_administered": flu_count,
            "encounters_created": enc_count
        }
    }


if __name__ == "__main__":
    import shutil

    mock_result = {
        "task_start": 1700000000,
        "patients": {
            "36": {"name": "Sandra Pratt", "init_imm_count": 0, "curr_imm_count": 1,
                   "flu_vaccine_added": True, "new_vaccine_added": True,
                   "latest_vaccine_name": "Influenza, seasonal",
                   "init_enc_count": 1, "curr_enc_count": 2, "new_encounter": True},
            "37": {"name": "Gregory Holt", "init_imm_count": 0, "curr_imm_count": 1,
                   "flu_vaccine_added": True, "new_vaccine_added": True,
                   "latest_vaccine_name": "Influenza, seasonal",
                   "init_enc_count": 1, "curr_enc_count": 2, "new_encounter": True},
            "38": {"name": "Wendy Kaufman", "init_imm_count": 0, "curr_imm_count": 0,
                   "flu_vaccine_added": False, "new_vaccine_added": False,
                   "latest_vaccine_name": "",
                   "init_enc_count": 1, "curr_enc_count": 1, "new_encounter": False}
        },
        "noise": {
            "39": {"name": "Donald Peck", "flu_count": 1},
            "40": {"name": "Irene Foley", "flu_count": 1}
        }
    }

    tmp = tempfile.NamedTemporaryFile(mode='w', suffix='.json', delete=False)
    json.dump(mock_result, tmp)
    tmp.close()

    def mock_copy(src, dst):
        shutil.copy(tmp.name, dst)

    result = verify_diabetic_care_gap_intervention(
        traj={}, env_info={'copy_from_env': mock_copy}, task_info={}
    )
    print(f"Score: {result['score']}/100, Passed: {result['passed']}")
    print(f"Feedback: {result['feedback']}")
    os.unlink(tmp.name)
