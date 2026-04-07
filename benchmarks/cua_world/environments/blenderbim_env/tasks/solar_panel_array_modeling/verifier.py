#!/usr/bin/env python3
"""
Verifier for solar_panel_array_modeling task.

Scoring Rubric (100 points total, Pass Threshold = 70):
  - File Output & Integrity : 15 pts (Output exists, modified during session, walls intact)
  - Solar Device Entities   : 25 pts (>= 6 IfcSolarDevice entities; partial for fewer)
  - Logical System Exists   : 20 pts (IfcSystem with 'Solar' or 'PV' in name)
  - System Assignment       : 25 pts (>= 6 Devices assigned to the system; partial for fewer)
  - Power Property Added    : 15 pts (Property containing Power/Watt/Capacity found)
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_solar_panel_array_modeling(traj, env_info, task_info):
    score = 0
    feedback_lines = []

    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {
            "passed": False, 
            "score": 0,
            "feedback": "copy_from_env not available in env_info."
        }

    # Retrieve the exported JSON from the container
    with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as f:
        tmp_path = f.name

    try:
        copy_from_env("/tmp/solar_result.json", tmp_path)
        with open(tmp_path, "r") as f:
            result = json.load(f)
    except FileNotFoundError:
        return {
            "passed": False, 
            "score": 0,
            "feedback": "Result file not found — export script may not have run."
        }
    except Exception as e:
        return {
            "passed": False, 
            "score": 0,
            "feedback": f"Could not read result file: {e}"
        }
    finally:
        try:
            os.unlink(tmp_path)
        except Exception:
            pass

    # 1. Critical Gate: Output File & Integrity (15 pts)
    file_exists = result.get("file_exists", False)
    if not file_exists:
        return {
            "passed": False,
            "score": 0,
            "feedback": "FAIL: Output IFC file /home/ga/BIMProjects/fzk_solar_retrofit.ifc was not created. Score: 0/100."
        }

    file_mtime = result.get("file_mtime", 0.0)
    task_start = result.get("task_start", 0.0)
    n_walls = result.get("n_walls", 0)
    
    # Anti-gaming: Ensure they didn't just save an empty project
    if n_walls < 10:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"FAIL: Base building geometry is missing (only {n_walls} walls found). The original model must remain intact. Score: 0/100."
        }
        
    if task_start > 0 and file_mtime > task_start:
        score += 15
        feedback_lines.append("PASS: Output IFC created during this task session and base geometry is intact. (+15)")
    else:
        feedback_lines.append(f"FAIL: Output file not modified during task (file_mtime={file_mtime:.1f}, task_start={task_start:.1f}). (+0)")

    # 2. Solar Device Entities (25 pts)
    n_solar_devices = result.get("n_solar_devices", 0)
    if n_solar_devices >= 6:
        score += 25
        feedback_lines.append(f"PASS: {n_solar_devices} IfcSolarDevice entities found (>= 6 required). (+25)")
    elif n_solar_devices >= 3:
        score += 12
        feedback_lines.append(f"PARTIAL: {n_solar_devices}/6 IfcSolarDevice entities found. (+12)")
    elif n_solar_devices >= 1:
        score += 5
        feedback_lines.append(f"PARTIAL: {n_solar_devices}/6 IfcSolarDevice entities found. (+5)")
    else:
        feedback_lines.append("FAIL: No IfcSolarDevice entities found. (+0)")

    # 3. Logical System Exists (20 pts)
    system_names = result.get("system_names", [])
    # Re-evaluate logic to check if a PV system exists (using same logic as export)
    pv_system_found = any(any(k in s.lower() for k in ["solar", "pv", "photovoltaic"]) for s in system_names)
    
    if pv_system_found:
        score += 20
        feedback_lines.append(f"PASS: Valid Solar/PV IfcSystem found (System Names: {system_names}). (+20)")
    else:
        feedback_lines.append(f"FAIL: No IfcSystem with 'Solar', 'PV', or 'Photovoltaic' in its name was found. (+0)")

    # 4. System Assignment (25 pts)
    n_assigned = result.get("n_devices_in_solar_system", 0)
    if n_assigned >= 6:
        score += 25
        feedback_lines.append(f"PASS: {n_assigned} solar devices properly assigned to the electrical system. (+25)")
    elif n_assigned >= 3:
        score += 12
        feedback_lines.append(f"PARTIAL: {n_assigned}/6 solar devices assigned to the electrical system. (+12)")
    elif n_assigned >= 1:
        score += 5
        feedback_lines.append(f"PARTIAL: {n_assigned}/6 solar devices assigned to the electrical system. (+5)")
    else:
        feedback_lines.append("FAIL: No solar devices were assigned to the electrical system via IfcRelAssignsToGroup. (+0)")

    # 5. Power Property Added (15 pts)
    property_found = result.get("power_property_found", False)
    if property_found:
        score += 15
        feedback_lines.append("PASS: Required capacity property (Power/Watt/Capacity) successfully found on the system or devices. (+15)")
    else:
        feedback_lines.append("FAIL: No property containing 'Power', 'Watt', or 'Capacity' was found on the system or devices. (+0)")

    passed = score >= 70
    
    feedback_lines.append(f"\nTotal score: {score}/100. {'PASSED' if passed else 'FAILED'} (threshold: 70).")

    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback_lines)
    }