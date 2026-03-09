#!/usr/bin/env python3
"""
Verifier for hypertension_panel_remediation task in NOSH ChartingSystem.

Scenario: Quality improvement audit. 5 patients have Essential Hypertension (I10).
Pids 22, 23, 24 are untreated — agent must prescribe Amlodipine 5mg + create encounter for each.
Pids 25, 26 already have antihypertensives (noise — agent must NOT double-prescribe).

Scoring (100 points total):
- Antihypertensive prescribed for pid 22 (Eleanor Whitfield): 25 points
- Antihypertensive prescribed for pid 23 (Russell Hartley):   25 points
- Antihypertensive prescribed for pid 24 (Margaret Toomey):   25 points
- At least 1 encounter created across treated patients:        25 points

Pass threshold: 60 points (at least 2 of 3 prescriptions completed)
"""

import json
import os
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

RESULT_PATH = "/tmp/hypertension_panel_remediation_result.json"


def verify_hypertension_panel_remediation(traj, env_info, task_info):
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
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Could not read result file: {e}"
        }

    score = 0
    feedback_parts = []
    patients = result.get('patients', {})

    # ---- Criterion 1: Antihypertensive for Eleanor Whitfield (pid 22) ----
    try:
        p22 = patients.get('22', {})
        if p22.get('any_antihtn_found') or p22.get('new_rx'):
            score += 25
            drug = p22.get('drug_name', 'unknown drug')
            feedback_parts.append(f"PASS: Eleanor Whitfield (pid 22) prescribed {drug}")
        else:
            feedback_parts.append("FAIL: Eleanor Whitfield (pid 22) still has no antihypertensive")
    except Exception as e:
        feedback_parts.append(f"ERROR checking pid 22: {e}")

    # ---- Criterion 2: Antihypertensive for Russell Hartley (pid 23) ----
    try:
        p23 = patients.get('23', {})
        if p23.get('any_antihtn_found') or p23.get('new_rx'):
            score += 25
            drug = p23.get('drug_name', 'unknown drug')
            feedback_parts.append(f"PASS: Russell Hartley (pid 23) prescribed {drug}")
        else:
            feedback_parts.append("FAIL: Russell Hartley (pid 23) still has no antihypertensive")
    except Exception as e:
        feedback_parts.append(f"ERROR checking pid 23: {e}")

    # ---- Criterion 3: Antihypertensive for Margaret Toomey (pid 24) ----
    try:
        p24 = patients.get('24', {})
        if p24.get('any_antihtn_found') or p24.get('new_rx'):
            score += 25
            drug = p24.get('drug_name', 'unknown drug')
            feedback_parts.append(f"PASS: Margaret Toomey (pid 24) prescribed {drug}")
        else:
            feedback_parts.append("FAIL: Margaret Toomey (pid 24) still has no antihypertensive")
    except Exception as e:
        feedback_parts.append(f"ERROR checking pid 24: {e}")

    # ---- Criterion 4: Encounter created for at least 1 treated patient ----
    try:
        enc_count = sum([
            1 for pid_key in ['22', '23', '24']
            if patients.get(pid_key, {}).get('new_encounter', False)
        ])
        if enc_count >= 3:
            score += 25
            feedback_parts.append(f"PASS: Encounter notes created for all 3 treated patients")
        elif enc_count >= 2:
            score += 17
            feedback_parts.append(f"PARTIAL: Encounter notes created for {enc_count}/3 treated patients")
        elif enc_count >= 1:
            score += 8
            feedback_parts.append(f"PARTIAL: Encounter note created for {enc_count}/3 treated patients")
        else:
            feedback_parts.append("FAIL: No encounter notes created for treated patients")
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
            "pid22_rx": patients.get('22', {}).get('any_antihtn_found', False),
            "pid23_rx": patients.get('23', {}).get('any_antihtn_found', False),
            "pid24_rx": patients.get('24', {}).get('any_antihtn_found', False),
        }
    }


if __name__ == "__main__":
    import shutil

    mock_result = {
        "task_start": 1700000000,
        "patients": {
            "22": {"name": "Eleanor Whitfield", "init_rx_count": 0, "curr_rx_count": 1,
                   "amlodipine_found": True, "any_antihtn_found": True, "drug_name": "Amlodipine",
                   "init_enc_count": 0, "curr_enc_count": 1, "new_rx": True, "new_encounter": True},
            "23": {"name": "Russell Hartley",   "init_rx_count": 0, "curr_rx_count": 1,
                   "amlodipine_found": True, "any_antihtn_found": True, "drug_name": "Amlodipine",
                   "init_enc_count": 0, "curr_enc_count": 1, "new_rx": True, "new_encounter": True},
            "24": {"name": "Margaret Toomey",   "init_rx_count": 0, "curr_rx_count": 0,
                   "amlodipine_found": False, "any_antihtn_found": False, "drug_name": "",
                   "init_enc_count": 0, "curr_enc_count": 0, "new_rx": False, "new_encounter": False}
        },
        "noise": {
            "25": {"name": "Bernard Keane", "rx_count": 1},
            "26": {"name": "Dolores Vance", "rx_count": 1}
        }
    }

    tmp = tempfile.NamedTemporaryFile(mode='w', suffix='.json', delete=False)
    json.dump(mock_result, tmp)
    tmp.close()

    def mock_copy(src, dst):
        shutil.copy(tmp.name, dst)

    result = verify_hypertension_panel_remediation(
        traj={}, env_info={'copy_from_env': mock_copy}, task_info={}
    )
    print(f"Score: {result['score']}/100, Passed: {result['passed']}")
    print(f"Feedback: {result['feedback']}")
    os.unlink(tmp.name)
