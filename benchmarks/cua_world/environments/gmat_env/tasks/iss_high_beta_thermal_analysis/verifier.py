#!/usr/bin/env python3
"""
Verifier for iss_high_beta_thermal_analysis@1

Agent must simulate the ISS beta angle over 180 days with a high-fidelity force model
and correctly extract the maximum beta angle and number of days spent above 60 degrees.

Scoring (total 100 pts, pass >= 60):
  - script_created (10): Script created/modified during task
  - force_model_correct (20): Gravity degree/order >= 4 used
  - report_file_setup (10): ReportFile outputs BetaAngle
  - propagation_duration (10): Propagator runs for >= 180 days
  - results_file_exists (10): Result report written in correct format
  - max_beta_correct (20): Max Beta Angle in [68.0, 76.0]
  - high_beta_days_correct (20): High Beta Days in [10, 25]

Pass condition: score >= 60 AND max_beta_correct AND high_beta_days_correct
(Physics boundaries strictly check if the agent correctly applied J2 oblateness).
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_iss_high_beta_thermal_analysis(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    max_beta_min = metadata.get('max_beta_min', 68.0)
    max_beta_max = metadata.get('max_beta_max', 76.0)
    high_beta_days_min = metadata.get('high_beta_days_min', 10)
    high_beta_days_max = metadata.get('high_beta_days_max', 25)

    scores = {
        "script_created": 10,
        "force_model_correct": 20,
        "report_file_setup": 10,
        "propagation_duration": 10,
        "results_file_exists": 10,
        "max_beta_correct": 20,
        "high_beta_days_correct": 20,
    }

    total_score = 0
    feedback = []
    max_beta_ok = False
    high_beta_ok = False

    # 1. Load task result JSON
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

    # 2. Check if script exists
    script_exists = task_result.get('script_exists', False)
    if script_exists:
        total_score += scores["script_created"]
        feedback.append("Script created during task.")
    else:
        feedback.append("No GMAT script was created or modified during the task.")

    # 3. Analyze the script content
    temp_script = tempfile.NamedTemporaryFile(delete=False, suffix='.script')
    if script_exists:
        try:
            copy_from_env("/tmp/agent_script.script", temp_script.name)
            with open(temp_script.name, 'r', encoding='utf-8', errors='ignore') as f:
                script_content = f.read()

            # Check Force Model (Degree/Order)
            # Default point mass has no Degree/Order. J2 requires >= 2, but standard is >= 4.
            degree_match = re.search(r'\.Degree\s*=\s*([0-9]+)', script_content)
            order_match = re.search(r'\.Order\s*=\s*([0-9]+)', script_content)
            
            degree = int(degree_match.group(1)) if degree_match else 0
            order = int(order_match.group(1)) if order_match else 0
            
            # GMAT default creates a JGM-2 4x4 or 8x8. If they just use point mass, it'll fail physics anyway.
            if degree >= 2 and order >= 0:
                total_score += scores["force_model_correct"]
                feedback.append(f"High-fidelity gravity model used (Degree={degree}, Order={order}).")
            else:
                feedback.append(f"Gravity model lacks sufficient Degree/Order (Found: {degree}x{order}). This causes RAAN drift failures.")

            # Check ReportFile configuration for BetaAngle
            if 'BetaAngle' in script_content:
                total_score += scores["report_file_setup"]
                feedback.append("ReportFile correctly tracks BetaAngle.")
            else:
                feedback.append("BetaAngle not found in script.")

            # Check Propagation duration (looking for ElapsedDays = 180 or similar)
            prop_match = re.search(r'ElapsedDays\s*=\s*([0-9\.]+)', script_content)
            duration = float(prop_match.group(1)) if prop_match else 0.0
            
            if duration >= 179.0:
                total_score += scores["propagation_duration"]
                feedback.append(f"Propagation duration set correctly ({duration} days).")
            else:
                feedback.append(f"Propagation duration too short ({duration} days found).")
                
        except Exception as e:
            feedback.append(f"Error parsing script: {e}")
        finally:
            if os.path.exists(temp_script.name):
                os.unlink(temp_script.name)

    # 4. Check results file
    report_exists = task_result.get('report_exists', False)
    report_created_during = task_result.get('report_created_during_task', False)
    
    if report_exists and report_created_during:
        total_score += scores["results_file_exists"]
        feedback.append("Analysis report successfully written.")
    else:
        feedback.append("Analysis report missing or not updated during task.")

    # 5. Check Output Values
    try:
        max_beta = float(task_result.get('max_beta_angle_deg', 0))
    except (ValueError, TypeError):
        max_beta = 0.0

    try:
        high_beta_days = int(task_result.get('high_beta_days', 0))
    except (ValueError, TypeError):
        high_beta_days = 0

    if max_beta_min <= max_beta <= max_beta_max:
        total_score += scores["max_beta_correct"]
        max_beta_ok = True
        feedback.append(f"Max Beta Angle correct: {max_beta} deg (expected {max_beta_min}-{max_beta_max}).")
    else:
        feedback.append(f"Max Beta Angle incorrect: {max_beta} deg (expected {max_beta_min}-{max_beta_max}). Did you use a point-mass gravity model?")

    if high_beta_days_min <= high_beta_days <= high_beta_days_max:
        total_score += scores["high_beta_days_correct"]
        high_beta_ok = True
        feedback.append(f"High Beta Days correct: {high_beta_days} days (expected {high_beta_days_min}-{high_beta_days_max}).")
    else:
        feedback.append(f"High Beta Days incorrect: {high_beta_days} days (expected {high_beta_days_min}-{high_beta_days_max}).")

    # Final Pass Evaluation
    key_criteria_met = max_beta_ok and high_beta_ok
    passed = (total_score >= 60) and key_criteria_met

    return {
        "passed": passed,
        "score": total_score,
        "feedback": " | ".join(feedback),
        "details": {
            "max_beta_angle": max_beta,
            "high_beta_days": high_beta_days,
            "key_criteria_met": key_criteria_met
        }
    }