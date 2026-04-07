#!/usr/bin/env python3
"""
Verifier for jupiter_orbit_insertion_capture@1

Scoring (total 100 pts, pass >= 60):
  - script_created_and_jupiter (15): Script created during task and contains "Jupiter" configuration
  - targeting_logic (15): DifferentialCorrector used to target SMA
  - results_file_written (10): Results file exported with required variables
  - deltav_accurate (25): Delta-V mathematically correct (~833 m/s)
  - final_sma_accurate (10): SMA successfully targeted to ~9.85e6 km
  - eccentricity_accurate (10): Eccentricity matches physics ~0.992
  - vlm_process_verification (15): Trajectory images show agent actively setting up the deep space mission

Pass condition: score >= 60 AND deltav_accurate AND targeting_logic
"""

import json
import os
import re
import math
import tempfile
import logging

try:
    from gym_anything.vlm import sample_trajectory_frames, query_vlm, get_final_screenshot
    VLM_AVAILABLE = True
except ImportError:
    VLM_AVAILABLE = False

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_vlm(traj, env_info):
    """Uses VLM to verify the agent actually interacted with GMAT UI for this task."""
    if not VLM_AVAILABLE or not traj:
        return 0, "VLM not available or trajectory empty."
        
    query = env_info.get("query_vlm", query_vlm)
    frames = sample_trajectory_frames(traj, n=4)
    if not frames:
        return 0, "No trajectory frames found."
        
    prompt = """
    You are an AI auditor checking a user's work in the NASA GMAT software.
    The task is to design a Jupiter Orbit Insertion maneuver. 
    Review these trajectory screenshots taken while the agent was working.
    
    Check for ANY of these activities:
    1. Creating or modifying a "Jupiter" centralized coordinate system.
    2. Setting up a spacecraft with hyperbolic incoming elements.
    3. Working in the "DifferentialCorrector" or "Target" sequence.
    4. Modifying Propagator or ImpulsiveBurn settings.
    
    Did the agent actively work on setting up this deep space mission in the GMAT interface?
    Respond with JSON containing:
    {
      "actively_worked": true/false,
      "reasoning": "brief explanation"
    }
    """
    
    try:
        res = query(prompt=prompt, images=frames)
        parsed = res.get("parsed", {})
        if parsed.get("actively_worked"):
            return 15, "VLM confirmed agent actively set up the mission in GMAT UI."
        else:
            return 0, "VLM could not confirm active GMAT interaction for this mission."
    except Exception as e:
        logger.error(f"VLM verification failed: {e}")
        return 0, "VLM error during verification."


def verify_jupiter_orbit_insertion(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    expected_dv = metadata.get('expected_deltav_mps', 833.0)
    dv_tol = metadata.get('deltav_tolerance_mps', 25.0)
    
    expected_sma = metadata.get('target_sma_km', 9850000.0)
    sma_tol = metadata.get('sma_tolerance_km', 20000.0)
    
    expected_ecc = metadata.get('expected_eccentricity', 0.992)
    ecc_tol = metadata.get('eccentricity_tolerance', 0.007)

    scores = {
        "script_created_and_jupiter": 15,
        "targeting_logic": 15,
        "results_file_written": 10,
        "deltav_accurate": 25,
        "final_sma_accurate": 10,
        "eccentricity_accurate": 10,
    }

    total_score = 0
    feedback = []
    dv_ok = False
    targeting_ok = False

    # 1. Load exported result JSON
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

    # 2. Extract parsed values
    try:
        dv_val_raw = float(task_result.get('required_deltav_m_s', 0))
    except (ValueError, TypeError):
        dv_val_raw = 0.0

    try:
        sma_val = float(task_result.get('final_sma_km', 0))
    except (ValueError, TypeError):
        sma_val = 0.0

    try:
        ecc_val = float(task_result.get('final_eccentricity', 0))
    except (ValueError, TypeError):
        ecc_val = 0.0

    # 3. Assess Script Logic
    script_file = task_result.get('script_file', {})
    script_path = task_result.get('script_path', '')
    
    script_created = script_file.get('created_during_task', False)
    
    if script_created and script_file.get('exists'):
        temp_script = tempfile.NamedTemporaryFile(delete=False, suffix='.script')
        try:
            copy_from_env(script_path, temp_script.name)
            with open(temp_script.name, 'r', encoding='utf-8', errors='ignore') as f:
                script_content = f.read()

            # Check if Jupiter was used as central body
            if re.search(r'CentralBody\s*=\s*Jupiter', script_content) or re.search(r'Origin\s*=\s*Jupiter', script_content):
                total_score += scores["script_created_and_jupiter"]
                feedback.append("Script created during task window and configured for Jupiter.")
            else:
                total_score += scores["script_created_and_jupiter"] // 2
                feedback.append("Script created, but missing explicit Jupiter CentralBody configuration.")
                
            # Check Targeting Logic
            if ("Create DifferentialCorrector" in script_content and 
                "Target" in script_content and 
                "Vary" in script_content and 
                "Achieve" in script_content):
                total_score += scores["targeting_logic"]
                targeting_ok = True
                feedback.append("DifferentialCorrector targeting logic found in script.")
            else:
                feedback.append("Missing DifferentialCorrector / Target sequence logic.")

        except Exception as e:
            logger.warning(f"Error parsing script file: {e}")
        finally:
            if os.path.exists(temp_script.name):
                os.unlink(temp_script.name)
    else:
        feedback.append("Script not created during task or missing.")

    # 4. Assess Results File
    results_file = task_result.get('results_file', {})
    if results_file.get('created_during_task', False) and results_file.get('exists', False):
        total_score += scores["results_file_written"]
        feedback.append("Results file written during task window.")
    else:
        feedback.append("Results file not written during task window or missing.")

    # Handle agent outputting km/s instead of m/s just in case
    # ~833 m/s vs 0.833 km/s
    dv_val = abs(dv_val_raw)
    if 0.1 < dv_val < 10.0:
        dv_val *= 1000.0  # Assumed they provided km/s

    # 5. Check Physics Values
    if abs(dv_val - expected_dv) <= dv_tol:
        total_score += scores["deltav_accurate"]
        dv_ok = True
        feedback.append(f"Delta-V mathematically correct: {dv_val_raw} (Expected ~{expected_dv} m/s).")
    else:
        feedback.append(f"Delta-V incorrect: {dv_val_raw} (Expected ~{expected_dv} m/s).")

    if abs(sma_val - expected_sma) <= sma_tol:
        total_score += scores["final_sma_accurate"]
        feedback.append(f"Final SMA targeted correctly: {sma_val} km.")
    else:
        feedback.append(f"Final SMA out of tolerance: {sma_val} km (Expected ~{expected_sma} km).")

    if abs(ecc_val - expected_ecc) <= ecc_tol:
        total_score += scores["eccentricity_accurate"]
        feedback.append(f"Final Eccentricity matches physics: {ecc_val}.")
    else:
        feedback.append(f"Final Eccentricity out of tolerance: {ecc_val} (Expected ~{expected_ecc}).")

    # 6. VLM Verification
    vlm_score, vlm_feed = verify_vlm(traj, env_info)
    total_score += vlm_score
    feedback.append(vlm_feed)

    # 7. Final Determination
    key_criteria_met = dv_ok and targeting_ok
    passed = total_score >= 60 and key_criteria_met

    return {
        "passed": passed,
        "score": total_score,
        "feedback": " | ".join(feedback),
        "details": {
            "required_deltav_m_s": dv_val_raw,
            "final_sma_km": sma_val,
            "final_ecc": ecc_val,
            "dv_ok": dv_ok,
            "targeting_ok": targeting_ok
        }
    }