#!/usr/bin/env python3
"""
Verifier for mars_transfer_trajectory_design@1

Evaluates the agent's ability to set up an interplanetary transfer in GMAT.
Checks for presence of appropriate coordinate systems, propagators, 
differential correction loop, and verifies that the reported output parameters 
(C3, TMI delta-V, time of flight, Mars CA) are physically correct.
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_mars_transfer_trajectory_design(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    c3_min = metadata.get('c3_min', 6.0)
    c3_max = metadata.get('c3_max', 20.0)
    tmi_min = metadata.get('tmi_min_kms', 3.4)
    tmi_max = metadata.get('tmi_max_kms', 4.5)
    tof_min = metadata.get('tof_min_days', 180.0)
    tof_max = metadata.get('tof_max_days', 350.0)
    mars_ca_max = metadata.get('mars_ca_max_km', 500000.0)

    scores = {
        "script_created": 8,
        "sun_propagator": 12,
        "earth_propagator": 8,
        "spacecraft_defined": 7,
        "tmi_burn_defined": 10,
        "targeting_logic": 15,
        "mars_reference": 5,
        "results_written": 10,
        "c3_valid": 8,
        "tmi_deltav_valid": 8,
        "tof_valid": 5,
        "mars_ca_achieved": 4
    }

    total_score = 0
    feedback = []
    
    # Extract exported JSON
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

    # 1. Verification: Was the script actually created during the task?
    script_file = task_result.get('script_file', {})
    if isinstance(script_file, dict) and script_file.get('exists'):
        if script_file.get('created_during_task'):
            total_score += scores["script_created"]
            feedback.append("Script created during task window.")
        else:
            feedback.append("Script exists but was not created/modified during task.")
    else:
        feedback.append("Script not found.")

    # 2. Structural script verification via regex
    script_path = task_result.get('script_path', '/home/ga/GMAT_output/mars_transfer.script')
    targeting_logic_ok = False
    
    if isinstance(script_file, dict) and script_file.get('exists'):
        temp_script = tempfile.NamedTemporaryFile(delete=False, suffix='.script')
        try:
            copy_from_env(script_path, temp_script.name)
            with open(temp_script.name, 'r', encoding='utf-8', errors='ignore') as f:
                script_content = f.read()

            # Spacecraft check
            if "Create Spacecraft" in script_content:
                total_score += scores["spacecraft_defined"]
                feedback.append("Spacecraft defined.")
            else:
                feedback.append("Spacecraft definition missing.")

            # Sun propagator check
            if re.search(r'CentralBody\s*=\s*Sun', script_content, re.IGNORECASE) or \
               re.search(r'PrimaryBodies\s*=\s*\{[^}]*Sun[^}]*\}', script_content, re.IGNORECASE):
                total_score += scores["sun_propagator"]
                feedback.append("Sun-centered propagator found.")
            else:
                feedback.append("Sun-centered propagator missing.")

            # Earth propagator check
            if re.search(r'CentralBody\s*=\s*Earth', script_content, re.IGNORECASE):
                total_score += scores["earth_propagator"]
                feedback.append("Earth-centered propagator found.")
            else:
                feedback.append("Earth-centered propagator missing.")

            # TMI Burn Check
            if "Create ImpulsiveBurn" in script_content:
                total_score += scores["tmi_burn_defined"]
                feedback.append("ImpulsiveBurn defined for TMI.")
            else:
                feedback.append("ImpulsiveBurn missing.")

            # Differential Corrector Check
            if "Create DifferentialCorrector" in script_content and \
               "Target" in script_content and \
               "Vary" in script_content and \
               "Achieve" in script_content:
                total_score += scores["targeting_logic"]
                targeting_logic_ok = True
                feedback.append("DifferentialCorrector targeting logic found.")
            else:
                feedback.append("DifferentialCorrector targeting logic missing.")

            # Mars Reference
            if "Mars" in script_content:
                total_score += scores["mars_reference"]
                feedback.append("Mars referenced in script.")
            else:
                feedback.append("Mars reference missing.")
                
        except Exception as e:
            feedback.append(f"Error parsing script: {e}")
        finally:
            if os.path.exists(temp_script.name):
                os.unlink(temp_script.name)

    # 3. Analyze output numerical values
    results_file = task_result.get('results_file', {})
    if isinstance(results_file, dict) and results_file.get('exists'):
        total_score += scores["results_written"]
        feedback.append("Results file written.")
    else:
        feedback.append("Results file not found.")

    try:
        c3_val = float(task_result.get('c3_km2s2', 0))
    except (ValueError, TypeError):
        c3_val = 0.0

    try:
        tmi_val = float(task_result.get('tmi_deltav_kms', 0))
    except (ValueError, TypeError):
        tmi_val = 0.0

    try:
        tof_val = float(task_result.get('tof_days', 0))
    except (ValueError, TypeError):
        tof_val = 0.0

    try:
        mars_ca_val = float(task_result.get('mars_ca_km', 0))
    except (ValueError, TypeError):
        mars_ca_val = float('inf')

    # Value validations against expected orbital mechanics ranges
    c3_ok = False
    tmi_ok = False

    if c3_val > 0 and c3_min <= c3_val <= c3_max:
        total_score += scores["c3_valid"]
        c3_ok = True
        feedback.append(f"C3 valid: {c3_val} km^2/s^2.")
    elif c3_val > 0:
        feedback.append(f"C3 out of range: {c3_val} km^2/s^2.")

    if tmi_val > 0 and tmi_min <= tmi_val <= tmi_max:
        total_score += scores["tmi_deltav_valid"]
        tmi_ok = True
        feedback.append(f"TMI DeltaV valid: {tmi_val} km/s.")
    elif tmi_val > 0:
        feedback.append(f"TMI DeltaV out of range: {tmi_val} km/s.")

    if tof_val > 0 and tof_min <= tof_val <= tof_max:
        total_score += scores["tof_valid"]
        feedback.append(f"TOF valid: {tof_val} days.")
    elif tof_val > 0:
        feedback.append(f"TOF out of range: {tof_val} days.")

    if mars_ca_val > 0 and mars_ca_val <= mars_ca_max:
        total_score += scores["mars_ca_achieved"]
        feedback.append(f"Mars CA target achieved: {mars_ca_val} km.")
    elif mars_ca_val > 0 and mars_ca_val != float('inf'):
        feedback.append(f"Mars CA target missed: {mars_ca_val} km.")

    # Pass condition relies on properly executing Differential Correction targeting OR
    # calculating physically sound parameter estimates through Hohmann analysis
    key_criteria_met = targeting_logic_ok or (c3_ok and tmi_ok)
    passed = total_score >= 55 and key_criteria_met

    return {
        "passed": passed,
        "score": total_score,
        "feedback": " | ".join(feedback)
    }