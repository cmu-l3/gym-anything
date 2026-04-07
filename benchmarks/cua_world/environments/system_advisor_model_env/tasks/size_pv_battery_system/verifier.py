#!/usr/bin/env python3
"""Verifier for size_pv_battery_system task.

Validates PySAM execution, output file structure, and physics-based results
of the PV + Battery simulation.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_size_pv_battery_system(traj, env_info, task_info):
    """Verify PySAM commercial PV + battery sizing task.

    Criteria (100 pts total):
    - File exists (10)
    - File created/modified during task (10)
    - Valid JSON structure (10)
    - PV capacity = 100 (5)
    - Battery capacity = 200 (5)
    - Battery power = 50 (5)
    - Weather file path is valid (5)
    - PV annual generation in range (15)
    - Capacity factor in range (5)
    - Monthly generation seasonal check (10)
    - Monthly sums to annual (5)
    - Battery throughput physical check (10)
    - Grid energy >= 0 (5)
    """

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    
    score = 0
    feedback_parts = []
    
    # 1. Read the export script's metadata
    temp_meta = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_meta.name)
        with open(temp_meta.name, 'r') as f:
            result_meta = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read metadata: {e}"}
    finally:
        if os.path.exists(temp_meta.name):
            os.unlink(temp_meta.name)

    file_exists = result_meta.get('file_exists', False)
    file_modified = result_meta.get('file_modified', False)
    weather_file_exists = result_meta.get('weather_file_exists', False)

    if file_exists:
        score += 10
        feedback_parts.append("Report file exists")
    else:
        feedback_parts.append("Report file missing")
        return {
            "passed": False, 
            "score": score, 
            "feedback": " | ".join(feedback_parts)
        }

    if file_modified:
        score += 10
        feedback_parts.append("File created during task")
    else:
        feedback_parts.append("File not created during task")

    if weather_file_exists:
        score += 5
        feedback_parts.append("Weather file valid")
    else:
        feedback_parts.append("Weather file invalid or missing")

    # 2. Copy and read the actual agent output JSON
    agent_report_path = "/home/ga/Documents/SAM_Projects/pv_battery_report.json"
    temp_report = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env(agent_report_path, temp_report.name)
        with open(temp_report.name, 'r') as f:
            report_data = json.load(f)
    except Exception as e:
        feedback_parts.append(f"Invalid JSON format: {e}")
        return {
            "passed": False, 
            "score": score, 
            "feedback": " | ".join(feedback_parts)
        }
    finally:
        if os.path.exists(temp_report.name):
            os.unlink(temp_report.name)

    # 3. Validate JSON structure
    sys_config = report_data.get("system_config", {})
    annual_res = report_data.get("annual_results", {})
    monthly_gen = report_data.get("monthly_pv_generation_kwh", [])

    if sys_config and annual_res and isinstance(monthly_gen, list):
        score += 10
        feedback_parts.append("Valid JSON structure")
    else:
        feedback_parts.append("Missing required JSON top-level keys")

    # 4. Check Config Values
    pv_cap = sys_config.get("pv_capacity_kw_dc", 0)
    batt_cap = sys_config.get("battery_capacity_kwh", 0)
    batt_pow = sys_config.get("battery_power_kw", 0)

    if pv_cap == metadata.get("pv_capacity", 100):
        score += 5
    if batt_cap == metadata.get("batt_capacity", 200):
        score += 5
    if batt_pow == metadata.get("batt_power", 50):
        score += 5

    # 5. Check Annual Results
    annual_kwh = annual_res.get("pv_annual_generation_kwh", 0)
    cf = annual_res.get("capacity_factor_percent", 0)
    batt_thru = annual_res.get("battery_annual_throughput_kwh", 0)
    to_grid = annual_res.get("annual_energy_to_grid_kwh", -1)
    from_grid = annual_res.get("annual_energy_from_grid_kwh", -1)

    pv_min = metadata.get("pv_annual_min", 150000)
    pv_max = metadata.get("pv_annual_max", 195000)
    
    if pv_min <= annual_kwh <= pv_max:
        score += 15
        feedback_parts.append("PV generation in range")
    else:
        feedback_parts.append(f"PV generation out of bounds: {annual_kwh}")

    cf_min = metadata.get("cf_min", 17)
    cf_max = metadata.get("cf_max", 22)
    if cf_min <= cf <= cf_max:
        score += 5
        
    if batt_thru > 0 and batt_thru < annual_kwh:
        score += 10
        feedback_parts.append("Battery throughput physically valid")
    else:
        feedback_parts.append("Battery throughput invalid")

    if to_grid >= 0 and from_grid >= 0:
        score += 5

    # 6. Check Monthly Arrays
    if len(monthly_gen) == 12:
        # Sum validation
        monthly_sum = sum(monthly_gen)
        if abs(monthly_sum - annual_kwh) / max(1, annual_kwh) < 0.05:
            score += 5
        
        # Seasonal logic for Phoenix: Summer (Jun-Aug) should produce more than Winter (Dec-Feb)
        summer_gen = sum(monthly_gen[5:8])  # Index 5,6,7 = Jun, Jul, Aug
        winter_gen = monthly_gen[11] + monthly_gen[0] + monthly_gen[1] # Dec, Jan, Feb
        
        if summer_gen > winter_gen:
            score += 10
            feedback_parts.append("Seasonal generation pattern correct")
        else:
            feedback_parts.append("Seasonal generation pattern inverted or flat")

    # Evaluate Pass/Fail
    passed = score >= 70 and file_exists and (pv_min <= annual_kwh <= pv_max)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }