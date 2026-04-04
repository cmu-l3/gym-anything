#!/usr/bin/env python3
"""Verifier for configure_commercial_pv_system task.

Uses physics-based cross-checks AND independent file verification.
"""

import json
import tempfile
import os


def _physics_sanity_check(dc_size_kw, annual_kwh, location, array_type=0):
    """Check if reported energy is physically plausible."""
    if dc_size_kw <= 0 or annual_kwh <= 0:
        return False, "Missing values"

    cf = annual_kwh / (dc_size_kw * 8760) * 100

    location_lower = location.lower()
    if array_type == 2:
        if any(c in location_lower for c in ['daggett', 'blythe', 'imperial', 'phoenix', 'tucson']):
            cf_min, cf_max = 22, 32
        else:
            cf_min, cf_max = 16, 28
    else:
        if any(c in location_lower for c in ['daggett', 'blythe', 'imperial', 'phoenix', 'tucson']):
            cf_min, cf_max = 16, 26
        else:
            cf_min, cf_max = 12, 22

    if cf_min <= cf <= cf_max:
        return True, f"CF={cf:.1f}% plausible for {location} (tracking={array_type})"
    else:
        return False, f"CF={cf:.1f}% NOT plausible for {location} (expected {cf_min}-{cf_max}%)"


def _iter_values(obj):
    """Recursively iterate all leaf values in a JSON object."""
    if isinstance(obj, dict):
        for v in obj.values():
            yield from _iter_values(v)
    elif isinstance(obj, list):
        for v in obj:
            yield from _iter_values(v)
    else:
        yield obj


def _deep_find_numeric(obj, keys):
    """Recursively search for any of the given keys and return the first numeric value found."""
    if isinstance(obj, dict):
        for k, v in obj.items():
            if k.lower() in [key.lower() for key in keys] and isinstance(v, (int, float)):
                return v
            result = _deep_find_numeric(v, keys)
            if result is not None:
                return result
    elif isinstance(obj, list):
        for item in obj:
            result = _deep_find_numeric(item, keys)
            if result is not None:
                return result
    return None


def _independent_file_check(copy_from_env):
    """Copy the agent's actual output file and independently verify its contents."""
    path = "/home/ga/Documents/SAM_Projects/Daggett_Commercial_100kW.json"
    temp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env(path, temp.name)
        with open(temp.name, 'r') as f:
            raw = json.load(f)

        details = {'raw_file_found': True}
        raw_str = json.dumps(raw).lower()
        details['has_weather_ref'] = any(
            city in raw_str for city in ['daggett', 'psmv3', 'tmy']
        )

        numeric_count = sum(1 for v in _iter_values(raw) if isinstance(v, (int, float)))
        details['numeric_field_count'] = numeric_count
        details['looks_like_real_output'] = numeric_count >= 5 and details['has_weather_ref']

        details['ind_annual_kwh'] = _deep_find_numeric(raw, [
            'ac_annual_kwh', 'annual_energy', 'annual_energy_kwh', 'annual_kwh', 'ac_annual'
        ])
        details['ind_dc_size'] = _deep_find_numeric(raw, [
            'system_capacity_kw', 'system_capacity', 'dc_capacity_kw', 'dc_size_kw'
        ])

        return True, details
    except Exception:
        return False, {'raw_file_found': False}
    finally:
        if os.path.exists(temp.name):
            os.unlink(temp.name)


def verify_configure_commercial_pv_system(traj, env_info, task_info):
    """Verify commercial PV system was configured correctly.

    Scoring: 100 points max
    - File exists: 10
    - File created during task: 10
    - Location correct: 10
    - DC size correct: 10
    - Array type correct: 10
    - Module type correct: 10
    - Annual energy in range: 10
    - Capacity factor in range: 5
    - Physics check: 15
    - Independent file cross-check: 10
    """

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_location = metadata.get('expected_location', 'daggett')
    expected_dc_size_min = metadata.get('expected_dc_size_min', 95)
    expected_dc_size_max = metadata.get('expected_dc_size_max', 105)
    expected_array_type = metadata.get('expected_array_type', 2)
    expected_module_type = metadata.get('expected_module_type', 1)
    expected_annual_kwh_min = metadata.get('expected_annual_kwh_min', 200000)
    expected_annual_kwh_max = metadata.get('expected_annual_kwh_max', 260000)
    expected_cf_min = metadata.get('expected_capacity_factor_min', 23)
    expected_cf_max = metadata.get('expected_capacity_factor_max', 30)

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

    # Criterion 2: File was created during task (10 points)
    file_modified = result.get('file_modified') is True or str(result.get('file_modified')) == 'true'
    if file_modified:
        score += 10
        feedback_parts.append("File created during task")
    elif file_exists:
        feedback_parts.append("File exists but not created during task")
        score += 2
    else:
        feedback_parts.append("No file modification detected")

    # Criterion 3: Location matches Daggett (10 points)
    location_info = str(result.get('location_info', ''))
    if expected_location.lower() in location_info.lower():
        score += 10
        feedback_parts.append(f"Location correct: {location_info}")
    elif location_info:
        feedback_parts.append(f"Location mismatch: {location_info}")
        score += 1
    else:
        feedback_parts.append("No location info")

    # Criterion 4: DC system size correct (10 points)
    dc_size = 0
    try:
        dc_size = float(result.get('dc_size', '0'))
        if expected_dc_size_min <= dc_size <= expected_dc_size_max:
            score += 10
            feedback_parts.append(f"DC size correct: {dc_size} kW")
        elif dc_size > 0:
            feedback_parts.append(f"DC size wrong: {dc_size} kW")
            score += 1
        else:
            feedback_parts.append("DC size not found")
    except (ValueError, TypeError):
        feedback_parts.append("DC size parse error")

    # Criterion 5: Array type correct - 1-axis tracking (10 points)
    array_type = -1
    try:
        array_type = int(result.get('array_type', '-1'))
        if array_type == expected_array_type:
            score += 10
            feedback_parts.append(f"Array type correct: {array_type} (1-axis tracking)")
        elif array_type >= 0:
            feedback_parts.append(f"Array type wrong: {array_type} (expected {expected_array_type})")
            score += 1
        else:
            feedback_parts.append("Array type not found")
    except (ValueError, TypeError):
        feedback_parts.append("Array type parse error")

    # Criterion 6: Module type correct - Premium (10 points)
    try:
        module_type = int(result.get('module_type', '-1'))
        if module_type == expected_module_type:
            score += 10
            feedback_parts.append(f"Module type correct: {module_type} (Premium)")
        elif module_type >= 0:
            feedback_parts.append(f"Module type wrong: {module_type} (expected {expected_module_type})")
            score += 1
        else:
            feedback_parts.append("Module type not found")
    except (ValueError, TypeError):
        feedback_parts.append("Module type parse error")

    # Criterion 7: Annual energy in expected range (10 points)
    annual_kwh = 0
    try:
        annual_kwh = float(result.get('annual_kwh', '0'))
        if expected_annual_kwh_min <= annual_kwh <= expected_annual_kwh_max:
            score += 10
            feedback_parts.append(f"Annual energy: {annual_kwh:.0f} kWh")
        elif annual_kwh > 0:
            feedback_parts.append(f"Annual energy unexpected: {annual_kwh:.0f} kWh")
            score += 2
        else:
            feedback_parts.append("No simulation results")
    except (ValueError, TypeError):
        feedback_parts.append("Energy output parse error")

    # Criterion 8: Capacity factor in expected range (5 points)
    capacity_factor = 0
    try:
        capacity_factor = float(result.get('capacity_factor', '0'))
        if expected_cf_min <= capacity_factor <= expected_cf_max:
            score += 5
            feedback_parts.append(f"Capacity factor: {capacity_factor:.1f}%")
        elif capacity_factor > 0:
            feedback_parts.append(f"Capacity factor unexpected: {capacity_factor:.1f}%")
            score += 2
        else:
            feedback_parts.append("No capacity factor")
    except (ValueError, TypeError):
        feedback_parts.append("Capacity factor parse error")

    # Criterion 9: Physics sanity check (15 points)
    if dc_size > 0 and annual_kwh > 0:
        plausible, reason = _physics_sanity_check(
            dc_size, annual_kwh, expected_location,
            array_type if array_type >= 0 else 0
        )
        if plausible:
            score += 15
            feedback_parts.append(f"Physics check PASSED: {reason}")
        else:
            feedback_parts.append(f"Physics check FAILED: {reason}")
    else:
        feedback_parts.append("Physics check: insufficient data")

    # Criterion 10: Independent file cross-check (10 points)
    raw_found, raw_details = _independent_file_check(copy_from_env)
    if raw_found and raw_details.get('looks_like_real_output'):
        ind_kwh = raw_details.get('ind_annual_kwh')
        if ind_kwh and annual_kwh > 0 and abs(ind_kwh - annual_kwh) / annual_kwh < 0.01:
            score += 10
            feedback_parts.append(f"Independent cross-check PASSED: {raw_details['numeric_field_count']} numeric fields, weather ref found")
        elif ind_kwh and annual_kwh > 0:
            score += 5
            feedback_parts.append(f"Independent cross-check PARTIAL: values differ ({ind_kwh:.0f} vs {annual_kwh:.0f})")
        else:
            score += 5
            feedback_parts.append("Independent cross-check: file looks real but couldn't extract energy")
    elif raw_found:
        score += 1
        feedback_parts.append(f"Independent cross-check WARN: file found but missing weather ref or few fields ({raw_details.get('numeric_field_count', 0)})")
    else:
        feedback_parts.append("Independent cross-check: could not copy agent's output file")

    # Anti-bypass: verify Python was actually used during the task
    python_ran = result.get('python_ran') is True or str(result.get('python_ran')) == 'true'
    if not python_ran:
        feedback_parts.append("ANTI-BYPASS: No evidence Python was executed during task")
        score = min(score, 20)

    score = min(score, 100)
    key_criteria_met = file_exists and file_modified and python_ran
    passed = score >= 70 and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }
