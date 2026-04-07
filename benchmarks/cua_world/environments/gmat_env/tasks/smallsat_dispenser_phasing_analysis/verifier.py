#!/usr/bin/env python3
"""
Verifier for smallsat_dispenser_phasing_analysis@1

Agent must simulate 4 spacecraft ejected with varying delta-Vs (+0.5, +1.0, +1.5, +2.0 m/s)
and calculate their resulting SMA differences and along-track angular drift over 30 days.

Scoring (total 100 pts, pass >= 70):
  - script_structure (20): 4 Spacecraft and 4 ImpulsiveBurns present in script.
  - sma_values_correct (20): All 4 SMAs within +/- 0.5 km of theoretical predictions.
  - angle_A_B_correct (15): Angle within expected range [28.0, 38.0]
  - angle_A_C_correct (15): Angle within expected range [60.0, 72.0]
  - angle_A_D_correct (20): Angle within expected range [90.0, 105.0]
  - report_format (10): Report format correctly read with all 7 fields.

Pass condition: score >= 70
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_smallsat_dispenser_phasing(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    
    expected_sma_A = metadata.get('sma_A_expected', 6872.04)
    expected_sma_B = metadata.get('sma_B_expected', 6872.95)
    expected_sma_C = metadata.get('sma_C_expected', 6873.85)
    expected_sma_D = metadata.get('sma_D_expected', 6874.75)
    sma_tol = metadata.get('sma_tolerance', 0.5)
    
    min_A_B = metadata.get('angle_A_B_min', 28.0)
    max_A_B = metadata.get('angle_A_B_max', 38.0)
    min_A_C = metadata.get('angle_A_C_min', 60.0)
    max_A_C = metadata.get('angle_A_C_max', 72.0)
    min_A_D = metadata.get('angle_A_D_min', 90.0)
    max_A_D = metadata.get('angle_A_D_max', 105.0)

    scores = {
        "script_structure": 20,
        "sma_values_correct": 20,
        "angle_A_B_correct": 15,
        "angle_A_C_correct": 15,
        "angle_A_D_correct": 20,
        "report_format": 10
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

    # 1. Script structure
    script_file = task_result.get('script_file', {})
    script_path = task_result.get('script_path', '/home/ga/Documents/missions/dispenser_mission.script')
    
    if isinstance(script_file, dict) and script_file.get('created_during_task') and script_file.get('exists'):
        temp_script = tempfile.NamedTemporaryFile(delete=False, suffix='.script')
        try:
            copy_from_env(script_path, temp_script.name)
            with open(temp_script.name, 'r', encoding='utf-8', errors='ignore') as f:
                script_content = f.read()

            sc_count = len(re.findall(r'Create\s+(Spacecraft|spacecraft)', script_content))
            burn_count = len(re.findall(r'Create\s+ImpulsiveBurn', script_content))

            if sc_count >= 4 and burn_count >= 4:
                total_score += scores["script_structure"]
                feedback.append(f"Script structure valid: {sc_count} Spacecraft, {burn_count} ImpulsiveBurns.")
            else:
                total_score += scores["script_structure"] // 2
                feedback.append(f"Script lacks structure: found {sc_count} Spacecraft, {burn_count} ImpulsiveBurns (expected 4 each).")
        except Exception as e:
            feedback.append(f"Could not analyze script content: {e}")
        finally:
            if os.path.exists(temp_script.name):
                os.unlink(temp_script.name)
    else:
        feedback.append("Script not created during task window.")

    # Parse and safely convert numeric variables
    def get_float(key, default=0.0):
        try:
            val = float(task_result.get(key, default))
            return val
        except (ValueError, TypeError):
            return default

    sma_A = get_float('sma_A_km')
    sma_B = get_float('sma_B_km')
    sma_C = get_float('sma_C_km')
    sma_D = get_float('sma_D_km')
    ang_AB = abs(get_float('angle_A_to_B_deg'))
    ang_AC = abs(get_float('angle_A_to_C_deg'))
    ang_AD = abs(get_float('angle_A_to_D_deg'))

    # 2. Report Format Check
    report_file = task_result.get('report_file', {})
    if isinstance(report_file, dict) and report_file.get('exists') and report_file.get('created_during_task'):
        if all(v != 0.0 for v in [sma_A, sma_B, sma_C, sma_D, ang_AB, ang_AC, ang_AD]):
            total_score += scores["report_format"]
            feedback.append("Report format valid and all 7 fields extracted.")
        else:
            total_score += scores["report_format"] // 2
            feedback.append("Report format partially correct or missing some fields.")
    else:
        feedback.append("Report not created during task window.")

    # 3. SMA check
    sma_A_ok = abs(sma_A - expected_sma_A) <= sma_tol
    sma_B_ok = abs(sma_B - expected_sma_B) <= sma_tol
    sma_C_ok = abs(sma_C - expected_sma_C) <= sma_tol
    sma_D_ok = abs(sma_D - expected_sma_D) <= sma_tol

    if sma_A_ok and sma_B_ok and sma_C_ok and sma_D_ok:
        total_score += scores["sma_values_correct"]
        feedback.append("All 4 final SMA values match theoretical physics.")
    else:
        feedback.append(f"SMA values incorrect or missing. Evaluated: A={sma_A}, B={sma_B}, C={sma_C}, D={sma_D}.")

    # 4. Angle A to B
    if min_A_B <= ang_AB <= max_A_B:
        total_score += scores["angle_A_B_correct"]
        feedback.append(f"Angle A-B is physically correct ({ang_AB} deg).")
    else:
        feedback.append(f"Angle A-B incorrect ({ang_AB} deg). Expected {min_A_B}-{max_A_B}.")

    # 5. Angle A to C
    if min_A_C <= ang_AC <= max_A_C:
        total_score += scores["angle_A_C_correct"]
        feedback.append(f"Angle A-C is physically correct ({ang_AC} deg).")
    else:
        feedback.append(f"Angle A-C incorrect ({ang_AC} deg). Expected {min_A_C}-{max_A_C}.")

    # 6. Angle A to D
    if min_A_D <= ang_AD <= max_A_D:
        total_score += scores["angle_A_D_correct"]
        feedback.append(f"Angle A-D is physically correct ({ang_AD} deg).")
    else:
        feedback.append(f"Angle A-D incorrect ({ang_AD} deg). Expected {min_A_D}-{max_A_D}.")

    passed = total_score >= 70
    return {
        "passed": passed,
        "score": total_score,
        "feedback": " | ".join(feedback)
    }