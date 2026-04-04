"""
Verifier for ehr_clinical_risk_stratification task.

Checks that two high-risk patients each had:
  (1) The correct clinical risk problem added to their medical problem list
  (2) A new follow-up appointment scheduled in the EHR

Scoring (100 pts total):
  - Patient 1 risk problem added:       20 pts
  - Patient 1 appointment scheduled:    30 pts
  - Patient 2 risk problem added:       20 pts
  - Patient 2 appointment scheduled:    30 pts

Pass threshold: 60 pts
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

PASS_THRESHOLD = 60
RESULT_PATH = '/tmp/lh_risk_result.json'


def _risk_problem_present(problems, keyword):
    """Check if any problem title contains the keyword (case-insensitive)."""
    kw = keyword.lower()
    for p in problems:
        if kw in p.lower():
            return True
    return False


def verify_ehr_clinical_risk_stratification(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0,
                "feedback": "No copy_from_env available"}

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp.close()
    try:
        copy_from_env(RESULT_PATH, tmp.name)
    except Exception as e:
        try:
            os.unlink(tmp.name)
        except Exception:
            pass
        return {"passed": False, "score": 0,
                "feedback": f"No result file: {e}"}

    try:
        with open(tmp.name, 'r') as f:
            data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0,
                "feedback": f"Cannot parse result JSON: {e}"}
    finally:
        try:
            os.unlink(tmp.name)
        except Exception:
            pass

    gt = data.get('ground_truth', {})
    patients_result = data.get('patients_result', [])
    expected_patients = gt.get('patients', [])

    if not expected_patients:
        return {"passed": False, "score": 0,
                "feedback": "Ground truth unavailable — setup may not have run"}

    result_by_pid = {pr['pid']: pr for pr in patients_result}

    score = 0
    feedback = []
    subscores = {}

    for idx, expected in enumerate(expected_patients):
        pid = expected['pid']
        fname = expected.get('fname', '?')
        lname = expected.get('lname', '?')
        risk_keyword = expected.get('risk_keyword', '')
        risk_problem = expected.get('risk_problem', '')
        init_appts = expected.get('init_appts', 0)
        prob_key = f"p{idx+1}_risk_problem"
        appt_key = f"p{idx+1}_appointment"

        patient_result = result_by_pid.get(pid)
        if patient_result is None:
            subscores[prob_key] = 0
            subscores[appt_key] = 0
            feedback.append(f"MISSING: {fname} {lname} — no patient data")
            continue

        # Check risk problem added
        problems = patient_result.get('problems', [])
        if _risk_problem_present(problems, risk_keyword):
            score += 20
            subscores[prob_key] = 20
            feedback.append(f"FOUND: {fname} {lname} — risk problem documented ✓")
        else:
            subscores[prob_key] = 0
            feedback.append(f"MISSING: {fname} {lname} — '{risk_problem}' not in problem list")

        # Check new appointment scheduled (count must have increased)
        current_appts = patient_result.get('appt_count', 0)
        if current_appts > init_appts:
            score += 30
            subscores[appt_key] = 30
            feedback.append(
                f"FOUND: {fname} {lname} — appointment scheduled "
                f"(was {init_appts}, now {current_appts}) ✓"
            )
        else:
            subscores[appt_key] = 0
            feedback.append(
                f"MISSING: {fname} {lname} — no new appointment found "
                f"(count still {current_appts})"
            )

    passed = score >= PASS_THRESHOLD
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback),
        "subscores": subscores
    }
