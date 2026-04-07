#!/usr/bin/env python3
"""
Verifier for model_solar_water_heating task.

Verifies the output JSON from the agent's PySAM Swh simulation script.
Checks that realistic physics values are returned and parameters match expectations.
"""

import json
import os
import sys
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_model_solar_water_heating(traj, env_info, task_info):
    """Verify the Solar Water Heating task results."""
    
    score = 0
    max_score = 100
    details = []

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Get metadata configuration
    metadata = task_info.get('metadata', {})
    energy_min = metadata.get('annual_energy_min', 1500)
    energy_max = metadata.get('annual_energy_max', 6000)
    sf_min = metadata.get('solar_fraction_min', 0.30)
    sf_max = metadata.get('solar_fraction_max', 0.99)

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            data = json.load(f)
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Failed to load result file: {e}"
        }
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    parsed = data.get("parsed_data", {})
    mandatory_met = True

    # --- Criterion 1: Output file exists (15 pts) ---
    if data.get("file_exists", False):
        score += 15
        details.append("PASS [15/15]: Output file exists")
    else:
        mandatory_met = False
        details.append("FAIL [0/15]: Output file does not exist")

    # --- Criterion 2: File created during task (10 pts) ---
    if data.get("file_created_during_task", False):
        score += 10
        details.append("PASS [10/10]: File created during task window")
    elif data.get("file_exists", False):
        details.append("FAIL [0/10]: File exists but was not created during task window")
    else:
        details.append("FAIL [0/10]: File not created during task window")

    # --- Criterion 3: Valid JSON structure (10 pts) ---
    if parsed.get("valid_json", False):
        score += 10
        details.append("PASS [10/10]: Valid JSON structure")
    else:
        details.append("FAIL [0/10]: Invalid JSON or missing expected structure")

    # --- Criterion 4: Annual energy in range (15 pts) ---
    annual_energy = parsed.get("annual_energy")
    if annual_energy is not None:
        try:
            ae = float(annual_energy)
            if energy_min <= ae <= energy_max:
                score += 15
                details.append(f"PASS [15/15]: Annual energy {ae:.1f} kWh in valid range [{energy_min}-{energy_max}]")
            else:
                mandatory_met = False
                details.append(f"FAIL [0/15]: Annual energy {ae:.1f} kWh outside valid range [{energy_min}-{energy_max}]")
        except (ValueError, TypeError):
            mandatory_met = False
            details.append(f"FAIL [0/15]: Annual energy not a valid number: {annual_energy}")
    else:
        mandatory_met = False
        details.append("FAIL [0/15]: Annual energy not found in results")

    # --- Criterion 5: Solar fraction in range (15 pts) ---
    solar_fraction = parsed.get("solar_fraction")
    if solar_fraction is not None:
        try:
            sf = float(solar_fraction)
            if sf_min <= sf <= sf_max:
                score += 15
                details.append(f"PASS [15/15]: Solar fraction {sf:.3f} in valid range [{sf_min}-{sf_max}]")
            else:
                details.append(f"FAIL [0/15]: Solar fraction {sf:.3f} outside valid range [{sf_min}-{sf_max}]")
        except (ValueError, TypeError):
            details.append(f"FAIL [0/15]: Solar fraction not a valid number: {solar_fraction}")
    else:
        details.append("FAIL [0/15]: Solar fraction not found in results")

    # --- Criterion 6: Monthly data present (10 pts) ---
    monthly_count = parsed.get("monthly_count", 0)
    try:
        mc = int(monthly_count)
    except (ValueError, TypeError):
        mc = 0

    if mc == 12:
        score += 10
        details.append("PASS [10/10]: Monthly energy data has 12 values")
    else:
        details.append(f"FAIL [0/10]: Monthly data has {mc} values (expected 12)")

    # --- Criterion 7: Monthly seasonal pattern (10 pts) ---
    summer_energy = parsed.get("summer_energy")
    winter_energy = parsed.get("winter_energy")
    if summer_energy is not None and winter_energy is not None:
        try:
            se = float(summer_energy)
            we = float(winter_energy)
            if se > 0 and we > 0 and se > we:
                score += 10
                details.append(f"PASS [10/10]: Seasonal pattern correct — summer ({se:.1f} kWh) > winter ({we:.1f} kWh)")
            elif se > 0 and we > 0:
                details.append(f"FAIL [0/10]: No seasonal pattern — summer ({se:.1f}) not > winter ({we:.1f})")
            else:
                details.append(f"FAIL [0/10]: Invalid seasonal values — summer={se}, winter={we}")
        except (ValueError, TypeError):
            details.append("FAIL [0/10]: Seasonal energy values not valid numbers")
    else:
        details.append("FAIL [0/10]: Monthly data insufficient for seasonal check")

    # --- Criterion 8: System parameters match (15 pts, 3 pts per parameter) ---
    param_score = 0
    param_details = []

    if parsed.get("has_system_params", False):
        # Check ncoll
        ncoll = parsed.get("ncoll")
        if ncoll is not None:
            try:
                if abs(float(ncoll) - metadata.get('expected_ncoll', 2)) < 0.1:
                    param_score += 3
                    param_details.append("ncoll=2 ✓")
                else:
                    param_details.append(f"ncoll={ncoll} ✗")
            except (ValueError, TypeError):
                param_details.append(f"ncoll invalid")

        # Check area_coll
        area_coll = parsed.get("area_coll")
        if area_coll is not None:
            try:
                if abs(float(area_coll) - metadata.get('expected_area_coll', 2.98)) < 0.5:
                    param_score += 3
                    param_details.append("area_coll≈2.98 ✓")
                else:
                    param_details.append(f"area_coll={area_coll} ✗")
            except (ValueError, TypeError):
                param_details.append(f"area_coll invalid")

        # Check tilt
        tilt = parsed.get("tilt")
        if tilt is not None:
            try:
                if abs(float(tilt) - metadata.get('expected_tilt', 33.4)) < 5.0:
                    param_score += 3
                    param_details.append("tilt≈33.4 ✓")
                else:
                    param_details.append(f"tilt={tilt} ✗")
            except (ValueError, TypeError):
                param_details.append(f"tilt invalid")

        # Check azimuth
        azimuth = parsed.get("azimuth")
        if azimuth is not None:
            try:
                if abs(float(azimuth) - metadata.get('expected_azimuth', 180)) < 10:
                    param_score += 3
                    param_details.append("azimuth≈180 ✓")
                else:
                    param_details.append(f"azimuth={azimuth} ✗")
            except (ValueError, TypeError):
                param_details.append(f"azimuth invalid")

        # Check V_tank
        v_tank = parsed.get("V_tank")
        if v_tank is not None:
            try:
                if abs(float(v_tank) - metadata.get('expected_V_tank', 303)) < 50:
                    param_score += 3
                    param_details.append("V_tank≈303 ✓")
                else:
                    param_details.append(f"V_tank={v_tank} ✗")
            except (ValueError, TypeError):
                param_details.append(f"V_tank invalid")
    else:
        param_details.append("No system_parameters object found")

    score += param_score
    details.append(f"{'PASS' if param_score >= 9 else 'PARTIAL' if param_score > 0 else 'FAIL'} [{param_score}/15]: System parameters — {'; '.join(param_details)}")

    # Script files created check (Anti-gaming check)
    script_files = data.get('script_files_created', 0)
    if script_files == 0:
        details.append("WARNING: No python scripts created during task (potential hardcoded result)")

    # Final result determination
    passed = score >= 70 and mandatory_met

    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(details)
    }