#!/usr/bin/env python3
"""
Verifier for model_pv_lifetime_degradation task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_pv_degradation(traj, env_info, task_info):
    """
    Verify the PV lifetime degradation modeling task.
    
    Reads from /tmp/task_result.json extracted via copy_from_env.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_capacity = metadata.get('capacity_kw', 100000)
    year1_min = metadata.get('year1_min_kwh', 160000000)
    year1_max = metadata.get('year1_max_kwh', 240000000)

    # Temporary file for the results
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read exported result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    max_score = 100
    details = []
    critical_pass = True

    # 1. File exists
    if result.get("file_exists", False):
        score += 10
        details.append("PASS [10/10]: Result JSON file exists")
    else:
        critical_pass = False
        details.append("FAIL [0/10]: Result JSON file not found")
        return {"passed": False, "score": score, "feedback": " | ".join(details)}

    # 2. File modified during task
    if result.get("file_modified_during_task", False):
        score += 10
        details.append("PASS [10/10]: File was modified during task execution")
    else:
        details.append("FAIL [0/10]: File existed before task and was not modified")
        critical_pass = False

    # 3. Keys present
    keys_missing = result.get("keys_missing", [])
    keys_present = result.get("keys_present", [])
    if len(keys_missing) == 0 and len(keys_present) >= 14:
        score += 10
        details.append("PASS [10/10]: All 14 required JSON keys present")
    elif len(keys_present) >= 7:
        score += 5
        details.append(f"PARTIAL [5/10]: {len(keys_present)}/14 keys present, missing: {keys_missing}")
    else:
        details.append(f"FAIL [0/10]: Only {len(keys_present)}/14 keys present")

    values = result.get("values", {})

    # 4. System parameters correct
    param_score = 0
    param_checks = [
        ("system_capacity_kw", expected_capacity, 1),
        ("dc_ac_ratio", 1.2, 0.05),
        ("tilt_degrees", 30, 0.5),
        ("azimuth_degrees", 180, 0.5),
        ("degradation_rate_pct_per_year", 0.5, 0.01),
    ]
    for key, expected, tol in param_checks:
        val = values.get(key)
        if val is not None:
            try:
                if abs(float(val) - expected) <= tol:
                    param_score += 2
            except (TypeError, ValueError):
                pass
    score += param_score
    details.append(f"{'PASS' if param_score == 10 else 'PARTIAL/FAIL'} [{param_score}/10]: System configuration parameters check")

    # 5. Year 1 energy reasonable
    year1 = values.get("year1_annual_energy_kwh")
    year1_reasonable = False
    if year1 is not None:
        try:
            year1 = float(year1)
            # 100 MW in AZ: expect ~160-240 GWh
            if year1_min <= year1 <= year1_max:
                score += 15
                year1_reasonable = True
                details.append(f"PASS [15/15]: Year 1 energy = {year1/1e6:.1f} GWh (physically reasonable for AZ)")
            elif (year1_min * 0.7) <= year1 <= (year1_max * 1.3):
                score += 8
                year1_reasonable = True
                details.append(f"PARTIAL [8/15]: Year 1 energy = {year1/1e6:.1f} GWh (marginally reasonable)")
            else:
                details.append(f"FAIL [0/15]: Year 1 energy = {year1/1e6:.1f} GWh (outside expected range)")
                critical_pass = False
        except (TypeError, ValueError):
            details.append("FAIL [0/15]: year1_annual_energy_kwh is not a valid number")
            critical_pass = False
    else:
        details.append("FAIL [0/15]: year1_annual_energy_kwh not found")
        critical_pass = False

    # Proceed to derivative calculations only if year 1 is reasonably numeric
    if year1_reasonable:
        # 6. Year 25 Energy Correct
        year25 = values.get("year25_annual_energy_kwh")
        if year25 is not None:
            try:
                year25 = float(year25)
                expected_y25 = year1 * (0.995 ** 24)
                rel_error = abs(year25 - expected_y25) / expected_y25 if expected_y25 > 0 else 1.0
                if rel_error <= 0.01:
                    score += 10
                    details.append(f"PASS [10/10]: Year 25 energy matches compounding degradation")
                elif rel_error <= 0.05:
                    score += 5
                    details.append(f"PARTIAL [5/10]: Year 25 energy near target (error {rel_error*100:.1f}%)")
                else:
                    details.append(f"FAIL [0/10]: Year 25 energy incorrect (error {rel_error*100:.1f}%)")
            except (TypeError, ValueError):
                details.append("FAIL [0/10]: year25_annual_energy_kwh is invalid")

        # 7. Cumulative Energy Correct
        cumulative = values.get("cumulative_25yr_energy_kwh")
        if cumulative is not None:
            try:
                cumulative = float(cumulative)
                expected_cum = sum(year1 * (0.995 ** n) for n in range(25))
                rel_error = abs(cumulative - expected_cum) / expected_cum if expected_cum > 0 else 1.0
                if rel_error <= 0.01:
                    score += 10
                    details.append("PASS [10/10]: Cumulative 25yr energy matches expected formula")
                elif rel_error <= 0.05:
                    score += 5
                    details.append(f"PARTIAL [5/10]: Cumulative energy near target (error {rel_error*100:.1f}%)")
                else:
                    details.append(f"FAIL [0/10]: Cumulative energy incorrect (error {rel_error*100:.1f}%)")
            except (TypeError, ValueError):
                details.append("FAIL [0/10]: cumulative_25yr_energy_kwh is invalid")

        # 8. Lifetime Capacity Factor
        lcf = values.get("lifetime_capacity_factor")
        if cumulative is not None and lcf is not None:
            try:
                lcf = float(lcf)
                expected_lcf = float(cumulative) / (expected_capacity * 8760 * 25)
                abs_error = abs(lcf - expected_lcf)
                if abs_error <= 0.005:
                    score += 10
                    details.append("PASS [10/10]: Lifetime capacity factor calculated correctly")
                elif abs_error <= 0.02:
                    score += 5
                    details.append(f"PARTIAL [5/10]: Lifetime capacity factor error: {abs_error:.4f}")
                else:
                    details.append(f"FAIL [0/10]: Lifetime CF incorrect. Expected ~{expected_lcf:.3f}, got {lcf:.3f}")
            except (TypeError, ValueError):
                details.append("FAIL [0/10]: lifetime_capacity_factor is invalid")

        # 9. Degradation Loss
        deg_loss = values.get("total_degradation_loss_kwh")
        if cumulative is not None and deg_loss is not None:
            try:
                deg_loss = float(deg_loss)
                expected_loss = (year1 * 25) - cumulative
                rel_error = abs(deg_loss - expected_loss) / expected_loss if expected_loss > 0 else 1.0
                if rel_error <= 0.01:
                    score += 5
                    details.append("PASS [5/5]: Total degradation loss calculated correctly")
                else:
                    details.append(f"FAIL [0/5]: Degradation loss incorrect (error {rel_error*100:.1f}%)")
            except (TypeError, ValueError):
                details.append("FAIL [0/5]: total_degradation_loss_kwh is invalid")

        # 10 & 11. Annual Series
        annual_list = values.get("annual_energy_by_year_kwh")
        if isinstance(annual_list, list):
            if len(annual_list) == 25:
                score += 5
                details.append("PASS [5/5]: annual_energy_by_year_kwh has exactly 25 values")
                
                # Check consistency
                try:
                    consistent = True
                    for i in range(25):
                        expected_val = year1 * (0.995 ** i)
                        actual_val = float(annual_list[i])
                        if abs(actual_val - expected_val) / expected_val > 0.01:
                            consistent = False
                            break
                    if consistent:
                        score += 5
                        details.append("PASS [5/5]: Annual series values follow the 0.5% degradation curve")
                    else:
                        details.append("FAIL [0/5]: Annual series values are inconsistent with degradation curve")
                except (TypeError, ValueError):
                    details.append("FAIL [0/5]: Annual series contains invalid numbers")
            else:
                details.append(f"FAIL [0/10]: annual_energy_by_year_kwh has {len(annual_list)} values (expected 25)")
        else:
            details.append("FAIL [0/10]: annual_energy_by_year_kwh is missing or not a list")
    else:
        details.append("FAIL [0/45]: Remaining calculations skipped due to invalid Year 1 energy")

    passed = score >= 70 and critical_pass

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(details)
    }