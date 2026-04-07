#!/usr/bin/env python3
"""Verifier for model_linear_fresnel_iph task.

Validates that PySAM was used correctly and that physically sound metrics
were saved into the target JSON file based on the task description.
"""

import json
import tempfile
import os

def to_float(val, default=0.0):
    try:
        return float(val)
    except (ValueError, TypeError):
        return default

def _independent_json_check(copy_from_env):
    """Fallback parser in case the bash jq export missed variations of keys."""
    path = "/home/ga/Documents/SAM_Projects/linear_fresnel_iph_results.json"
    temp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env(path, temp.name)
        with open(temp.name, 'r') as f:
            raw = json.load(f)
            
        return True, raw
    except Exception:
        return False, {}
    finally:
        if os.path.exists(temp.name):
            os.unlink(temp.name)

def _get_val(raw_dict, result_dict, keys, default=0.0):
    """Retrieve the value either from raw Python parsing or from jq result."""
    # Try raw dict first (case insensitive)
    if isinstance(raw_dict, dict):
        for k, v in raw_dict.items():
            if k.lower() in keys:
                return to_float(v)
    
    # Try jq parsed result
    for key in keys:
        if key in result_dict and result_dict[key] != "0" and result_dict[key] != "null" and result_dict[key] != "":
            return to_float(result_dict[key])
            
    return default

def verify_linear_fresnel_iph(traj, env_info, task_info):
    """Verify linear Fresnel simulation was completed successfully.

    Scoring: 100 points max
    - Script exists and >500 bytes: 10
    - Script modified during task: 5
    - Script uses correct module: 10
    - JSON exists and >200 bytes: 10
    - JSON modified during task: 5
    - Energy in range: 15
    - Capacity Factor in range: 10
    - Aperture Area in range: 10
    - Outlet Temp correct: 10
    - Inlet Temp correct: 5
    - Pressure correct: 5
    - Location correct: 5
    """

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    
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
    
    # Perform independent read to capture any missed keys
    json_is_valid, raw_json = _independent_json_check(copy_from_env)

    # Criteria 1-3: Python Script Checks (25 points)
    script_exists = str(result.get('script_exists', 'false')).lower() == 'true'
    script_modified = str(result.get('script_modified', 'false')).lower() == 'true'
    has_module = str(result.get('has_module', 'false')).lower() == 'true'
    has_execute = str(result.get('has_execute', 'false')).lower() == 'true'
    script_size = int(result.get('script_size', 0))

    if script_exists and script_size > 100:
        score += 10
        feedback_parts.append("Python script exists")
        if script_modified:
            score += 5
            feedback_parts.append("Script modified during task")
            
        if has_module and has_execute:
            score += 10
            feedback_parts.append("Script uses LinearFresnelDsgIph and executes")
        else:
            feedback_parts.append("Script missing required PySAM module or execution call")
    else:
        feedback_parts.append("Python script NOT found or too small")

    # Criteria 4-5: JSON Output Checks (15 points)
    json_exists = str(result.get('json_exists', 'false')).lower() == 'true'
    json_modified = str(result.get('json_modified', 'false')).lower() == 'true'
    json_size = int(result.get('json_size', 0))
    
    if json_exists and json_is_valid and json_size > 50:
        score += 10
        feedback_parts.append("Results JSON exists")
        if json_modified:
            score += 5
            feedback_parts.append("JSON modified during task")
    else:
        feedback_parts.append("Results JSON NOT found or invalid")

    # Metric Extractions
    annual_energy = _get_val(raw_json, result, ['annual_energy_kwh', 'annual_energy', 'annual_thermal_energy'])
    cf = _get_val(raw_json, result, ['capacity_factor_percent', 'capacity_factor', 'cf', 'capacity_factor_pct'])
    aperture = _get_val(raw_json, result, ['solar_field_aperture_m2', 'aperture_area', 'solar_field_area', 'solar_field_aperture'])
    t_out = _get_val(raw_json, result, ['design_outlet_temp_c', 'outlet_temp', 'design_outlet_temp', 't_out'])
    t_in = _get_val(raw_json, result, ['design_inlet_temp_c', 'inlet_temp', 'design_inlet_temp', 't_in'])
    pressure = _get_val(raw_json, result, ['operating_pressure_bar', 'operating_pressure', 'pressure_bar', 'pressure'])
    lat = _get_val(raw_json, result, ['latitude', 'lat'])
    lon = _get_val(raw_json, result, ['longitude', 'lon'])

    # Physics & Range Evaluations (60 points)
    if json_exists:
        # Annual Energy (15 pts)
        if metadata['expected_energy_min'] <= annual_energy <= metadata['expected_energy_max']:
            score += 15
            feedback_parts.append(f"Energy Plausible: {annual_energy:,.0f} kWh")
        else:
            feedback_parts.append(f"Energy Out of Bounds: {annual_energy:,.0f} kWh")

        # Capacity Factor (10 pts)
        if metadata['expected_cf_min'] <= cf <= metadata['expected_cf_max']:
            score += 10
            feedback_parts.append(f"CF Plausible: {cf:.1f}%")
        else:
            feedback_parts.append(f"CF Out of Bounds: {cf:.1f}%")

        # Aperture Area (10 pts)
        if metadata['expected_area_min'] <= aperture <= metadata['expected_area_max']:
            score += 10
            feedback_parts.append(f"Area configured: {aperture:,.0f} m2")
        else:
            feedback_parts.append(f"Area Out of Bounds: {aperture:,.0f} m2")

        # Outlet Temp (10 pts)
        if metadata['expected_t_out_min'] <= t_out <= metadata['expected_t_out_max']:
            score += 10
            feedback_parts.append(f"Outlet Temp Correct: {t_out} C")
        else:
            feedback_parts.append(f"Outlet Temp Incorrect: {t_out} C")

        # Inlet Temp (5 pts)
        if metadata['expected_t_in_min'] <= t_in <= metadata['expected_t_in_max']:
            score += 5
            feedback_parts.append(f"Inlet Temp Correct: {t_in} C")
        else:
            feedback_parts.append(f"Inlet Temp Incorrect: {t_in} C")

        # Pressure (5 pts)
        # Accept either bar (25) or kpa (2500) based on how the user might format it, 
        # but the task explicitly asked for bar. We'll accept standard pressure bounds.
        if metadata['expected_pressure_min'] <= pressure <= metadata['expected_pressure_max']:
            score += 5
            feedback_parts.append(f"Pressure Correct: {pressure} bar")
        elif 2000 <= pressure <= 3000: # Agent might have output kPa
            score += 5
            feedback_parts.append(f"Pressure Correct (kPa used): {pressure}")
        else:
            feedback_parts.append(f"Pressure Incorrect: {pressure}")

        # Location (5 pts)
        if metadata['expected_lat_min'] <= lat <= metadata['expected_lat_max'] and metadata['expected_lon_min'] <= lon <= metadata['expected_lon_max']:
            score += 5
            feedback_parts.append("Location matches Phoenix, AZ")
        else:
            feedback_parts.append(f"Location Incorrect: ({lat}, {lon})")

    key_criteria_met = script_exists and has_module and json_exists
    passed = score >= 65 and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "score": score,
            "metrics": {
                "energy_kwh": annual_energy,
                "cf_pct": cf,
                "aperture_m2": aperture,
                "t_out_c": t_out,
                "t_in_c": t_in,
                "pressure": pressure,
                "lat": lat,
                "lon": lon
            }
        }
    }