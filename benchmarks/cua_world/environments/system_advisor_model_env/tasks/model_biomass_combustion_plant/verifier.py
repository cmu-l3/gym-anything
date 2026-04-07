#!/usr/bin/env python3
"""Verifier for model_biomass_combustion_plant task.

Validates the presence and correctness of the generated JSON output and PySAM script.
Includes physics-based cross-checks (CF vs Energy vs Nameplate) to prevent gaming.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def _deep_find_numeric(obj, keys):
    """Recursively search for any of the given keys and return the first numeric value found."""
    if isinstance(obj, dict):
        for k, v in obj.items():
            if k.lower() in [key.lower() for key in keys] and isinstance(v, (int, float)):
                return float(v)
            result = _deep_find_numeric(v, keys)
            if result is not None:
                return float(result)
    elif isinstance(obj, list):
        for item in obj:
            result = _deep_find_numeric(item, keys)
            if result is not None:
                return float(result)
    return None


def _independent_file_check(copy_from_env):
    """Copy the agent's actual script and JSON files and independently verify their contents."""
    json_path = "/home/ga/Documents/SAM_Projects/biomass_results.json"
    py_path = "/home/ga/Documents/SAM_Projects/biomass_model.py"
    
    details = {
        'raw_json_found': False,
        'raw_py_found': False,
        'ind_nameplate': 0.0,
        'ind_annual_kwh': 0.0,
        'ind_cf': 0.0,
        'py_contains_biomass': False
    }
    
    # Check JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env(json_path, temp_json.name)
        with open(temp_json.name, 'r') as f:
            raw = json.load(f)
            
        details['raw_json_found'] = True
        
        # Extract independently
        details['ind_nameplate'] = _deep_find_numeric(raw, ['nameplate_kw', 'nameplate', 'system_capacity_kw']) or 0.0
        details['ind_annual_kwh'] = _deep_find_numeric(raw, ['annual_energy_kwh', 'annual_energy', 'annual_kwh']) or 0.0
        details['ind_cf'] = _deep_find_numeric(raw, ['capacity_factor_percent', 'capacity_factor', 'cf']) or 0.0
        
    except Exception as e:
        logger.warning(f"Independent JSON check failed: {e}")
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)
            
    # Check Python Script
    temp_py = tempfile.NamedTemporaryFile(delete=False, suffix='.py')
    try:
        copy_from_env(py_path, temp_py.name)
        with open(temp_py.name, 'r') as f:
            script_content = f.read()
            
        details['raw_py_found'] = True
        if 'PySAM.Biomass' in script_content or 'from PySAM import Biomass' in script_content:
            details['py_contains_biomass'] = True
            
    except Exception as e:
        logger.warning(f"Independent Python check failed: {e}")
    finally:
        if os.path.exists(temp_py.name):
            os.unlink(temp_py.name)
            
    return details


def verify_model_biomass_combustion_plant(traj, env_info, task_info):
    """Verify the biomass combustion plant modeling task.
    
    Scoring system (100 pts total):
    - JSON file exists and has content (10 pts)
    - JSON created/modified during task (10 pts)
    - Python script exists (10 pts)
    - Python script imports PySAM/Biomass (10 pts)
    - Nameplate capacity is 50,000 kW (15 pts)
    - Annual energy in plausible range (15 pts)
    - Capacity factor in plausible range (15 pts)
    - Physics math consistency: CF ≈ Energy / (Nameplate * 8760) (15 pts)
    """

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_nameplate_kw = metadata.get('expected_nameplate_kw', 50000)
    expected_annual_min = metadata.get('expected_annual_kwh_min', 150000000)
    expected_annual_max = metadata.get('expected_annual_kwh_max', 450000000)
    expected_cf_min = metadata.get('expected_capacity_factor_min', 30.0)
    expected_cf_max = metadata.get('expected_capacity_factor_max', 95.0)

    # Read exported task result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read exported result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Run independent file checks
    ind_details = _independent_file_check(copy_from_env)

    score = 0
    feedback_parts = []

    # 1. JSON File Checks (20 points)
    json_exists = result.get('json_exists') is True or str(result.get('json_exists')).lower() == 'true'
    json_modified = result.get('json_modified') is True or str(result.get('json_modified')).lower() == 'true'
    
    if json_exists and ind_details['raw_json_found']:
        score += 10
        feedback_parts.append("JSON output exists")
        if json_modified:
            score += 10
            feedback_parts.append("JSON modified during task")
        else:
            feedback_parts.append("Warning: JSON not modified during task (possible cheat)")
    else:
        feedback_parts.append("JSON output missing")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    # 2. Python Script Checks (20 points)
    py_exists = result.get('py_exists') is True or str(result.get('py_exists')).lower() == 'true'
    pysam_imported = result.get('pysam_imported') is True or str(result.get('pysam_imported')).lower() == 'true'
    
    if py_exists and ind_details['raw_py_found']:
        score += 10
        feedback_parts.append("Python script exists")
        if pysam_imported or ind_details['py_contains_biomass']:
            score += 10
            feedback_parts.append("Script imports PySAM correctly")
        else:
            feedback_parts.append("Script does not appear to import PySAM")
    else:
        feedback_parts.append("Python script missing")

    # 3. Parse Values (fallback to independent details if jq failed)
    try:
        nameplate_kw = float(result.get('nameplate_kw', 0))
        if nameplate_kw == 0: nameplate_kw = ind_details['ind_nameplate']
            
        annual_kwh = float(result.get('annual_kwh', 0))
        if annual_kwh == 0: annual_kwh = ind_details['ind_annual_kwh']
            
        cf_pct = float(result.get('capacity_factor', 0))
        if cf_pct == 0: cf_pct = ind_details['ind_cf']
    except (ValueError, TypeError):
        nameplate_kw, annual_kwh, cf_pct = 0.0, 0.0, 0.0

    # 4. Value Range Checks
    # Nameplate (15 pts)
    # Allow small tolerance around 50,000 kW
    if abs(nameplate_kw - expected_nameplate_kw) < 100:
        score += 15
        feedback_parts.append(f"Nameplate correct ({nameplate_kw:,.0f} kW)")
    else:
        feedback_parts.append(f"Nameplate incorrect (Expected {expected_nameplate_kw}, got {nameplate_kw})")

    # Annual Energy (15 pts)
    if expected_annual_min <= annual_kwh <= expected_annual_max:
        score += 15
        feedback_parts.append(f"Annual Energy in range ({annual_kwh:,.0f} kWh)")
    else:
        feedback_parts.append(f"Annual Energy out of bounds ({annual_kwh:,.0f} kWh)")

    # Capacity Factor (15 pts)
    if expected_cf_min <= cf_pct <= expected_cf_max:
        score += 15
        feedback_parts.append(f"Capacity Factor in range ({cf_pct:.1f}%)")
    else:
        feedback_parts.append(f"Capacity Factor out of bounds ({cf_pct:.1f}%)")

    # 5. Physics Math Consistency Check (15 pts)
    # Anti-gaming: Ensure the agent didn't just hardcode random numbers
    if nameplate_kw > 0 and annual_kwh > 0:
        calculated_cf = (annual_kwh / (nameplate_kw * 8760)) * 100
        cf_difference = abs(calculated_cf - cf_pct)
        
        if cf_difference < 5.0:  # Allow 5% margin for slight differences in reporting/rounding
            score += 15
            feedback_parts.append("Math consistency check passed")
        else:
            feedback_parts.append(f"Math inconsistency detected (Calculated CF: {calculated_cf:.1f}%, Reported: {cf_pct:.1f}%)")
    else:
        feedback_parts.append("Cannot perform math consistency check (missing values)")

    # Determine Pass/Fail
    # To pass, they need at least 65 points AND the JSON file must have been created AND Nameplate must be close
    key_criteria_met = json_modified and (abs(nameplate_kw - expected_nameplate_kw) < 100) and (annual_kwh > 0)
    passed = (score >= 65) and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "nameplate_kw": nameplate_kw,
            "annual_kwh": annual_kwh,
            "capacity_factor": cf_pct,
            "ind_details": ind_details
        }
    }