#!/usr/bin/env python3
"""
Verifier for Simulate Tidal Turbine Performance task.

Logic:
1. Physics Verification (CRITICAL):
   - In Air (1.225 kg/m3): Power ~ 0.3 - 0.4 kW
   - In Water (1025 kg/m3): Power ~ 250 - 350 kW
   - The verifier checks if the reported value falls within the "Water" range.
   - Range set to > 150 kW to be generous, but clearly distinguishing from air.

2. File Artifacts:
   - Project file must exist and be valid (> 1KB).
   - Report file must exist.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_tidal_simulation(traj, env_info, task_info):
    """
    Verify tidal turbine simulation results.
    """
    # 1. Setup and Load Data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: Copy function not available"}

    metadata = task_info.get('metadata', {})
    min_power = metadata.get('min_power_kw', 150)
    max_power = metadata.get('max_power_kw', 400)
    air_limit = metadata.get('air_power_limit_kw', 5)

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Extract Metrics
    project_exists = result.get("project_exists", False)
    project_size = result.get("project_size_bytes", 0)
    report_exists = result.get("report_exists", False)
    raw_value = result.get("extracted_power_value", "0")
    
    try:
        power_value = float(raw_value)
    except (ValueError, TypeError):
        power_value = 0.0

    score = 0
    feedback = []

    # 3. Score Calculation

    # Criterion A: Project File Created (20 pts)
    if project_exists and project_size > 5000: # Real projects are usually >10KB
        score += 20
        feedback.append("Project file saved successfully.")
    elif project_exists:
        score += 10
        feedback.append("Project file saved but seems small/empty.")
    else:
        feedback.append("Project file (.wpa) not found.")

    # Criterion B: Report Exists (10 pts)
    if report_exists:
        score += 10
        feedback.append("Report file found.")
    else:
        feedback.append("Report file not found.")

    # Criterion C: Physics Verification (70 pts)
    # This is the main check. Did they simulate water or air?
    if power_value > min_power:
        # User likely simulated water (approx 280kW expected)
        if power_value <= max_power:
            score += 70
            feedback.append(f"Power value ({power_value} kW) is correct for seawater density.")
        else:
            # Value unreasonably high (e.g. > 400kW for a 5m blade @ 2.5m/s)
            score += 40
            feedback.append(f"Power value ({power_value} kW) indicates water density but is higher than physically expected (check efficiency).")
    elif power_value > 0:
        if power_value < air_limit:
            # User likely simulated air (approx 0.3kW expected)
            feedback.append(f"Power value ({power_value} kW) is too low. Did you forget to change density to 1025 kg/m^3? (Air density results in ~0.3 kW)")
        else:
            # Value is in no-man's land (between 5kW and 150kW)
            # Maybe wrong radius or wrong velocity?
            score += 20
            feedback.append(f"Power value ({power_value} kW) is incorrect. Expected ~280 kW for water, ~0.3 kW for air.")
    else:
        feedback.append("Could not read a valid numeric power value from the report.")

    # 4. Final Determination
    passed = score >= 75
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }