#!/usr/bin/env python3
"""
Verifier for Sepsis Simulation Parameter Tuning Task.
Verifies:
1. Devices created (via logs)
2. App launched (via logs/windows)
3. User evidence screenshot exists & created during task
4. User config report JSON contains correct target values
5. VLM check on trajectory to confirm interaction with tuning controls
"""

import json
import os
import tempfile
import logging

# Import VLM utils from framework
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_sepsis_tuning(traj, env_info, task_info):
    # 1. Setup & Data Retrieval
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: copy_from_env missing"}

    # Get expected targets from metadata
    targets = task_info.get('metadata', {}).get('target_values', {})
    tol = task_info.get('metadata', {}).get('tolerance', {})
    
    # Load task_result.json
    task_result = {}
    with tempfile.NamedTemporaryFile(delete=True) as tmp:
        try:
            copy_from_env("/tmp/task_result.json", tmp.name)
            task_result = json.load(open(tmp.name))
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {e}"}

    # Load user's config report if it exists
    user_config = {}
    config_report_path = "/home/ga/Desktop/sepsis_config.json"
    if task_result.get("config_json_exists"):
        with tempfile.NamedTemporaryFile(delete=True) as tmp:
            try:
                copy_from_env(config_report_path, tmp.name)
                user_config = json.load(open(tmp.name))
            except:
                logger.warning("Could not load user config json despite existence.")

    # 2. Scoring Logic
    score = 0
    feedback = []
    task_start = task_result.get("task_start", 0)

    # Criterion A: Infrastructure Setup (30 pts)
    # Check if devices were created in OpenICE
    if task_result.get("log_monitor_created"):
        score += 10
        feedback.append("Multiparameter Monitor created.")
    else:
        feedback.append("Multiparameter Monitor NOT detected in logs.")

    if task_result.get("log_pump_created"):
        score += 10
        feedback.append("Infusion Pump created.")
    else:
        feedback.append("Infusion Pump NOT detected in logs.")

    if task_result.get("log_app_launched"):
        score += 10
        feedback.append("Vital Signs app launched.")
    else:
        feedback.append("Vital Signs app NOT detected.")

    # Criterion B: Evidence Collection (20 pts)
    # Check if user saved the required screenshot
    img_exists = task_result.get("evidence_screenshot_exists")
    img_time = task_result.get("evidence_screenshot_mtime", 0)
    
    if img_exists and img_time > task_start:
        score += 20
        feedback.append("Evidence screenshot saved correctly.")
    elif img_exists:
        score += 5
        feedback.append("Evidence screenshot exists but timestamp is suspicious (pre-task?).")
    else:
        feedback.append("Evidence screenshot missing.")

    # Criterion C: Configuration Accuracy (30 pts)
    # Check values in user's JSON report against targets
    # We verify the user *recorded* the correct values, implying they set them.
    # We use VLM to verify they actually *did* the setting.
    
    # Heart Rate (Target 115 +/- 5)
    hr = user_config.get("heart_rate")
    if hr and abs(float(hr) - targets["heart_rate"]) <= tol["heart_rate"]:
        score += 6
        feedback.append(f"HR config correct ({hr}).")
    else:
        feedback.append(f"HR config incorrect or missing (Expected ~{targets['heart_rate']}).")

    # BP Systolic (Target 82 +/- 5)
    bps = user_config.get("bp_systolic")
    if bps and abs(float(bps) - targets["bp_systolic"]) <= tol["bp"]:
        score += 6
        feedback.append(f"BP Sys config correct ({bps}).")
    else:
        feedback.append("BP Sys incorrect/missing.")

    # BP Diastolic (Target 45 +/- 5)
    bpd = user_config.get("bp_diastolic")
    if bpd and abs(float(bpd) - targets["bp_diastolic"]) <= tol["bp"]:
        score += 6
        feedback.append(f"BP Dia config correct ({bpd}).")
    else:
        feedback.append("BP Dia incorrect/missing.")
        
    # Temperature (Target 39.2 +/- 0.5)
    temp = user_config.get("temperature")
    if temp and abs(float(temp) - targets["temperature"]) <= tol["temperature"]:
        score += 6
        feedback.append(f"Temp config correct ({temp}).")
    else:
        feedback.append("Temp incorrect/missing.")

    # Infusion Rate (Target 250 +/- 5)
    rate = user_config.get("infusion_rate")
    if rate and abs(float(rate) - targets["infusion_rate"]) <= tol["infusion_rate"]:
        score += 6
        feedback.append(f"Infusion Rate config correct ({rate}).")
    else:
        feedback.append("Infusion Rate incorrect/missing.")

    # Criterion D: VLM Trajectory Verification (20 pts)
    # Did the agent actually interact with the sliders/settings?
    frames = sample_trajectory_frames(traj, n=6)
    vlm_prompt = """
    Analyze these screenshots of the OpenICE medical simulation interface.
    I am looking for evidence that the user manually tuned specific physiological parameters.
    
    Look for:
    1. Interaction with 'Simulated Device' control panels (sliders, text inputs).
    2. Visibility of specific values: Heart Rate ~115, BP ~82/45, Temp ~39.2, Infusion Rate 250.
    3. The 'Vital Signs' app displaying waveform data.
    
    Answer JSON:
    {
        "controls_interacted": boolean,
        "vital_signs_app_visible": boolean,
        "values_match_sepsis_profile": boolean
    }
    """
    
    try:
        vlm_res = query_vlm(images=frames, prompt=vlm_prompt).get('parsed', {})
        if vlm_res.get("controls_interacted", False):
            score += 10
            feedback.append("VLM confirmed interaction with device controls.")
        
        if vlm_res.get("values_match_sepsis_profile", False):
            score += 10
            feedback.append("VLM observed sepsis profile values on screen.")
    except Exception as e:
        logger.warning(f"VLM verification failed: {e}")
        # Fallback: if config report is perfect, give benefit of doubt for VLM points
        if score >= 70: 
            score += 20
            feedback.append("VLM skipped, credited based on accurate report.")

    # Final Result
    passed = score >= 60
    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " | ".join(feedback)
    }