#!/usr/bin/env python3
"""
Verifier for geo_station_relocation@1

The agent must design a longitude drift maneuver for a GEO satellite.
Eastward drift requires LOWERING the orbit to create a shorter period.

Scoring (Total 100 points, Pass >= 60):
  - script_created (10)
  - spacecraft_defined (10)
  - two_burns_defined (15)
  - drift_orbit_lower (15) - MOST CRITICAL PHYSICS CHECK
  - propagation_present (10)
  - results_written (10)
  - deltav_total_valid (10)
  - drift_time_valid (10)
  - vlm_verification (10) - Trajectory frames show GMAT usage

Pass Condition: score >= 60 AND two_burns_defined AND drift_orbit_lower
"""

import json
import os
import re
import tempfile
import logging

try:
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
    VLM_AVAILABLE = True
except ImportError:
    VLM_AVAILABLE = False

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_geo_station_relocation(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    geo_sma = metadata.get('geo_sma_km', 42164.17)
    drift_sma_min = metadata.get('drift_sma_min_km', 42000.0)
    drift_sma_max = metadata.get('drift_sma_max_km', 42160.0)
    dv_min = metadata.get('total_dv_min_mps', 2.0)
    dv_max = metadata.get('total_dv_max_mps', 20.0)
    time_min = metadata.get('drift_time_min_days', 15.0)
    time_max = metadata.get('drift_time_max_days', 45.0)

    total_score = 0
    feedback = []
    burns_ok = False
    drift_ok = False

    scores = {
        "script_created": 10,
        "spacecraft_defined": 10,
        "two_burns_defined": 15,
        "drift_orbit_lower": 15,
        "propagation_present": 10,
        "results_written": 10,
        "deltav_total_valid": 10,
        "drift_time_valid": 10,
        "vlm_verification": 10
    }

    # 1. Load exported result metadata
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

    # 2. Check Script Creation
    script_file = task_result.get('script_file', {})
    script_exists = script_file.get('exists', False)
    if script_exists and script_file.get('created_during_task', False):
        total_score += scores['script_created']
        feedback.append("Script file created during task.")
    elif script_exists:
        total_score += scores['script_created'] // 2
        feedback.append("Script found but timestamps could not be strictly verified.")
    else:
        feedback.append("No script file found.")

    script_path = task_result.get('script_path_actual', '')
    script_content = ""
    if script_exists and script_path:
        temp_script = tempfile.NamedTemporaryFile(delete=False, suffix='.script')
        try:
            copy_from_env(script_path, temp_script.name)
            with open(temp_script.name, 'r', encoding='utf-8', errors='ignore') as f:
                script_content = f.read()
            
            # 3. Check Spacecraft Definition
            if re.search(r'Create\s+Spacecraft', script_content) and re.search(r'SMA\s*=\s*4216[0-9]', script_content):
                total_score += scores['spacecraft_defined']
                feedback.append("Spacecraft configured at GEO altitude.")
            elif re.search(r'Create\s+Spacecraft', script_content):
                total_score += scores['spacecraft_defined'] // 2
                feedback.append("Spacecraft created but initial SMA may be incorrect.")

            # 4. Check Burns
            burns_found = len(re.findall(r'Create\s+ImpulsiveBurn', script_content))
            if burns_found >= 2:
                total_score += scores['two_burns_defined']
                burns_ok = True
                feedback.append(f"{burns_found} ImpulsiveBurns defined.")
            elif burns_found == 1:
                total_score += scores['two_burns_defined'] // 3
                feedback.append("Only 1 ImpulsiveBurn found. Need 2 for relocation.")

            # 5. Check Propagation
            prop_found = len(re.findall(r'Propagate\s+', script_content))
            if prop_found >= 2:
                total_score += scores['propagation_present']
                feedback.append("Multiple propagation phases found.")
            elif prop_found == 1:
                total_score += scores['propagation_present'] // 2
                feedback.append("Only 1 propagation phase found.")

        except Exception as e:
            logger.error(f"Error parsing script: {e}")
        finally:
            if os.path.exists(temp_script.name):
                os.unlink(temp_script.name)

    # 6. Parse Results File
    results_file = task_result.get('results_file', {})
    if results_file.get('exists', False):
        temp_txt = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        try:
            copy_from_env(results_file.get('path', ''), temp_txt.name)
            with open(temp_txt.name, 'r', encoding='utf-8', errors='ignore') as f:
                txt_content = f.read().lower()

            # Simple robust extraction of numbers using regex logic
            # E.g. "Total delta-V: 11.36 m/s", "drift sma: 42050 km"
            nums = re.findall(r'[-+]?\d*\.\d+|\d+', txt_content)
            floats = [float(n) for n in nums]

            # Find specific values near keywords
            def find_val_near(content, keywords):
                best_val = None
                for line in content.split('\n'):
                    if any(kw in line for kw in keywords):
                        # Get all numbers in this line
                        lnums = re.findall(r'[-+]?\d*\.\d+|\d+', line)
                        if lnums:
                            return float(lnums[-1]) # Usually the value is at the end
                return best_val

            drift_sma = find_val_near(txt_content, ['drift', 'sma', 'semi-major'])
            total_dv = find_val_near(txt_content, ['total', 'delta-v', 'deltav', 'dv'])
            drift_time = find_val_near(txt_content, ['duration', 'time', 'days'])
            
            # Assess Results Written
            if drift_sma and total_dv and drift_time:
                total_score += scores['results_written']
                feedback.append("Results report well-formatted with needed values.")
            elif len(floats) >= 3:
                total_score += scores['results_written'] // 2
                feedback.append("Results report exists but format requires guessing values.")
                
            # Physics Checks
            # Drift SMA MUST be lower than GEO (42164.17) for an eastward drift
            if drift_sma is not None and drift_sma_min <= drift_sma <= drift_sma_max:
                total_score += scores['drift_orbit_lower']
                drift_ok = True
                feedback.append(f"Physics Valid: Drift SMA ({drift_sma} km) is correctly lower than GEO for eastward drift.")
            elif drift_sma is not None:
                feedback.append(f"Physics Error: Drift SMA ({drift_sma} km) is not physically valid for this drift rate.")

            if total_dv is not None and dv_min <= total_dv <= dv_max:
                total_score += scores['deltav_total_valid']
                feedback.append(f"Total DeltaV ({total_dv} m/s) in correct bounds.")
            
            if drift_time is not None and time_min <= drift_time <= time_max:
                total_score += scores['drift_time_valid']
                feedback.append(f"Drift Time ({drift_time} days) in correct bounds.")

        except Exception as e:
            logger.error(f"Error parsing results text: {e}")
        finally:
            if os.path.exists(temp_txt.name):
                os.unlink(temp_txt.name)
    else:
        feedback.append("No results report file found.")

    # 7. VLM Verification of Trajectory
    if VLM_AVAILABLE and traj:
        try:
            frames = sample_trajectory_frames(traj, n=5)
            final = get_final_screenshot(traj)
            prompt = (
                "You are evaluating a spacecraft mission design agent using NASA GMAT. "
                "Look closely at these trajectory screenshots.\n"
                "1. Did the agent actively use the GMAT GUI interface (e.g. configuring Spacecraft, Burns, or Propagators)?\n"
                "2. Is there evidence that the mission was actually run (e.g. an orbital plot window, console output, or a message window)?\n"
                "Return JSON with 'used_gmat_gui' (boolean) and 'ran_simulation' (boolean)."
            )
            vlm_res = query_vlm(images=frames + [final], prompt=prompt)
            if vlm_res.get("success"):
                parsed = vlm_res.get("parsed", {})
                if parsed.get("used_gmat_gui", False) and parsed.get("ran_simulation", False):
                    total_score += scores["vlm_verification"]
                    feedback.append("VLM confirms agent used GMAT GUI and ran simulation.")
                elif parsed.get("used_gmat_gui", False):
                    total_score += scores["vlm_verification"] // 2
                    feedback.append("VLM confirms GMAT usage but unclear if simulated.")
            else:
                feedback.append("VLM evaluation failed to parse.")
        except Exception as e:
            logger.error(f"VLM verification error: {e}")
            feedback.append("VLM verification encountered an error.")
    else:
        # Give grace points if VLM is unavailable
        total_score += scores["vlm_verification"]
        feedback.append("VLM unavailable, awarding grace points for visual check.")

    # 8. Final Evaluation
    passed = total_score >= 60 and burns_ok and drift_ok

    if not passed:
        if not burns_ok:
            feedback.append("FAILED: Missing two ImpulsiveBurns.")
        if not drift_ok:
            feedback.append("FAILED: Did not correctly lower the drift orbit SMA for eastward drift.")

    return {
        "passed": passed,
        "score": total_score,
        "feedback": "\n".join(feedback)
    }