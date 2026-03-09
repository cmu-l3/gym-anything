#!/usr/bin/env python3
"""
Verifier for blade_modal_analysis task.

Checks:
1. QBlade project file exists and was modified during task.
2. Project file contains structural definition data.
3. JSON report exists.
4. Reported mass is within physics tolerance (approx 808 kg +/- 15%).
5. Reported frequency is within reasonable range (0.5 - 3.0 Hz).
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_blade_modal_analysis(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve metadata targets
    metadata = task_info.get('metadata', {}).get('physics_target', {})
    target_mass = metadata.get('mass_kg', 808.0)
    mass_tolerance = metadata.get('mass_tolerance_percent', 15)
    freq_min = metadata.get('freq_min_hz', 0.5)
    freq_max = metadata.get('freq_max_hz', 3.0)

    # Copy result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []

    # Criterion 1: Project Saved (25 pts)
    if result.get("project_exists") and result.get("file_created_during_task"):
        score += 25
        feedback_parts.append("Project file saved successfully")
    elif result.get("project_exists"):
        score += 10
        feedback_parts.append("Project file exists but timestamp check failed (reused?)")
    else:
        feedback_parts.append("Project file not found")

    # Criterion 2: Structural Data Generated (25 pts)
    if result.get("structural_data_found"):
        score += 25
        feedback_parts.append("Structural properties found in project")
    else:
        feedback_parts.append("No structural data found in project (did you run QFem generation?)")

    # Criterion 3: JSON Report & Mass Accuracy (25 pts)
    reported_mass = result.get("reported_mass", 0)
    mass_error_pct = abs(reported_mass - target_mass) / target_mass * 100 if target_mass else 100

    if result.get("json_report_exists"):
        if mass_error_pct <= mass_tolerance:
            score += 25
            feedback_parts.append(f"Blade mass accurate ({reported_mass:.1f} kg)")
        elif mass_error_pct <= (mass_tolerance * 2):
            score += 15
            feedback_parts.append(f"Blade mass somewhat accurate ({reported_mass:.1f} kg, expected ~{target_mass})")
        else:
            score += 5
            feedback_parts.append(f"Blade mass incorrect ({reported_mass:.1f} kg, expected ~{target_mass})")
    else:
        feedback_parts.append("JSON results report not found")

    # Criterion 4: Frequency Plausibility (25 pts)
    reported_freq = result.get("reported_freq", 0)
    if freq_min <= reported_freq <= freq_max:
        score += 25
        feedback_parts.append(f"Eigenfrequency reasonable ({reported_freq:.2f} Hz)")
    elif reported_freq > 0:
        score += 10
        feedback_parts.append(f"Eigenfrequency out of expected range ({reported_freq:.2f} Hz)")
    else:
        feedback_parts.append("No valid frequency reported")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }