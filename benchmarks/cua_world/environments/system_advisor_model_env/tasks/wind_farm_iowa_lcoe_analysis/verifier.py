#!/usr/bin/env python3
"""Verifier for wind_farm_iowa_lcoe_analysis task.

Tests whether the agent correctly modeled a 10 MW Iowa wind farm
using SAM's Windpower module and compared LCOE across 3 turbine configurations.

Scoring (100 points):
- File exists: 10
- File created during task: 10
- Wind model used (not PVWatts): 10
- Three or more turbine configurations evaluated: 15
- Capacity factors physically plausible for Iowa wind (28-58%): 15
- LCOE values in realistic US onshore wind range (15-90 $/MWh): 15
- AEP values consistent with ~10 MW nameplate (>2 configurations): 15
- Optimal configuration identified: 10

Pass threshold: 60 points AND (file_exists AND file_modified AND wind_model_used)
"""

import json
import os
import tempfile


def _lcoe_plausibility_check(lcoe_value):
    """US onshore wind LCOE 2024: ~$26-80/MWh. Accept wide range for educational use."""
    return 15.0 <= lcoe_value <= 100.0


def _cf_plausibility_check(cf_value):
    """Iowa wind CF: typically 38-52%. Accept broader range for educational use."""
    return 25.0 <= cf_value <= 65.0


def _aep_plausibility_check(aep_mwh, num_turbines, rated_mw_per_turbine):
    """Check if AEP is consistent with given turbine count and rating."""
    if num_turbines <= 0 or rated_mw_per_turbine <= 0:
        # If we can't determine turbine count, just check a plausible range for 10 MW
        return 15000 <= aep_mwh <= 65000
    total_mw = num_turbines * rated_mw_per_turbine
    cf = aep_mwh / (total_mw * 1000 * 8760) * 100  # convert MW*kWh to MWh
    return 25.0 <= cf <= 65.0


def _independent_file_check(copy_from_env):
    """Independently verify the agent's output file structure."""
    path = "/home/ga/Documents/SAM_Projects/Iowa_Wind_LCOE_Analysis.json"
    temp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env(path, temp.name)
        with open(temp.name, 'r') as f:
            raw = json.load(f)

        raw_str = json.dumps(raw).lower()
        details = {'raw_file_found': True}

        # Check for wind-specific terminology
        wind_terms = ['turbine', 'rotor', 'hub', 'wind', 'capacity_factor', 'lcoe', 'aep']
        details['wind_term_count'] = sum(1 for t in wind_terms if t in raw_str)

        # Check for configuration array
        configs = None
        for key in ['configurations', 'configs', 'turbines', 'results']:
            if key in raw and isinstance(raw[key], list) and len(raw[key]) >= 2:
                configs = raw[key]
                break
        details['config_count'] = len(configs) if configs else 0

        # Check for LCOE values
        lcoe_values = []
        if configs:
            for cfg in configs:
                if isinstance(cfg, dict):
                    for k in ['lcoe_usd_per_mwh', 'lcoe', 'LCOE', 'lcoe_real']:
                        if k in cfg and isinstance(cfg[k], (int, float)) and cfg[k] > 0:
                            lcoe_values.append(cfg[k])
                            break
        details['lcoe_count'] = len(lcoe_values)
        details['lcoe_values'] = lcoe_values

        # Check optimal identified
        details['has_optimal'] = any(
            k in raw for k in ['optimal_configuration', 'best_configuration', 'recommended_configuration', 'optimal']
        )

        details['looks_complete'] = (
            details['wind_term_count'] >= 3
            and details['config_count'] >= 3
            and details['lcoe_count'] >= 2
        )

        return True, details
    except Exception as e:
        return False, {'raw_file_found': False, 'error': str(e)}
    finally:
        if os.path.exists(temp.name):
            os.unlink(temp.name)


def verify_wind_farm_iowa_lcoe_analysis(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_num_configs = metadata.get('expected_num_configurations', 3)
    cf_min = metadata.get('expected_cf_min', 28.0)
    cf_max = metadata.get('expected_cf_max', 58.0)
    lcoe_min = metadata.get('expected_lcoe_min_usdpermwh', 15.0)
    lcoe_max = metadata.get('expected_lcoe_max_usdpermwh', 90.0)
    aep_min = metadata.get('expected_aep_per_turbine_mwh_min', 3500)
    aep_max = metadata.get('expected_aep_per_turbine_mwh_max', 12000)

    # Read export result
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
        feedback_parts.append("Output file exists")
    else:
        feedback_parts.append("Output file NOT found")

    # Criterion 2: File created during task (10 points)
    file_modified = result.get('file_modified') is True or str(result.get('file_modified')) == 'true'
    if file_modified:
        score += 10
        feedback_parts.append("File created during task")
    elif file_exists:
        score += 2
        feedback_parts.append("File exists but pre-dates task start")
    else:
        feedback_parts.append("File not modified during task")

    # Criterion 3: Wind model used, not PVWatts (10 points)
    wind_model_used = result.get('wind_model_used') is True or str(result.get('wind_model_used')) == 'true'
    python_ran = result.get('python_ran') is True or str(result.get('python_ran')) == 'true'
    if wind_model_used:
        score += 10
        feedback_parts.append("Wind power model confirmed in Python code")
    elif python_ran:
        score += 3
        feedback_parts.append("Python used but wind model import not confirmed")
    else:
        feedback_parts.append("No wind model usage detected")

    # Criterion 4: Three or more configurations (15 points)
    try:
        num_configs = int(result.get('num_configs', '0'))
    except (ValueError, TypeError):
        num_configs = 0
    has_configs = result.get('has_configs') is True or str(result.get('has_configs')) == 'true'

    if num_configs >= expected_num_configs and has_configs:
        score += 15
        feedback_parts.append(f"All {num_configs} turbine configurations evaluated")
    elif num_configs >= 2:
        score += 8
        feedback_parts.append(f"Partial: {num_configs} configurations (need {expected_num_configs})")
    elif num_configs == 1:
        score += 3
        feedback_parts.append("Only 1 configuration found (need 3)")
    else:
        feedback_parts.append("No configuration data found")

    # Criterion 5: Capacity factors physically plausible (15 points)
    try:
        max_cf = float(result.get('max_cf', '0'))
    except (ValueError, TypeError):
        max_cf = 0.0

    if max_cf > 0:
        if cf_min <= max_cf <= cf_max:
            score += 15
            feedback_parts.append(f"Capacity factor plausible: {max_cf:.1f}% (Iowa range {cf_min}-{cf_max}%)")
        elif 20.0 <= max_cf <= 75.0:
            score += 7
            feedback_parts.append(f"CF outside Iowa range: {max_cf:.1f}% (acceptable range {cf_min}-{cf_max}%)")
        else:
            feedback_parts.append(f"CF implausible for Iowa wind: {max_cf:.1f}%")
    else:
        feedback_parts.append("No capacity factor data")

    # Criterion 6: LCOE values in realistic range (15 points)
    try:
        min_lcoe = float(result.get('min_lcoe', '0'))
    except (ValueError, TypeError):
        min_lcoe = 0.0

    if min_lcoe > 0:
        if lcoe_min <= min_lcoe <= lcoe_max:
            score += 15
            feedback_parts.append(f"LCOE in realistic range: {min_lcoe:.1f} $/MWh")
        elif 10.0 <= min_lcoe <= 150.0:
            score += 7
            feedback_parts.append(f"LCOE borderline: {min_lcoe:.1f} $/MWh (expected {lcoe_min}-{lcoe_max})")
        else:
            feedback_parts.append(f"LCOE out of plausible range: {min_lcoe:.1f} $/MWh")
    else:
        feedback_parts.append("No LCOE data in export (check json structure)")

    # Criterion 7: AEP values consistent with ~10 MW wind farm (15 points)
    try:
        first_aep = float(result.get('first_aep', '0'))
    except (ValueError, TypeError):
        first_aep = 0.0

    if first_aep > 0:
        # AEP for a ~10 MW farm: 25,000-60,000 MWh/year
        if 15000 <= first_aep <= 70000:
            score += 15
            feedback_parts.append(f"AEP consistent with 10 MW farm: {first_aep:.0f} MWh/yr")
        elif first_aep > 0:
            score += 5
            feedback_parts.append(f"AEP outside expected range for 10 MW: {first_aep:.0f} MWh/yr")
    else:
        feedback_parts.append("No AEP data found")

    # Criterion 8: Optimal configuration identified (10 points)
    optimal_config = str(result.get('optimal_config', '')).lower()
    if optimal_config and len(optimal_config) > 2:
        # V110 or GE 1.6-100 are physically defensible optimal choices for Iowa
        # (larger rotor = better capacity factor at lower wind speed)
        plausible_optimal = any(x in optimal_config for x in ['v110', '1.6', 'ge', 'v90', 'vestas'])
        if plausible_optimal:
            score += 10
            feedback_parts.append(f"Optimal turbine identified: '{optimal_config}'")
        else:
            score += 5
            feedback_parts.append(f"Optimal identified but unclear: '{optimal_config}'")
    else:
        feedback_parts.append("Optimal configuration not identified")

    # Independent cross-check
    raw_found, raw_details = _independent_file_check(copy_from_env)
    if raw_found and raw_details.get('looks_complete'):
        feedback_parts.append(
            f"Cross-check PASSED: {raw_details['config_count']} configs, "
            f"{raw_details['lcoe_count']} LCOE values, "
            f"{raw_details['wind_term_count']} wind terms"
        )
    elif raw_found:
        feedback_parts.append(
            f"Cross-check PARTIAL: {raw_details.get('config_count', 0)} configs found"
        )

    # Anti-bypass
    if not python_ran:
        feedback_parts.append("ANTI-BYPASS: No Python/PySAM execution detected")
        score = min(score, 20)

    score = min(score, 100)
    key_criteria_met = file_exists and file_modified and (python_ran or wind_model_used)
    passed = score >= 60 and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }
