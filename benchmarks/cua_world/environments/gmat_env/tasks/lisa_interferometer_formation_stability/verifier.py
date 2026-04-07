#!/usr/bin/env python3
"""
Verifier for lisa_interferometer_formation_stability@1

Agent must simulate the LISA 3-spacecraft formation in GMAT using a custom
Sun-centered Ecliptic frame and Mean Anomaly. If done correctly, the physics
of the Clohessy-Wiltshire geometry ensure the arm length remains ~2.5 million km
with a ~24,100 km variation over 1 year.

Scoring (total 100 pts, pass >= 60):
  - script_created (10): GMAT script saved in output directory
  - coord_system_valid (15): Sun-centered MJ2000Ec system created
  - spacecraft_configured (20): 3 spacecraft configured, MA used
  - force_model_valid (10): Point mass Sun only
  - propagation_valid (10): Propagation duration is 365 days
  - report_exists (10): Summary text file generated
  - arm_length_accurate (15): Nominal arm ~2.5 million km
  - variation_accurate (10): Variation ~24,000 km

Pass condition: score >= 60 AND arm_length_accurate AND coord_system_valid
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_lisa_interferometer_formation_stability(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    exp_arm = metadata.get('expected_arm_length_km', 2498260.0)
    arm_tol = metadata.get('arm_length_tolerance_km', 50000.0)
    exp_var = metadata.get('expected_variation_km', 24100.0)
    var_tol = metadata.get('variation_tolerance_km', 10000.0)

    scores = {
        "script_created": 10,
        "coord_system_valid": 15,
        "spacecraft_configured": 20,
        "force_model_valid": 10,
        "propagation_valid": 10,
        "report_exists": 10,
        "arm_length_accurate": 15,
        "variation_accurate": 10,
    }

    total_score = 0
    feedback = []
    coord_ok = False
    arm_ok = False

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

    # 1. Check script exists
    script_file = task_result.get('script_file', {})
    if isinstance(script_file, dict) and script_file.get('created_during_task'):
        total_score += scores["script_created"]
        feedback.append("Script created during task window.")
    elif isinstance(script_file, dict) and script_file.get('exists'):
        total_score += scores["script_created"] // 2
        feedback.append("Script exists but may not have been created during task window.")
    else:
        feedback.append("GMAT script not found at expected path.")

    # 2. Analyze script content
    script_path = task_result.get('script_path', '/home/ga/GMAT_output/lisa_formation.script')
    if isinstance(script_file, dict) and script_file.get('exists'):
        temp_script = tempfile.NamedTemporaryFile(delete=False, suffix='.script')
        try:
            copy_from_env(script_path, temp_script.name)
            with open(temp_script.name, 'r', encoding='utf-8', errors='ignore') as f:
                script_content = f.read()

            # Check Coordinate System
            # Should have Origin = Sun and Axes = MJ2000Ec
            has_sun_origin = bool(re.search(r'\.Origin\s*=\s*Sun', script_content))
            has_ec_axes = bool(re.search(r'\.Axes\s*=\s*MJ2000Ec', script_content))
            
            if has_sun_origin and has_ec_axes:
                total_score += scores["coord_system_valid"]
                coord_ok = True
                feedback.append("Custom Sun-centered Ecliptic coordinate system found.")
            else:
                feedback.append("Sun-centered Ecliptic coordinate system not properly defined.")

            # Check Spacecraft & Mean Anomaly
            sc_count = len(re.findall(r'Create\s+Spacecraft', script_content))
            has_ma = bool(re.search(r'\.MA\s*=', script_content))
            has_ta = bool(re.search(r'\.TA\s*=', script_content))
            
            if sc_count >= 3 and has_ma and not has_ta:
                total_score += scores["spacecraft_configured"]
                feedback.append(f"{sc_count} Spacecraft found using Mean Anomaly.")
            elif sc_count >= 3 and has_ma and has_ta:
                total_score += scores["spacecraft_configured"] // 2
                feedback.append(f"{sc_count} Spacecraft found but True Anomaly also used (might be incorrect).")
            elif sc_count >= 3:
                total_score += scores["spacecraft_configured"] // 3
                feedback.append(f"{sc_count} Spacecraft found, but missing Mean Anomaly (MA) usage.")
            else:
                feedback.append(f"Expected 3 spacecraft, found {sc_count}.")

            # Check Force Model
            # Should be CentralBody = Sun, PointMasses = {Sun} (and no Earth gravity/drag)
            has_sun_cb = bool(re.search(r'\.CentralBody\s*=\s*Sun', script_content))
            has_earth = bool(re.search(r'\.CentralBody\s*=\s*Earth', script_content))
            has_drag = bool(re.search(r'\.Drag\.', script_content))

            if has_sun_cb and not has_earth and not has_drag:
                total_score += scores["force_model_valid"]
                feedback.append("Force model correctly set to Sun only.")
            elif has_sun_cb:
                total_score += scores["force_model_valid"] // 2
                feedback.append("Sun central body used, but other forces might be active.")
            else:
                feedback.append("Force model does not use Sun as Central Body.")

            # Check Propagation duration (365 days)
            if bool(re.search(r'\.ElapsedDays\s*=\s*365', script_content)):
                total_score += scores["propagation_valid"]
                feedback.append("Propagation set to 365 days.")
            else:
                feedback.append("Propagation duration not set to exactly 365 days.")

        except Exception as e:
            feedback.append(f"Failed to read script content: {e}")
        finally:
            if os.path.exists(temp_script.name):
                os.unlink(temp_script.name)

    # 3. Check report and values
    report_file = task_result.get('report_file', {})
    if isinstance(report_file, dict) and report_file.get('exists'):
        total_score += scores["report_exists"]
        feedback.append("Summary report exists.")

        try:
            nom_len = float(task_result.get('nominal_arm_length_km', 0))
        except (ValueError, TypeError):
            nom_len = 0.0

        try:
            var_len = float(task_result.get('variation_km', 0))
        except (ValueError, TypeError):
            var_len = 0.0

        # Validate nominal arm length
        if abs(nom_len - exp_arm) <= arm_tol:
            total_score += scores["arm_length_accurate"]
            arm_ok = True
            feedback.append(f"Nominal arm length accurate: {nom_len} km (Expected ~{exp_arm} km).")
        else:
            feedback.append(f"Nominal arm length inaccurate: {nom_len} km (Expected ~{exp_arm} km).")

        # Validate variation
        if abs(var_len - exp_var) <= var_tol:
            total_score += scores["variation_accurate"]
            feedback.append(f"Arm length variation accurate: {var_len} km (Expected ~{exp_var} km).")
        else:
            feedback.append(f"Arm length variation inaccurate: {var_len} km (Expected ~{exp_var} km).")
            
    else:
        feedback.append("Summary report not found.")

    # 4. Final calculation
    passed = (total_score >= 60) and arm_ok and coord_ok

    return {
        "passed": passed,
        "score": total_score,
        "feedback": " | ".join(feedback)
    }