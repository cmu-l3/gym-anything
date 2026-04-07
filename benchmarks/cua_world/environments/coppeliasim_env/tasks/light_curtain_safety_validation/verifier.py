#!/usr/bin/env python3
"""
Verifier for light_curtain_safety_validation task.

Uses multi-criteria verification including output files analysis and VLM trajectory analysis.
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

RESULT_PATH = "/tmp/light_curtain_result.json"

VLM_PROMPT = """You are verifying if a user successfully performed a robotics simulation task.
The task involves writing a Python script to control a robot arm and spawn sensors in CoppeliaSim.

Look at these screenshots from the user's session.
Determine:
1. Did the user use a text editor or IDE to write a Python script?
2. Did the user run a simulation in CoppeliaSim (does the robot arm appear to move or are sensors visible in the scene)?

Respond ONLY in JSON format:
{
    "wrote_script": true/false,
    "ran_simulation": true/false,
    "reasoning": "Brief explanation"
}
"""

def verify_light_curtain_safety(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    # Load result data
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    tmp.close()
    try:
        copy_from_env(RESULT_PATH, tmp.name)
        with open(tmp.name, "r") as f:
            result = json.load(f)
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found — export script did not complete."}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read result: {e}"}
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)

    score = 0
    feedback = []

    # 1. File existence and anti-gaming (15 points)
    csv_ok = result.get("csv_exists") and result.get("csv_is_new")
    json_ok = result.get("json_exists") and result.get("json_is_new")
    
    if csv_ok and json_ok:
        score += 15
        feedback.append("✅ Both CSV and JSON files created during task (+15)")
    elif csv_ok or json_ok:
        score += 7
        feedback.append("⚠️ Only one output file created properly (+7)")
    else:
        feedback.append("❌ Output files missing or stale")

    # 2. CSV Structure and Rows (20 points)
    row_count = int(result.get("csv_row_count", 0))
    analysis = result.get("csv_analysis", {})
    if isinstance(analysis, dict) and analysis.get("has_cols"):
        if row_count >= 5:
            score += 20
            feedback.append(f"✅ CSV has correct columns and {row_count} breach events (+20)")
        elif row_count > 0:
            score += 10
            feedback.append(f"⚠️ CSV has correct columns but only {row_count} breach events (+10)")
        else:
            feedback.append("❌ CSV has columns but 0 rows")
    else:
        feedback.append("❌ CSV is missing required columns (sim_time_s, sensor_z_m, sensor_index)")

    # 3. Z-Height & Dynamic Timestamping Plausibility (25 points)
    if isinstance(analysis, dict):
        unique_times = int(analysis.get("unique_times", 0))
        min_z = float(analysis.get("min_z", 0.0))
        max_z = float(analysis.get("max_z", 0.0))
        
        plausible_z = (0.05 <= min_z <= 0.85) and (0.05 <= max_z <= 0.85)
        dynamic_times = unique_times >= 2
        
        if plausible_z and dynamic_times:
            score += 25
            feedback.append(f"✅ Recorded data is physically plausible (Z in [{min_z:.2f}, {max_z:.2f}], {unique_times} unique timesteps) (+25)")
        elif plausible_z or dynamic_times:
            score += 12
            feedback.append("⚠️ Recorded data is partially plausible (check Z-heights and timesteps) (+12)")
        elif row_count > 0:
            feedback.append(f"❌ Recorded data is physically implausible (Z in [{min_z:.2f}, {max_z:.2f}])")

    # 4. JSON Summary Valid (20 points)
    json_fields = result.get("json_fields", {})
    if isinstance(json_fields, dict):
        has_fields = json_fields.get("has_fields", False)
        total_sensors = int(json_fields.get("total_sensors", 0))
        triggered = int(json_fields.get("sensors_triggered", 0))
        
        if has_fields and total_sensors == 15 and triggered > 0:
            score += 20
            feedback.append(f"✅ JSON summary valid: {total_sensors} sensors, {triggered} triggered (+20)")
        elif has_fields and total_sensors == 15:
            score += 10
            feedback.append("⚠️ JSON summary exists but 0 sensors triggered (+10)")
        elif has_fields:
            feedback.append(f"❌ JSON summary exists but incorrect total_sensors: {total_sensors} (expected 15)")
        else:
            feedback.append("❌ JSON summary is missing required fields")

    # 5. VLM Trajectory Verification (20 points)
    query_vlm = env_info.get("query_vlm")
    if query_vlm:
        try:
            frames = sample_trajectory_frames(traj, n=4)
            final_img = get_final_screenshot(traj)
            if final_img:
                frames.append(final_img)
                
            vlm_res = query_vlm(prompt=VLM_PROMPT, images=frames)
            vlm_parsed = vlm_res.get("parsed", {})
            
            wrote_script = vlm_parsed.get("wrote_script", False)
            ran_sim = vlm_parsed.get("ran_simulation", False)
            
            if wrote_script and ran_sim:
                score += 20
                feedback.append("✅ VLM confirmed script writing and simulation execution (+20)")
            elif wrote_script or ran_sim:
                score += 10
                feedback.append("⚠️ VLM partially confirmed agent activity (+10)")
            else:
                feedback.append("❌ VLM did not visually detect script execution or simulation")
        except Exception as e:
            logger.error(f"VLM verification failed: {e}")
            feedback.append(f"⚠️ VLM verification encountered an error: {e}")
            # Do not completely fail the task if purely VLM error, just grant partial credit
            score += 10 
    else:
        feedback.append("⚠️ VLM capability not available, granting partial credit for visual step (+10)")
        score += 10

    # Key criteria requirement
    key_criteria_met = (row_count >= 5) and (result.get("csv_is_new") == True)
    
    passed = (score >= 75) and key_criteria_met

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": "\n".join(feedback)
    }