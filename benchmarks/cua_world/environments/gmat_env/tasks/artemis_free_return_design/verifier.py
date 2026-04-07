#!/usr/bin/env python3
"""
Verifier for artemis_free_return_design@1
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_artemis_free_return(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    dv_min = metadata.get('dv_min_kms', 3.0)
    dv_max = metadata.get('dv_max_kms', 3.3)
    luna_target = metadata.get('luna_rmag_target_km', 4000.0)
    earth_target = metadata.get('earth_rmag_target_km', 6411.14)
    tolerance = metadata.get('tolerance_km', 5.0)

    scores = {
        "script_created": 10,
        "propagator_configured": 10,
        "target_sequence_valid": 15,
        "targeter_converged": 10,
        "deltav_reported": 15,
        "lunar_rmag_reported": 15,
        "earth_rmag_reported": 15,
        "results_written": 10,
    }

    total_score = 0
    feedback = []
    target_ok = False
    earth_ok = False
    run_success = False

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

    run_success = str(task_result.get('console_run_success', 'false')).lower() == 'true'
    dc_converged = task_result.get('dc_converged', False)

    # 1. Script created
    script_file = task_result.get('script_file', {})
    if isinstance(script_file, dict) and script_file.get('created_during_task'):
        total_score += scores["script_created"]
        feedback.append("Script created during task window.")
    else:
        feedback.append("Script not created during task window.")

    # 2. Analyze script
    script_path = task_result.get('script_path', '/home/ga/GMAT_output/artemis_free_return.script')
    if isinstance(script_file, dict) and script_file.get('exists'):
        temp_script = tempfile.NamedTemporaryFile(delete=False, suffix='.script')
        try:
            copy_from_env(script_path, temp_script.name)
            with open(temp_script.name, 'r', encoding='utf-8', errors='ignore') as f:
                script_content = f.read()

            # Propagator check
            has_earth = bool(re.search(r'(PointMasses|PrimaryBodies)\s*=\s*\{[^}]*Earth[^}]*\}', script_content, re.IGNORECASE))
            has_luna = bool(re.search(r'(PointMasses|PrimaryBodies)\s*=\s*\{[^}]*Luna[^}]*\}', script_content, re.IGNORECASE))
            if has_earth and has_luna:
                total_score += scores["propagator_configured"]
                feedback.append("Propagator configured with Earth and Luna.")
            else:
                feedback.append("Propagator missing Earth or Luna.")

            # Target sequence check
            has_target = bool(re.search(r'\bTarget\b', script_content, re.IGNORECASE))
            has_vary = bool(re.search(r'\bVary\b', script_content, re.IGNORECASE))
            has_achieve = bool(re.search(r'\bAchieve\b', script_content, re.IGNORECASE))
            has_propagate = bool(re.search(r'\bPropagate\b', script_content, re.IGNORECASE))
            if has_target and has_vary and has_achieve and has_propagate:
                total_score += scores["target_sequence_valid"]
                target_ok = True
                feedback.append("Target sequence (Target/Vary/Achieve/Propagate) is present.")
            else:
                feedback.append("Target sequence is missing required commands.")
        except Exception as e:
            feedback.append(f"Error reading script: {e}")
        finally:
            if os.path.exists(temp_script.name):
                os.unlink(temp_script.name)
    else:
        feedback.append("Script file not found.")

    if dc_converged:
        total_score += scores["targeter_converged"]
        feedback.append("Targeter successfully converged during verification run.")
    else:
        feedback.append("Targeter did not converge (or script failed to run).")

    # 3. Analyze results text
    results_file = task_result.get('results_file', {})
    results_path = task_result.get('results_path', '/home/ga/GMAT_output/free_return_results.txt')
    if isinstance(results_file, dict) and results_file.get('exists'):
        total_score += scores["results_written"]
        feedback.append("Results file written.")
        
        temp_results = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        try:
            copy_from_env(results_path, temp_results.name)
            with open(temp_results.name, 'r', encoding='utf-8', errors='ignore') as f:
                results_content = f.read()

            # Extract numbers (ignore negative signs just in case, but allow them)
            numbers = [float(n) for n in re.findall(r'[-+]?\d*\.\d+|\d+', results_content)]
            
            if any(dv_min <= n <= dv_max for n in numbers):
                total_score += scores["deltav_reported"]
                feedback.append("Converged TLI Delta-V is physically accurate.")
            else:
                feedback.append("Reported TLI Delta-V is missing or out of valid range.")

            if any(abs(n - luna_target) <= tolerance for n in numbers):
                total_score += scores["lunar_rmag_reported"]
                feedback.append("Achieved Lunar RMAG is reported.")
            else:
                feedback.append("Reported Lunar RMAG is missing or out of tolerance.")

            if any(abs(n - earth_target) <= tolerance for n in numbers):
                total_score += scores["earth_rmag_reported"]
                earth_ok = True
                feedback.append("Achieved Earth RMAG is reported.")
            else:
                feedback.append("Reported Earth RMAG is missing or out of tolerance.")

        except Exception as e:
            feedback.append(f"Error reading results: {e}")
        finally:
            if os.path.exists(temp_results.name):
                os.unlink(temp_results.name)
    else:
        feedback.append("Results file not found.")

    # Pass condition:
    # Score >= 70, script must have target sequence, reported earth target, AND the script must run successfully.
    passed = total_score >= 70 and target_ok and earth_ok and run_success

    return {
        "passed": passed,
        "score": total_score,
        "feedback": " | ".join(feedback)
    }