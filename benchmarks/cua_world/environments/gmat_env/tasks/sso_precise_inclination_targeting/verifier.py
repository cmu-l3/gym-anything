#!/usr/bin/env python3
"""
Verifier for sso_precise_inclination_targeting@1

The agent must use GMAT's Differential Corrector to adjust inclination until
the final RAAN after 10 days is exactly 9.8565 degrees.

Scoring (total 100 pts, pass >= 60):
  - script_modified (10): Script was saved/modified during the task
  - report_created (10): precise_sso_report.txt was created
  - targeting_logic (20): Script contains Target, Vary, Achieve keywords
  - inc_reported (20): Reported inclination is physically realistic (97.79 - 97.83)
  - raan_achieved (40): Reported RAAN matches target exactly (9.8565 +/- 0.005) AND
                        either console run matches or script achieve statement matches.

Pass threshold: score >= 60 AND Targeting Logic AND RAAN Achieved.
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_sso_precise_inclination_targeting(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    target_raan = metadata.get('target_raan', 9.8565)
    raan_tol = metadata.get('target_raan_tolerance', 0.005)
    inc_min = metadata.get('expected_inc_min', 97.79)
    inc_max = metadata.get('expected_inc_max', 97.83)

    scores = {
        "script_modified": 10,
        "report_created": 10,
        "targeting_logic": 20,
        "inc_reported": 20,
        "raan_achieved": 40,
    }

    total_score = 0
    feedback = []
    targeting_ok = False
    raan_ok = False

    # 1. Load exported result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # 2. Check if files exist and were modified
    script_file = task_result.get('script_file', {})
    if isinstance(script_file, dict) and script_file.get('created_during_task'):
        total_score += scores["script_modified"]
        feedback.append("Script modified successfully.")
    else:
        feedback.append("Script was not modified during the task window.")

    report_file = task_result.get('report_file', {})
    if isinstance(report_file, dict) and report_file.get('exists'):
        total_score += scores["report_created"]
        feedback.append("Diagnosis report created.")
    else:
        feedback.append("Diagnosis report was not created.")

    # 3. Analyze script for targeting logic
    script_path = task_result.get('script_path', '/home/ga/Documents/missions/sso_baseline.script')
    if isinstance(script_file, dict) and script_file.get('exists'):
        temp_script = tempfile.NamedTemporaryFile(delete=False, suffix='.script')
        try:
            copy_from_env(script_path, temp_script.name)
            with open(temp_script.name, 'r', encoding='utf-8', errors='ignore') as f:
                script_content = f.read()

            has_target = bool(re.search(r'\bTarget\b', script_content))
            has_vary = bool(re.search(r'\bVary\b.*\bINC\b', script_content))
            has_achieve = bool(re.search(r'\bAchieve\b.*\bRAAN\b', script_content))
            target_raan_found = bool(re.search(r'RAAN\s*=\s*9\.8565', script_content))

            if has_target and has_vary and has_achieve:
                total_score += scores["targeting_logic"]
                targeting_ok = True
                feedback.append("Differential Corrector targeting logic (Target/Vary/Achieve) found in script.")
            elif has_target or has_vary or has_achieve:
                total_score += scores["targeting_logic"] // 2
                feedback.append("Partial targeting logic found in script.")
            else:
                feedback.append("No targeting logic (Target/Vary/Achieve) found in script.")
                
            if target_raan_found:
                feedback.append("Found Achieve target value exactly matching 9.8565.")

        except Exception as e:
            feedback.append(f"Could not read script content: {e}")
        finally:
            if os.path.exists(temp_script.name):
                os.unlink(temp_script.name)

    # 4. Check Reported Values
    try:
        reported_inc = float(task_result.get('reported_inc', 0))
    except (ValueError, TypeError):
        reported_inc = 0.0

    try:
        reported_raan = float(task_result.get('reported_raan', 0))
    except (ValueError, TypeError):
        reported_raan = 0.0

    if inc_min <= reported_inc <= inc_max:
        total_score += scores["inc_reported"]
        feedback.append(f"Reported inclination {reported_inc} is within physically valid range [{inc_min}, {inc_max}].")
    else:
        feedback.append(f"Reported inclination {reported_inc} is OUTSIDE expected valid range [{inc_min}, {inc_max}].")

    # 5. Check RAAN Achieved
    # We check the agent's reported value AND confirm it either against the script target or the rerun result.
    actual_raan_run = 0.0
    try:
        actual_raan_run = float(task_result.get('actual_final_raan', 0))
    except (ValueError, TypeError):
        pass

    agent_raan_matches = abs(reported_raan - target_raan) <= raan_tol
    rerun_raan_matches = abs(actual_raan_run - target_raan) <= raan_tol

    if agent_raan_matches:
        if rerun_raan_matches or (targeting_ok and target_raan_found):
            total_score += scores["raan_achieved"]
            raan_ok = True
            feedback.append(f"Final RAAN targeted successfully: {reported_raan} (Target: {target_raan}).")
        else:
            total_score += scores["raan_achieved"] // 2
            feedback.append(f"Agent reported correct RAAN {reported_raan}, but script execution/targeting verification failed.")
    else:
        feedback.append(f"Failed to achieve target RAAN. Reported: {reported_raan}, Target: {target_raan}.")

    # Pass logic
    key_criteria_met = targeting_ok and raan_ok
    passed = total_score >= 60 and key_criteria_met

    if not passed and total_score >= 60:
        feedback.append("Failed: Mandatory criteria (Targeting Logic and correct RAAN output) were not fully met.")

    return {
        "passed": passed,
        "score": total_score,
        "feedback": " | ".join(feedback),
        "details": {
            "reported_inc": reported_inc,
            "reported_raan": reported_raan,
            "actual_run_raan": actual_raan_run,
            "targeting_ok": targeting_ok,
            "raan_ok": raan_ok
        }
    }