#!/usr/bin/env python3
"""
Verifier for bering_sea_freezing_spray_assessment task.
"""

import json
import os
import tempfile
import re

def verify_bering_sea_freezing_spray_assessment(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp.close()
    try:
        copy_from_env('/tmp/bering_sea_freezing_spray_assessment_result.json', tmp.name)
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
    # Criterion 1: SST Map Exported (20 pts)
    # ----------------------------------------------------------------
    sst_exists = result.get('sst_plot_exists', False)
    sst_mtime = int(result.get('sst_plot_mtime', 0))
    sst_size = int(result.get('sst_plot_size', 0))

    if sst_exists and sst_mtime >= task_start and sst_size >= 15000:
        score += 20
        feedback.append(f"SST plot exported ({sst_size} bytes)")
    elif sst_exists and sst_mtime >= task_start and sst_size >= 5000:
        score += 10
        feedback.append(f"SST plot present but small ({sst_size} bytes, expected >=15KB)")
    else:
        feedback.append(f"SST plot missing or not created during task "
                        f"(exists={sst_exists}, size={sst_size}, mtime={sst_mtime} vs start={task_start})")

    # ----------------------------------------------------------------
    # Criterion 2: Air Temp Map Exported (20 pts)
    # ----------------------------------------------------------------
    airtemp_exists = result.get('airtemp_plot_exists', False)
    airtemp_mtime = int(result.get('airtemp_plot_mtime', 0))
    airtemp_size = int(result.get('airtemp_plot_size', 0))

    if airtemp_exists and airtemp_mtime >= task_start and airtemp_size >= 15000:
        score += 20
        feedback.append(f"Air Temp plot exported ({airtemp_size} bytes)")
    elif airtemp_exists and airtemp_mtime >= task_start and airtemp_size >= 5000:
        score += 10
        feedback.append(f"Air Temp plot present but small ({airtemp_size} bytes, expected >=15KB)")
    else:
        feedback.append(f"Air Temp plot missing or not created during task "
                        f"(exists={airtemp_exists}, size={airtemp_size})")

    # ----------------------------------------------------------------
    # Criterion 3: Report Structure (20 pts)
    # ----------------------------------------------------------------
    report_exists = result.get('report_exists', False)
    report_mtime = int(result.get('report_mtime', 0))
    target_basin = result.get('target_basin', '').strip()
    analysis_month = result.get('analysis_month', '').strip()
    hazard_type = result.get('hazard_type', '').strip()
    risk_level = result.get('risk_level', '').strip()

    has_basin = bool(target_basin)
    has_month = bool(analysis_month)
    has_hazard = bool(hazard_type)
    has_risk = bool(risk_level)

    if report_exists and report_mtime >= task_start and has_basin and has_month and has_hazard and has_risk:
        score += 20
        feedback.append(f"Report complete (basin='{target_basin}', hazard='{hazard_type}')")
    elif report_exists and report_mtime >= task_start and (has_basin or has_month):
        score += 10
        missing = [f for f, v in [('TARGET_BASIN', target_basin),
                                  ('ANALYSIS_MONTH', analysis_month),
                                  ('HAZARD_TYPE', hazard_type),
                                  ('RISK_LEVEL', risk_level)] if not v]
        feedback.append(f"Report partial — missing fields: {missing}")
    else:
        feedback.append(f"Report missing or incomplete (exists={report_exists})")

    # Helper function to extract numeric value from string
    def extract_float(text):
        match = re.search(r'[-+]?\d*\.\d+|\d+', text)
        if match:
            return float(match.group())
        return None

    # ----------------------------------------------------------------
    # Criterion 4: Scientific Accuracy - Water (20 pts)
    # Expected central Bering Sea SST in Jan: -2°C to 6°C
    # ----------------------------------------------------------------
    sst_c_raw = result.get('approx_sst_c', '').strip()
    sst_val = extract_float(sst_c_raw)
    
    sci_water_pass = False
    if sst_val is not None:
        if -2.0 <= sst_val <= 6.0:
            score += 20
            sci_water_pass = True
            feedback.append(f"APPROX_SST_C={sst_val}°C is within valid winter range (-2 to 6°C)")
        else:
            feedback.append(f"APPROX_SST_C={sst_val}°C is outside typical winter range (-2 to 6°C)")
    else:
        feedback.append("Could not parse APPROX_SST_C value")

    # ----------------------------------------------------------------
    # Criterion 5: Scientific Accuracy - Air Temp (Unit Check) (20 pts)
    # Expected central Bering Sea Air Temp in Jan: -25°C to 0°C
    # Panoply shows Kelvin (~248 to ~273 K). If agent puts ~260, they fail unit conversion.
    # ----------------------------------------------------------------
    air_c_raw = result.get('approx_air_temp_c', '').strip()
    air_val = extract_float(air_c_raw)
    
    sci_air_pass = False
    if air_val is not None:
        if -25.0 <= air_val <= 0.0:
            score += 20
            sci_air_pass = True
            feedback.append(f"APPROX_AIR_TEMP_C={air_val}°C is within valid winter range (-25 to 0°C). Unit conversion successful.")
        elif 248.0 <= air_val <= 273.15:
            # Agent failed to convert Kelvin to Celsius
            feedback.append(f"APPROX_AIR_TEMP_C={air_val} appears to be in Kelvin, not Celsius as required!")
        else:
            feedback.append(f"APPROX_AIR_TEMP_C={air_val}°C is outside typical winter range (-25 to 0°C)")
    else:
        feedback.append("Could not parse APPROX_AIR_TEMP_C value")

    # Overall pass condition: Score >= 80 AND both scientific criteria passed
    passed = (score >= 80) and sci_water_pass and sci_air_pass

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "subscores": {
            "sst_plot": sst_exists and sst_size >= 15000,
            "airtemp_plot": airtemp_exists and airtemp_size >= 15000,
            "report_structure": has_basin and has_month and has_hazard and has_risk,
            "sci_water_pass": sci_water_pass,
            "sci_air_pass": sci_air_pass
        }
    }