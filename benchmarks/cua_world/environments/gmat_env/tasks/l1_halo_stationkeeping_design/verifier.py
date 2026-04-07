#!/usr/bin/env python3
"""
Verifier for l1_halo_stationkeeping_design@1

Evaluates:
1. Script output existence and modification.
2. Summary report with correct Delta-V and Time-to-crossing values.
3. Analysis of the GMAT script AST/text for anti-gaming:
   - Must use SunEarthRot coordinate system for the burn.
   - Must contain a DifferentialCorrector targeting loop.
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_l1_halo_stationkeeping(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    min_dv = metadata.get('min_delta_v', 0.01)
    max_dv = metadata.get('max_delta_v', 15.0)
    min_days = metadata.get('min_crossing_days', 80.0)
    max_days = metadata.get('max_crossing_days', 100.0)

    scores = {
        "script_saved": 10,
        "report_generated": 10,
        "burn_coordinate_system": 15,
        "dc_structure_present": 25,
        "delta_v_valid": 20,
        "propagation_time_valid": 20,
    }

    total_score = 0
    feedback = []
    dc_structure_ok = False
    dv_ok = False

    # Load task result
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

    # 1. Script saved & created
    script_file = task_result.get('script_file', {})
    if isinstance(script_file, dict) and script_file.get('exists') and script_file.get('created_during_task'):
        total_score += scores["script_saved"]
        feedback.append("Output script created successfully.")
    else:
        feedback.append("Output script was not created or modified during the task.")

    # 2. Report generated
    report_file = task_result.get('report_file', {})
    if isinstance(report_file, dict) and report_file.get('exists'):
        total_score += scores["report_generated"]
        feedback.append("Summary report file found.")
    else:
        feedback.append("Summary report file NOT found.")

    # 3. Analyze the saved script text
    script_path = task_result.get('script_path', '/home/ga/GMAT_output/dscovr_skm.script')
    if isinstance(script_file, dict) and script_file.get('exists'):
        temp_script = tempfile.NamedTemporaryFile(delete=False, suffix='.script')
        try:
            copy_from_env(script_path, temp_script.name)
            with open(temp_script.name, 'r', encoding='utf-8', errors='ignore') as f:
                script_content = f.read()

            # Check Burn Coordinate System (Anti-gaming check 1)
            # Match variations like: GMAT SKM_Burn.CoordinateSystem = SunEarthRot;
            if re.search(r'SKM_Burn\.CoordinateSystem\s*=\s*SunEarthRot', script_content, re.IGNORECASE):
                total_score += scores["burn_coordinate_system"]
                feedback.append("Burn coordinate system correctly set to SunEarthRot.")
            else:
                feedback.append("Burn coordinate system was NOT set to SunEarthRot.")

            # Check DC Structure (Anti-gaming check 2)
            has_target = bool(re.search(r'Target\s+DC1', script_content, re.IGNORECASE))
            has_vary = bool(re.search(r'Vary\s+DC1.*SKM_Burn\.Element1', script_content, re.IGNORECASE))
            has_apply = bool(re.search(r'Apply\s+SKM_Burn', script_content, re.IGNORECASE))
            has_prop = bool(re.search(r'Propagate.*DSCOVR\.SunEarthRot\.Y\s*=\s*0', script_content, re.IGNORECASE))
            has_achieve = bool(re.search(r'Achieve\s+DC1.*DSCOVR\.SunEarthRot\.VX\s*=\s*0', script_content, re.IGNORECASE))

            # Partial credit logic
            dc_components = sum([has_target, has_vary, has_apply, has_prop, has_achieve])
            if dc_components == 5:
                total_score += scores["dc_structure_present"]
                dc_structure_ok = True
                feedback.append("Full DC targeting structure correctly implemented.")
            elif dc_components > 0:
                total_score += (scores["dc_structure_present"] * dc_components) // 5
                feedback.append(f"Partial DC structure found ({dc_components}/5 components).")
            else:
                feedback.append("No valid DC targeting loop found in script.")
                
        except Exception as e:
            feedback.append(f"Failed to parse script for logic checks: {e}")
        finally:
            if os.path.exists(temp_script.name):
                os.unlink(temp_script.name)

    # 4. Check Extracted Report Values
    try:
        dv_val = abs(float(task_result.get('delta_v_x_m_s', 0)))
    except (ValueError, TypeError):
        dv_val = 0.0

    try:
        time_val = float(task_result.get('time_to_crossing_days', 0))
    except (ValueError, TypeError):
        time_val = 0.0

    if min_dv <= dv_val <= max_dv:
        total_score += scores["delta_v_valid"]
        dv_ok = True
        feedback.append(f"Delta-V value {dv_val} m/s is physically valid.")
    elif dv_val > 0:
        feedback.append(f"Delta-V value {dv_val} m/s is outside expected range [{min_dv}, {max_dv}].")
    else:
        feedback.append("Valid Delta-V value not found in report.")

    if min_days <= time_val <= max_days:
        total_score += scores["propagation_time_valid"]
        feedback.append(f"Crossing time {time_val} days is physically valid.")
    elif time_val > 0:
        feedback.append(f"Crossing time {time_val} days is outside expected range [{min_days}, {max_days}].")
    else:
        feedback.append("Valid crossing time not found in report.")

    # Pass Condition: > 70 points, DC structure present, and physically valid DV reported
    passed = total_score >= 70 and dc_structure_ok and dv_ok

    return {
        "passed": passed,
        "score": total_score,
        "feedback": " | ".join(feedback),
        "details": {
            "dc_structure_ok": dc_structure_ok,
            "dv_ok": dv_ok,
            "reported_dv": dv_val,
            "reported_time": time_val
        }
    }