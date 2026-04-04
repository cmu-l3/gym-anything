#!/usr/bin/env python3
"""Verifier for compare_pv_locations task.

Validates that the agent compared Phoenix, Tucson, and Des Moines
with physically plausible results, correct ranking, AND independent file cross-check.
"""

import json
import tempfile
import os


def _physics_sanity_check(dc_size_kw, annual_kwh, location):
    """Check if reported energy is physically plausible for the location."""
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
    """Copy the agent's actual comparison file and independently verify its contents."""
    path = "/home/ga/Documents/SAM_Projects/PV_Location_Comparison.json"
    temp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env(path, temp.name)
        with open(temp.name, 'r') as f:
            raw = json.load(f)

        details = {'raw_file_found': True}
        raw_str = json.dumps(raw).lower()

        # Check for weather/location references
        has_phoenix = 'phoenix' in raw_str
        has_tucson = 'tucson' in raw_str
        has_des_moines = 'des moines' in raw_str or 'des_moines' in raw_str
        details['has_all_cities'] = has_phoenix and has_tucson and has_des_moines
        details['city_count'] = sum([has_phoenix, has_tucson, has_des_moines])

        numeric_count = sum(1 for v in _iter_values(raw) if isinstance(v, (int, float)))
        details['numeric_field_count'] = numeric_count

        # Look for comparison array
        comp_array_len = 0
        for key in ['comparison', 'results', 'locations', 'cities', 'data']:
            if key in raw and isinstance(raw[key], list):
                comp_array_len = len(raw[key])
                break
        details['comp_array_len'] = comp_array_len

        details['looks_like_real_output'] = (
            details['has_all_cities']
            and numeric_count >= 6
            and comp_array_len >= 3
        )

        return True, details
    except Exception:
        return False, {'raw_file_found': False}
    finally:
        if os.path.exists(temp.name):
            os.unlink(temp.name)


def verify_compare_pv_locations(traj, env_info, task_info):
    """Verify PV location comparison was completed successfully.

    Scoring: 100 points max
    - File exists: 10
    - File created during task: 10
    - Comparison data with 3 locations: 10
    - Best location correct: 10
    - Worst location correct: 10
    - Phoenix kWh in range: 10
    - Des Moines kWh in range: 10
    - Tucson kWh in range + correct ranking: 10
    - Physics sanity check: 10
    - Independent file cross-check: 10
    """

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_best = metadata.get('expected_best_location', 'tucson')
    expected_worst = metadata.get('expected_worst_location', 'des moines')
    expected_num_locations = metadata.get('expected_num_locations', 3)
    expected_phoenix_kwh_min = metadata.get('expected_phoenix_kwh_min', 15000)
    expected_phoenix_kwh_max = metadata.get('expected_phoenix_kwh_max', 20000)
    expected_tucson_kwh_min = metadata.get('expected_tucson_kwh_min', 16000)
    expected_tucson_kwh_max = metadata.get('expected_tucson_kwh_max', 21000)
    expected_des_moines_kwh_min = metadata.get('expected_des_moines_kwh_min', 11000)
    expected_des_moines_kwh_max = metadata.get('expected_des_moines_kwh_max', 15000)

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

    # Criterion 3: Has comparison data with correct number of locations (10 points)
    has_comparison = result.get('has_comparison') is True or str(result.get('has_comparison')) == 'true'
    try:
        num_locations = int(result.get('num_locations', '0'))
    except (ValueError, TypeError):
        num_locations = 0

    if has_comparison and num_locations >= expected_num_locations:
        score += 10
        feedback_parts.append(f"Comparison has {num_locations} locations")
    elif has_comparison and num_locations > 0:
        score += 3
        feedback_parts.append(f"Comparison incomplete: {num_locations} locations (need {expected_num_locations})")
    else:
        feedback_parts.append("No comparison data found")

    # Criterion 4: Best location identified correctly (10 points)
    best_location = str(result.get('best_location', '')).lower()
    if expected_best.lower() in best_location:
        score += 10
        feedback_parts.append(f"Best location correct: {best_location}")
    elif best_location:
        feedback_parts.append(f"Best location wrong: {best_location} (expected {expected_best})")
        score += 1
    else:
        feedback_parts.append("Best location not identified")

    # Criterion 5: Worst location identified correctly (10 points)
    worst_location = str(result.get('worst_location', '')).lower()
    if expected_worst.lower() in worst_location:
        score += 10
        feedback_parts.append(f"Worst location correct: {worst_location}")
    elif worst_location:
        feedback_parts.append(f"Worst location wrong: {worst_location} (expected {expected_worst})")
        score += 1
    else:
        feedback_parts.append("Worst location not identified")

    # Criterion 6: Phoenix kWh in expected range (10 points)
    phoenix_kwh = 0
    try:
        phoenix_kwh = float(result.get('phoenix_kwh', '0'))
        if expected_phoenix_kwh_min <= phoenix_kwh <= expected_phoenix_kwh_max:
            score += 10
            feedback_parts.append(f"Phoenix energy: {phoenix_kwh:.0f} kWh")
        elif phoenix_kwh > 0:
            feedback_parts.append(f"Phoenix energy unexpected: {phoenix_kwh:.0f} kWh")
            score += 1
        else:
            feedback_parts.append("No Phoenix energy data")
    except (ValueError, TypeError):
        feedback_parts.append("Phoenix energy parse error")

    # Criterion 7: Des Moines kWh in expected range (10 points)
    des_moines_kwh = 0
    try:
        des_moines_kwh = float(result.get('des_moines_kwh', '0'))
        if expected_des_moines_kwh_min <= des_moines_kwh <= expected_des_moines_kwh_max:
            score += 10
            feedback_parts.append(f"Des Moines energy: {des_moines_kwh:.0f} kWh")
        elif des_moines_kwh > 0:
            feedback_parts.append(f"Des Moines energy unexpected: {des_moines_kwh:.0f} kWh")
            score += 1
        else:
            feedback_parts.append("No Des Moines energy data")
    except (ValueError, TypeError):
        feedback_parts.append("Des Moines energy parse error")

    # Criterion 8: Tucson kWh in range AND correct ranking (10 points combined)
    # 5 points for Tucson energy in range, 5 points for correct ranking order
    tucson_kwh = 0
    try:
        tucson_kwh = float(result.get('tucson_kwh', '0'))
        if expected_tucson_kwh_min <= tucson_kwh <= expected_tucson_kwh_max:
            score += 5
            feedback_parts.append(f"Tucson energy: {tucson_kwh:.0f} kWh")
        elif tucson_kwh > 0:
            feedback_parts.append(f"Tucson energy unexpected: {tucson_kwh:.0f} kWh")
            score += 2
        else:
            feedback_parts.append("No Tucson energy data")
    except (ValueError, TypeError):
        feedback_parts.append("Tucson energy parse error")

    if phoenix_kwh > 0 and tucson_kwh > 0 and des_moines_kwh > 0:
        if tucson_kwh > phoenix_kwh > des_moines_kwh:
            score += 5
            feedback_parts.append(
                f"Ranking correct: Tucson ({tucson_kwh:.0f}) > Phoenix ({phoenix_kwh:.0f}) > Des Moines ({des_moines_kwh:.0f})"
            )
        elif tucson_kwh > des_moines_kwh and phoenix_kwh > des_moines_kwh:
            score += 2
            feedback_parts.append("Partial ranking: SW cities > Des Moines but internal order wrong")
        else:
            feedback_parts.append("Energy ranking WRONG")
    else:
        feedback_parts.append("Cannot verify energy ranking")

    # Criterion 9: Physics sanity check on all cities (10 points)
    dc_size = 10.0
    physics_ok_count = 0
    physics_total = 0
    for city, kwh in [("phoenix", phoenix_kwh), ("tucson", tucson_kwh), ("des moines", des_moines_kwh)]:
        if kwh > 0:
            physics_total += 1
            plausible, reason = _physics_sanity_check(dc_size, kwh, city)
            if plausible:
                physics_ok_count += 1
            else:
                feedback_parts.append(f"Physics FAIL {city}: {reason}")

    if physics_total > 0:
        physics_score = int(10 * physics_ok_count / physics_total)
        score += physics_score
        if physics_ok_count == physics_total:
            feedback_parts.append(f"Physics check PASSED: all {physics_total} cities plausible")
        else:
            feedback_parts.append(f"Physics check: {physics_ok_count}/{physics_total} cities plausible")
    else:
        feedback_parts.append("Physics check: no energy data")

    # Criterion 10: Independent file cross-check (10 points)
    raw_found, raw_details = _independent_file_check(copy_from_env)
    if raw_found and raw_details.get('looks_like_real_output'):
        score += 10
        feedback_parts.append(
            f"Independent cross-check PASSED: {raw_details['city_count']} cities, "
            f"{raw_details['comp_array_len']} comparison entries, "
            f"{raw_details['numeric_field_count']} numeric fields"
        )
    elif raw_found and raw_details.get('has_all_cities'):
        score += 5
        feedback_parts.append(f"Independent cross-check PARTIAL: all cities found but structure incomplete ({raw_details.get('comp_array_len', 0)} entries)")
    elif raw_found:
        score += 1
        feedback_parts.append(f"Independent cross-check WARN: only {raw_details.get('city_count', 0)}/3 cities found")
    else:
        feedback_parts.append("Independent cross-check: could not copy agent's output file")

    # Anti-bypass: verify Python was actually used during the task
    python_ran = result.get('python_ran') is True or str(result.get('python_ran')) == 'true'
    if not python_ran:
        feedback_parts.append("ANTI-BYPASS: No evidence Python was executed during task")
        score = min(score, 20)

    # Cap at 100
    score = min(score, 100)

    key_criteria_met = file_exists and file_modified and python_ran
    passed = score >= 70 and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }
