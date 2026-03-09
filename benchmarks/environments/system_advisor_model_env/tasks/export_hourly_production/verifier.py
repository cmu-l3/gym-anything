#!/usr/bin/env python3
"""Verifier for export_hourly_production task.

Validates CSV structure, physics sanity, AND independent file cross-check.
"""

import json
import tempfile
import os
import csv


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


def _independent_csv_check(copy_from_env, expected_num_hours):
    """Copy the agent's actual CSV file and independently verify its contents."""
    csv_path = "/home/ga/Documents/SAM_Projects/Tucson_Hourly_Production.csv"
    temp = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
    try:
        copy_from_env(csv_path, temp.name)
        with open(temp.name, 'r') as f:
            reader = csv.reader(f)
            rows = list(reader)

        details = {'raw_csv_found': True}
        if len(rows) < 2:
            details['looks_like_real_output'] = False
            return True, details

        # Check header
        header = [h.lower().strip() for h in rows[0]]
        details['header'] = rows[0]
        details['has_power_column'] = any(
            col in ' '.join(header) for col in ['power', 'watt', 'ac', 'output', 'generation']
        )

        data_rows = rows[1:]
        details['data_row_count'] = len(data_rows)

        # Try to find numeric power column and compute sum
        power_col_idx = None
        for i, h in enumerate(header):
            if any(kw in h for kw in ['power', 'watt', 'ac', 'output']):
                power_col_idx = i
                break
        # Fall back to second column if no match
        if power_col_idx is None and len(header) >= 2:
            power_col_idx = 1

        if power_col_idx is not None:
            total_wh = 0
            valid_rows = 0
            for row in data_rows:
                try:
                    val = float(row[power_col_idx])
                    total_wh += val
                    valid_rows += 1
                except (ValueError, IndexError):
                    continue
            details['ind_total_wh'] = total_wh
            details['ind_annual_kwh'] = total_wh / 1000.0 if total_wh > 1000 else total_wh
            details['valid_data_rows'] = valid_rows

        details['looks_like_real_output'] = (
            details['data_row_count'] >= expected_num_hours - 10
            and details.get('has_power_column', False)
        )

        return True, details
    except Exception:
        return False, {'raw_csv_found': False}
    finally:
        if os.path.exists(temp.name):
            os.unlink(temp.name)


def verify_export_hourly_production(traj, env_info, task_info):
    """Verify hourly production data was exported correctly.

    Scoring: 100 points max
    - CSV file exists: 10
    - JSON summary exists: 5
    - Files created during task: 10
    - CSV row count: 10
    - CSV header: 5
    - Location correct: 5
    - DC size correct: 5
    - Annual energy in range: 10
    - Peak watts in range: 5
    - Physics check: 15
    - Independent CSV cross-check: 20
    """

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_location = metadata.get('expected_location', 'tucson')
    expected_num_hours = metadata.get('expected_num_hours', 8760)
    expected_dc_size_min = metadata.get('expected_dc_size_min', 7.0)
    expected_dc_size_max = metadata.get('expected_dc_size_max', 8.0)
    expected_annual_kwh_min = metadata.get('expected_annual_kwh_min', 12000)
    expected_annual_kwh_max = metadata.get('expected_annual_kwh_max', 15000)
    expected_peak_min = metadata.get('expected_peak_watts_min', 5500)
    expected_peak_max = metadata.get('expected_peak_watts_max', 7500)

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

    # Criterion 1: CSV file exists (10 points)
    csv_exists = result.get('csv_exists') is True or str(result.get('csv_exists')) == 'true'
    if csv_exists:
        score += 10
        feedback_parts.append("CSV file exists")
    else:
        feedback_parts.append("CSV file NOT found")

    # Criterion 2: JSON summary exists (5 points)
    json_exists = result.get('json_exists') is True or str(result.get('json_exists')) == 'true'
    if json_exists:
        score += 5
        feedback_parts.append("JSON summary exists")
    else:
        feedback_parts.append("JSON summary NOT found")

    # Criterion 3: Files created during task (10 points)
    file_modified = result.get('file_modified') is True or str(result.get('file_modified')) == 'true'
    if file_modified:
        score += 10
        feedback_parts.append("Files created during task")
    elif csv_exists:
        feedback_parts.append("Files exist but not created during task")
        score += 2
    else:
        feedback_parts.append("No file modification detected")

    # Criterion 4: CSV has correct number of data rows (10 points)
    csv_lines = 0
    try:
        csv_lines = int(result.get('csv_lines', '0'))
        if csv_lines == expected_num_hours:
            score += 10
            feedback_parts.append(f"CSV has {csv_lines} data rows (correct)")
        elif abs(csv_lines - expected_num_hours) <= 10:
            score += 7
            feedback_parts.append(f"CSV has {csv_lines} rows (close to {expected_num_hours})")
        elif csv_lines > 1000:
            score += 2
            feedback_parts.append(f"CSV has {csv_lines} rows (expected {expected_num_hours})")
        elif csv_lines > 0:
            score += 1
            feedback_parts.append(f"CSV too short: {csv_lines} rows")
        else:
            feedback_parts.append("CSV has no data rows")
    except (ValueError, TypeError):
        feedback_parts.append("CSV line count parse error")

    # Criterion 5: CSV has proper header (5 points)
    has_header = result.get('has_header') is True or str(result.get('has_header')) == 'true'
    if has_header:
        score += 5
        feedback_parts.append("CSV header present")
    else:
        feedback_parts.append("CSV header missing or wrong format")

    # Criterion 6: Location matches Tucson (5 points)
    location_info = str(result.get('location_info', ''))
    if expected_location.lower() in location_info.lower():
        score += 5
        feedback_parts.append(f"Location correct: {location_info}")
    elif location_info:
        feedback_parts.append(f"Location mismatch: {location_info}")
        score += 1
    else:
        feedback_parts.append("No location info")

    # Criterion 7: DC system size correct (5 points)
    dc_size = 0
    try:
        dc_size = float(result.get('dc_size', '0'))
        if expected_dc_size_min <= dc_size <= expected_dc_size_max:
            score += 5
            feedback_parts.append(f"DC size correct: {dc_size} kW")
        elif dc_size > 0:
            feedback_parts.append(f"DC size wrong: {dc_size} kW")
            score += 1
        else:
            feedback_parts.append("DC size not found")
    except (ValueError, TypeError):
        feedback_parts.append("DC size parse error")

    # Criterion 8: Annual energy in expected range (10 points)
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

    # Criterion 9: Peak watts in expected range (5 points)
    peak_watts = 0
    try:
        peak_watts = float(result.get('peak_watts', '0'))
        if expected_peak_min <= peak_watts <= expected_peak_max:
            score += 5
            feedback_parts.append(f"Peak output: {peak_watts:.0f} W")
        elif peak_watts > 0:
            feedback_parts.append(f"Peak output unexpected: {peak_watts:.0f} W")
            score += 1
        else:
            feedback_parts.append("No peak output data")
    except (ValueError, TypeError):
        feedback_parts.append("Peak output parse error")

    # Criterion 10: Physics sanity check (15 points)
    physics_score = 0
    if dc_size > 0 and annual_kwh > 0:
        plausible, reason = _physics_sanity_check(dc_size, annual_kwh, expected_location)
        if plausible:
            physics_score += 8
            feedback_parts.append(f"Physics check PASSED: {reason}")
        else:
            feedback_parts.append(f"Physics check FAILED: {reason}")

    if peak_watts > 0 and dc_size > 0:
        max_theoretical = dc_size * 1200
        if peak_watts <= max_theoretical:
            physics_score += 4
            feedback_parts.append("Peak power physically consistent")
        else:
            feedback_parts.append(f"Peak power {peak_watts:.0f}W exceeds theoretical max {max_theoretical:.0f}W")

    if csv_lines == expected_num_hours:
        physics_score += 3
        feedback_parts.append("Hourly granularity confirmed (8760 hours)")
    elif csv_lines > 0:
        feedback_parts.append(f"Non-standard row count: {csv_lines}")

    score += physics_score

    # Criterion 11: Independent CSV cross-check (20 points)
    raw_found, raw_details = _independent_csv_check(copy_from_env, expected_num_hours)
    if raw_found and raw_details.get('looks_like_real_output'):
        ind_row_count = raw_details.get('data_row_count', 0)
        ind_kwh = raw_details.get('ind_annual_kwh', 0)
        # Cross-check row count matches what export_result.sh reported
        if ind_row_count == csv_lines and csv_lines >= expected_num_hours - 10:
            score += 10
            feedback_parts.append(f"Independent CSV row count confirmed: {ind_row_count}")
        elif ind_row_count > 0:
            score += 5
            feedback_parts.append(f"Independent CSV rows: {ind_row_count} (export reported {csv_lines})")

        # Cross-check energy total
        if ind_kwh > 0 and annual_kwh > 0 and abs(ind_kwh - annual_kwh) / annual_kwh < 0.05:
            score += 10
            feedback_parts.append(f"Independent energy sum matches: {ind_kwh:.0f} kWh")
        elif ind_kwh > 0 and annual_kwh > 0:
            score += 5
            feedback_parts.append(f"Independent energy sum differs: {ind_kwh:.0f} vs {annual_kwh:.0f} kWh")
        elif ind_kwh > 0:
            score += 3
            feedback_parts.append(f"Independent energy sum: {ind_kwh:.0f} kWh (no reported total to compare)")
    elif raw_found:
        score += 1
        feedback_parts.append(f"Independent CSV check WARN: {raw_details.get('data_row_count', 0)} rows, header={'has' if raw_details.get('has_power_column') else 'missing'}")
    else:
        feedback_parts.append("Independent CSV check: could not copy agent's CSV file")

    # Anti-bypass: verify Python was actually used during the task
    python_ran = result.get('python_ran') is True or str(result.get('python_ran')) == 'true'
    if not python_ran:
        feedback_parts.append("ANTI-BYPASS: No evidence Python was executed during task")
        score = min(score, 20)

    score = min(score, 100)
    key_criteria_met = csv_exists and file_modified and python_ran
    passed = score >= 70 and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }
