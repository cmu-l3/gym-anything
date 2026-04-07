#!/usr/bin/env python3
"""
Verifier for hokkaido_drift_ice_thermal_forcing task.

Occupation: Marine Forecaster / Climatologist
Industry: Maritime Safety / Coast Guard Ice Information Center
Difficulty: hard

Scoring criteria (100 pts total, pass threshold = 80):
  1. Air Temperature plot exported (20 pts): okhotsk_airtemp_feb.png exists,
     was created after task start, size >= 15KB.
  2. SLP plot exported (20 pts): okhotsk_slp_feb.png exists, created after
     task start, size >= 15KB.
  3. Report Structure (20 pts): thermal_forcing_report.txt exists, contains all 5 key fields.
  4. SLP Accuracy (20 pts): SIBERIAN_HIGH_CENTER_SLP_HPA must be in [1025, 1045] hPa.
  5. Temp Accuracy (20 pts): MIN_AIR_TEMP_NORTH_OKHOTSK must be in [-40, -5] C OR [233, 268] K.
"""

import json
import os
import re
import tempfile


def extract_number(s):
    """Extract the first floating point number from a string."""
    m = re.search(r'-?\d+\.?\d*', s)
    return float(m.group(0)) if m else None


def verify_hokkaido_drift_ice_thermal_forcing(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    # Retrieve result JSON from the VM
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp.close()
    try:
        copy_from_env('/tmp/hokkaido_drift_ice_thermal_forcing_result.json', tmp.name)
        with open(tmp.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve result JSON: {e}"}
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)

    score = 0
    feedback = []
    task_start = int(result.get('task_start', 0))

    # ----------------------------------------------------------------
    # Criterion 1: Air Temp plot exported (20 pts)
    # ----------------------------------------------------------------
    airtemp_exists = result.get('airtemp_plot_exists', False)
    airtemp_mtime = int(result.get('airtemp_plot_mtime', 0))
    airtemp_size = int(result.get('airtemp_plot_size', 0))

    if airtemp_exists and airtemp_mtime >= task_start and airtemp_size >= 15000:
        score += 20
        feedback.append(f"Air temp plot exported successfully ({airtemp_size} bytes).")
    elif airtemp_exists and airtemp_mtime >= task_start and airtemp_size > 0:
        score += 10
        feedback.append(f"Air temp plot present but size is suspiciously small ({airtemp_size} bytes).")
    else:
        feedback.append(f"Air temp plot missing or pre-dates task start (exists={airtemp_exists}).")

    # ----------------------------------------------------------------
    # Criterion 2: SLP plot exported (20 pts)
    # ----------------------------------------------------------------
    slp_exists = result.get('slp_plot_exists', False)
    slp_mtime = int(result.get('slp_plot_mtime', 0))
    slp_size = int(result.get('slp_plot_size', 0))

    if slp_exists and slp_mtime >= task_start and slp_size >= 15000:
        score += 20
        feedback.append(f"SLP plot exported successfully ({slp_size} bytes).")
    elif slp_exists and slp_mtime >= task_start and slp_size > 0:
        score += 10
        feedback.append(f"SLP plot present but size is suspiciously small ({slp_size} bytes).")
    else:
        feedback.append(f"SLP plot missing or pre-dates task start (exists={slp_exists}).")

    # ----------------------------------------------------------------
    # Criterion 3: Report Structure (20 pts)
    # ----------------------------------------------------------------
    report_exists = result.get('report_exists', False)
    report_mtime = int(result.get('report_mtime', 0))
    
    analysis_month = result.get('analysis_month', '').strip()
    region = result.get('region', '').strip()
    min_air_temp_raw = result.get('min_air_temp', '').strip()
    siberian_high_raw = result.get('siberian_high_slp', '').strip()
    inferred_wind = result.get('inferred_wind', '').strip()

    has_all_fields = (analysis_month and region and min_air_temp_raw and 
                      siberian_high_raw and inferred_wind)

    if report_exists and report_mtime >= task_start and has_all_fields:
        score += 20
        feedback.append("Report successfully created with all required fields.")
    elif report_exists and report_mtime >= task_start:
        score += 10
        feedback.append(f"Report is missing one or more required fields "
                        f"(Temp='{min_air_temp_raw}', SLP='{siberian_high_raw}').")
    else:
        feedback.append(f"Thermal forcing report missing or not created during task (exists={report_exists}).")

    # ----------------------------------------------------------------
    # Criterion 4: SLP Accuracy (20 pts)
    # Range: 1025 to 1045 hPa (Siberian High center in February)
    # ----------------------------------------------------------------
    slp_val = extract_number(siberian_high_raw)
    if slp_val is not None:
        if 1025.0 <= slp_val <= 1045.0:
            score += 20
            feedback.append(f"Siberian High SLP value ({slp_val} hPa) is scientifically accurate.")
        else:
            feedback.append(f"Siberian High SLP value ({slp_val} hPa) is outside the expected February climatological range [1025, 1045].")
    else:
        feedback.append("Could not extract a numeric value for SIBERIAN_HIGH_CENTER_SLP_HPA.")

    # ----------------------------------------------------------------
    # Criterion 5: Temp Accuracy (20 pts)
    # Range: -40 to -5 C OR 233 to 268 K
    # ----------------------------------------------------------------
    temp_val = extract_number(min_air_temp_raw)
    if temp_val is not None:
        # Check both Celsius and Kelvin valid ranges
        is_celsius = -40.0 <= temp_val <= -5.0
        is_kelvin = 233.0 <= temp_val <= 268.0
        
        if is_celsius or is_kelvin:
            score += 20
            unit_guess = "C" if is_celsius else "K"
            feedback.append(f"Minimum air temperature value ({temp_val} {unit_guess}) is scientifically accurate.")
        else:
            feedback.append(f"Minimum air temperature value ({temp_val}) is outside the expected February climatological range ([-40, -5] C or [233, 268] K).")
    else:
        feedback.append("Could not extract a numeric value for MIN_AIR_TEMP_NORTH_OKHOTSK.")

    # ----------------------------------------------------------------
    # Final Result Compilation
    # ----------------------------------------------------------------
    # Key criteria: Must have successfully extracted at least one scientifically valid parameter 
    # and produced at least one plot.
    key_criteria_met = (slp_val is not None and 1025.0 <= slp_val <= 1045.0) or \
                       (temp_val is not None and (-40.0 <= temp_val <= -5.0 or 233.0 <= temp_val <= 268.0))
    key_criteria_met = key_criteria_met and (airtemp_exists or slp_exists)
    
    passed = score >= 80 and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "details": {
            "airtemp_plot_exists": airtemp_exists,
            "slp_plot_exists": slp_exists,
            "report_exists": report_exists,
            "extracted_slp": slp_val,
            "extracted_temp": temp_val,
            "score": score
        }
    }