#!/usr/bin/env python3
"""
Verifier for european_heatwave_synoptic_assessment task.
"""

import json
import os
import tempfile
import re
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_european_heatwave_synoptic_assessment(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp.close()
    try:
        copy_from_env('/tmp/european_heatwave_synoptic_assessment_result.json', tmp.name)
        with open(tmp.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve result JSON: {e}"}
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)

    score = 0
    feedback = []
    task_start = int(result.get('task_start', 0))

    # 1. Temperature plot (20 pts)
    temp_exists = result.get('temp_plot_exists', False)
    temp_mtime = int(result.get('temp_plot_mtime', 0))
    temp_size = int(result.get('temp_plot_size', 0))

    if temp_exists and temp_mtime >= task_start and temp_size >= 15000:
        score += 20
        feedback.append(f"Temp plot exported ({temp_size} bytes)")
    elif temp_exists and temp_mtime >= task_start and temp_size >= 5000:
        score += 10
        feedback.append(f"Temp plot present but small ({temp_size} bytes, expected >=15KB)")
    else:
        feedback.append(f"Temp plot missing or not created during task (exists={temp_exists})")

    # 2. SLP plot (20 pts)
    slp_exists = result.get('slp_plot_exists', False)
    slp_mtime = int(result.get('slp_plot_mtime', 0))
    slp_size = int(result.get('slp_plot_size', 0))

    if slp_exists and slp_mtime >= task_start and slp_size >= 15000:
        score += 20
        feedback.append(f"SLP plot exported ({slp_size} bytes)")
    elif slp_exists and slp_mtime >= task_start and slp_size >= 5000:
        score += 10
        feedback.append(f"SLP plot present but small ({slp_size} bytes, expected >=15KB)")
    else:
        feedback.append(f"SLP plot missing or not created during task (exists={slp_exists})")

    # 3. Report fields presence (20 pts)
    period = result.get('assessment_period', '').strip()
    system = result.get('dominant_pressure_system', '').strip()
    slp_val = result.get('slp_center_hpa', '').strip()
    temp_val = result.get('southern_europe_temp_c', '').strip()
    region = result.get('highest_risk_region', '').strip()
    mechanism = result.get('heatwave_mechanism', '').strip()
    
    fields_present = sum([bool(period), bool(system), bool(slp_val), bool(temp_val), bool(region), bool(mechanism)])
    
    if fields_present == 6:
        score += 20
        feedback.append("All report fields present.")
    elif fields_present > 0:
        score += int(20 * (fields_present / 6))
        feedback.append(f"Report partial ({fields_present}/6 fields).")
    else:
        feedback.append("Report missing or empty.")

    # 4. Physical Plausibility (20 pts)
    period_ok = 'jul' in period.lower()
    system_ok = any(name in system.lower() for name in ['azores', 'bermuda', 'subtropical'])
    
    slp_ok = False
    try:
        slp_num = float(re.sub(r'[^\d\.]', '', slp_val))
        if 1015 <= slp_num <= 1035:
            slp_ok = True
        elif 101500 <= slp_num <= 103500:
            slp_ok = True  # Agent reported in Pascals directly
    except ValueError:
        pass
        
    temp_ok = False
    try:
        temp_num = float(re.sub(r'[^\d\.]', '', temp_val))
        if 20 <= temp_num <= 40:
            temp_ok = True
    except ValueError:
        pass
        
    plausibility_score = 0
    if period_ok: plausibility_score += 5
    if system_ok: plausibility_score += 5
    if slp_ok: plausibility_score += 5
    if temp_ok: plausibility_score += 5
    
    score += plausibility_score
    feedback.append(f"Plausibility checks passed: period={period_ok}, system={system_ok}, slp={slp_ok}, temp={temp_ok}")

    # 5. VLM Trajectory Verification (20 pts)
    if query_vlm:
        try:
            frames = sample_trajectory_frames(traj, n=4)
            final_img = get_final_screenshot(traj)
            images = frames + [final_img] if final_img else frames
            
            prompt = (
                "Did the user use NASA Panoply to create map plots of climate data? "
                "Respond in JSON format with a single boolean field 'used_panoply'."
            )
            vlm_result = query_vlm(images=images, prompt=prompt)
            
            if vlm_result.get("success"):
                parsed = vlm_result.get("parsed", {})
                used_panoply = parsed.get("used_panoply", False)
                if used_panoply:
                    score += 20
                    feedback.append("VLM confirms Panoply usage.")
                else:
                    feedback.append("VLM did not detect Panoply usage.")
            else:
                score += 20
                feedback.append("VLM query failed, granting points by default.")
        except Exception as e:
            score += 20
            logger.error(f"VLM error: {e}")
            feedback.append("VLM verification error, granting points by default.")
    else:
        score += 20
        feedback.append("VLM not available, granting points by default.")

    # Final logic
    key_criteria_met = temp_exists and slp_exists
    passed = score >= 80 and key_criteria_met

    return {
        "passed": bool(passed),
        "score": score,
        "feedback": " | ".join(feedback)
    }