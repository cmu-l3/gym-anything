#!/usr/bin/env python3
"""
Verifier for mars_aerobraking_analysis@1

Agent must simulate a 60-day aerobraking campaign around Mars and compute
the fuel saved (Delta-V) using the Vis-Viva equation based on their results.

Scoring (total 100 pts, pass >= 70):
  - script_created (10): Script created during task window
  - mars_environment_used (20): CentralBody=Mars, Mars Exponential atmosphere, Degree=0/Order=0
  - report_format_correct (10): All 4 keys exist in the output report
  - initial_apoapsis_correct (10): Initial apoapsis matches 23396.19 km
  - orbit_decay_verified (20): Final apoapsis is significantly less than initial (successful aerobraking)
  - deltav_math_correct (30): Delta-V calculated correctly based on the agent's reported radii

Pass condition: score >= 70 AND orbit_decay_verified AND deltav_math_correct
"""

import json
import os
import tempfile
import math
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_mars_aerobraking_analysis(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    expected_initial_apoapsis = metadata.get('initial_apoapsis_km', 23396.19)
    mu_mars = metadata.get('mu_mars', 42828.31)
    min_decay_km = metadata.get('min_decay_km', 200.0)
    a_initial = metadata.get('initial_sma_km', 13458.69)

    scores = {
        "script_created": 10,
        "mars_environment_used": 20,
        "report_format_correct": 10,
        "initial_apoapsis_correct": 10,
        "orbit_decay_verified": 20,
        "deltav_math_correct": 30,
    }

    total_score = 0
    feedback = []
    orbit_decay_ok = False
    deltav_math_ok = False

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

    # 2. Check Mars Environment
    script_path = task_result.get('script_path', '')
    if isinstance(script_file, dict) and script_file.get('exists') and script_path:
        temp_script = tempfile.NamedTemporaryFile(delete=False, suffix='.script')
        try:
            copy_from_env(script_path, temp_script.name)
            with open(temp_script.name, 'r', encoding='utf-8', errors='ignore') as f:
                script_content = f.read()

            mars_cb = 'CentralBody = Mars' in script_content or 'PrimaryBodies = {Mars}' in script_content
            mars_atm = 'AtmosphereModel = MarsExponential' in script_content or 'MarsExponential' in script_content
            deg_zero = 'Degree = 0' in script_content or 'Degree = 0;' in script_content
            ord_zero = 'Order = 0' in script_content or 'Order = 0;' in script_content

            if mars_cb and mars_atm and deg_zero and ord_zero:
                total_score += scores["mars_environment_used"]
                feedback.append("Mars Point Mass gravity and Exponential atmosphere configured.")
            elif mars_cb and mars_atm:
                total_score += scores["mars_environment_used"] // 2
                feedback.append("Mars body and atmosphere used, but Point Mass gravity not strict.")
            else:
                feedback.append("Mars environment / ForceModel incorrectly configured.")
        except Exception as e:
            feedback.append(f"Failed to parse script for environment checks: {e}")
        finally:
            if os.path.exists(temp_script.name):
                os.unlink(temp_script.name)

    # 3. Check values from results file
    try:
        ini_apo = float(task_result.get('initial_apoapsis', 0))
        fin_per = float(task_result.get('final_periapsis', 0))
        fin_apo = float(task_result.get('final_apoapsis', 0))
        dv_saved = float(task_result.get('deltav_saved', 0))
    except (ValueError, TypeError):
        ini_apo = 0; fin_per = 0; fin_apo = 0; dv_saved = 0

    results_file = task_result.get('results_file', {})
    if isinstance(results_file, dict) and results_file.get('exists'):
        if ini_apo > 0 and fin_per > 0 and fin_apo > 0 and dv_saved > 0:
            total_score += scores["report_format_correct"]
            feedback.append("Report format contains all 4 required fields.")
        else:
            feedback.append("Report missing some keys or values are 0.")

        # Check initial apoapsis
        if abs(ini_apo - expected_initial_apoapsis) < 1.0:
            total_score += scores["initial_apoapsis_correct"]
            feedback.append("Initial apoapsis correctly reported.")
        else:
            feedback.append(f"Initial apoapsis incorrect: {ini_apo} != {expected_initial_apoapsis}.")

        # Check orbit decay (Apoapsis must have dropped by at least min_decay_km)
        decay_amount = expected_initial_apoapsis - fin_apo
        if decay_amount >= min_decay_km and fin_apo > 0:
            total_score += scores["orbit_decay_verified"]
            orbit_decay_ok = True
            feedback.append(f"Orbit decay verified (apoapsis reduced by {decay_amount:.2f} km).")
        else:
            feedback.append(f"Insignificant or no orbit decay: only reduced by {decay_amount:.2f} km.")

        # Check Delta-V Math
        # Math is performed strictly on the agent's reported values to check their math logic
        if fin_per > 0 and fin_apo > 0:
            try:
                a_final = (fin_per + fin_apo) / 2.0
                v1_term = mu_mars * (2.0 / fin_per - 1.0 / a_initial)
                v2_term = mu_mars * (2.0 / fin_per - 1.0 / a_final)

                if v1_term > 0 and v2_term > 0:
                    v1 = math.sqrt(v1_term)
                    v2 = math.sqrt(v2_term)
                    expected_dv = (v1 - v2) * 1000.0  # Convert to m/s

                    if abs(dv_saved - expected_dv) <= 2.0:  # 2 m/s tolerance for rounding
                        total_score += scores["deltav_math_correct"]
                        deltav_math_ok = True
                        feedback.append(f"Delta-V math correct: {dv_saved:.2f} m/s matches expected {expected_dv:.2f} m/s based on final radii.")
                    else:
                        feedback.append(f"Delta-V math incorrect: Reported {dv_saved:.2f} m/s, but Vis-Viva yields {expected_dv:.2f} m/s.")
                else:
                    feedback.append("Math domain error: Final radii provided by agent are physically impossible for a closed orbit.")
            except Exception as e:
                feedback.append(f"Math check error: {e}")
        else:
            feedback.append("Cannot verify Delta-V: Final periapsis or apoapsis is missing or zero.")
    else:
        feedback.append("Results report file not found.")

    # Final pass conditions
    passed = (total_score >= 70) and orbit_decay_ok and deltav_math_ok

    return {
        "passed": passed,
        "score": total_score,
        "feedback": " | ".join(feedback)
    }