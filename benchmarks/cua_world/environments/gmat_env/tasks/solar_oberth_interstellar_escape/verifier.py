#!/usr/bin/env python3
"""
Verifier for solar_oberth_interstellar_escape@1

Agent must simulate a deep-space solar drop to perihelion and execute a precisely
targeted impulsive burn to achieve C3 = 1500 km^2/s^2 relative to the Sun.

Scoring (total 100 pts, pass >= 70):
  - script_created (10): Script created during task window
  - sun_centered_model (15): Sun used as CentralBody in ForceModel
  - propagate_to_periapsis (15): Agent correctly targets Sun.Periapsis
  - targeting_logic (20): DifferentialCorrector / Target / Achieve logic present
  - report_written (10): Results report created with parsed data
  - deltav_valid (15): DeltaV falls within mathematical reality [4.80, 4.95] km/s
  - velocity_valid (10): Velocity at perihelion correct [191.5, 193.0] km/s
  - c3_achieved (5): Final C3 value meets exact target range [1499.0, 1501.0]
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_solar_oberth_interstellar_escape(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    dv_min = metadata.get('deltav_min_kms', 4.80)
    dv_max = metadata.get('deltav_max_kms', 4.95)
    vel_min = metadata.get('velocity_min_kms', 191.5)
    vel_max = metadata.get('velocity_max_kms', 193.0)
    c3_min = metadata.get('c3_min', 1499.0)
    c3_max = metadata.get('c3_max', 1501.0)

    scores = {
        "script_created": 10,
        "sun_centered_model": 15,
        "propagate_to_periapsis": 15,
        "targeting_logic": 20,
        "report_written": 10,
        "deltav_valid": 15,
        "velocity_valid": 10,
        "c3_achieved": 5,
    }

    total_score = 0
    feedback = []
    targeting_ok = False
    deltav_ok = False

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

    # 2. Analyze script content
    script_path = task_result.get('script_path', '/home/ga/GMAT_output/oberth_maneuver.script')
    if isinstance(script_file, dict) and script_file.get('exists'):
        temp_script = tempfile.NamedTemporaryFile(delete=False, suffix='.script')
        try:
            copy_from_env(script_path, temp_script.name)
            with open(temp_script.name, 'r', encoding='utf-8', errors='ignore') as f:
                script_content = f.read()

            # Check for Sun-centered Force Model
            if "CentralBody = Sun" in script_content and "PointMasses = {Sun}" in script_content:
                total_score += scores["sun_centered_model"]
                feedback.append("Sun-centric force model found.")
            elif "CentralBody = Sun" in script_content:
                total_score += scores["sun_centered_model"] // 2
                feedback.append("Sun CentralBody found, but point mass might be missing.")
            else:
                feedback.append("Sun-centric force model not properly defined.")

            # Check for propagation to periapsis
            if re.search(r'Propagate[^;]+Sun\.Periapsis', script_content):
                total_score += scores["propagate_to_periapsis"]
                feedback.append("Propagation to Sun Periapsis found.")
            else:
                feedback.append("Propagation to Sun Periapsis not found.")

            # Check DifferentialCorrector logic targeting C3Energy
            if "DifferentialCorrector" in script_content and "Target" in script_content and "Achieve" in script_content and "C3Energy" in script_content:
                total_score += scores["targeting_logic"]
                targeting_ok = True
                feedback.append("DifferentialCorrector targeting logic for C3Energy present.")
            else:
                feedback.append("Targeting logic for C3Energy missing.")

        except Exception as e:
            feedback.append(f"Error reading script from environment: {e}")
        finally:
            if os.path.exists(temp_script.name):
                os.unlink(temp_script.name)

    # 3. Report file validation
    report_file = task_result.get('report_file', {})
    if isinstance(report_file, dict) and report_file.get('exists'):
        if report_file.get('created_during_task'):
            total_score += scores["report_written"]
            feedback.append("Results report created during task window.")
        else:
            feedback.append("Results report exists but was not created during task window.")

        # Extract values
        try:
            dv_val = float(task_result.get('deltav_kms', 0))
            vel_val = float(task_result.get('velocity_kms', 0))
            c3_val = float(task_result.get('c3_km2s2', 0))
        except ValueError:
            dv_val = 0.0
            vel_val = 0.0
            c3_val = 0.0

        if dv_min <= dv_val <= dv_max:
            total_score += scores["deltav_valid"]
            deltav_ok = True
            feedback.append(f"DeltaV is valid: {dv_val:.3f} km/s.")
        else:
            feedback.append(f"DeltaV is invalid: {dv_val:.3f} km/s (expected {dv_min}-{dv_max}).")

        if vel_min <= vel_val <= vel_max:
            total_score += scores["velocity_valid"]
            feedback.append(f"Perihelion Velocity is valid: {vel_val:.3f} km/s.")
        else:
            feedback.append(f"Perihelion Velocity is invalid: {vel_val:.3f} km/s (expected {vel_min}-{vel_max}).")

        if c3_min <= c3_val <= c3_max:
            total_score += scores["c3_achieved"]
            feedback.append(f"Target C3 achieved: {c3_val:.1f} km^2/s^2.")
        else:
            feedback.append(f"Target C3 invalid: {c3_val:.1f} km^2/s^2 (expected exactly 1500.0).")
    else:
        feedback.append("Results report not found.")

    passed = (total_score >= 70) and targeting_ok and deltav_ok

    return {
        "passed": passed,
        "score": total_score,
        "feedback": " | ".join(feedback)
    }