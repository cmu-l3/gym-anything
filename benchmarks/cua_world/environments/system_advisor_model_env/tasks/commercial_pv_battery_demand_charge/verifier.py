#!/usr/bin/env python3
"""Verifier for commercial_pv_battery_demand_charge task.

Tests whether the agent correctly modeled a 250 kW commercial PV + battery
system in Denver, CO and compared 3 battery configurations for demand charge
reduction, including NPV, payback, and financial metrics.

Scoring (100 points):
- File exists: 10
- File created during task: 10
- Battery model used (PySAM Battery / Utilityrate): 10
- Three battery configurations evaluated: 15
- Demand charge savings physically plausible ($5k-$120k/yr): 15
- NPV values span a realistic commercial range: 15
- Payback period in realistic range (2-30 years): 15
- Optimal configuration identified: 10

Pass threshold: 60 points AND (file_exists AND file_modified AND (python_ran OR battery_model_used))
"""

import json
import os
import tempfile


def _independent_file_check(copy_from_env):
    """Independently verify the agent's output file structure."""
    path = "/home/ga/Documents/SAM_Projects/Denver_Commercial_Battery_Analysis.json"
    temp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env(path, temp.name)
        with open(temp.name, 'r') as f:
            raw = json.load(f)

        raw_str = json.dumps(raw).lower()
        details = {'raw_file_found': True}

        # Check for battery-specific terminology
        batt_terms = ['battery', 'demand_charge', 'payback', 'npv', 'savings', 'battery_kwh', 'irr']
        details['batt_term_count'] = sum(1 for t in batt_terms if t in raw_str)

        # Check for configurations array
        configs = None
        for key in ['configurations', 'configs', 'results']:
            if key in raw and isinstance(raw[key], list) and len(raw[key]) >= 2:
                configs = raw[key]
                break
        details['config_count'] = len(configs) if configs else 0

        # Check for NPV values
        npv_values = []
        if configs:
            for cfg in configs:
                if isinstance(cfg, dict):
                    for k in ['npv_25yr_usd', 'npv_usd', 'npv', 'NPV']:
                        v = cfg.get(k)
                        if v is not None and isinstance(v, (int, float)):
                            npv_values.append(float(v))
                            break
        details['npv_count'] = len(npv_values)

        # Check battery sizes present
        kwh_values = []
        if configs:
            for cfg in configs:
                if isinstance(cfg, dict):
                    v = cfg.get('battery_kwh') or cfg.get('batt_kwh') or cfg.get('capacity_kwh')
                    if v and isinstance(v, (int, float)):
                        kwh_values.append(float(v))
        details['battery_sizes'] = sorted(kwh_values)

        # Check optimal identified
        details['has_optimal'] = any(
            k in raw for k in ['optimal_configuration', 'best_configuration', 'optimal', 'recommended']
        )

        details['looks_complete'] = (
            details['batt_term_count'] >= 3
            and details['config_count'] >= 3
            and details['npv_count'] >= 2
            and details['has_optimal']
        )

        return True, details
    except Exception as e:
        return False, {'raw_file_found': False, 'error': str(e)}
    finally:
        if os.path.exists(temp.name):
            os.unlink(temp.name)


def verify_commercial_pv_battery_demand_charge(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_num_configs = metadata.get('expected_num_configs', 3)
    demand_savings_min = metadata.get('expected_demand_savings_min_usd', 5000)
    demand_savings_max = metadata.get('expected_demand_savings_max_usd', 120000)
    npv_low = metadata.get('expected_npv_range_low_usd', -500000)
    npv_high = metadata.get('expected_npv_range_high_usd', 500000)
    payback_min = metadata.get('expected_payback_min_yr', 2.0)
    payback_max = metadata.get('expected_payback_max_yr', 30.0)

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

    # Criterion 3: Battery model used (10 points)
    battery_model_used = result.get('battery_model_used') is True or str(result.get('battery_model_used')) == 'true'
    python_ran = result.get('python_ran') is True or str(result.get('python_ran')) == 'true'
    if battery_model_used:
        score += 10
        feedback_parts.append("Battery/Utilityrate model confirmed in Python code")
    elif python_ran:
        score += 3
        feedback_parts.append("Python used but Battery model import not confirmed")
    else:
        feedback_parts.append("No Battery model usage detected")

    # Criterion 4: Three configurations evaluated (15 points)
    try:
        num_configs = int(result.get('num_configs', '0'))
    except (ValueError, TypeError):
        num_configs = 0
    has_configs = result.get('has_configs') is True or str(result.get('has_configs')) == 'true'

    if num_configs >= expected_num_configs and has_configs:
        score += 15
        feedback_parts.append(f"All {num_configs} battery configurations evaluated")
    elif num_configs == 2:
        score += 8
        feedback_parts.append(f"Partial: {num_configs} configurations (need {expected_num_configs})")
    elif num_configs == 1:
        score += 4
        feedback_parts.append("Only 1 battery configuration found (need 3)")
    else:
        feedback_parts.append("No battery configuration data found")

    # Criterion 5: Demand charge savings physically plausible (15 points)
    try:
        first_demand_savings = float(result.get('first_demand_savings', '0'))
    except (ValueError, TypeError):
        first_demand_savings = 0.0

    if first_demand_savings != 0:
        # Allow negative (if battery doesn't help much) but check absolute magnitude
        abs_savings = abs(first_demand_savings)
        if demand_savings_min <= abs_savings <= demand_savings_max:
            score += 15
            feedback_parts.append(f"Demand savings plausible: ${first_demand_savings:,.0f}/yr")
        elif 500 <= abs_savings <= 300000:
            score += 7
            feedback_parts.append(f"Demand savings outside expected range: ${first_demand_savings:,.0f}/yr")
        else:
            feedback_parts.append(f"Demand savings implausible: ${first_demand_savings:,.0f}/yr")
    else:
        feedback_parts.append("No demand charge savings data found")

    # Criterion 6: NPV values in realistic commercial range (15 points)
    try:
        max_npv = float(result.get('max_npv', '0'))
    except (ValueError, TypeError):
        max_npv = 0.0

    if max_npv != 0:
        if npv_low <= max_npv <= npv_high:
            score += 15
            feedback_parts.append(f"NPV in realistic commercial range: ${max_npv:,.0f}")
        elif -2000000 <= max_npv <= 2000000:
            score += 7
            feedback_parts.append(f"NPV borderline for commercial: ${max_npv:,.0f}")
        else:
            feedback_parts.append(f"NPV outside plausible range: ${max_npv:,.0f}")
    else:
        feedback_parts.append("No NPV data found")

    # Criterion 7: Payback period in realistic range (15 points)
    try:
        min_payback = float(result.get('min_payback', '0'))
    except (ValueError, TypeError):
        min_payback = 0.0

    if min_payback > 0:
        if payback_min <= min_payback <= payback_max:
            score += 15
            feedback_parts.append(f"Payback period realistic: {min_payback:.1f} years")
        elif 0.5 <= min_payback <= 50.0:
            score += 7
            feedback_parts.append(f"Payback borderline: {min_payback:.1f} years (expected {payback_min}-{payback_max})")
        else:
            feedback_parts.append(f"Payback period implausible: {min_payback:.1f} years")
    else:
        feedback_parts.append("No payback period data found")

    # Criterion 8: Optimal configuration identified (10 points)
    optimal_config = str(result.get('optimal_config', '')).lower()
    if optimal_config and len(optimal_config) > 3:
        # Any of the three configs is a defensible answer depending on assumptions
        plausible_optimal = any(x in optimal_config for x in ['100', '200', '400', 'config', 'kwh', 'kw'])
        if plausible_optimal:
            score += 10
            feedback_parts.append(f"Optimal battery configuration identified: '{optimal_config[:60]}'")
        else:
            score += 5
            feedback_parts.append(f"Optimal identified but unclear: '{optimal_config[:60]}'")
    else:
        feedback_parts.append("Optimal battery configuration not identified")

    # Independent cross-check
    raw_found, raw_details = _independent_file_check(copy_from_env)
    if raw_found and raw_details.get('looks_complete'):
        feedback_parts.append(
            f"Cross-check PASSED: {raw_details['config_count']} configs, "
            f"battery sizes {raw_details.get('battery_sizes', [])}, "
            f"{raw_details['npv_count']} NPV values, "
            f"{raw_details['batt_term_count']} battery terms"
        )
    elif raw_found:
        feedback_parts.append(
            f"Cross-check PARTIAL: {raw_details.get('config_count', 0)} configs, "
            f"{raw_details.get('batt_term_count', 0)} battery terms"
        )

    # Anti-bypass
    if not python_ran:
        feedback_parts.append("ANTI-BYPASS: No Python/PySAM execution detected")
        score = min(score, 20)

    score = min(score, 100)
    key_criteria_met = file_exists and file_modified and (python_ran or battery_model_used)
    passed = score >= 60 and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }
