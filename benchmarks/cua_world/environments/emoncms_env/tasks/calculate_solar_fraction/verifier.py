#!/usr/bin/env python3
"""
Verifier for calculate_solar_fraction task.
"""

import json
import tempfile
import os
import re
import base64
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_calculate_solar_fraction(traj, env_info, task_info):
    """
    Verifies that the agent calculated the solar fraction correctly.
    
    Criteria:
    1. Report file exists and was created during task.
    2. Format matches expected (parsed via regex).
    3. Values are within tolerance of ground truth.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Basic Checks
    file_exists = result.get("file_exists", False)
    file_fresh = result.get("file_created_during_task", False)
    content_b64 = result.get("report_content_base64", "")
    
    if not file_exists:
        return {"passed": False, "score": 0, "feedback": "Report file not found at /home/ga/solar_fraction_report.txt"}
    
    if not file_fresh:
        return {"passed": False, "score": 0, "feedback": "Report file was not created/modified during the task window."}

    # Decode content
    try:
        content = base64.b64decode(content_b64).decode('utf-8')
    except:
        return {"passed": False, "score": 10, "feedback": "Report file exists but content is unreadable."}

    # Parse Agent Values
    # Expected format:
    # Total House Consumption (kWh): <value>
    # Total Solar Generation (kWh): <value>
    # Solar Fraction (%): <value>
    
    house_match = re.search(r"Total House Consumption.*:\s*([\d\.]+)", content, re.IGNORECASE)
    solar_match = re.search(r"Total Solar Generation.*:\s*([\d\.]+)", content, re.IGNORECASE)
    fraction_match = re.search(r"Solar Fraction.*:\s*([\d\.]+)", content, re.IGNORECASE)

    agent_house = float(house_match.group(1)) if house_match else None
    agent_solar = float(solar_match.group(1)) if solar_match else None
    agent_fraction = float(fraction_match.group(1)) if fraction_match else None

    # Get Ground Truth
    gt = result.get("ground_truth", {})
    gt_house = gt.get("house_total", 0.0)
    gt_solar = gt.get("solar_total", 0.0)
    gt_fraction = gt.get("fraction", 0.0)

    # Tolerances
    metadata = task_info.get("metadata", {})
    tol_kwh_pct = metadata.get("tolerances", {}).get("kwh_percent", 10) / 100.0
    tol_frac_pts = metadata.get("tolerances", {}).get("fraction_points", 5.0)

    score = 20 # Points for valid file
    feedback = []

    # Verify House Consumption (30 pts)
    if agent_house is not None:
        delta = abs(agent_house - gt_house)
        allowed = gt_house * tol_kwh_pct
        if delta <= allowed:
            score += 30
            feedback.append(f"House Consumption correct ({agent_house} vs {gt_house:.2f})")
        else:
            feedback.append(f"House Consumption incorrect (Got {agent_house}, Expected ~{gt_house:.2f})")
    else:
        feedback.append("Could not parse House Consumption value")

    # Verify Solar Generation (30 pts)
    if agent_solar is not None:
        delta = abs(agent_solar - gt_solar)
        allowed = gt_solar * tol_kwh_pct
        if delta <= allowed:
            score += 30
            feedback.append(f"Solar Generation correct ({agent_solar} vs {gt_solar:.2f})")
        else:
            feedback.append(f"Solar Generation incorrect (Got {agent_solar}, Expected ~{gt_solar:.2f})")
    else:
        feedback.append("Could not parse Solar Generation value")

    # Verify Fraction (20 pts)
    # Be lenient if they calculated correctly based on their own wrong values vs absolute ground truth
    # But strictly, we compare against GT.
    if agent_fraction is not None:
        delta = abs(agent_fraction - gt_fraction)
        if delta <= tol_frac_pts:
            score += 20
            feedback.append(f"Solar Fraction correct ({agent_fraction}% vs {gt_fraction:.2f}%)")
        else:
            feedback.append(f"Solar Fraction incorrect (Got {agent_fraction}%, Expected ~{gt_fraction:.2f}%)")
    else:
        feedback.append("Could not parse Solar Fraction value")

    passed = (score >= 80)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback)
    }