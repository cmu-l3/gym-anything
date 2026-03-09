#!/usr/bin/env python3
"""Verifier for utility_pv_module_technology_lcoe task.

Tests whether the agent correctly used PySAM.Pvsamv1 (detailed PV model)
to compare three module technologies (Mono-Si, HJT, CdTe) for a 50 MW
utility-scale PV project in Daggett, CA, computing LCOE and NPV for each.

Scoring (100 points):
- File exists: 10
- File created during task: 10
- Pvsamv1 detailed model used (not just PVWatts): 15
- Three module technologies evaluated: 15
- Capacity factors physically plausible for Daggett utility PV (22-35%): 15
- LCOE values in realistic utility PV range (20-80 $/MWh): 15
- AEP values consistent with 50 MW utility plant: 10
- Optimal technology identified: 10

Pass threshold: 60 points AND (file_exists AND file_modified AND python_ran)
"""

import json
import os
import tempfile


def _independent_file_check(copy_from_env):
    """Independently verify the agent's output file structure."""
    path = "/home/ga/Documents/SAM_Projects/Daggett_Module_Technology_LCOE.json"
    temp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env(path, temp.name)
        with open(temp.name, 'r') as f:
            raw = json.load(f)

        raw_str = json.dumps(raw).lower()
        details = {'raw_file_found': True}

        # Check for module-technology specific terminology
        tech_terms = ['module_efficiency', 'module_price', 'lcoe', 'capacity_factor',
                      'mono', 'hjt', 'cdte', 'thin_film', 'heterojunction', 'tech_a', 'tech_b', 'tech_c']
        details['tech_term_count'] = sum(1 for t in tech_terms if t in raw_str)

        # Check for configurations array
        configs = None
        for key in ['configurations', 'configs', 'results', 'technologies']:
            if key in raw and isinstance(raw[key], list) and len(raw[key]) >= 2:
                configs = raw[key]
                break
        details['config_count'] = len(configs) if configs else 0

        # Check LCOE values
        lcoe_values = []
        if configs:
            for cfg in configs:
                if isinstance(cfg, dict):
                    for k in ['lcoe_real_usd_per_mwh', 'lcoe_real', 'lcoe', 'LCOE']:
                        v = cfg.get(k)
                        if v and isinstance(v, (int, float)) and v > 0:
                            val = float(v)
                            if val < 5:
                                val *= 10  # cents/kWh -> $/MWh
                            lcoe_values.append(val)
                            break
        details['lcoe_count'] = len(lcoe_values)
        details['lcoe_values'] = lcoe_values

        # Check tech names for variety
        tech_names = []
        if configs:
            for cfg in configs:
                if isinstance(cfg, dict):
                    name = cfg.get('tech_name') or cfg.get('name') or cfg.get('technology') or ''
                    if name:
                        tech_names.append(str(name).lower()[:50])
        details['tech_names'] = tech_names

        # Check optimal identified
        details['has_optimal'] = any(
            k in raw for k in ['optimal_technology', 'best_technology', 'optimal_tech', 'optimal']
        )

        details['looks_complete'] = (
            details['tech_term_count'] >= 3
            and details['config_count'] >= 3
            and details['lcoe_count'] >= 2
            and details['has_optimal']
        )

        return True, details
    except Exception as e:
        return False, {'raw_file_found': False, 'error': str(e)}
    finally:
        if os.path.exists(temp.name):
            os.unlink(temp.name)


def verify_utility_pv_module_technology_lcoe(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_num_tech = metadata.get('expected_num_technologies', 3)
    cf_min = metadata.get('expected_cf_min_pct', 22.0)
    cf_max = metadata.get('expected_cf_max_pct', 35.0)
    lcoe_min = metadata.get('expected_lcoe_min_usdpermwh', 20.0)
    lcoe_max = metadata.get('expected_lcoe_max_usdpermwh', 80.0)
    aep_min = metadata.get('expected_aep_min_mwh', 90000)
    aep_max = metadata.get('expected_aep_max_mwh', 160000)

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

    # Criterion 3: Pvsamv1 detailed model used (15 points - weighted higher)
    pvsamv1_used = result.get('pvsamv1_used') is True or str(result.get('pvsamv1_used')) == 'true'
    python_ran = result.get('python_ran') is True or str(result.get('python_ran')) == 'true'
    if pvsamv1_used:
        score += 15
        feedback_parts.append("Pvsamv1 detailed PV model confirmed (CEC parameters used)")
    elif python_ran:
        score += 5
        feedback_parts.append("Python used but Pvsamv1/CEC model not confirmed (PVWatts may have been used instead)")
    else:
        feedback_parts.append("No detailed PV model usage detected")

    # Criterion 4: Three module technologies evaluated (15 points)
    try:
        num_tech = int(result.get('num_technologies', '0'))
    except (ValueError, TypeError):
        num_tech = 0
    has_configs = result.get('has_configs') is True or str(result.get('has_configs')) == 'true'

    if num_tech >= expected_num_tech and has_configs:
        score += 15
        feedback_parts.append(f"All {num_tech} module technologies evaluated")
    elif num_tech == 2:
        score += 8
        feedback_parts.append(f"Partial: {num_tech} technologies (need {expected_num_tech})")
    elif num_tech == 1:
        score += 3
        feedback_parts.append("Only 1 technology found (need 3)")
    else:
        feedback_parts.append("No module technology data found")

    # Criterion 5: Capacity factors physically plausible for Daggett utility PV (15 points)
    try:
        max_cf = float(result.get('max_cf', '0'))
    except (ValueError, TypeError):
        max_cf = 0.0

    if max_cf > 0:
        if cf_min <= max_cf <= cf_max:
            score += 15
            feedback_parts.append(f"CF plausible for Daggett utility PV: {max_cf:.1f}% (expected {cf_min}-{cf_max}%)")
        elif 15.0 <= max_cf <= 45.0:
            score += 7
            feedback_parts.append(f"CF outside expected range: {max_cf:.1f}% (expected {cf_min}-{cf_max}%)")
        else:
            feedback_parts.append(f"CF implausible for utility PV: {max_cf:.1f}%")
    else:
        feedback_parts.append("No capacity factor data found")

    # Criterion 6: LCOE in realistic utility PV range (15 points)
    try:
        min_lcoe = float(result.get('min_lcoe', '0'))
    except (ValueError, TypeError):
        min_lcoe = 0.0

    if min_lcoe > 0:
        if lcoe_min <= min_lcoe <= lcoe_max:
            score += 15
            feedback_parts.append(f"LCOE in realistic utility PV range: {min_lcoe:.1f} $/MWh")
        elif 10.0 <= min_lcoe <= 150.0:
            score += 7
            feedback_parts.append(f"LCOE borderline for utility PV: {min_lcoe:.1f} $/MWh (expected {lcoe_min}-{lcoe_max})")
        else:
            feedback_parts.append(f"LCOE outside plausible utility PV range: {min_lcoe:.1f} $/MWh")
    else:
        feedback_parts.append("No LCOE data found (check JSON structure)")

    # Criterion 7: AEP consistent with 50 MW utility PV (10 points)
    try:
        first_aep = float(result.get('first_aep', '0'))
    except (ValueError, TypeError):
        first_aep = 0.0

    if first_aep > 0:
        if aep_min <= first_aep <= aep_max:
            score += 10
            feedback_parts.append(f"AEP consistent with 50 MW utility PV: {first_aep:.0f} MWh/yr")
        elif first_aep > 0:
            score += 3
            feedback_parts.append(f"AEP outside expected range for 50 MW: {first_aep:.0f} MWh/yr")
    else:
        feedback_parts.append("No AEP data found")

    # Criterion 8: Optimal technology identified (10 points)
    optimal_tech = str(result.get('optimal_technology', '')).lower()
    if optimal_tech and len(optimal_tech) > 3:
        # CdTe (Tech C) often has lowest LCOE due to lower module price + good temp coefficient at Daggett
        # HJT (Tech B) may win on energy production but higher upfront cost
        plausible_optimal = any(x in optimal_tech for x in
                                ['cdte', 'thin_film', 'tech c', 'tech_c', 'c -', 'tech a', 'tech_a',
                                 'mono', 'hjt', 'tech b', 'tech_b', 'a -', 'b -'])
        if plausible_optimal:
            score += 10
            feedback_parts.append(f"Optimal technology identified: '{optimal_tech[:60]}'")
        else:
            score += 5
            feedback_parts.append(f"Optimal identified but unclear: '{optimal_tech[:60]}'")
    else:
        feedback_parts.append("Optimal module technology not identified")

    # Independent cross-check
    raw_found, raw_details = _independent_file_check(copy_from_env)
    if raw_found and raw_details.get('looks_complete'):
        feedback_parts.append(
            f"Cross-check PASSED: {raw_details['config_count']} techs, "
            f"LCOEs {[f'{v:.1f}' for v in raw_details.get('lcoe_values', [])]}, "
            f"{raw_details['tech_term_count']} tech terms"
        )
    elif raw_found:
        feedback_parts.append(
            f"Cross-check PARTIAL: {raw_details.get('config_count', 0)} techs found, "
            f"{raw_details.get('tech_term_count', 0)} tech terms"
        )

    # Anti-bypass
    if not python_ran:
        feedback_parts.append("ANTI-BYPASS: No Python/PySAM execution detected")
        score = min(score, 20)

    score = min(score, 100)
    key_criteria_met = file_exists and file_modified and python_ran
    passed = score >= 60 and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }
