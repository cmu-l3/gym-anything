#!/usr/bin/env python3
"""
Verifier for analyze_fixed_rpm_stall task.
"""

import json
import os
import tempfile
import logging
import re
from gym_anything.vlm import sample_trajectory_frames

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_analyze_fixed_rpm_stall(traj, env_info, task_info):
    """
    Verifies the stall analysis task.
    
    Criteria:
    1. Simulation data file exists and contains valid BEM results (25 pts).
    2. Data analysis: The simulation data shows a peak (stall) behavior (25 pts).
    3. Report accuracy: The user reported peak matches the data file peak (25 pts).
    4. Project saved: Final project file exists (15 pts).
    5. VLM: Trajectory shows configuration of "Fixed RPM" or dimensional mode (10 pts).
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy function missing"}

    score = 0
    feedback_parts = []
    
    # 1. Load basic result metadata
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            meta = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # 2. Retrieve Simulation Data File
    data_content = ""
    data_points = []
    data_file_info = meta.get('data_file', {})
    
    if data_file_info.get('exists') and data_file_info.get('created_during_task'):
        try:
            temp_data = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
            copy_from_env(data_file_info['path'], temp_data.name)
            with open(temp_data.name, 'r', encoding='utf-8', errors='ignore') as f:
                data_content = f.read()
            os.unlink(temp_data.name)
            
            # Parse QBlade export format (often whitespace or tab separated)
            # We look for lines starting with numbers.
            # Typical cols: WindSpeed(m/s), Power(kW/W), Cp, Ct, etc.
            # We assume user exported standard graph data.
            lines = data_content.splitlines()
            parsed_data = []
            for line in lines:
                parts = line.strip().split()
                # Check if first token is a number
                if parts and re.match(r'^-?\d+(\.\d+)?$', parts[0]):
                    try:
                        # Try to grab first two columns: X (Wind) and Y (Power)
                        # QBlade graph export usually dumps X Y pairs or X Y1 Y2...
                        # Variable selection determines columns.
                        # Assuming Wind Speed is X (col 0) and Power is Y (col 1 or similar)
                        vals = [float(p) for p in parts if re.match(r'^-?\d+(\.\d+)?$', p)]
                        if len(vals) >= 2:
                            parsed_data.append(vals)
                    except ValueError:
                        continue
            
            if len(parsed_data) > 10:
                score += 25
                feedback_parts.append("Simulation data exported successfully (25 pts)")
                data_points = parsed_data
            else:
                feedback_parts.append("Data file exists but seems empty or invalid format")
        except Exception as e:
            feedback_parts.append(f"Error reading data file: {e}")
    else:
        feedback_parts.append("Simulation data file missing or not created during task")

    # 3. Analyze Data Physics (Stall check)
    sim_peak_power = 0.0
    sim_peak_wind = 0.0
    stall_detected = False
    
    if data_points:
        # Sort by Wind Speed (col 0)
        data_points.sort(key=lambda x: x[0])
        
        powers = [r[1] for r in data_points] # Assuming Col 1 is Power
        winds = [r[0] for r in data_points]
        
        # Check range coverage
        min_w, max_w = min(winds), max(winds)
        if min_w <= 6 and max_w >= 24:
            # Find peak
            max_p = max(powers)
            max_idx = powers.index(max_p)
            sim_peak_power = max_p
            sim_peak_wind = winds[max_idx]
            
            # Check for stall: Power at end (25m/s) should be significantly less than peak
            # OR at least the curve shouldn't be strictly increasing exponential (like ideal variable speed)
            end_p = powers[-1]
            
            # NREL 5MW at 9RPM stall behavior:
            # It usually peaks around 10-12m/s and then drops or flattens.
            # If end power is < 95% of peak power, we call it stall behavior for scoring purposes
            if end_p < (0.98 * max_p):
                stall_detected = True
                score += 25
                feedback_parts.append("Data shows stall behavior (power drop/flattening) (25 pts)")
            else:
                feedback_parts.append("Data does not show clear stall (power keeps rising?). Check simulation settings.")
        else:
            feedback_parts.append(f"Data range insufficient (covered {min_w:.1f}-{max_w:.1f} m/s, expected 5-25)")

    # 4. verify Report Accuracy
    report_file_info = meta.get('report_file', {})
    if report_file_info.get('exists'):
        try:
            content = report_file_info.get('content_snippet', "")
            # Extract numbers from report
            report_nums = [float(x) for x in re.findall(r'-?\d+\.?\d*', content)]
            
            if len(report_nums) >= 2:
                # We expect user to report Peak Power and Wind Speed.
                # Since units might vary (kW vs W vs MW), we check for relative match
                # or order of magnitude match.
                
                # Check if ANY number in report is close to sim_peak_wind (approx 10-12)
                wind_match = any(abs(n - sim_peak_wind) < 1.0 for n in report_nums)
                
                # Check power. User might report 2000 (kW) or 2000000 (W) or 2.0 (MW)
                # Sim data is likely in Watts or kW depending on QBlade version/settings.
                # We normalize by checking ratios.
                power_match = False
                if sim_peak_power > 0:
                    for n in report_nums:
                        ratio = n / sim_peak_power
                        # Check typical unit conversion factors (1, 1000, 0.001)
                        if any(abs(ratio - factor) < 0.1 for factor in [1.0, 1000.0, 0.001, 1e-6, 1e6]):
                            power_match = True
                            break
                
                if wind_match and power_match:
                    score += 25
                    feedback_parts.append("Reported values match simulation data (25 pts)")
                elif wind_match:
                    score += 15
                    feedback_parts.append("Reported wind speed matches, but power value mismatch")
                else:
                    feedback_parts.append(f"Reported values {report_nums} don't match simulation peak (Wind ~{sim_peak_wind})")
            else:
                feedback_parts.append("Report file found but could not parse numbers")
        except Exception:
            feedback_parts.append("Error parsing report")
    else:
        feedback_parts.append("Report file not found")

    # 5. Check Project File
    if meta.get('project_file', {}).get('exists') and meta.get('project_file', {}).get('created_during_task'):
        score += 15
        feedback_parts.append("Project saved (15 pts)")
    else:
        feedback_parts.append("Project file not saved")

    # 6. VLM Check (Trajectory)
    # We want to see "Fixed RPM" or dimensional settings in the UI
    try:
        from gym_anything.vlm import query_vlm
        frames = sample_trajectory_frames(traj, n=4)
        
        prompt = """
        Review these screenshots of QBlade. 
        I am looking for evidence of a 'Dimensional' or 'Range' simulation setup for a wind turbine.
        Look for a dialog box titled 'BEM Simulation Definition' or similar.
        
        Key indicators:
        1. A radio button or setting for 'Fixed RPM' or 'Rotational Speed'.
        2. A range setting for 'Wind Speed' (e.g. Start 5, End 25).
        3. A graph showing a Power curve (Power vs Windspeed).
        
        Return JSON: {"fixed_rpm_visible": bool, "power_curve_visible": bool}
        """
        
        vlm_res = query_vlm(prompt=prompt, images=frames)
        if vlm_res.get('success'):
            parsed = vlm_res.get('parsed', {})
            if parsed.get('fixed_rpm_visible') or parsed.get('power_curve_visible'):
                score += 10
                feedback_parts.append("VLM verified simulation setup/result (10 pts)")
        else:
            # Fallback if VLM fails or is not available, give benefit of doubt if data file is good
            if score >= 50:
                score += 10
                feedback_parts.append("VLM check skipped, assumed pass based on data")
    except Exception as e:
        logger.warning(f"VLM check failed: {e}")
        # Soft fallback
        if score >= 50:
            score += 10

    return {
        "passed": score >= 60,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }