#!/usr/bin/env python3
"""Verifier for csp_parabolic_trough_solar_multiple task.

Tests whether the agent correctly modeled a 50 MW CSP parabolic trough plant
in Daggett, CA and systematically swept solar multiples 1.0-3.0 to find the
NPV-optimal configuration with 6-hour TES.

Scoring (100 points):
- File exists: 10
- File created during task: 10
- CSP model used (not PVWatts): 10
- 7 or more SM values evaluated: 15
- Capacity factors physically plausible for CSP (25-75%): 15
- LCOE values in realistic CSP range (60-350 $/MWh): 15
- AEP values consistent with ~50 MW CSP plant: 15
- Optimal SM identified and within plausible range (1.5-2.75): 10

Pass threshold: 60 points AND (file_exists AND file_modified AND (python_ran OR csp_model_used))
"""

import json
import os
import tempfile


def _independent_file_check(copy_from_env):
    """Independently verify the agent's output file structure."""
    path = "/home/ga/Documents/SAM_Projects/Daggett_CSP_SM_Analysis.json"
    temp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env(path, temp.name)
        with open(temp.name, 'r') as f:
            raw = json.load(f)

        raw_str = json.dumps(raw).lower()
        details = {'raw_file_found': True}

        # Check for CSP-specific terminology
        csp_terms = ['solar_multiple', 'trough', 'csp', 'capacity_factor', 'lcoe', 'annual_energy', 'tshours', 'tes']
        details['csp_term_count'] = sum(1 for t in csp_terms if t in raw_str)

        # Check for configurations array
        configs = None
        for key in ['configurations', 'configs', 'results', 'simulations']:
            if key in raw and isinstance(raw[key], list) and len(raw[key]) >= 2:
                configs = raw[key]
                break
        details['config_count'] = len(configs) if configs else 0

        # Check for SM range coverage (1.0 to 3.0)
        sm_values = []
        if configs:
            for cfg in configs:
                if isinstance(cfg, dict):
                    for k in ['solar_multiple', 'sm', 'solar_mult']:
                        v = cfg.get(k)
                        if v is not None and isinstance(v, (int, float)) and 0.5 <= v <= 4.0:
                            sm_values.append(float(v))
                            break
        details['sm_values'] = sorted(sm_values)
        details['sm_range'] = (min(sm_values), max(sm_values)) if sm_values else (0, 0)

        # Check for LCOE values
        lcoe_values = []
        if configs:
            for cfg in configs:
                if isinstance(cfg, dict):
                    for k in ['lcoe_real_usd_per_mwh', 'lcoe_real', 'lcoe', 'LCOE', 'lcoe_usd_per_mwh']:
                        v = cfg.get(k)
                        if v is not None and isinstance(v, (int, float)) and v > 0:
                            lcoe_values.append(float(v))
                            break
        details['lcoe_count'] = len(lcoe_values)

        # Check optimal SM identified
        details['has_optimal'] = any(
            k in raw for k in ['optimal_solar_multiple', 'optimal_sm', 'best_solar_multiple', 'optimal']
        )

        details['looks_complete'] = (
            details['csp_term_count'] >= 3
            and details['config_count'] >= 7
            and details['lcoe_count'] >= 5
            and details['has_optimal']
        )

        return True, details
    except Exception as e:
        return False, {'raw_file_found': False, 'error': str(e)}
    finally:
        if os.path.exists(temp.name):
            os.unlink(temp.name)


def verify_csp_parabolic_trough_solar_multiple(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_num_sm = metadata.get('expected_num_sm_values', 9)
    cf_min = metadata.get('expected_cf_min_pct', 25.0)
    cf_max = metadata.get('expected_cf_max_pct', 75.0)
    lcoe_min = metadata.get('expected_lcoe_min_usdpermwh', 60.0)
    lcoe_max = metadata.get('expected_lcoe_max_usdpermwh', 350.0)
    aep_min = metadata.get('expected_aep_min_mwh', 80000)
    aep_max = metadata.get('expected_aep_max_mwh', 350000)
    opt_sm_low = metadata.get('optimal_sm_range_low', 1.5)
    opt_sm_high = metadata.get('optimal_sm_range_high', 2.75)

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

    # Criterion 3: CSP model used (10 points)
    csp_model_used = result.get('csp_model_used') is True or str(result.get('csp_model_used')) == 'true'
    python_ran = result.get('python_ran') is True or str(result.get('python_ran')) == 'true'
    if csp_model_used:
        score += 10
        feedback_parts.append("CSP parabolic trough model confirmed in Python code")
    elif python_ran:
        score += 3
        feedback_parts.append("Python used but CSP model import not confirmed")
    else:
        feedback_parts.append("No CSP model usage detected")

    # Criterion 4: 7+ SM values evaluated (15 points)
    try:
        num_sm = int(result.get('num_sm_values', '0'))
    except (ValueError, TypeError):
        num_sm = 0
    has_configs = result.get('has_configs') is True or str(result.get('has_configs')) == 'true'

    if num_sm >= expected_num_sm and has_configs:
        score += 15
        feedback_parts.append(f"All {num_sm} solar multiple configurations evaluated")
    elif num_sm >= 7:
        score += 12
        feedback_parts.append(f"Good coverage: {num_sm} SM values (expected {expected_num_sm})")
    elif num_sm >= 5:
        score += 8
        feedback_parts.append(f"Partial: {num_sm} SM values (expected {expected_num_sm})")
    elif num_sm >= 3:
        score += 4
        feedback_parts.append(f"Minimal: {num_sm} SM values (need {expected_num_sm})")
    else:
        feedback_parts.append(f"Insufficient SM values: {num_sm}")

    # Criterion 5: Capacity factors physically plausible for CSP (15 points)
    try:
        max_cf = float(result.get('max_cf', '0'))
    except (ValueError, TypeError):
        max_cf = 0.0

    if max_cf > 0:
        if cf_min <= max_cf <= cf_max:
            score += 15
            feedback_parts.append(f"Capacity factor plausible for CSP: {max_cf:.1f}% (range {cf_min}-{cf_max}%)")
        elif 15.0 <= max_cf <= 85.0:
            score += 7
            feedback_parts.append(f"CF outside expected CSP range: {max_cf:.1f}% (acceptable {cf_min}-{cf_max}%)")
        else:
            feedback_parts.append(f"CF implausible for CSP: {max_cf:.1f}%")
    else:
        feedback_parts.append("No capacity factor data found")

    # Criterion 6: LCOE values in realistic CSP range (15 points)
    try:
        min_lcoe = float(result.get('min_lcoe', '0'))
    except (ValueError, TypeError):
        min_lcoe = 0.0

    if min_lcoe > 0:
        if lcoe_min <= min_lcoe <= lcoe_max:
            score += 15
            feedback_parts.append(f"LCOE in realistic CSP range: {min_lcoe:.1f} $/MWh")
        elif 30.0 <= min_lcoe <= 500.0:
            score += 7
            feedback_parts.append(f"LCOE borderline for CSP: {min_lcoe:.1f} $/MWh (expected {lcoe_min}-{lcoe_max})")
        else:
            feedback_parts.append(f"LCOE outside plausible CSP range: {min_lcoe:.1f} $/MWh")
    else:
        feedback_parts.append("No LCOE data found (check JSON structure)")

    # Criterion 7: AEP consistent with 50 MW CSP plant (15 points)
    try:
        first_aep = float(result.get('first_aep', '0'))
    except (ValueError, TypeError):
        first_aep = 0.0

    if first_aep > 0:
        if aep_min <= first_aep <= aep_max:
            score += 15
            feedback_parts.append(f"AEP consistent with 50 MW CSP plant: {first_aep:.0f} MWh/yr")
        elif first_aep > 0:
            score += 5
            feedback_parts.append(f"AEP outside expected range for 50 MW: {first_aep:.0f} MWh/yr")
    else:
        feedback_parts.append("No AEP data found")

    # Criterion 8: Optimal SM identified within plausible range (10 points)
    try:
        optimal_sm = float(result.get('optimal_sm', '0'))
    except (ValueError, TypeError):
        optimal_sm = 0.0

    if optimal_sm > 0:
        if opt_sm_low <= optimal_sm <= opt_sm_high:
            score += 10
            feedback_parts.append(f"Optimal SM identified in plausible range: {optimal_sm:.2f} (expected {opt_sm_low}-{opt_sm_high})")
        elif 1.0 <= optimal_sm <= 3.0:
            score += 5
            feedback_parts.append(f"Optimal SM identified but outside expected range: {optimal_sm:.2f}")
        else:
            feedback_parts.append(f"Optimal SM value implausible: {optimal_sm:.2f}")
    else:
        feedback_parts.append("Optimal solar multiple not identified")

    # Independent cross-check
    raw_found, raw_details = _independent_file_check(copy_from_env)
    if raw_found and raw_details.get('looks_complete'):
        sm_range = raw_details.get('sm_range', (0, 0))
        feedback_parts.append(
            f"Cross-check PASSED: {raw_details['config_count']} configs, "
            f"SM range {sm_range[0]:.2f}-{sm_range[1]:.2f}, "
            f"{raw_details['lcoe_count']} LCOE values, "
            f"{raw_details['csp_term_count']} CSP terms"
        )
    elif raw_found:
        feedback_parts.append(
            f"Cross-check PARTIAL: {raw_details.get('config_count', 0)} configs, "
            f"{raw_details.get('csp_term_count', 0)} CSP terms found"
        )

    # Anti-bypass: cap score if Python didn't run
    if not python_ran:
        feedback_parts.append("ANTI-BYPASS: No Python/PySAM execution detected")
        score = min(score, 20)

    score = min(score, 100)
    key_criteria_met = file_exists and file_modified and (python_ran or csp_model_used)
    passed = score >= 60 and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }
