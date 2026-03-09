#!/usr/bin/env python3
"""
Verifier for vaccine_audit_and_schedule task in NOSH ChartingSystem.

Scenario: Preventive care audit for seniors (65+).
Pids 27, 28, 29 are missing Shingrix — agent must:
  (1) add Shingrix vaccine record, and (2) schedule 2026-09-15 9:00 AM appointment.
Pid 30 already has Shingrix (noise — should NOT get a new vaccine entry).

Scoring (100 points total):
- Shingrix vaccine recorded for pid 27 (Virginia Slagle):  15 pts
- Appointment on 2026-09-15 for pid 27:                    10 pts
- Shingrix vaccine recorded for pid 28 (Harold Dunbar):    15 pts
- Appointment on 2026-09-15 for pid 28:                    10 pts
- Shingrix vaccine recorded for pid 29 (Agnes Morley):     15 pts
- Appointment on 2026-09-15 for pid 29:                    10 pts
- All 3 vaccinations correctly completed:                   25 pts bonus

Pass threshold: 60 points (at least 2 complete patient interventions)
"""

import json
import os
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

RESULT_PATH = "/tmp/vaccine_audit_and_schedule_result.json"


def verify_vaccine_audit_and_schedule(traj, env_info, task_info):
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

    all_vaccinated = True
    all_scheduled = True

    for pid_key, name, label in [('27', 'Virginia Slagle', 'pid 27'),
                                  ('28', 'Harold Dunbar', 'pid 28'),
                                  ('29', 'Agnes Morley', 'pid 29')]:
        try:
            p = patients.get(pid_key, {})
            # Vaccine criterion (15 pts each)
            if p.get('shingrix_found') or p.get('new_vaccine_added'):
                score += 15
                feedback_parts.append(f"PASS: Shingrix recorded for {name} ({label})")
            else:
                all_vaccinated = False
                feedback_parts.append(f"FAIL: No Shingrix recorded for {name} ({label})")

            # Appointment criterion (10 pts each)
            if p.get('appointment_sep15'):
                score += 10
                feedback_parts.append(f"PASS: 2026-09-15 appointment scheduled for {name} ({label})")
            else:
                all_scheduled = False
                feedback_parts.append(f"FAIL: No 2026-09-15 appointment for {name} ({label})")
        except Exception as e:
            all_vaccinated = False
            all_scheduled = False
            feedback_parts.append(f"ERROR checking {label}: {e}")

    # Bonus: all 3 fully completed
    try:
        if all_vaccinated and all_scheduled:
            score += 25
            feedback_parts.append("BONUS: All 3 patients fully vaccinated and scheduled (+25)")
        elif all_vaccinated:
            score += 10
            feedback_parts.append("PARTIAL BONUS: All 3 patients vaccinated but appointments incomplete (+10)")
    except Exception:
        pass

    passed = score >= 60
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
        "patients": {
            "27": {"name": "Virginia Slagle", "init_imm_count": 2, "curr_imm_count": 3,
                   "shingrix_found": True, "new_vaccine_added": True,
                   "latest_vaccine_name": "Zoster (Shingrix)",
                   "init_sch_count": 0, "curr_sch_count": 1, "appointment_sep15": True},
            "28": {"name": "Harold Dunbar", "init_imm_count": 1, "curr_imm_count": 2,
                   "shingrix_found": True, "new_vaccine_added": True,
                   "latest_vaccine_name": "Zoster (Shingrix)",
                   "init_sch_count": 0, "curr_sch_count": 1, "appointment_sep15": True},
            "29": {"name": "Agnes Morley", "init_imm_count": 2, "curr_imm_count": 2,
                   "shingrix_found": False, "new_vaccine_added": False,
                   "latest_vaccine_name": "Pneumococcal polysaccharide PPV23",
                   "init_sch_count": 0, "curr_sch_count": 0, "appointment_sep15": False}
        },
        "noise_pid30": {"name": "Clarence Webb", "init_imm_count": 3,
                        "curr_imm_count": 3, "shingrix_count": 1}
    }

    tmp = tempfile.NamedTemporaryFile(mode='w', suffix='.json', delete=False)
    json.dump(mock_result, tmp)
    tmp.close()

    def mock_copy(src, dst):
        shutil.copy(tmp.name, dst)

    result = verify_vaccine_audit_and_schedule(
        traj={}, env_info={'copy_from_env': mock_copy}, task_info={}
    )
    print(f"Score: {result['score']}/100, Passed: {result['passed']}")
    print(f"Feedback: {result['feedback']}")
    os.unlink(tmp.name)
