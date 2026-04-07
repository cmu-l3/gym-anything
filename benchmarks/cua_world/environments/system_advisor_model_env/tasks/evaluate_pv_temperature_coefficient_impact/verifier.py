#!/usr/bin/env python3
"""Verifier for evaluate_pv_temperature_coefficient_impact task."""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_evaluate_pv_temperature_coefficient_impact(traj, env_info, task_info):
    """Verify temperature coefficient comparison was completed successfully."""

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_annual_min = metadata.get('expected_annual_min', 100000000)
    expected_annual_max = metadata.get('expected_annual_max', 130000000)
    expected_summer_fraction_min = metadata.get('expected_summer_fraction_min', 0.28)
    expected_summer_fraction_max = metadata.get('expected_summer_fraction_max', 0.38)
    expected_winter_fraction_min = metadata.get('expected_winter_fraction_min', 0.15)
    expected_winter_fraction_max = metadata.get('expected_winter_fraction_max', 0.25)

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

    # Criterion 1: File exists (10 points)
    file_exists = result.get('file_exists') is True or str(result.get('file_exists')) == 'true'
    if file_exists:
        score += 10
        feedback_parts.append("File exists")
    else:
        feedback_parts.append("File NOT found")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    # Criterion 2: File was created during task (10 points)
    file_modified = result.get('file_modified') is True or str(result.get('file_modified')) == 'true'
    if file_modified:
        score += 10
        feedback_parts.append("File created during task")
    else:
        feedback_parts.append("File not created/modified during task")

    # Read the agent's output file independently
    output_path = "/home/ga/Documents/SAM_Projects/temp_coef_comparison.json"
    temp_output = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    
    agent_data = {}
    try:
        copy_from_env(output_path, temp_output.name)
        with open(temp_output.name, 'r') as f:
            agent_data = json.load(f)
    except Exception as e:
        feedback_parts.append(f"Could not read/parse agent output JSON: {e}")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}
    finally:
        if os.path.exists(temp_output.name):
            os.unlink(temp_output.name)

    # Criterion 3: Schema Conformance (10 points)
    required_keys = [
        "premium_annual_energy_kwh", "thinfilm_annual_energy_kwh",
        "premium_summer_energy_kwh", "thinfilm_summer_energy_kwh",
        "premium_winter_energy_kwh", "thinfilm_winter_energy_kwh",
        "thinfilm_summer_gain_percent", "thinfilm_winter_gain_percent"
    ]
    
    missing_keys = [k for k in required_keys if k not in agent_data]
    if not missing_keys:
        score += 10
        feedback_parts.append("All required keys present")
    else:
        feedback_parts.append(f"Missing keys: {missing_keys}")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    try:
        prem_ann = float(agent_data["premium_annual_energy_kwh"])
        thin_ann = float(agent_data["thinfilm_annual_energy_kwh"])
        prem_sum = float(agent_data["premium_summer_energy_kwh"])
        thin_sum = float(agent_data["thinfilm_summer_energy_kwh"])
        prem_win = float(agent_data["premium_winter_energy_kwh"])
        thin_win = float(agent_data["thinfilm_winter_energy_kwh"])
        thin_sum_gain = float(agent_data["thinfilm_summer_gain_percent"])
        thin_win_gain = float(agent_data["thinfilm_winter_gain_percent"])
    except ValueError:
        feedback_parts.append("Output contains non-numeric values")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    # Criterion 4: Annual Energy Accuracy (20 points)
    if expected_annual_min <= prem_ann <= expected_annual_max and expected_annual_min <= thin_ann <= expected_annual_max:
        score += 20
        feedback_parts.append("Annual energy values plausible")
    else:
        feedback_parts.append("Annual energy values outside expected range (check scaling/inputs)")

    # Criterion 5: Seasonal Aggregation (25 points)
    prem_sum_frac = prem_sum / prem_ann if prem_ann > 0 else 0
    prem_win_frac = prem_win / prem_ann if prem_ann > 0 else 0
    thin_sum_frac = thin_sum / thin_ann if thin_ann > 0 else 0
    thin_win_frac = thin_win / thin_ann if thin_ann > 0 else 0
    
    sum_ok = expected_summer_fraction_min <= prem_sum_frac <= expected_summer_fraction_max and \
             expected_summer_fraction_min <= thin_sum_frac <= expected_summer_fraction_max
    win_ok = expected_winter_fraction_min <= prem_win_frac <= expected_winter_fraction_max and \
             expected_winter_fraction_min <= thin_win_frac <= expected_winter_fraction_max
             
    if sum_ok and win_ok:
        score += 25
        feedback_parts.append("Seasonal aggregations plausible")
    else:
        feedback_parts.append(f"Seasonal aggregations irregular (Summer: {prem_sum_frac:.2f}, Winter: {prem_win_frac:.2f})")

    # Criterion 6: Gain Calculation Math (15 points)
    calc_sum_gain = ((thin_sum - prem_sum) / prem_sum) * 100 if prem_sum > 0 else 0
    calc_win_gain = ((thin_win - prem_win) / prem_win) * 100 if prem_win > 0 else 0
    
    if abs(calc_sum_gain - thin_sum_gain) < 0.1 and abs(calc_win_gain - thin_win_gain) < 0.1:
        score += 15
        feedback_parts.append("Gain math correct")
    else:
        feedback_parts.append("Gain math incorrect based on seasonal values")

    # Criterion 7: Engineering Logic (10 points)
    if thin_sum_gain > thin_win_gain:
        score += 10
        feedback_parts.append("Engineering logic holds (Summer gain > Winter gain)")
    else:
        feedback_parts.append("Engineering logic failed (Thin Film should perform relatively better in summer)")

    key_criteria_met = file_exists and file_modified and not missing_keys

    passed = score >= 80 and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }