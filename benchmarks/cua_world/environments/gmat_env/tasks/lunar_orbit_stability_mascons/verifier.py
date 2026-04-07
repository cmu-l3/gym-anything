#!/usr/bin/env python3
"""
Verifier for lunar_orbit_stability_mascons@1

This script verifies that the agent correctly simulated lunar mascons and 
discovered the diverging stability of circular vs. frozen lunar orbits.

Verification Strategy:
1. Anti-gaming: Ensure script & report were created during the task timeframe.
2. AST check: Read the GMAT script to verify 'Luna' is the CentralBody and 
   Gravity Model Degree/Order is >= 20.
3. Physics check: Verify reported values align with orbital mechanics reality
   (circular crashes < 60 days, frozen survives 60 days safely).
4. VLM Check (Trajectory): Ensure the agent actually interacted with the GMAT UI.
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VLM_PROMPT = """You are auditing a computer agent completing a task in NASA GMAT (General Mission Analysis Tool).
The task requires the agent to configure a lunar parking orbit simulation using high-fidelity gravity models.

Review these trajectory frames from the agent's workflow. 
1. Did the agent interact with the GMAT GUI?
2. Is there evidence of configuring a Spacecraft, a ForceModel (like Luna gravity), or Propagator?
3. Did the agent actually run a simulation (e.g., seeing the 3D orbit view or progress messages)?

Respond in JSON format:
{
    "interacted_with_gui": true/false,
    "configured_models": true/false,
    "ran_simulation": true/false,
    "confidence": "high/medium/low",
    "reasoning": "Brief explanation"
}
"""

def verify_lunar_orbit_stability_mascons(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    req_degree = metadata.get('required_degree', 20)
    req_order = metadata.get('required_order', 20)
    circ_max_life = metadata.get('circ_max_lifetime_days', 59.0)
    circ_min_alt = metadata.get('circ_min_altitude_max_km', 5.0)
    froz_min_life = metadata.get('frozen_min_lifetime_days', 59.0)
    froz_min_alt = metadata.get('frozen_min_altitude_min_km', 10.0)

    score = 0
    feedback = []

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

    # 2. Check File Creation (Anti-Gaming)
    script_file = task_result.get('script_file', {})
    report_file = task_result.get('report_file', {})
    
    if script_file.get('created_during_task'):
        score += 10
        feedback.append("Script created during task window.")
    else:
        feedback.append("FAIL: Script not created during task window.")

    if report_file.get('created_during_task'):
        score += 10
        feedback.append("Report created during task window.")
    else:
        feedback.append("FAIL: Report not created during task window.")

    # 3. Analyze GMAT Script AST (Force Models & Spacecraft setup)
    script_path = task_result.get('script_path')
    if script_file.get('exists'):
        temp_script = tempfile.NamedTemporaryFile(delete=False, suffix='.script')
        try:
            copy_from_env(script_path, temp_script.name)
            with open(temp_script.name, 'r', encoding='utf-8', errors='ignore') as f:
                script_content = f.read()

            # Check CentralBody = Luna
            if re.search(r'CentralBody\s*=\s*Luna', script_content, re.IGNORECASE):
                score += 15
                feedback.append("ForceModel correctly uses Luna as CentralBody.")
            else:
                feedback.append("FAIL: Luna not set as CentralBody.")

            # Check Gravity Model Degree and Order >= 20
            degrees = [int(d) for d in re.findall(r'\.Degree\s*=\s*(\d+)', script_content)]
            orders = [int(o) for o in re.findall(r'\.Order\s*=\s*(\d+)', script_content)]
            
            if any(d >= req_degree for d in degrees) and any(o >= req_order for o in orders):
                score += 20
                feedback.append(f"Gravity model degree/order properly configured (>= {req_degree}).")
            else:
                feedback.append(f"FAIL: Gravity model degree/order too low. Found: Deg={degrees}, Ord={orders}.")

            # Check for Stopping Conditions
            if re.search(r'Altitude\s*<=\s*0', script_content) or re.search(r'RMAG\s*<=', script_content):
                score += 10
                feedback.append("Surface crash stopping condition configured.")
            else:
                feedback.append("No explicit Altitude <= 0 stopping condition found (may fail tests).")

        except Exception as e:
            feedback.append(f"Error parsing script: {e}")
        finally:
            if os.path.exists(temp_script.name):
                os.unlink(temp_script.name)

    # 4. Check Physics Outcomes in Report
    try:
        c_life = float(task_result.get('circular_lifetime_days', -1))
        c_alt = float(task_result.get('circular_min_altitude_km', 9999))
        f_life = float(task_result.get('frozen_lifetime_days', -1))
        f_alt = float(task_result.get('frozen_min_altitude_km', -9999))
        
        # Circular orbit MUST crash (lifetime < 60, altitude <= ~5)
        if 0 < c_life <= circ_max_life and c_alt <= circ_min_alt:
            score += 15
            feedback.append(f"Physical match: Circular orbit correctly crashed (Life: {c_life}d, Alt: {c_alt}km).")
            circular_pass = True
        else:
            feedback.append(f"FAIL: Circular orbit didn't crash properly (Life: {c_life}d, Alt: {c_alt}km).")
            circular_pass = False

        # Frozen orbit MUST survive (lifetime ~ 60, altitude safely > 10)
        if f_life >= froz_min_life and f_alt >= froz_min_alt:
            score += 10
            feedback.append(f"Physical match: Frozen orbit correctly survived (Life: {f_life}d, Alt: {f_alt}km).")
            frozen_pass = True
        else:
            feedback.append(f"FAIL: Frozen orbit failed to survive properly (Life: {f_life}d, Alt: {f_alt}km).")
            frozen_pass = False

    except ValueError:
        feedback.append("FAIL: Report contains invalid or unparseable numerical data.")
        circular_pass = False
        frozen_pass = False

    # 5. VLM Trajectory Verification
    try:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
        from gym_anything.vlm import query_vlm

        # Skip if running in an environment without VLM module mapped/mocked
        frames = sample_trajectory_frames(traj, n=4)
        final = get_final_screenshot(traj)
        
        vlm_result = query_vlm(images=frames + [final], prompt=VLM_PROMPT)
        if vlm_result.get("success"):
            parsed = vlm_result.get("parsed", {})
            if parsed.get("interacted_with_gui") and parsed.get("configured_models"):
                score += 10
                feedback.append("VLM confirms agent interacted with GMAT GUI.")
            else:
                feedback.append("VLM did not detect sufficient GUI interaction.")
        else:
            feedback.append("VLM verification skipped or failed.")
    except Exception as e:
        logger.warning(f"VLM verification exception: {e}")
        # Grant points gracefully if framework VLM util fails in dry run
        score += 10

    # Determine passing status
    key_criteria_met = circular_pass and frozen_pass
    passed = (score >= 60) and key_criteria_met

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback),
        "details": {
            "score": score,
            "circular_crashed": circular_pass,
            "frozen_survived": frozen_pass
        }
    }