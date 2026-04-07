#!/usr/bin/env python3
"""
Verifier for heo_third_body_stability@1

Agent must simulate a Highly Elliptical Orbit under 3rd-body perturbations,
find the baseline crash day, and discover a stable RAAN that survives 5 years.

Scoring (total 100 pts, pass >= 70):
  - script_created (10): Script created during task window
  - force_model_correct (15): Script contains Sun and Luna in ForceModel
  - stopping_conditions (10): Script contains ElapsedDays and Altitude stopping conditions
  - report_written (10): Report written with required baseline and RAAN fields
  - baseline_evaluated (20): Baseline lifetime matches ground truth within +/- 15 days
  - stable_solution_verified (35): Dynamic ground-truth re-simulation verifies the agent's RAAN survives 1825 days

Pass condition: Score >= 70 AND stable_solution_verified is True.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_heo_third_body_stability(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    baseline_tol = metadata.get('baseline_tolerance_days', 15.0)

    scores = {
        "script_created": 10,
        "force_model_correct": 15,
        "stopping_conditions": 10,
        "report_written": 10,
        "baseline_evaluated": 20,
        "stable_solution_verified": 35,
    }

    total_score = 0
    feedback = []
    stable_verified = False

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

    # 1. Script created
    script_file = task_result.get('script_file', {})
    if isinstance(script_file, dict) and script_file.get('created_during_task'):
        total_score += scores["script_created"]
        feedback.append("Script created during task window.")
    else:
        feedback.append("Script not created during task window.")

    # 2. Check Script Content (Force Model & Stopping Conditions)
    script_path = task_result.get('script_path', '/home/ga/GMAT_output/stable_heo_mission.script')
    if isinstance(script_file, dict) and script_file.get('exists'):
        temp_script = tempfile.NamedTemporaryFile(delete=False, suffix='.script')
        try:
            copy_from_env(script_path, temp_script.name)
            with open(temp_script.name, 'r', encoding='utf-8', errors='ignore') as f:
                script_content = f.read()

            # Force Model Check
            has_sun = "Sun" in script_content
            has_luna = "Luna" in script_content or "Moon" in script_content
            if has_sun and has_luna:
                total_score += scores["force_model_correct"]
                feedback.append("Sun and Luna explicitly included in ForceModel.")
            else:
                feedback.append("Sun or Luna missing from ForceModel.")

            # Stopping Conditions Check
            has_elapsed = "ElapsedDays" in script_content
            has_altitude = "Altitude" in script_content
            if has_elapsed and has_altitude:
                total_score += scores["stopping_conditions"]
                feedback.append("Both ElapsedDays and Altitude stopping conditions present.")
            else:
                feedback.append("Missing required stopping condition(s).")
                
        except Exception as e:
            feedback.append(f"Could not read script content: {e}")
        finally:
            if os.path.exists(temp_script.name):
                os.unlink(temp_script.name)
    else:
        feedback.append("Script file does not exist, skipping content checks.")

    # 3. Report Written
    report_file = task_result.get('report_file', {})
    agent_baseline_str = task_result.get('agent_baseline_days', "")
    agent_raan_str = task_result.get('agent_stable_raan', "")
    
    if isinstance(report_file, dict) and report_file.get('exists') and agent_baseline_str and agent_raan_str:
        total_score += scores["report_written"]
        feedback.append("Analysis report formatted correctly.")
    else:
        feedback.append("Analysis report missing or incorrectly formatted.")

    # 4. Baseline Evaluated
    try:
        truth_baseline = float(task_result.get('truth_baseline_days', 0))
        agent_baseline = float(agent_baseline_str) if agent_baseline_str else -999.0
        
        diff = abs(truth_baseline - agent_baseline)
        if diff <= baseline_tol and truth_baseline > 0:
            total_score += scores["baseline_evaluated"]
            feedback.append(f"Baseline evaluated correctly: {agent_baseline:.1f} days (Truth: {truth_baseline:.1f}).")
        else:
            feedback.append(f"Baseline evaluation incorrect: {agent_baseline:.1f} days (Expected ~{truth_baseline:.1f}).")
    except ValueError:
        feedback.append("Could not parse baseline days as float.")

    # 5. Stable Solution Verified
    survived = task_result.get('agent_raan_survived', False)
    final_days = task_result.get('verify_final_days', "0")
    final_alt = task_result.get('verify_final_alt_km', "0")
    
    if survived:
        total_score += scores["stable_solution_verified"]
        stable_verified = True
        feedback.append(f"Agent's RAAN ({agent_raan_str} deg) verified! Survived {final_days} days, final min altitude {final_alt} km.")
    else:
        if agent_raan_str:
            feedback.append(f"Agent's RAAN ({agent_raan_str} deg) FAILED. Crashed after {final_days} days (Alt: {final_alt} km).")
        else:
            feedback.append("No valid RAAN provided to test.")

    # Pass Condition
    passed = (total_score >= 70) and stable_verified

    return {
        "passed": passed,
        "score": total_score,
        "feedback": " | ".join(feedback),
        "details": task_result
    }