#!/usr/bin/env python3
"""Verifier for analyze_pv_tilt_sensitivity task.

Uses physics-based cross-checks AND independent file verification.
"""

import json
import tempfile
import os


def _physics_sanity_check(dc_size_kw, annual_kwh, location):
    """Check if reported energy is physically plausible."""
    if dc_size_kw <= 0 or annual_kwh <= 0:
        return False, "Missing values"

    cf = annual_kwh / (dc_size_kw * 8760) * 100

    location_lower = location.lower()
    if any(c in location_lower for c in ['phoenix', 'tucson', 'daggett', 'blythe', 'imperial']):
        cf_min, cf_max = 16, 26
    elif any(c in location_lower for c in ['des moines', 'fargo']):
        cf_min, cf_max = 12, 20
    else:
        cf_min, cf_max = 10, 28

    if cf_min <= cf <= cf_max:
        return True, f"CF={cf:.1f}% plausible for {location}"
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


def _independent_file_check(copy_from_env):
    """Copy the agent's actual output file and independently verify its contents."""
    path = "/home/ga/Documents/SAM_Projects/Tucson_Tilt_Analysis.json"
    temp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env(path, temp.name)
        with open(temp.name, 'r') as f:
            raw = json.load(f)

        details = {'raw_file_found': True}
        raw_str = json.dumps(raw).lower()
        details['has_weather_ref'] = any(
            city in raw_str for city in ['tucson', 'psmv3', 'tmy']
        )

        numeric_count = sum(1 for v in _iter_values(raw) if isinstance(v, (int, float)))
        details['numeric_field_count'] = numeric_count

        # Look for an array with multiple tilt entries (sign of real sweep)
        tilt_array_len = 0
        for key in ['tilt_results', 'results', 'tilt_sweep', 'data']:
            if key in raw and isinstance(raw[key], list):
                tilt_array_len = len(raw[key])
                break
        details['tilt_array_len'] = tilt_array_len
        details['looks_like_real_output'] = tilt_array_len >= 5 and details['has_weather_ref']

        return True, details
    except Exception:
        return False, {'raw_file_found': False}
    finally:
        if os.path.exists(temp.name):
            os.unlink(temp.name)


def verify_analyze_pv_tilt_sensitivity(traj, env_info, task_info):
    """Verify PV tilt sensitivity analysis was completed successfully.

    Scoring: 100 points max
    - File exists: 10
    - File created during task: 10
    - Location correct: 10
    - Tilt results array: 15
    - Optimal tilt in range: 10
    - Optimal kWh in range: 10
    - Physics check: 10
    - Curve shape check: 10
    - Independent file cross-check: 15
    """

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_location = metadata.get('expected_location', 'tucson')
    expected_optimal_tilt_min = metadata.get('expected_optimal_tilt_min', 25)
    expected_optimal_tilt_max = metadata.get('expected_optimal_tilt_max', 40)
    expected_num_tilts_min = metadata.get('expected_num_tilts_min', 10)
    expected_optimal_kwh_min = metadata.get('expected_optimal_kwh_min', 8500)
    expected_optimal_kwh_max = metadata.get('expected_optimal_kwh_max', 9500)

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

    # Criterion 3: Location matches Tucson (10 points)
    location_info = str(result.get('location_info', ''))
    if expected_location.lower() in location_info.lower():
        score += 10
        feedback_parts.append(f"Location correct: {location_info}")
    elif location_info:
        feedback_parts.append(f"Location mismatch: {location_info}")
        score += 1
    else:
        feedback_parts.append("No location info")

    # Criterion 4: Has tilt results array with sufficient entries (15 points)
    has_tilt_results = result.get('has_tilt_results') is True or str(result.get('has_tilt_results')) == 'true'
    try:
        num_tilts = int(result.get('num_tilts', '0'))
    except (ValueError, TypeError):
        num_tilts = 0

    if has_tilt_results and num_tilts >= expected_num_tilts_min:
        score += 15
        feedback_parts.append(f"Tilt results: {num_tilts} data points")
    elif has_tilt_results and num_tilts > 0:
        score += 7
        feedback_parts.append(f"Tilt results incomplete: {num_tilts} data points (need {expected_num_tilts_min}+)")
    else:
        feedback_parts.append("No tilt results array found")

    # Criterion 5: Optimal tilt in expected range (10 points)
    optimal_tilt = 0
    try:
        optimal_tilt = float(result.get('optimal_tilt', '0'))
        if expected_optimal_tilt_min <= optimal_tilt <= expected_optimal_tilt_max:
            score += 10
            feedback_parts.append(f"Optimal tilt correct: {optimal_tilt} deg")
        elif optimal_tilt > 0:
            feedback_parts.append(f"Optimal tilt outside range: {optimal_tilt} deg (expected {expected_optimal_tilt_min}-{expected_optimal_tilt_max})")
            score += 2
        else:
            feedback_parts.append("Optimal tilt not found")
    except (ValueError, TypeError):
        feedback_parts.append("Optimal tilt parse error")

    # Criterion 6: Optimal annual kWh in expected range (10 points)
    optimal_kwh = 0
    try:
        optimal_kwh = float(result.get('optimal_kwh', '0'))
        if expected_optimal_kwh_min <= optimal_kwh <= expected_optimal_kwh_max:
            score += 10
            feedback_parts.append(f"Optimal energy: {optimal_kwh:.0f} kWh")
        elif optimal_kwh > 0:
            feedback_parts.append(f"Optimal energy unexpected: {optimal_kwh:.0f} kWh")
            score += 2
        else:
            feedback_parts.append("No optimal energy result")
    except (ValueError, TypeError):
        feedback_parts.append("Energy output parse error")

    # Criterion 7: Physics sanity check (10 points)
    dc_size = 5.0
    if optimal_kwh > 0:
        plausible, reason = _physics_sanity_check(dc_size, optimal_kwh, expected_location)
        if plausible:
            score += 10
            feedback_parts.append(f"Physics check PASSED: {reason}")
        else:
            feedback_parts.append(f"Physics check FAILED: {reason}")
    else:
        feedback_parts.append("Physics check: no energy data")

    # Criterion 8: Tilt curve shape check (10 points)
    # Requires interior optimum AND that it's in a physically reasonable range for the latitude
    # Tucson is ~32N, so optimal should be near latitude (25-40 deg)
    if expected_optimal_tilt_min <= optimal_tilt <= expected_optimal_tilt_max and num_tilts >= expected_num_tilts_min:
        score += 10
        feedback_parts.append(f"Curve shape check PASSED: interior optimum at {optimal_tilt} deg with {num_tilts} sweep points")
    elif 10 < optimal_tilt < 50 and num_tilts >= 5:
        score += 5
        feedback_parts.append(f"Curve shape check PARTIAL: optimum at {optimal_tilt} deg (expected {expected_optimal_tilt_min}-{expected_optimal_tilt_max})")
    elif optimal_tilt > 0:
        feedback_parts.append(f"Curve shape check FAIL: edge or implausible optimum at {optimal_tilt} deg")
    else:
        feedback_parts.append("Curve shape check: no tilt data")

    # Criterion 9: Independent file cross-check (15 points)
    raw_found, raw_details = _independent_file_check(copy_from_env)
    if raw_found and raw_details.get('looks_like_real_output'):
        tilt_arr_len = raw_details.get('tilt_array_len', 0)
        if tilt_arr_len >= expected_num_tilts_min:
            score += 15
            feedback_parts.append(f"Independent cross-check PASSED: {tilt_arr_len} tilt entries, weather ref found")
        else:
            score += 8
            feedback_parts.append(f"Independent cross-check PARTIAL: only {tilt_arr_len} tilt entries in raw file")
    elif raw_found:
        score += 1
        feedback_parts.append(f"Independent cross-check WARN: file found but missing weather ref or tilt array ({raw_details.get('tilt_array_len', 0)} entries)")
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
