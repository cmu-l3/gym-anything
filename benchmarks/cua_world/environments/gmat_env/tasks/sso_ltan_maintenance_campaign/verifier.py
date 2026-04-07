#!/usr/bin/env python3
"""
Verifier for sso_ltan_maintenance_campaign@1
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_sso_ltan_maintenance_campaign(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    target_ltan = metadata.get('target_ltan', 10.5)
    ltan_tol = metadata.get('target_ltan_tolerance', 0.05)
    inc_min = metadata.get('expected_inclination_min', 97.2)
    inc_max = metadata.get('expected_inclination_max', 97.75)
    dv_min = metadata.get('expected_deltav_min_kms', 0.010)
    dv_max = metadata.get('expected_deltav_max_kms', 0.080)

    scores = {
        "script_created": 10,
        "report_created": 10,
        "targeting_logic_present": 20,
        "j2_force_model_used": 10,
        "final_ltan_achieved": 20,
        "inclination_physics_valid": 15,
        "deltav_magnitude_valid": 15
    }

    total_score = 0
    feedback = []
    
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

    # 1. Script created
    script_file = task_result.get('script_file', {})
    if isinstance(script_file, dict) and script_file.get('created_during_task'):
        total_score += scores["script_created"]
        feedback.append("Script created during task window.")
    else:
        feedback.append("Script not created during task window.")

    # 2. Report created
    report_file = task_result.get('report_file', {})
    if isinstance(report_file, dict) and report_file.get('created_during_task'):
        total_score += scores["report_created"]
        feedback.append("Report created during task window.")
    else:
        feedback.append("Report not created during task window.")

    # 3 & 4. Script Logic and J2 Checks
    targeting_logic_ok = False
    script_path = task_result.get('script_path', '/home/ga/GMAT_output/ltan_campaign.script')
    if isinstance(script_file, dict) and script_file.get('exists'):
        temp_script = tempfile.NamedTemporaryFile(delete=False, suffix='.script')
        try:
            copy_from_env(script_path, temp_script.name)
            with open(temp_script.name, 'r', encoding='utf-8', errors='ignore') as f:
                script_content = f.read()

            # Targeter check
            if ("Target" in script_content and 
                "Vary" in script_content and 
                "Propagate" in script_content and 
                "Achieve" in script_content):
                total_score += scores["targeting_logic_present"]
                targeting_logic_ok = True
                feedback.append("Targeting logic (Target/Vary/Propagate/Achieve) found in script.")
            else:
                feedback.append("Targeting logic missing in script.")

            # J2 check (Degree=2, Order=0)
            if re.search(r'Degree\s*=\s*2', script_content) and re.search(r'Order\s*=\s*0', script_content):
                total_score += scores["j2_force_model_used"]
                feedback.append("J2 force model (Degree=2, Order=0) properly configured.")
            else:
                feedback.append("J2 force model not explicitly configured (missing Degree=2, Order=0).")

        except Exception as e:
            feedback.append(f"Error reading script: {e}")
        finally:
            if os.path.exists(temp_script.name):
                os.unlink(temp_script.name)
    else:
        feedback.append("Cannot analyze script because it does not exist.")

    # 5. Final LTAN check
    try:
        final_ltan = float(task_result.get('final_ltan', 0))
    except (ValueError, TypeError):
        final_ltan = 0.0

    if (target_ltan - ltan_tol) <= final_ltan <= (target_ltan + ltan_tol):
        total_score += scores["final_ltan_achieved"]
        ltan_ok = True
        feedback.append(f"Final LTAN achieved: {final_ltan}.")
    else:
        ltan_ok = False
        feedback.append(f"Final LTAN not achieved: {final_ltan} (expected ~{target_ltan}).")

    # 6. Inclination Physics Check
    try:
        drift_inc = float(task_result.get('drift_inclination_deg', 0))
    except (ValueError, TypeError):
        drift_inc = 0.0

    # The inclination must DECREASE from 97.787 to make cos(i) less negative.
    if inc_min <= drift_inc <= inc_max:
        total_score += scores["inclination_physics_valid"]
        feedback.append(f"Inclination physically valid: {drift_inc} deg (expected decrease to [{inc_min}, {inc_max}]).")
    else:
        feedback.append(f"Inclination not in expected range: {drift_inc} deg (expected [{inc_min}, {inc_max}]).")

    # 7. DeltaV Magnitude Check
    try:
        dv_normal = abs(float(task_result.get('deltav_normal_kms', 0)))
    except (ValueError, TypeError):
        dv_normal = 0.0

    if dv_min <= dv_normal <= dv_max:
        total_score += scores["deltav_magnitude_valid"]
        feedback.append(f"DeltaV Normal magnitude physically valid: {dv_normal:.4f} km/s (expected [{dv_min}, {dv_max}]).")
    else:
        feedback.append(f"DeltaV Normal magnitude out of range: {dv_normal:.4f} km/s (expected [{dv_min}, {dv_max}]).")

    # Final pass logic ensures it didn't just stumble on the final outcome by skipping targeting
    passed = (total_score >= 70) and targeting_logic_ok and ltan_ok

    return {
        "passed": passed,
        "score": total_score,
        "feedback": " | ".join(feedback)
    }