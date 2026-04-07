#!/usr/bin/env python3
"""
Verifier for lunar_orbit_insertion_design@1

Evaluates if the agent properly modeled an Earth-to-Moon transfer with
multi-body dynamics and DifferentialCorrector targeting.

Scoring (total 100 pts, pass >= 60):
  - script_created (5): GMAT script saved and modified during task
  - parking_orbit_correct (10): Initial LEO orbit matches spec
  - multi_body_propagator (15): Luna/Moon included in force model
  - tli_burn_defined (10): First ImpulsiveBurn defined
  - loi_burn_defined (10): Second ImpulsiveBurn defined
  - targeting_logic (15): Target/Optimize block present
  - results_written (10): Output report has required fields
  - tli_deltav_valid (10): TLI ΔV within [2800, 3500] m/s
  - loi_deltav_valid (10): LOI ΔV within [500, 1200] m/s
  - transfer_time_valid (5): Coast time within [2.0, 7.0] days

Pass condition: score >= 60 AND multi_body_propagator AND (tli_burn_defined OR loi_burn_defined)
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_lunar_orbit_insertion_design(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    leo_sma_target = metadata.get('leo_sma_km', 6556.14)
    leo_inc_target = metadata.get('leo_inc_deg', 28.5)
    
    tli_min = metadata.get('tli_dv_min_mps', 2800.0)
    tli_max = metadata.get('tli_dv_max_mps', 3500.0)
    loi_min = metadata.get('loi_dv_min_mps', 500.0)
    loi_max = metadata.get('loi_dv_max_mps', 1200.0)
    total_min = metadata.get('total_dv_min_mps', 3500.0)
    total_max = metadata.get('total_dv_max_mps', 4500.0)
    time_min = metadata.get('transfer_time_min_days', 2.0)
    time_max = metadata.get('transfer_time_max_days', 7.0)
    alt_min = metadata.get('final_lunar_alt_min_km', 50.0)
    alt_max = metadata.get('final_lunar_alt_max_km', 200.0)

    scores = {
        "script_created": 5,
        "parking_orbit_correct": 10,
        "multi_body_propagator": 15,
        "tli_burn_defined": 10,
        "loi_burn_defined": 10,
        "targeting_logic": 15,
        "results_written": 10,
        "tli_deltav_valid": 10,
        "loi_deltav_valid": 10,
        "transfer_time_valid": 5,
    }

    total_score = 0
    feedback = []
    
    multi_body_ok = False
    burns_ok = False

    # 1. Load exported results JSON
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

    # 2. Check Script File Status
    script_file = task_result.get('script_file', {})
    if script_file.get('exists') and script_file.get('created_during_task'):
        total_score += scores["script_created"]
        feedback.append("GMAT script saved and updated during task.")
    else:
        feedback.append("Script not found or not modified during task.")

    # 3. Analyze Script Content via RegEx
    script_path = task_result.get('script_path', '')
    script_content = ""
    
    if script_file.get('exists') and script_path:
        temp_script = tempfile.NamedTemporaryFile(delete=False, suffix='.script')
        try:
            copy_from_env(script_path, temp_script.name)
            with open(temp_script.name, 'r', encoding='utf-8', errors='ignore') as f:
                script_content = f.read()

            # Parking Orbit Checks
            # Looking for SMA around 6556 and INC around 28.5
            has_sma = bool(re.search(r'SMA\s*=\s*6556(\.[0-9]+)?', script_content))
            has_inc = bool(re.search(r'INC\s*=\s*28\.5', script_content))
            if has_sma and has_inc:
                total_score += scores["parking_orbit_correct"]
                feedback.append("LEO parking orbit configured correctly (SMA and INC).")
            elif has_sma or has_inc:
                total_score += scores["parking_orbit_correct"] // 2
                feedback.append("LEO parking orbit partially configured.")
            else:
                feedback.append("LEO parking orbit parameters not matched.")

            # Multi-body propagator check
            # GMAT uses "Luna" by default, but "Moon" is also acceptable if custom body
            if re.search(r'(PointMasses|PrimaryBodies)\s*=\s*\{[^}]*(Luna|Moon)[^}]*\}', script_content):
                total_score += scores["multi_body_propagator"]
                multi_body_ok = True
                feedback.append("Multi-body dynamics (Earth+Moon) configured.")
            else:
                feedback.append("Luna/Moon missing from ForceModel PointMasses.")

            # Burns check
            burns = len(re.findall(r'Create\s+ImpulsiveBurn', script_content))
            if burns >= 2:
                total_score += scores["tli_burn_defined"] + scores["loi_burn_defined"]
                burns_ok = True
                feedback.append("Multiple ImpulsiveBurns defined (TLI and LOI).")
            elif burns == 1:
                total_score += scores["tli_burn_defined"]
                burns_ok = True
                feedback.append("Only one ImpulsiveBurn defined.")
            else:
                feedback.append("No ImpulsiveBurns defined in the script.")

            # Targeting Logic Check
            if (("Create DifferentialCorrector" in script_content or "Create FminconOptimizer" in script_content) and
                ("Target" in script_content or "Optimize" in script_content)):
                total_score += scores["targeting_logic"]
                feedback.append("Targeting sequence (DifferentialCorrector/Optimizer) found.")
            else:
                feedback.append("Targeting logic missing from script.")

        except Exception as e:
            logger.error(f"Error reading script file: {e}")
            feedback.append("Error parsing the GMAT script.")
        finally:
            if os.path.exists(temp_script.name):
                os.unlink(temp_script.name)

    # 4. Check Results Report
    results_file = task_result.get('results_file', {})
    if results_file.get('exists') and results_file.get('created_during_task'):
        total_score += scores["results_written"]
        feedback.append("Results report generated.")
    else:
        feedback.append("Results report not written.")

    # 5. Validate Output Values
    try:
        tli_val = abs(float(task_result.get('tli_dv_mps', 0)))
        loi_val = abs(float(task_result.get('loi_dv_mps', 0)))
        total_val = abs(float(task_result.get('total_dv_mps', 0)))
        time_val = abs(float(task_result.get('transfer_time_days', 0)))
        alt_val = abs(float(task_result.get('final_lunar_alt_km', 0)))
        
        # Checking TLI Delta-V
        if tli_min <= tli_val <= tli_max:
            total_score += scores["tli_deltav_valid"]
            feedback.append(f"TLI Delta-V valid: {tli_val} m/s.")
        elif tli_val > 0:
            feedback.append(f"TLI Delta-V out of bounds: {tli_val} m/s (Expected {tli_min}-{tli_max}).")
            
        # Checking LOI Delta-V
        if loi_min <= loi_val <= loi_max:
            total_score += scores["loi_deltav_valid"]
            feedback.append(f"LOI Delta-V valid: {loi_val} m/s.")
        elif loi_val > 0:
            feedback.append(f"LOI Delta-V out of bounds: {loi_val} m/s (Expected {loi_min}-{loi_max}).")

        # Checking Transfer Time
        if time_min <= time_val <= time_max:
            total_score += scores["transfer_time_valid"]
            feedback.append(f"Transfer time valid: {time_val} days.")
        elif time_val > 0:
            feedback.append(f"Transfer time out of bounds: {time_val} days.")
            
    except (ValueError, TypeError) as e:
        feedback.append("Could not parse physical values from results report.")

    # Determine Pass/Fail
    passed = (total_score >= 60) and multi_body_ok and burns_ok

    return {
        "passed": passed,
        "score": total_score,
        "feedback": " | ".join(feedback),
        "details": {
            "multi_body_ok": multi_body_ok,
            "burns_ok": burns_ok,
            "tli_reported": tli_val,
            "loi_reported": loi_val
        }
    }