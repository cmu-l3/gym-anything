#!/usr/bin/env python3
"""
Verifier for interstellar_probe_kinematics_forecast@1

Scoring (total 100 pts, pass >= 75):
  - script_structure_valid (15): Sun is set as CentralBody in the script
  - planetary_perturbations (10): Jupiter, Saturn, Uranus, Neptune present in PointMasses
  - v1_metrics_accurate (20): V1 distance and velocity inside physical tolerances
  - v2_metrics_accurate (20): V2 distance and velocity inside physical tolerances
  - nh_metrics_accurate (20): NH distance and velocity inside physical tolerances
  - logical_conclusions (15): Correctly identified the fastest and furthest probe

Pass condition: Score >= 75 AND at least two probes correctly propagated and metrics verified.
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_interstellar_probe_kinematics_forecast(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    v1_dist_min = metadata.get('v1_dist_min_au', 252.0)
    v1_dist_max = metadata.get('v1_dist_max_au', 255.0)
    v1_vel_min = metadata.get('v1_vel_min_kms', 16.8)
    v1_vel_max = metadata.get('v1_vel_max_kms', 17.1)

    v2_dist_min = metadata.get('v2_dist_min_au', 216.0)
    v2_dist_max = metadata.get('v2_dist_max_au', 219.0)
    v2_vel_min = metadata.get('v2_vel_min_kms', 15.1)
    v2_vel_max = metadata.get('v2_vel_max_kms', 15.4)

    nh_dist_min = metadata.get('nh_dist_min_au', 132.0)
    nh_dist_max = metadata.get('nh_dist_max_au', 136.0)
    nh_vel_min = metadata.get('nh_vel_min_kms', 13.6)
    nh_vel_max = metadata.get('nh_vel_max_kms', 14.0)
    
    scores = {
        "script_structure_valid": 15,
        "planetary_perturbations": 10,
        "v1_metrics_accurate": 20,
        "v2_metrics_accurate": 20,
        "nh_metrics_accurate": 20,
        "logical_conclusions": 15
    }
    
    total_score = 0
    feedback = []

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

    # 1. Inspect Script contents
    script_file = task_result.get('script_file', {})
    script_path = task_result.get('script_path', '/home/ga/Documents/missions/interstellar_forecast.script')
    
    if isinstance(script_file, dict) and script_file.get('exists'):
        temp_script = tempfile.NamedTemporaryFile(delete=False, suffix='.script')
        try:
            copy_from_env(script_path, temp_script.name)
            with open(temp_script.name, 'r', encoding='utf-8', errors='ignore') as f:
                script_content = f.read()

            # Check CentralBody is Sun
            if re.search(r'\.CentralBody\s*=\s*Sun', script_content):
                total_score += scores["script_structure_valid"]
                feedback.append("Sun correctly set as CentralBody.")
            else:
                feedback.append("Sun not set as CentralBody.")

            # Check PointMasses for giant planets
            point_masses_match = re.search(r'\.PointMasses\s*=\s*\{([^}]+)\}', script_content)
            if point_masses_match:
                masses_str = point_masses_match.group(1)
                if all(planet in masses_str for planet in ['Jupiter', 'Saturn', 'Uranus', 'Neptune']):
                    total_score += scores["planetary_perturbations"]
                    feedback.append("Giant planets included in point masses.")
                else:
                    feedback.append(f"Missing giant planets in point masses: {masses_str}")
            else:
                feedback.append("No PointMasses found or could not parse PointMasses.")

        except Exception as e:
            feedback.append(f"Error reading script: {e}")
        finally:
            if os.path.exists(temp_script.name):
                os.unlink(temp_script.name)
    else:
        feedback.append("Script file not found.")

    def get_float(val, default=0.0):
        try:
            return float(val)
        except (ValueError, TypeError):
            return default

    v1_dist = get_float(task_result.get("v1_dist", 0))
    v1_vel = get_float(task_result.get("v1_vel", 0))
    v2_dist = get_float(task_result.get("v2_dist", 0))
    v2_vel = get_float(task_result.get("v2_vel", 0))
    nh_dist = get_float(task_result.get("nh_dist", 0))
    nh_vel = get_float(task_result.get("nh_vel", 0))
    fastest = str(task_result.get("fastest_probe", "")).strip().upper()
    furthest = str(task_result.get("furthest_probe", "")).strip().upper()

    correct_probes = 0

    # Evaluate Voyager 1
    if v1_dist_min <= v1_dist <= v1_dist_max and v1_vel_min <= v1_vel <= v1_vel_max:
        total_score += scores["v1_metrics_accurate"]
        correct_probes += 1
        feedback.append(f"V1 distance ({v1_dist} AU) and velocity ({v1_vel} km/s) inside valid tolerances.")
    else:
        feedback.append(f"V1 metrics out of bounds (Dist: {v1_dist} AU, Vel: {v1_vel} km/s).")

    # Evaluate Voyager 2
    if v2_dist_min <= v2_dist <= v2_dist_max and v2_vel_min <= v2_vel <= v2_vel_max:
        total_score += scores["v2_metrics_accurate"]
        correct_probes += 1
        feedback.append(f"V2 distance ({v2_dist} AU) and velocity ({v2_vel} km/s) inside valid tolerances.")
    else:
        feedback.append(f"V2 metrics out of bounds (Dist: {v2_dist} AU, Vel: {v2_vel} km/s).")

    # Evaluate New Horizons
    if nh_dist_min <= nh_dist <= nh_dist_max and nh_vel_min <= nh_vel <= nh_vel_max:
        total_score += scores["nh_metrics_accurate"]
        correct_probes += 1
        feedback.append(f"NH distance ({nh_dist} AU) and velocity ({nh_vel} km/s) inside valid tolerances.")
    else:
        feedback.append(f"NH metrics out of bounds (Dist: {nh_dist} AU, Vel: {nh_vel} km/s).")

    # Logical conclusions
    logical_score = 0
    if fastest == "V1":
        logical_score += scores["logical_conclusions"] / 2
    if furthest == "V1":
        logical_score += scores["logical_conclusions"] / 2

    if logical_score > 0:
        total_score += int(logical_score)
        feedback.append(f"Logical conclusions partial/fully correct: fastest={fastest}, furthest={furthest}.")
    else:
        feedback.append(f"Logical conclusions incorrect (got fastest={fastest}, furthest={furthest}).")

    passed = total_score >= 75 and correct_probes >= 2

    return {
        "passed": passed,
        "score": total_score,
        "feedback": " | ".join(feedback)
    }