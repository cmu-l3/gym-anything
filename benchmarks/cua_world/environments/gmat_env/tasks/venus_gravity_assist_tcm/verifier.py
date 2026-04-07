#!/usr/bin/env python3
"""
Verifier for venus_gravity_assist_tcm@1

Agent must modify a GMAT script to insert a Trajectory Correction Maneuver (TCM)
using a DifferentialCorrector to target specific Venus flyby conditions.

Scoring (total 100 pts, pass >= 75):
  - script_modified (10): Script modified and saved during task window
  - targeter_configured (20): Script contains Target, Vary, Maneuver, Achieve logic
  - targeter_converges (20): Mathematical convergence verified via GmatConsole
  - achieved_radper (20): Reported RadPer is 6351.8 +/- 1.0 km
  - achieved_inc (15): Reported INC is 105.0 +/- 0.5 deg
  - report_accuracy (15): Report text file exists and has properly extracted Delta-V fields

Pass condition: score >= 75 AND targeter_converges AND achieved_radper
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_venus_gravity_assist_tcm(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    target_radper = metadata.get('target_radper_km', 6351.8)
    target_inc = metadata.get('target_inc_deg', 105.0)
    radper_tol = metadata.get('radper_tolerance_km', 1.0)
    inc_tol = metadata.get('inc_tolerance_deg', 0.5)

    scores = {
        "script_modified": 10,
        "targeter_configured": 20,
        "targeter_converges": 20,
        "achieved_radper": 20,
        "achieved_inc": 15,
        "report_accuracy": 15,
    }

    total_score = 0
    feedback = []
    converged_ok = False
    radper_ok = False

    # Load task result
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

    # 1. Script Modified
    script_file = task_result.get('script_file', {})
    if isinstance(script_file, dict) and script_file.get('created_during_task'):
        total_score += scores["script_modified"]
        feedback.append("Script modified/saved during task window.")
    else:
        feedback.append("Script not modified during task window.")

    # 2. Targeter Configured
    script_path = task_result.get('script_path', '')
    if script_path and isinstance(script_file, dict) and script_file.get('exists'):
        temp_script = tempfile.NamedTemporaryFile(delete=False, suffix='.script')
        try:
            copy_from_env(script_path, temp_script.name)
            with open(temp_script.name, 'r', encoding='utf-8', errors='ignore') as f:
                script_content = f.read()

            has_target = re.search(r'\bTarget\b', script_content)
            has_vary = re.search(r'\bVary\b', script_content)
            has_maneuver = re.search(r'\bManeuver\b', script_content)
            has_achieve = re.search(r'\bAchieve\b', script_content)

            if has_target and has_vary and has_maneuver and has_achieve:
                total_score += scores["targeter_configured"]
                feedback.append("Differential Corrector targeting logic found in script.")
            else:
                missing = []
                if not has_target: missing.append("Target")
                if not has_vary: missing.append("Vary")
                if not has_maneuver: missing.append("Maneuver")
                if not has_achieve: missing.append("Achieve")
                feedback.append(f"Targeting logic incomplete. Missing: {', '.join(missing)}.")
        except Exception as e:
            feedback.append(f"Error reading script content: {e}")
        finally:
            if os.path.exists(temp_script.name):
                os.unlink(temp_script.name)

    # 3. Targeter Converges
    run_success = task_result.get('console_run_success') == "true"
    converged_in_log = task_result.get('targeter_converged_in_log', False)

    if run_success and converged_in_log:
        total_score += scores["targeter_converges"]
        converged_ok = True
        feedback.append("Differential Corrector converged successfully when run.")
    elif run_success:
        total_score += scores["targeter_converges"] // 2
        feedback.append("Script ran successfully but explicit convergence message not found.")
    else:
        feedback.append("Script failed to run or targeter did not converge.")

    # 4. Report Validation (Values)
    report_file = task_result.get('report_file', {})
    if isinstance(report_file, dict) and report_file.get('exists') and report_file.get('created_during_task'):
        try:
            reported_radper = float(task_result.get('reported_radper_km', 0))
            reported_inc = float(task_result.get('reported_inc_deg', 0))
            tcm_v = float(task_result.get('reported_tcm_v_mps', 0))
            tcm_n = float(task_result.get('reported_tcm_n_mps', 0))

            # RadPer Check
            if abs(reported_radper - target_radper) <= radper_tol:
                total_score += scores["achieved_radper"]
                radper_ok = True
                feedback.append(f"Achieved RadPer is correct: {reported_radper} km.")
            else:
                feedback.append(f"Achieved RadPer incorrect: {reported_radper} km (Target: {target_radper}).")

            # INC Check
            if abs(reported_inc - target_inc) <= inc_tol:
                total_score += scores["achieved_inc"]
                feedback.append(f"Achieved INC is correct: {reported_inc} deg.")
            else:
                feedback.append(f"Achieved INC incorrect: {reported_inc} deg (Target: {target_inc}).")

            # TCM realistic bounds check
            # A deep space TCM should rarely exceed a few hundred m/s.
            # If values are exactly 0, they likely failed to read or maneuver wasn't targeted.
            if tcm_v != 0.0 or tcm_n != 0.0:
                if abs(tcm_v) < 1000 and abs(tcm_n) < 1000:
                    total_score += scores["report_accuracy"]
                    feedback.append(f"TCM values reported correctly (V: {tcm_v} m/s, N: {tcm_n} m/s).")
                else:
                    feedback.append(f"TCM values reported but suspiciously large (V: {tcm_v}, N: {tcm_n}).")
            else:
                feedback.append("Reported TCM Delta-V components are exactly 0 or missing.")
        except ValueError:
            feedback.append("Failed to parse numeric values from the report text.")
    else:
        feedback.append("Diagnosis report not found or not created during task.")

    passed = (total_score >= 75) and converged_ok and radper_ok

    return {
        "passed": passed,
        "score": total_score,
        "feedback": " | ".join(feedback)
    }