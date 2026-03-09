#!/usr/bin/env python3
"""
Verifier for Configure MySolar App task.

Criteria:
1. App config exists (15 pts)
2. Solar Power feed correctly assigned (20 pts)
3. House Power feed correctly assigned (20 pts)
4. Solar kWh feed correctly assigned (15 pts)
5. House kWh feed correctly assigned (15 pts)
6. VLM Verification (15 pts)
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_mysolar_app(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # 2. Extract Data
    config_exists = result.get('config_exists', False)
    config = result.get('config_json', {})
    if not isinstance(config, dict):
        # Handle case where config might be a string (double encoded)
        try:
            if config and isinstance(config, str):
                config = json.loads(config)
        except:
            config = {}

    ref = result.get('reference_feeds', {})
    
    # Map common MySolar config keys to what we expect
    # Keys can vary slightly by version: 'solar', 'use', 'solar_kwh', 'use_kwh'
    # or 'solar_power', 'house_power', etc.
    # We will check values against reference IDs.
    
    # Get assigned IDs from config (ensure they are strings for comparison)
    assigned_solar = str(config.get('solar', '') or config.get('solar_power', ''))
    assigned_use = str(config.get('use', '') or config.get('house_power', '') or config.get('use_power', ''))
    assigned_solar_kwh = str(config.get('solar_kwh', ''))
    assigned_use_kwh = str(config.get('use_kwh', '') or config.get('house_kwh', ''))

    # Reference IDs
    ref_solar = str(ref.get('solar_power', 'ref_solar_missing'))
    ref_use = str(ref.get('house_power', 'ref_use_missing'))
    ref_solar_kwh = str(ref.get('solar_kwh', 'ref_solar_kwh_missing'))
    ref_use_kwh = str(ref.get('house_kwh', 'ref_use_kwh_missing'))

    # 3. Scoring
    
    # Criterion 1: Config Exists
    if config_exists and config:
        score += 15
        feedback.append("MySolar configuration saved.")
    else:
        feedback.append("No MySolar configuration found.")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback)}

    # Criterion 2: Solar Power
    if assigned_solar == ref_solar:
        score += 20
        feedback.append("Solar Power feed assigned correctly.")
    else:
        feedback.append(f"Solar Power incorrect (Expected {ref_solar}, got '{assigned_solar}').")

    # Criterion 3: House Power
    if assigned_use == ref_use:
        score += 20
        feedback.append("House Power feed assigned correctly.")
    else:
        feedback.append(f"House Power incorrect (Expected {ref_use}, got '{assigned_use}').")

    # Criterion 4: Solar kWh
    if assigned_solar_kwh == ref_solar_kwh:
        score += 15
        feedback.append("Solar Energy (kWh) assigned correctly.")
    else:
        feedback.append(f"Solar Energy incorrect (Expected {ref_solar_kwh}, got '{assigned_solar_kwh}').")

    # Criterion 5: House kWh
    if assigned_use_kwh == ref_use_kwh:
        score += 15
        feedback.append("House Energy (kWh) assigned correctly.")
    else:
        feedback.append(f"House Energy incorrect (Expected {ref_use_kwh}, got '{assigned_use_kwh}').")

    # Criterion 6: VLM Verification (Trajectory)
    # Check if the final view shows graphs/data instead of "Configure" prompt
    frames = sample_trajectory_frames(traj, n=4)
    final_screen = get_final_screenshot(traj)
    
    vlm_score = 0
    try:
        response = query_vlm(
            images=[final_screen],
            prompt="Does this screenshot show a configured MySolar dashboard with visible data graphs (solar/house power)? Or does it show an empty configuration screen? Answer YES for configured dashboard, NO for unconfigured."
        )
        if response and response.get('parsed', {}).get('answer', '').lower() in ['yes', 'true']:
            vlm_score = 15
            feedback.append("VLM confirms dashboard is active.")
        else:
            feedback.append("VLM did not detect active dashboard.")
    except Exception as e:
        logger.warning(f"VLM check failed: {e}")
        # Fallback: if Programmatic score is high (>=70), give VLM points as benefit of doubt
        if score >= 70:
            vlm_score = 15
            feedback.append("VLM check skipped, assuming visual success based on config.")

    score += vlm_score

    # Final Pass/Fail
    passed = score >= 70 and (assigned_solar == ref_solar) and (assigned_use == ref_use)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }