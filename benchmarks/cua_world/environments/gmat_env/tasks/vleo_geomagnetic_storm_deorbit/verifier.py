#!/usr/bin/env python3
"""
Verifier for vleo_geomagnetic_storm_deorbit@1
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_vleo_geomagnetic_storm_deorbit(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    
    scores = {
        "script_created": 10,
        "report_created": 10,
        "physics_ordering": 30,
        "nominal_valid": 20,
        "storm_valid": 20,
        "altitudes_valid": 10
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

    # Get values from result
    try:
        nom_days = float(task_result.get('nominal_survival_days', -1))
    except (ValueError, TypeError):
        nom_days = -1.0
        
    try:
        storm_days = float(task_result.get('storm_survival_days', -1))
    except (ValueError, TypeError):
        storm_days = -1.0
        
    try:
        nom_alt = float(task_result.get('nominal_final_alt_km', -1))
    except (ValueError, TypeError):
        nom_alt = -1.0
        
    try:
        storm_alt = float(task_result.get('storm_final_alt_km', -1))
    except (ValueError, TypeError):
        storm_alt = -1.0

    physics_ordering_met = False

    # 3. Physics ordering (storm decay faster than nominal)
    if nom_days > 0 and storm_days > 0 and storm_days < nom_days:
        total_score += scores["physics_ordering"]
        physics_ordering_met = True
        feedback.append(f"Physics ordering correct: storm decay ({storm_days} days) faster than nominal ({nom_days} days).")
    else:
        feedback.append(f"Physics ordering incorrect or missing values (storm={storm_days}, nom={nom_days}).")

    # 4. Nominal valid
    nom_min = metadata.get('nominal_survival_min', 4.0)
    nom_max = metadata.get('nominal_survival_max', 12.0)
    if nom_min <= nom_days <= nom_max:
        total_score += scores["nominal_valid"]
        feedback.append(f"Nominal survival time valid ({nom_days} days).")
    elif nom_days > 0:
        feedback.append(f"Nominal survival time out of expected range ({nom_days} days).")

    # 5. Storm valid
    storm_min = metadata.get('storm_survival_min', 1.0)
    storm_max = metadata.get('storm_survival_max', 4.0)
    if storm_min <= storm_days <= storm_max:
        total_score += scores["storm_valid"]
        feedback.append(f"Storm survival time valid ({storm_days} days).")
    elif storm_days > 0:
        feedback.append(f"Storm survival time out of expected range ({storm_days} days).")

    # 6. Altitudes valid
    alt_min = metadata.get('alt_min', 115.0)
    alt_max = metadata.get('alt_max', 122.0)
    if alt_min <= nom_alt <= alt_max and alt_min <= storm_alt <= alt_max:
        total_score += scores["altitudes_valid"]
        feedback.append(f"Final altitudes valid (nom={nom_alt} km, storm={storm_alt} km).")
    elif nom_alt > 0 or storm_alt > 0:
        feedback.append(f"Final altitudes out of range (nom={nom_alt} km, storm={storm_alt} km, expected {alt_min}-{alt_max} km).")

    # Also check if script uses JacchiaRoberts and appropriate commands
    script_path = task_result.get('script_path', '/home/ga/GMAT_output/storm_decay_simulation.script')
    if isinstance(script_file, dict) and script_file.get('exists'):
        temp_script = tempfile.NamedTemporaryFile(delete=False, suffix='.script')
        try:
            copy_from_env(script_path, temp_script.name)
            with open(temp_script.name, 'r', encoding='utf-8', errors='ignore') as f:
                script_content = f.read()

            if "JacchiaRoberts" not in script_content:
                feedback.append("WARNING: JacchiaRoberts model not found in script.")
            if "Altitude" not in script_content and "120" not in script_content:
                feedback.append("WARNING: Stopping condition (Altitude < 120) not apparent in script.")
        except Exception as e:
            logger.warning(f"Could not read script content: {e}")
        finally:
            if os.path.exists(temp_script.name):
                os.unlink(temp_script.name)

    passed = (total_score >= 70) and physics_ordering_met

    return {
        "passed": passed,
        "score": total_score,
        "feedback": " | ".join(feedback)
    }