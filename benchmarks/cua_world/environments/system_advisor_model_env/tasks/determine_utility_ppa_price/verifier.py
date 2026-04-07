#!/usr/bin/env python3
"""
Verifier for determine_utility_ppa_price task.

This task requires the agent to configure a Singleowner utility-scale PV model in PySAM
and solve for the PPA price that gives an 11% leveraged after-tax IRR.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def _get_float(d, key, default=0.0):
    try:
        val = d.get(key)
        if val is None:
            return default
        return float(val)
    except (ValueError, TypeError):
        return default

def _independent_file_check(copy_from_env):
    """Copy the agent's actual output file and independently verify its contents."""
    path = "/home/ga/Documents/SAM_Projects/utility_pv_ppa_results.json"
    temp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env(path, temp.name)
        with open(temp.name, 'r') as f:
            raw = json.load(f)
        return True, raw
    except Exception as e:
        logger.error(f"Failed to read agent JSON output: {e}")
        return False, {}
    finally:
        if os.path.exists(temp.name):
            os.unlink(temp.name)

def verify_determine_utility_ppa_price(traj, env_info, task_info):
    """Verify PySAM execution and PPA price solving logic.

    Scoring: 100 points max
    - File exists and modified: 20
    - All fields present: 10
    - Input params correct (capacity, cost): 10
    - Annual energy in range: 10
    - Capacity factor in range: 10
    - PPA price reasonable (2-9 cents): 15
    - IRR matches target (~11%): 15
    - NPV near zero: 5
    - LCOE reasonable and < PPA: 5
    """

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_capacity = metadata.get('expected_capacity_kw', 50000)
    expected_installed_cost = metadata.get('expected_installed_cost', 55000000)
    energy_min = metadata.get('annual_energy_min_kwh', 85000000)
    energy_max = metadata.get('annual_energy_max_kwh', 130000000)
    cf_min = metadata.get('capacity_factor_min', 19.0)
    cf_max = metadata.get('capacity_factor_max', 30.0)
    ppa_min = metadata.get('ppa_price_min', 2.0)
    ppa_max = metadata.get('ppa_price_max', 9.0)
    target_irr = metadata.get('irr_target', 11.0)
    npv_tol = metadata.get('npv_tolerance', 2000000)

    # 1. Read export wrapper JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            export_result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read export result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    file_exists = export_result.get('file_exists', False)
    file_modified = export_result.get('file_modified', False)

    if file_exists and file_modified:
        score += 20
        feedback_parts.append("File exists and created during task")
    elif file_exists:
        score += 5
        feedback_parts.append("File exists but was NOT created during task")
    else:
        feedback_parts.append("Output file not found")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    # 2. Read actual agent JSON payload independently
    has_payload, payload = _independent_file_check(copy_from_env)
    if not has_payload:
        feedback_parts.append("Output file is not valid JSON")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    # Define required keys
    req_keys = [
        "weather_file_used", "system_capacity_kw", "annual_energy_year1_kwh",
        "capacity_factor_percent", "ppa_price_year1_cents_per_kwh", 
        "leveraged_after_tax_irr_percent", "npv_dollars", 
        "lcoe_nominal_cents_per_kwh", "total_installed_cost_dollars"
    ]
    
    missing_keys = [k for k in req_keys if k not in payload]
    if not missing_keys:
        score += 10
        feedback_parts.append("All required fields present")
    else:
        feedback_parts.append(f"Missing fields: {', '.join(missing_keys)}")

    # Extract values safely
    capacity = _get_float(payload, 'system_capacity_kw')
    cost = _get_float(payload, 'total_installed_cost_dollars')
    energy = _get_float(payload, 'annual_energy_year1_kwh')
    cf = _get_float(payload, 'capacity_factor_percent')
    ppa = _get_float(payload, 'ppa_price_year1_cents_per_kwh')
    irr = _get_float(payload, 'leveraged_after_tax_irr_percent')
    npv = _get_float(payload, 'npv_dollars')
    lcoe = _get_float(payload, 'lcoe_nominal_cents_per_kwh')

    # Input param checks (Capacity and Cost)
    if abs(capacity - expected_capacity) < 1.0:
        score += 5
    else:
        feedback_parts.append(f"Incorrect capacity: {capacity} (expected {expected_capacity})")

    if abs(cost - expected_installed_cost) < 1000.0:
        score += 5
    else:
        feedback_parts.append(f"Incorrect installed cost: {cost} (expected {expected_installed_cost})")

    # Outputs: Energy & CF
    if energy_min <= energy <= energy_max:
        score += 10
        feedback_parts.append(f"Annual Energy {energy/1e6:.1f} GWh plausible")
    else:
        feedback_parts.append(f"Annual Energy {energy/1e6:.1f} GWh out of expected range")

    if cf_min <= cf <= cf_max:
        score += 10
        feedback_parts.append(f"CF {cf:.1f}% plausible")
    else:
        feedback_parts.append(f"CF {cf:.1f}% out of expected range")

    # Outputs: Financial Results
    if ppa_min <= ppa <= ppa_max:
        score += 15
        feedback_parts.append(f"PPA {ppa:.2f} ¢/kWh plausible")
    else:
        feedback_parts.append(f"PPA {ppa:.2f} ¢/kWh out of range")

    # Target IRR should be close to 11% if solver was used correctly
    if 10.5 <= irr <= 11.5:
        score += 15
        feedback_parts.append(f"IRR {irr:.2f}% matches target (11%)")
    elif 9.0 <= irr <= 13.0:
        score += 5
        feedback_parts.append(f"IRR {irr:.2f}% near target, but solver might not have converged")
    else:
        feedback_parts.append(f"IRR {irr:.2f}% does not match 11% target")

    # NPV should be near 0 when solving for target IRR
    if abs(npv) <= npv_tol:
        score += 5
        feedback_parts.append("NPV near zero (confirms solver)")
    else:
        feedback_parts.append(f"NPV {npv:,.0f} not near zero, solver may have failed")

    # LCOE should be reasonable and typically less than PPA
    if 1.0 <= lcoe <= 10.0 and lcoe < ppa:
        score += 5
        feedback_parts.append(f"LCOE {lcoe:.2f} ¢/kWh < PPA")
    else:
        feedback_parts.append(f"LCOE {lcoe:.2f} ¢/kWh not in valid range or >= PPA")

    key_criteria_met = file_exists and file_modified and not missing_keys
    passed = score >= 70 and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }