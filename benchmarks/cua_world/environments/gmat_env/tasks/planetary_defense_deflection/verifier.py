#!/usr/bin/env python3
"""
Verifier for planetary_defense_deflection@1

Agent must complete a GMAT DifferentialCorrector target loop to deflect an
asteroid to exactly 20,000 km miss distance and report the required Delta-V in cm/s.

Scoring (total 100 pts, pass >= 70):
  - script_created (10): Script was created and saved in the correct path
  - target_sequence_valid (20): Script contains Target, Vary, Maneuver, Propagate, Achieve commands
  - propagate_correct (10): Script propagates to Ast2028.Earth.Periapsis
  - achieve_correct (15): Achieve targets Ast2028.Earth.RMAG = 20000.0
  - script_execution_success (20): Script successfully runs and Targeter converges
  - report_created (10): Report exists
  - dv_calculated_correctly (15): Agent correctly converted DV to cm/s and reported the absolute magnitude

Pass condition: score >= 70 AND script_execution_success AND achieve_correct
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_planetary_defense_deflection(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: copy_from_env not available"}

    scores = {
        "script_created": 10,
        "target_sequence_valid": 20,
        "propagate_correct": 10,
        "achieve_correct": 15,
        "script_execution_success": 20,
        "report_created": 10,
        "dv_calculated_correctly": 15
    }

    total_score = 0
    feedback = []
    
    script_exec_ok = False
    achieve_ok = False

    # Load task result JSON
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

    # 1. Script Created
    script_file = task_result.get('script_file', {})
    if isinstance(script_file, dict) and script_file.get('created_during_task'):
        total_score += scores["script_created"]
        feedback.append("Script created/saved successfully.")
    else:
        feedback.append("Output script not created at the expected path.")

    # 2. Analyze Script Content
    script_path = task_result.get('script_path', '/home/ga/GMAT_output/asteroid_deflection.script')
    if isinstance(script_file, dict) and script_file.get('exists'):
        temp_script = tempfile.NamedTemporaryFile(delete=False, suffix='.script')
        try:
            copy_from_env(script_path, temp_script.name)
            with open(temp_script.name, 'r', encoding='utf-8', errors='ignore') as f:
                script_content = f.read()

            # Target sequence validity
            has_target = re.search(r'\bTarget\s+DC1', script_content)
            has_vary = re.search(r'\bVary\s+DC1', script_content)
            has_maneuver = re.search(r'\bManeuver\s+DeflectionBurn', script_content)
            has_propagate = re.search(r'\bPropagate\s+', script_content)
            has_achieve = re.search(r'\bAchieve\s+DC1', script_content)

            if has_target and has_vary and has_maneuver and has_propagate and has_achieve:
                total_score += scores["target_sequence_valid"]
                feedback.append("Valid Target sequence logic constructed.")
            else:
                feedback.append("Target sequence is missing required components (Vary/Maneuver/Propagate/Achieve).")

            # Propagate correct
            if 'Ast2028.Earth.Periapsis' in script_content:
                total_score += scores["propagate_correct"]
                feedback.append("Correctly propagates to Earth.Periapsis.")
            else:
                feedback.append("Does not properly propagate to Ast2028.Earth.Periapsis.")

            # Achieve correct
            if 'Ast2028.Earth.RMAG' in script_content and '20000' in script_content:
                total_score += scores["achieve_correct"]
                achieve_ok = True
                feedback.append("Correctly targets RMAG = 20000 km.")
            else:
                feedback.append("Missing or incorrect Achieve condition for RMAG.")

        except Exception as e:
            feedback.append(f"Failed to read agent script: {e}")
        finally:
            if os.path.exists(temp_script.name):
                os.unlink(temp_script.name)

    # 3. Script Execution Success
    console_run = str(task_result.get('console_run_success', '')).lower() == 'true'
    converged = str(task_result.get('targeter_converged', '')).lower() == 'true'

    if console_run and converged:
        total_score += scores["script_execution_success"]
        script_exec_ok = True
        feedback.append("Agent script successfully ran and DifferentialCorrector converged!")
    elif console_run:
        feedback.append("Agent script ran, but DifferentialCorrector failed to converge.")
    else:
        feedback.append("Agent script failed to run via GmatConsole (likely syntax error).")

    # 4. Report Created
    report_file = task_result.get('report_file', {})
    if isinstance(report_file, dict) and report_file.get('created_during_task'):
        total_score += scores["report_created"]
        feedback.append("Deflection report created.")
    else:
        feedback.append("Deflection report not created.")

    # 5. DV Calculated Correctly
    # Compare GMAT's actual converged physics result with what the agent wrote
    try:
        actual_dv_kms = float(task_result.get('actual_dv_kms', 0))
        reported_dv_cms = float(task_result.get('reported_dv_cm_s', 0))
    except (ValueError, TypeError):
        actual_dv_kms = 0.0
        reported_dv_cms = 0.0

    # km/s to cm/s absolute magnitude
    actual_dv_cms = abs(actual_dv_kms * 100000.0)

    if converged and actual_dv_cms > 0.1:
        # Give a +/- 0.2 cm/s tolerance for slight convergence/scaling differences
        if abs(actual_dv_cms - reported_dv_cms) <= 0.2:
            total_score += scores["dv_calculated_correctly"]
            feedback.append(f"DV correctly calculated and reported: {reported_dv_cms:.3f} cm/s (Ground Truth: {actual_dv_cms:.3f} cm/s).")
        else:
            feedback.append(f"Reported DV ({reported_dv_cms:.3f} cm/s) does not match ground truth physics ({actual_dv_cms:.3f} cm/s).")
    else:
        feedback.append("Could not verify reported DV (targeter did not converge).")

    # Check pass condition
    passed = (total_score >= 70) and script_exec_ok and achieve_ok

    return {
        "passed": passed,
        "score": total_score,
        "feedback": " | ".join(feedback)
    }