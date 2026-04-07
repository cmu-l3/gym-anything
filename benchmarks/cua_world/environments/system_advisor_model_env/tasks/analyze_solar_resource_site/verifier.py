#!/usr/bin/env python3
"""
Verifier for analyze_solar_resource_site task.

Verifies that the agent correctly parsed a TMY weather file and calculated 
annual/monthly resource statistics, generating a strictly formatted JSON report.
"""

import os
import json
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_solar_resource_assessment(traj, env_info, task_info):
    """
    Verify the site assessment JSON output.
    
    Scoring: 100 points total
    - File exists & created during task: 15
    - Valid JSON structure: 15
    - Annual stats in range (GHI, DNI, DHI, PSH): 30
    - Environmental stats in range (Temp, Wind): 10
    - Math checks (Latitude, Tilt): 10
    - Monthly GHI arrays present & seasonal pattern: 10
    - Internal consistency (Monthly sum ≈ Annual): 10
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    ranges = metadata.get('ranges', {})

    score = 0
    feedback_parts = []
    
    # 1. Read metadata from export_result.sh
    meta_temp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", meta_temp.name)
        with open(meta_temp.name, 'r') as f:
            export_meta = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read export metadata: {e}"}
    finally:
        if os.path.exists(meta_temp.name):
            os.unlink(meta_temp.name)

    # Criterion 1: File Exists & Created During Task (15 pts)
    file_exists = export_meta.get('file_exists', False)
    file_modified = export_meta.get('file_modified_during_task', False)
    
    if not file_exists:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Output file /home/ga/Documents/SAM_Projects/phoenix_site_assessment.json does not exist."
        }
        
    if file_modified:
        score += 15
        feedback_parts.append("File created/modified during task")
    else:
        feedback_parts.append("File exists but timestamp indicates it wasn't modified during task")
        # Give partial credit if it exists but wasn't flagged as modified (time edge cases)
        score += 5

    # 2. Read actual agent output file
    target_path = "/home/ga/Documents/SAM_Projects/phoenix_site_assessment.json"
    agent_temp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    
    agent_data = {}
    valid_json = False
    try:
        copy_from_env(target_path, agent_temp.name)
        with open(agent_temp.name, 'r') as f:
            agent_data = json.load(f)
        valid_json = True
    except Exception as e:
        feedback_parts.append(f"Invalid JSON format: {e}")
    finally:
        if os.path.exists(agent_temp.name):
            os.unlink(agent_temp.name)

    if not valid_json:
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }
        
    # Criterion 2: Valid JSON structure (15 pts)
    expected_keys = [
        "latitude", "annual_ghi_kwh_per_m2", "annual_dni_kwh_per_m2",
        "annual_dhi_kwh_per_m2", "peak_sun_hours_per_day", "avg_temperature_c",
        "avg_wind_speed_ms", "recommended_tilt_deg", "monthly_ghi_kwh_per_m2"
    ]
    
    missing_keys = [k for k in expected_keys if k not in agent_data]
    if not missing_keys:
        score += 15
        feedback_parts.append("JSON contains all required keys")
    else:
        found_keys = len(expected_keys) - len(missing_keys)
        score += int(15 * (found_keys / len(expected_keys)))
        feedback_parts.append(f"Missing JSON keys: {', '.join(missing_keys)}")

    # Helper function for range checking
    def check_range(key, range_tuple, pts):
        val = agent_data.get(key)
        if val is None:
            return 0, f"Missing {key}"
        try:
            val = float(val)
            if range_tuple[0] <= val <= range_tuple[1]:
                return pts, f"{key} correct ({val:.1f})"
            else:
                return 0, f"{key} out of range ({val:.1f}, expected {range_tuple})"
        except (ValueError, TypeError):
            return 0, f"{key} is not a valid number"

    # Criterion 3: Annual stats in range (30 pts)
    ghi_pts, ghi_fb = check_range("annual_ghi_kwh_per_m2", ranges.get("annual_ghi", [1800, 2300]), 10)
    dni_pts, dni_fb = check_range("annual_dni_kwh_per_m2", ranges.get("annual_dni", [2300, 2900]), 8)
    dhi_pts, dhi_fb = check_range("annual_dhi_kwh_per_m2", ranges.get("annual_dhi", [500, 900]), 6)
    psh_pts, psh_fb = check_range("peak_sun_hours_per_day", ranges.get("psh", [4.9, 6.3]), 6)
    
    score += (ghi_pts + dni_pts + dhi_pts + psh_pts)
    feedback_parts.extend([ghi_fb, dni_fb, dhi_fb, psh_fb])

    # Criterion 4: Environmental stats (10 pts)
    temp_pts, temp_fb = check_range("avg_temperature_c", ranges.get("temp", [20, 28]), 5)
    wind_pts, wind_fb = check_range("avg_wind_speed_ms", ranges.get("wind", [1.0, 6.0]), 5)
    
    score += (temp_pts + wind_pts)
    feedback_parts.extend([temp_fb, wind_fb])

    # Criterion 5: Math Checks (10 pts)
    lat_pts, lat_fb = check_range("latitude", ranges.get("latitude", [33.0, 34.0]), 5)
    tilt_pts, tilt_fb = check_range("recommended_tilt_deg", ranges.get("tilt", [25.0, 35.0]), 5)
    
    score += (lat_pts + tilt_pts)
    feedback_parts.extend([lat_fb, tilt_fb])

    # Criterion 6: Monthly GHI Arrays (10 pts)
    monthly = agent_data.get("monthly_ghi_kwh_per_m2")
    monthly_valid = False
    if isinstance(monthly, list) and len(monthly) == 12:
        try:
            monthly_vals = [float(x) for x in monthly]
            
            # Seasonal Check: Summer (Jun-Aug) > Winter (Dec-Feb)
            summer_avg = sum(monthly_vals[5:8]) / 3
            winter_avg = (monthly_vals[11] + monthly_vals[0] + monthly_vals[1]) / 3
            
            if summer_avg > winter_avg * 1.3:
                score += 10
                feedback_parts.append("Monthly GHI present and shows realistic seasonal curve")
                monthly_valid = True
            else:
                score += 5
                feedback_parts.append("Monthly GHI present but seasonal curve looks flat/incorrect")
                monthly_valid = True
        except (ValueError, TypeError):
            feedback_parts.append("Monthly GHI contains non-numeric values")
    else:
        feedback_parts.append("Monthly GHI is missing or not a list of 12 elements")

    # Criterion 7: Internal consistency (10 pts)
    if monthly_valid and ghi_pts > 0:
        annual_calc = sum(monthly_vals)
        annual_reported = float(agent_data.get("annual_ghi_kwh_per_m2", 0))
        
        # Should be within ~5% tolerance due to floating point or leap year variations
        if abs(annual_calc - annual_reported) < (annual_reported * 0.05):
            score += 10
            feedback_parts.append("Internal consistency passed (sum of monthly ≈ annual)")
        else:
            feedback_parts.append(f"Internal consistency failed (sum monthly={annual_calc:.1f} vs reported={annual_reported:.1f})")

    # Final pass/fail determination
    key_criteria_met = file_modified and valid_json and (ghi_pts > 0)
    passed = score >= 75 and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }