#!/usr/bin/env python3
"""Verifier for model_mhk_wave_energy task.
Validates PySAM output for MHK wave simulations, checks loss configurations, and ensures physical consistency.
"""

import json
import os
import tempfile

def verify_model_mhk_wave_energy(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_sys_cap = metadata.get('system_capacity_kw', 300)
    expected_losses = metadata.get('losses', {
        "loss_array_spacing_pct": 0,
        "loss_resource_overprediction_pct": 5,
        "loss_transmission_pct": 2,
        "loss_downtime_pct": 5,
        "loss_additional_pct": 0
    })

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
    feedback = []

    file_exists = result.get('file_exists', False)
    valid_json = result.get('valid_json', False)
    file_created = result.get('file_created_during_task', False)
    data = result.get('data', {})

    # 1. File Exists
    if not file_exists:
        feedback.append("Result file does not exist.")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback)}
    score += 10
    feedback.append("Result file exists (+10)")

    # 2. File Created During Task
    if file_created:
        score += 10
        feedback.append("File created during task (+10)")
    else:
        feedback.append("File not created during task.")

    # 3. Valid JSON and Keys
    required_keys = [
        "annual_energy_kwh", "capacity_factor_percent", "device_average_power_kw",
        "system_capacity_kw", "loss_array_spacing_pct", "loss_resource_overprediction_pct",
        "loss_transmission_pct", "loss_downtime_pct", "loss_additional_pct",
        "wave_resource_matrix_rows", "wave_resource_matrix_cols"
    ]
    missing_keys = [k for k in required_keys if k not in data]
    
    if valid_json and not missing_keys:
        score += 10
        feedback.append("Valid JSON with all required keys (+10)")
    else:
        if not valid_json:
            feedback.append("File is not valid JSON.")
        if missing_keys:
            feedback.append(f"Missing keys: {missing_keys}")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback)}

    # 4. Check Capacity
    sys_cap = data.get("system_capacity_kw", 0)
    if sys_cap == expected_sys_cap:
        score += 10
        feedback.append(f"System capacity is {expected_sys_cap} kW (+10)")
    else:
        feedback.append(f"Incorrect system capacity: {sys_cap} kW")

    # 5. Check Losses
    losses_correct = True
    for k, v in expected_losses.items():
        if data.get(k) != v:
            losses_correct = False
            feedback.append(f"Incorrect loss {k}: expected {v}, got {data.get(k)}")
    if losses_correct:
        score += 10
        feedback.append("All loss parameters correct (+10)")

    # 6. Reasonableness of AEP
    aep = data.get("annual_energy_kwh", 0)
    if isinstance(aep, (int, float)) and 0 < aep < (expected_sys_cap * 8760):
        score += 10
        feedback.append(f"AEP physically reasonable: {aep:.1f} kWh (+10)")
    else:
        feedback.append(f"AEP out of bounds or invalid: {aep}")

    # 7. Reasonableness of CF
    cf = data.get("capacity_factor_percent", 0)
    if isinstance(cf, (int, float)) and 1 <= cf <= 65:
        score += 10
        feedback.append(f"CF reasonable: {cf:.2f}% (+10)")
    else:
        feedback.append(f"CF out of bounds or invalid: {cf}")

    # 8. AEP-power consistency
    avg_power = data.get("device_average_power_kw", 0)
    aep_consistency = False
    if isinstance(avg_power, (int, float)) and isinstance(aep, (int, float)) and avg_power > 0 and aep > 0:
        expected_aep = avg_power * 8760
        if abs(expected_aep - aep) / aep < 0.05:
            aep_consistency = True
            score += 10
            feedback.append("AEP-power consistent (+10)")
        else:
            feedback.append("AEP-power inconsistent")
            
    # 9. CF-power consistency
    if isinstance(avg_power, (int, float)) and isinstance(cf, (int, float)) and avg_power > 0 and cf > 0 and sys_cap > 0:
        expected_cf = (avg_power / sys_cap) * 100
        if abs(expected_cf - cf) / cf < 0.05:
            score += 10
            feedback.append("CF-power consistent (+10)")
        else:
            feedback.append("CF-power inconsistent")
            
    # 10. Resource matrix check
    rows = data.get("wave_resource_matrix_rows", 0)
    cols = data.get("wave_resource_matrix_cols", 0)
    if isinstance(rows, int) and isinstance(cols, int) and rows > 2 and cols > 2:
        score += 10
        feedback.append(f"Resource matrix non-trivial {rows}x{cols} (+10)")
    else:
        feedback.append("Resource matrix trivial or missing")

    # Pass condition
    passed = score >= 80 and file_exists and aep_consistency

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "details": {
            "file_exists": file_exists,
            "valid_json": valid_json,
            "file_created": file_created,
            "aep": aep,
            "cf": cf,
            "avg_power": avg_power,
            "score": score
        }
    }