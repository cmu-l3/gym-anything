#!/usr/bin/env python3
"""
Verifier for targeted_ocean_reentry_design@1

Agent must simulate a targeted deorbit maneuver placing the spacecraft at 80km altitude
over the South Pacific Ocean Uninhabited Area (SPOUA).

Scoring (total 100 pts, pass >= 70):
  - script_created (10): Script created during task window
  - maneuver_applied (15): Script contains ImpulsiveBurn command
  - interface_reached (15): Final altitude in trajectory is ~80 km
  - latitude_compliant (20): Final latitude falls in [-55, -35]
  - longitude_compliant (20): Final longitude falls in [220, 250] or [-140, -110]
  - deltav_realistic (10): Summary DeltaV in range [150, 250] m/s
  - summary_written (10): Summary file written with required fields

Pass condition: score >= 70 AND latitude_compliant AND longitude_compliant
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_targeted_ocean_reentry_design(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    target_alt = metadata.get('target_altitude_km', 80.0)
    alt_tol = metadata.get('altitude_tolerance_km', 1.0)
    lat_min = metadata.get('lat_min_deg', -55.0)
    lat_max = metadata.get('lat_max_deg', -35.0)
    lon_e_min = metadata.get('lon_east_min_deg', 220.0)
    lon_e_max = metadata.get('lon_east_max_deg', 250.0)
    lon_w_min = metadata.get('lon_west_min_deg', -140.0)
    lon_w_max = metadata.get('lon_west_max_deg', -110.0)
    dv_min = metadata.get('deltav_min_ms', 150.0)
    dv_max = metadata.get('deltav_max_ms', 250.0)

    scores = {
        "script_created": 10,
        "maneuver_applied": 15,
        "interface_reached": 15,
        "latitude_compliant": 20,
        "longitude_compliant": 20,
        "deltav_realistic": 10,
        "summary_written": 10,
    }

    total_score = 0
    feedback = []
    lat_ok = False
    lon_ok = False

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

    # 2. Check Script File
    script_file = task_result.get('script_file', {})
    if isinstance(script_file, dict) and script_file.get('created_during_task'):
        total_score += scores["script_created"]
        feedback.append("Script created during task window.")
    else:
        feedback.append("Script not created during task window.")

    script_path = task_result.get('script_path', '')
    if script_path and isinstance(script_file, dict) and script_file.get('exists'):
        temp_script = tempfile.NamedTemporaryFile(delete=False, suffix='.script')
        try:
            copy_from_env(script_path, temp_script.name)
            with open(temp_script.name, 'r', encoding='utf-8', errors='ignore') as f:
                script_content = f.read()

            if "ImpulsiveBurn" in script_content:
                total_score += scores["maneuver_applied"]
                feedback.append("ImpulsiveBurn applied in script.")
            else:
                feedback.append("No ImpulsiveBurn found in script.")
        except Exception:
            feedback.append("Could not parse script file.")
        finally:
            if os.path.exists(temp_script.name):
                os.unlink(temp_script.name)

    # 3. Process Summary File
    summary_path = task_result.get('summary_path', '')
    summary_file = task_result.get('summary_file', {})
    if summary_path and isinstance(summary_file, dict) and summary_file.get('exists'):
        total_score += scores["summary_written"]
        temp_summary = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        try:
            copy_from_env(summary_path, temp_summary.name)
            with open(temp_summary.name, 'r', encoding='utf-8', errors='ignore') as f:
                summary_content = f.read()

            dv_match = re.search(r'DeltaV_Magnitude_ms:\s*([0-9]+\.?[0-9]*)', summary_content)
            if dv_match:
                dv_val = float(dv_match.group(1))
                if dv_min <= dv_val <= dv_max:
                    total_score += scores["deltav_realistic"]
                    feedback.append(f"DeltaV is realistic: {dv_val} m/s.")
                else:
                    feedback.append(f"DeltaV unrealistic: {dv_val} m/s (expected {dv_min}-{dv_max}).")
            else:
                feedback.append("Could not extract DeltaV from summary.")
        except Exception:
            feedback.append("Could not read summary file.")
        finally:
            if os.path.exists(temp_summary.name):
                os.unlink(temp_summary.name)

    # 4. Process Trajectory File (The ultimate source of truth, generated directly by GMAT)
    traj_path = task_result.get('trajectory_path', '')
    traj_file = task_result.get('trajectory_file_rerun', task_result.get('trajectory_file', {}))
    
    if traj_path and isinstance(traj_file, dict) and traj_file.get('exists'):
        temp_traj = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        try:
            copy_from_env(traj_path, temp_traj.name)
            with open(temp_traj.name, 'r', encoding='utf-8', errors='ignore') as f:
                lines = f.readlines()

            # Find the last line containing numbers
            last_valid_line = None
            for line in reversed(lines):
                if re.search(r'\d', line):
                    last_valid_line = line.strip()
                    break

            if last_valid_line:
                # Expected format from spec: ElapsedDays Altitude Latitude Longitude
                parts = last_valid_line.split()
                if len(parts) >= 4:
                    try:
                        # GMAT outputs can have multiple spaces. Indexing backwards guarantees we get the payload.
                        altitude = float(parts[-3])
                        latitude = float(parts[-2])
                        longitude = float(parts[-1])
                        
                        # Interface altitude check
                        if abs(altitude - target_alt) <= alt_tol:
                            total_score += scores["interface_reached"]
                            feedback.append(f"Reentry interface reached: {altitude} km.")
                        else:
                            feedback.append(f"Reentry interface failed: {altitude} km (target {target_alt} km).")

                        # Latitude check
                        if lat_min <= latitude <= lat_max:
                            total_score += scores["latitude_compliant"]
                            lat_ok = True
                            feedback.append(f"Latitude compliant: {latitude} deg.")
                        else:
                            feedback.append(f"Latitude non-compliant: {latitude} deg (target {lat_min} to {lat_max}).")

                        # Longitude check (handle both East and West representations)
                        if (lon_e_min <= longitude <= lon_e_max) or (lon_w_min <= longitude <= lon_w_max):
                            total_score += scores["longitude_compliant"]
                            lon_ok = True
                            feedback.append(f"Longitude compliant: {longitude} deg.")
                        else:
                            feedback.append(f"Longitude non-compliant: {longitude} deg (target {lon_e_min} to {lon_e_max} or {lon_w_min} to {lon_w_max}).")
                            
                    except ValueError:
                        feedback.append(f"Failed to parse numerical values from trajectory line: {last_valid_line}")
                else:
                    feedback.append(f"Not enough columns in trajectory output: {last_valid_line}")
            else:
                feedback.append("Trajectory file was empty or contained no valid data.")

        except Exception as e:
            feedback.append(f"Could not read trajectory file: {str(e)}")
        finally:
            if os.path.exists(temp_traj.name):
                os.unlink(temp_traj.name)
    else:
        feedback.append("Trajectory report file not generated by GMAT.")

    # 5. VLM verification fallback (Check if workflow happened, to prevent pure API spoofing)
    try:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
        frames = sample_trajectory_frames(traj, n=3)
        final = get_final_screenshot(traj)
        images = frames + [final] if final else frames
        
        if images:
            prompt = "Examine these screenshots of an agent using NASA GMAT. Did the agent actively configure a spacecraft, apply maneuvers, or run a mission sequence? Answer yes or no."
            vlm_res = query_vlm(images=images, prompt=prompt)
            if vlm_res and "yes" in str(vlm_res).lower():
                feedback.append("VLM visual confirmation: Agent actively used GMAT interface.")
            else:
                feedback.append("VLM visual warning: GMAT usage not clearly visible in trajectory.")
    except Exception as e:
        logger.warning(f"VLM verification skipped or failed: {e}")

    # Determine Pass/Fail
    passed = (total_score >= 70) and lat_ok and lon_ok

    return {
        "passed": passed,
        "score": total_score,
        "feedback": " | ".join(feedback)
    }