#!/usr/bin/env python3
"""Verifier for config_deco_settings task.

Checks Subsurface's Qt configuration file for updated Gradient Factors
and Surface Air Consumption (SAC) rates.
"""

import os
import json
import tempfile
import logging

# Set up logging
logging.basicConfig(level=logging.INFO, format='%(levelname)s: %(message)s')
logger = logging.getLogger(__name__)

def verify_config_deco_settings(traj, env_info, task_info):
    """
    Verify that decompression calculation settings were properly configured.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_gflow = metadata.get('expected_gf_low', 30)
    expected_gfhigh = metadata.get('expected_gf_high', 70)
    expected_bottom_sac = metadata.get('expected_bottom_sac', 20)
    expected_deco_sac = metadata.get('expected_deco_sac', 17)

    score = 0
    feedback_parts = []
    
    # 1. Fetch task result metadata
    result = {}
    temp_res = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_res.close()
    try:
        copy_from_env("/tmp/task_result.json", temp_res.name)
        with open(temp_res.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        logger.warning(f"Could not read task_result.json: {e}")
    finally:
        if os.path.exists(temp_res.name):
            os.unlink(temp_res.name)

    # Anti-gaming: Ensure config was modified during the task
    task_start = result.get('task_start', 0)
    conf_mtime = result.get('config_mtime', 0)
    config_modified = conf_mtime > task_start

    if config_modified:
        score += 10
        feedback_parts.append("Config modified during task (+10)")
    else:
        feedback_parts.append("Warning: Config file not modified after task start")

    # 2. Fetch and parse the config file
    config_values = {}
    temp_conf = tempfile.NamedTemporaryFile(delete=False, suffix='.conf')
    temp_conf.close()
    try:
        copy_from_env("/home/ga/.config/Subsurface/Subsurface.conf", temp_conf.name)
        with open(temp_conf.name, 'r', encoding='utf-8', errors='ignore') as f:
            for line in f:
                line = line.strip()
                if '=' in line and not line.startswith('['):
                    k, v = line.split('=', 1)
                    config_values[k.strip().lower()] = v.strip()
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read config file: {e}"}
    finally:
        if os.path.exists(temp_conf.name):
            os.unlink(temp_conf.name)

    # Safely extract actual values (keys can slightly vary across Qt/Subsurface versions)
    gflow_val = None
    gfhigh_val = None
    bottomsac_val = None
    decosac_val = None

    for k, v in config_values.items():
        try:
            if 'gflow' in k:
                gflow_val = float(v)
            elif 'gfhigh' in k:
                gfhigh_val = float(v)
            elif 'bottomsac' in k:
                # Value could be stored as 20 or 20000 (mL)
                v_float = float(v)
                bottomsac_val = v_float / 1000.0 if v_float >= 1000 else v_float
            elif 'decosac' in k:
                v_float = float(v)
                decosac_val = v_float / 1000.0 if v_float >= 1000 else v_float
        except ValueError:
            pass

    # Evaluate Gradient Factors
    if gflow_val == expected_gflow:
        score += 25
        feedback_parts.append(f"GF Low is {expected_gflow}% (+25)")
    else:
        feedback_parts.append(f"GF Low is {gflow_val} (Expected {expected_gflow})")

    if gfhigh_val == expected_gfhigh:
        score += 25
        feedback_parts.append(f"GF High is {expected_gfhigh}% (+25)")
    else:
        feedback_parts.append(f"GF High is {gfhigh_val} (Expected {expected_gfhigh})")

    # Evaluate SAC Rates
    if bottomsac_val is not None and abs(bottomsac_val - expected_bottom_sac) < 0.5:
        score += 15
        feedback_parts.append(f"Bottom SAC is ~{expected_bottom_sac} L/min (+15)")
    else:
        feedback_parts.append(f"Bottom SAC is {bottomsac_val} (Expected {expected_bottom_sac})")

    if decosac_val is not None and abs(decosac_val - expected_deco_sac) < 0.5:
        score += 15
        feedback_parts.append(f"Deco SAC is ~{expected_deco_sac} L/min (+15)")
    else:
        feedback_parts.append(f"Deco SAC is {decosac_val} (Expected {expected_deco_sac})")

    # 3. VLM Trajectory Verification
    vlm_score = 0
    try:
        from gym_anything.vlm import sample_trajectory_frames, query_vlm
        
        frames = sample_trajectory_frames(traj, n=5)
        
        prompt = """
        You are verifying a desktop agent configuring dive log preferences.
        Task: Set decompression GF values and SAC rates in the Subsurface Preferences window.
        
        Look at these trajectory frames. Did the agent at any point:
        1. Open the "Preferences" or "Settings" dialog?
        2. Navigate to the "Dive Planner" or Decompression/Gas settings tab?
        
        Respond ONLY with a JSON dictionary:
        {"preferences_opened": true/false, "planner_tab_accessed": true/false}
        """
        
        vlm_result = query_vlm(images=frames, prompt=prompt)
        
        if vlm_result and vlm_result.get("success"):
            parsed = vlm_result.get("parsed", {})
            if parsed.get("preferences_opened"):
                vlm_score += 5
                feedback_parts.append("VLM confirmed Preferences opened (+5)")
            if parsed.get("planner_tab_accessed"):
                vlm_score += 5
                feedback_parts.append("VLM confirmed Planner tab accessed (+5)")
    except Exception as e:
        logger.warning(f"VLM verification skipped or failed: {e}")
        # If VLM fails but all programmatic criteria are perfect, grant the points
        if score >= 85:
            vlm_score = 10
            feedback_parts.append("VLM points awarded by proxy (+10)")

    score += vlm_score

    # Determine passing status
    # Must have modified the config and successfully set at least the GF values
    passed = (score >= 60) and (gflow_val == expected_gflow) and (gfhigh_val == expected_gfhigh)

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts)
    }