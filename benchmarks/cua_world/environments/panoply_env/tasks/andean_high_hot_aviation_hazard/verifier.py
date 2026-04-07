#!/usr/bin/env python3
"""
Verifier for andean_high_hot_aviation_hazard task.

Occupation: Aviation Performance Engineer
Industry: Cargo Aviation / Flight Operations
Difficulty: hard

Scoring criteria (100 pts total, pass threshold = 80):
  1. Surface Pressure Map Exported (20 pts): andes_surface_pressure_jan.png exists,
     was created after task start, and has size >= 15KB.
  2. Air Temperature Map Exported (20 pts): andes_air_temperature_jan.png exists,
     was created after task start, and has size >= 15KB.
  3. Advisory Structure Complete (20 pts): high_hot_advisory.txt exists,
     was created after task start, and contains required structural keys.
  4. Pressure Plausibility & Units (20 pts): LOWEST_PRESSURE_HPA falls in [500, 750].
     - If ~1000, they wrongly used Sea Level Pressure (slp).
     - If ~50,000+, they forgot to convert from Pascals to hPa.
  5. Operational Logic Correct (20 pts): PAYLOAD_RESTRICTION_REQUIRED equals 'YES'.
"""

import json
import os
import tempfile
import re

def verify_andean_high_hot_aviation_hazard(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    # Safely extract result JSON
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp.close()
    try:
        copy_from_env('/tmp/andean_high_hot_aviation_hazard_result.json', tmp.name)
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

    # ----------------------------------------------------------------
    # Criterion 1: Surface Pressure Map Exported (20 pts)
    # ----------------------------------------------------------------
    pres_exists = result.get('pres_plot_exists', False)
    pres_mtime = int(result.get('pres_plot_mtime', 0))
    pres_size = int(result.get('pres_plot_size', 0))

    if pres_exists and pres_mtime >= task_start and pres_size >= 15000:
        score += 20
        feedback.append(f"Surface Pressure map exported successfully ({pres_size} bytes)")
    elif pres_exists and pres_size > 0:
        score += 10
        feedback.append(f"Surface Pressure map present but small or pre-existing ({pres_size} bytes, mtime {pres_mtime})")
    else:
        feedback.append(f"Surface Pressure map missing (exists={pres_exists})")

    # ----------------------------------------------------------------
    # Criterion 2: Air Temperature Map Exported (20 pts)
    # ----------------------------------------------------------------
    air_exists = result.get('air_plot_exists', False)
    air_mtime = int(result.get('air_plot_mtime', 0))
    air_size = int(result.get('air_plot_size', 0))

    if air_exists and air_mtime >= task_start and air_size >= 15000:
        score += 20
        feedback.append(f"Air Temperature map exported successfully ({air_size} bytes)")
    elif air_exists and air_size > 0:
        score += 10
        feedback.append(f"Air Temperature map present but small or pre-existing ({air_size} bytes, mtime {air_mtime})")
    else:
        feedback.append(f"Air Temperature map missing (exists={air_exists})")

    # ----------------------------------------------------------------
    # Criterion 3: Advisory Structure Complete (20 pts)
    # ----------------------------------------------------------------
    report_exists = result.get('report_exists', False)
    report_mtime = int(result.get('report_mtime', 0))
    
    lowest_pres_str = result.get('lowest_pressure', '').strip()
    payload_restriction = result.get('payload_restriction', '').strip().upper()
    aero_factor = result.get('aerodynamic_factor', '').strip()

    if report_exists and report_mtime >= task_start and lowest_pres_str and payload_restriction and aero_factor:
        score += 20
        feedback.append("Advisory report successfully parsed with required structural keys.")
    elif report_exists:
        score += 10
        feedback.append("Advisory report exists but is missing one or more required keys.")
    else:
        feedback.append("Advisory report is missing.")

    # ----------------------------------------------------------------
    # Criterion 4: Pressure Plausibility & Units (20 pts)
    # Must correctly convert Pascals to hPa, avoiding SLP.
    # Expected valid range for high Andes is ~ 500 to 750 hPa.
    # ----------------------------------------------------------------
    valid_pressure = False
    if lowest_pres_str:
        # Extract numeric content
        match = re.search(r'([0-9]+(?:\.[0-9]+)?)', lowest_pres_str)
        if match:
            try:
                pres_val = float(match.group(1))
                if 500 <= pres_val <= 750:
                    score += 20
                    valid_pressure = True
                    feedback.append(f"Pressure Plausibility Check Passed: {pres_val} hPa.")
                elif 950 <= pres_val <= 1050:
                    feedback.append(f"Data Trap Failed: {pres_val} hPa indicates Sea Level Pressure (slp) was incorrectly used instead of surface pressure (pres).")
                elif pres_val >= 50000:
                    feedback.append(f"Unit Trap Failed: {pres_val} indicates raw Pascals (Pa) were logged without converting to HectoPascals (hPa).")
                else:
                    feedback.append(f"Pressure Plausibility Failed: {pres_val} is outside expected range (500-750 hPa).")
            except ValueError:
                feedback.append(f"Could not parse pressure value: {lowest_pres_str}")
        else:
            feedback.append("No numeric value found in LOWEST_PRESSURE_HPA.")
    else:
        feedback.append("LOWEST_PRESSURE_HPA field was empty or missing.")

    # ----------------------------------------------------------------
    # Criterion 5: Operational Logic Correct (20 pts)
    # Payload restrictions are mandatory for high/hot conditions.
    # ----------------------------------------------------------------
    valid_logic = False
    if payload_restriction == 'YES':
        score += 20
        valid_logic = True
        feedback.append("Operational Logic Passed: PAYLOAD_RESTRICTION_REQUIRED correctly set to YES.")
    elif payload_restriction:
        feedback.append(f"Operational Logic Failed: Set to '{payload_restriction}' instead of YES.")

    # ----------------------------------------------------------------
    # Final Result Compilation
    # ----------------------------------------------------------------
    # For a firm "Pass", the agent must achieve >= 80% AND correctly navigate
    # the pressure data extraction and operational logic.
    is_passing = (score >= 80) and valid_pressure and valid_logic

    return {
        "passed": is_passing,
        "score": score,
        "feedback": " | ".join(feedback),
        "details": {
            "pres_file_valid": (pres_exists and pres_size >= 15000),
            "air_file_valid": (air_exists and air_size >= 15000),
            "pressure_value": lowest_pres_str,
            "restriction": payload_restriction
        }
    }