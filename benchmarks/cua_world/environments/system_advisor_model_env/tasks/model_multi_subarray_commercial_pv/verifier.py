#!/usr/bin/env python3
"""Verifier for model_multi_subarray_commercial_pv task.

Validates that the agent correctly modeled a two-subarray PV system
using PySAM and exported the required structured JSON output.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_multi_subarray_pv(traj, env_info, task_info):
    """Verify multi-subarray PV modeling was completed successfully.
    
    Scoring: 100 points max
    - File exists & recent: 10
    - Valid JSON structure: 10
    - Total DC capacity correct: 10
    - Subarray 1 config (azimuth, tilt, capacity): 10
    - Subarray 2 config (azimuth, tilt, capacity): 10
    - Annual energy plausible: 15
    - Subarray 1 outperforms Subarray 2 (per kW): 10
    - Capacity factor plausible: 10
    - LCOE reported & plausible: 10
    - Weather file referenced: 5
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_output_path = metadata.get('expected_output_path', '/home/ga/Documents/SAM_Projects/multi_subarray_results.json')
    expected_location = metadata.get('expected_location', 'phoenix')
    
    # Tolerances & ranges
    sys_dc_min = metadata.get('system_dc_min', 95.0)
    sys_dc_max = metadata.get('system_dc_max', 105.0)
    sa1_dc_min = metadata.get('sa1_dc_min', 55.0)
    sa1_dc_max = metadata.get('sa1_dc_max', 65.0)
    sa2_dc_min = metadata.get('sa2_dc_min', 35.0)
    sa2_dc_max = metadata.get('sa2_dc_max', 45.0)
    sa1_azi = metadata.get('sa1_azimuth', 180)
    sa1_tilt = metadata.get('sa1_tilt', 15)
    sa2_azi = metadata.get('sa2_azimuth', 270)
    sa2_tilt = metadata.get('sa2_tilt', 10)
    annual_en_min = metadata.get('annual_energy_min', 120000)
    annual_en_max = metadata.get('annual_energy_max', 220000)
    cf_min = metadata.get('cf_min', 14.0)
    cf_max = metadata.get('cf_max', 28.0)
    lcoe_min = metadata.get('lcoe_min', 3.0)
    lcoe_max = metadata.get('lcoe_max', 30.0)

    # 1. Read task_result.json from the container (for metadata & anti-gaming)
    temp_meta = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_meta.name)
        with open(temp_meta.name, 'r') as f:
            result_meta = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result meta: {e}"}
    finally:
        if os.path.exists(temp_meta.name):
            os.unlink(temp_meta.name)

    score = 0
    feedback_parts = []

    # Check existence & recency
    file_exists = result_meta.get('file_exists') is True or str(result_meta.get('file_exists')).lower() == 'true'
    file_modified = result_meta.get('file_modified') is True or str(result_meta.get('file_modified')).lower() == 'true'

    if file_modified:
        score += 10
        feedback_parts.append("File exists and was created/modified during task")
    elif file_exists:
        score += 2
        feedback_parts.append("File exists but was NOT modified during task (possible anti-gaming violation)")
    else:
        return {"passed": False, "score": 0, "feedback": "Output file does not exist."}

    # 2. Independently copy and parse the agent's output JSON
    temp_output = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    agent_data = {}
    try:
        copy_from_env(expected_output_path, temp_output.name)
        with open(temp_output.name, 'r') as f:
            agent_data = json.load(f)
    except Exception as e:
        feedback_parts.append(f"Failed to parse agent JSON output: {e}")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}
    finally:
        if os.path.exists(temp_output.name):
            os.unlink(temp_output.name)

    # Helper function to extract float safely
    def get_float(obj, key, default=None):
        try:
            val = obj.get(key)
            if val is not None:
                return float(val)
        except (ValueError, TypeError, AttributeError):
            pass
        return default

    # Structure Check (10 pts)
    req_keys = ['system', 'subarray1', 'subarray2', 'annual_energy_kwh', 'capacity_factor_pct', 'lcoe_real_cents_per_kwh']
    missing_keys = [k for k in req_keys if k not in agent_data]
    if not missing_keys:
        score += 10
        feedback_parts.append("Valid JSON structure")
    else:
        feedback_parts.append(f"JSON missing keys: {', '.join(missing_keys)}")

    # Weather file referenced (5 pts)
    weather_file = str(agent_data.get('weather_file', '')).lower()
    location_str = str(agent_data.get('location', '')).lower()
    if expected_location in weather_file or expected_location in location_str or 'tmy' in weather_file or 'az' in location_str:
        score += 5
        feedback_parts.append("Weather file/location plausible")
    else:
        feedback_parts.append("Location/Weather reference missing or incorrect")

    # Extract System info
    sys_info = agent_data.get('system', {})
    total_dc = get_float(sys_info, 'total_dc_capacity_kw', 0)
    
    if sys_dc_min <= total_dc <= sys_dc_max:
        score += 10
        feedback_parts.append(f"Total DC capacity correct ({total_dc} kW)")
    else:
        feedback_parts.append(f"Total DC capacity out of range ({total_dc} kW)")

    # Extract Subarray 1 info
    sa1 = agent_data.get('subarray1', {})
    sa1_dc = get_float(sa1, 'dc_capacity_kw', 0)
    sa1_az = get_float(sa1, 'azimuth_deg', -1)
    sa1_t = get_float(sa1, 'tilt_deg', -1)
    sa1_en = get_float(sa1, 'annual_energy_kwh', 0)

    sa1_config_ok = (sa1_dc_min <= sa1_dc <= sa1_dc_max) and (abs(sa1_az - sa1_azi) <= 5) and (abs(sa1_t - sa1_tilt) <= 5)
    if sa1_config_ok:
        score += 10
        feedback_parts.append("Subarray 1 config correct")
    else:
        feedback_parts.append(f"Subarray 1 config incorrect (DC:{sa1_dc}, Azi:{sa1_az}, Tilt:{sa1_t})")

    # Extract Subarray 2 info
    sa2 = agent_data.get('subarray2', {})
    sa2_dc = get_float(sa2, 'dc_capacity_kw', 0)
    sa2_az = get_float(sa2, 'azimuth_deg', -1)
    sa2_t = get_float(sa2, 'tilt_deg', -1)
    sa2_en = get_float(sa2, 'annual_energy_kwh', 0)

    sa2_config_ok = (sa2_dc_min <= sa2_dc <= sa2_dc_max) and (abs(sa2_az - sa2_azi) <= 5) and (abs(sa2_t - sa2_tilt) <= 5)
    if sa2_config_ok:
        score += 10
        feedback_parts.append("Subarray 2 config correct")
    else:
        feedback_parts.append(f"Subarray 2 config incorrect (DC:{sa2_dc}, Azi:{sa2_az}, Tilt:{sa2_t})")

    # Energy plausible (15 pts)
    tot_energy = get_float(agent_data, 'annual_energy_kwh', 0)
    if annual_en_min <= tot_energy <= annual_en_max:
        score += 15
        feedback_parts.append(f"Annual energy plausible ({tot_energy:,.0f} kWh)")
    else:
        feedback_parts.append(f"Annual energy out of range ({tot_energy:,.0f} kWh)")

    # Subarray comparison physics (10 pts)
    # South facing (SA1) should have a higher specific yield (kWh/kW) than West facing (SA2)
    if sa1_dc > 0 and sa2_dc > 0 and sa1_en > 0 and sa2_en > 0:
        sa1_yield = sa1_en / sa1_dc
        sa2_yield = sa2_en / sa2_dc
        if sa1_yield > sa2_yield:
            score += 10
            feedback_parts.append("Subarray yields physically logical (South > West)")
        else:
            feedback_parts.append(f"Subarray yields inverted or equal (South: {sa1_yield:.1f}, West: {sa2_yield:.1f} kWh/kW)")
    else:
        feedback_parts.append("Subarray energy missing for yield comparison")

    # Capacity factor plausible (10 pts)
    cf = get_float(agent_data, 'capacity_factor_pct', 0)
    if cf_min <= cf <= cf_max:
        score += 10
        feedback_parts.append(f"Capacity factor plausible ({cf}%)")
    else:
        feedback_parts.append(f"Capacity factor out of bounds ({cf}%)")

    # LCOE plausible (10 pts)
    lcoe = get_float(agent_data, 'lcoe_real_cents_per_kwh', -1)
    if lcoe_min <= lcoe <= lcoe_max:
        score += 10
        feedback_parts.append(f"LCOE plausible ({lcoe} ¢/kWh)")
    else:
        feedback_parts.append(f"LCOE missing or out of bounds ({lcoe} ¢/kWh)")

    passed = score >= 65 and file_modified and (annual_en_min <= tot_energy <= annual_en_max)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }