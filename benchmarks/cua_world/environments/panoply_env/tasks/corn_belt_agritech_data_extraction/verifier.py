#!/usr/bin/env python3
"""
Verifier for corn_belt_agritech_data_extraction task.

Occupation: Agricultural Data Scientist
Industry: AgTech / Precision Agriculture
Difficulty: hard

This task requires the agent to extract RAW DATA (CSV) rather than visual plots.
The verifier checks the numeric contents of the CSV files to guarantee that the
agent actually extracted data at the correct Lat/Lon coordinates (Anti-Gaming).

Scoring criteria (100 pts total, pass threshold = 80):
  1. Temperature CSV properly extracted (20 pts)
  2. Precipitation CSV properly extracted (20 pts)
  3. Temperature cryptographic/numeric accuracy (20 pts): The CSV must show
     the 42N/266E location in the header, and summer temps must > winter temps.
  4. Precipitation cryptographic/numeric accuracy (20 pts): The CSV must show
     the 42N/266E location.
  5. Summary report accuracy (20 pts): Report must have correct fields and correctly
     identify Summer (Jun/Jul/Aug) as the peak for both variables.
"""

import json
import os
import tempfile
import re


def _parse_panoply_csv(filepath):
    """
    Parses a Panoply exported 1D CSV file.
    Returns metadata dict and data list of floats.
    """
    metadata = {}
    data_values = []
    
    try:
        with open(filepath, 'r', encoding='utf-8', errors='replace') as f:
            lines = f.readlines()
            
        is_data_section = False
        for line in lines:
            line = line.strip()
            if not line:
                continue
            
            # Look for dimension headers like "lat","41.9047"
            if not is_data_section and line.startswith('"lat"'):
                parts = line.split(',')
                if len(parts) >= 2:
                    metadata['lat'] = parts[1].replace('"', '')
            elif not is_data_section and line.startswith('"lon"'):
                parts = line.split(',')
                if len(parts) >= 2:
                    metadata['lon'] = parts[1].replace('"', '')
            
            # Detect start of data
            if line.startswith('"Time"') or "Time" in line and "," in line:
                is_data_section = True
                continue
                
            if is_data_section:
                # Row looks like: "1", "22.5"
                parts = line.split(',')
                if len(parts) >= 2:
                    try:
                        val = float(parts[1].replace('"', '').strip())
                        data_values.append(val)
                    except ValueError:
                        pass
    except Exception as e:
        print(f"Error parsing CSV {filepath}: {e}")
        
    return metadata, data_values


def verify_corn_belt_agritech_data_extraction(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    # Retrieve all result files
    files_to_copy = {
        'result_json': '/tmp/corn_belt_agritech_data_extraction_result.json',
        'temp_csv': '/tmp/iowa_temp_climatology.csv',
        'precip_csv': '/tmp/iowa_precip_climatology.csv',
        'report': '/tmp/feature_summary.txt'
    }
    
    local_paths = {}
    
    for key, remote_path in files_to_copy.items():
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        tmp.close()
        try:
            copy_from_env(remote_path, tmp.name)
            local_paths[key] = tmp.name
        except Exception:
            local_paths[key] = None

    try:
        if local_paths['result_json'] and os.path.exists(local_paths['result_json']):
            with open(local_paths['result_json'], 'r') as f:
                result = json.load(f)
        else:
            result = {}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve result JSON: {e}"}

    score = 0
    feedback = []
    task_start = int(result.get('task_start', 0))

    # ----------------------------------------------------------------
    # Criterion 1 & 3: Temp CSV format and numeric accuracy (40 pts total)
    # ----------------------------------------------------------------
    temp_exists = result.get('temp_csv_exists', False)
    temp_mtime = int(result.get('temp_csv_mtime', 0))
    temp_size = int(result.get('temp_csv_size', 0))
    
    temp_data_valid = False
    
    if temp_exists and temp_mtime >= task_start and temp_size > 100:
        score += 20
        feedback.append("Temperature CSV created successfully.")
        
        # Numeric check
        if local_paths['temp_csv'] and os.path.exists(local_paths['temp_csv']):
            meta, data = _parse_panoply_csv(local_paths['temp_csv'])
            
            # Check if Lat/Lon matches approximately 42 and 266
            lat = meta.get('lat', '')
            lon = meta.get('lon', '')
            
            is_correct_location = ('41.' in lat or '42.' in lat) and ('266.' in lon)
            
            # Check seasonal curve: Summer (idx 5,6,7) > Winter (idx 0,1,11)
            is_curve_valid = False
            if len(data) >= 12:
                summer_avg = sum(data[5:8]) / 3
                winter_avg = (data[0] + data[1] + data[11]) / 3
                if summer_avg > winter_avg:
                    is_curve_valid = True
                    
            if is_correct_location and is_curve_valid:
                score += 20
                temp_data_valid = True
                feedback.append(f"Temperature data cryptographically verified (Lat: {lat}, Lon: {lon}, NCEP summer peak confirmed).")
            else:
                feedback.append(f"Temperature data is invalid or wrong location (Lat: {lat}, Lon: {lon}).")
    else:
        feedback.append("Temperature CSV missing or invalid.")

    # ----------------------------------------------------------------
    # Criterion 2 & 4: Precip CSV format and numeric accuracy (40 pts total)
    # ----------------------------------------------------------------
    precip_exists = result.get('precip_csv_exists', False)
    precip_mtime = int(result.get('precip_csv_mtime', 0))
    precip_size = int(result.get('precip_csv_size', 0))
    
    precip_data_valid = False

    if precip_exists and precip_mtime >= task_start and precip_size > 100:
        score += 20
        feedback.append("Precipitation CSV created successfully.")
        
        if local_paths['precip_csv'] and os.path.exists(local_paths['precip_csv']):
            meta, data = _parse_panoply_csv(local_paths['precip_csv'])
            
            lat = meta.get('lat', '')
            lon = meta.get('lon', '')
            
            is_correct_location = ('41.' in lat or '42.' in lat) and ('266.' in lon)
            if is_correct_location and len(data) >= 12:
                score += 20
                precip_data_valid = True
                feedback.append(f"Precipitation data cryptographically verified (Lat: {lat}, Lon: {lon}).")
            else:
                feedback.append(f"Precipitation data is invalid or wrong location (Lat: {lat}, Lon: {lon}).")
    else:
        feedback.append("Precipitation CSV missing or invalid.")

    # ----------------------------------------------------------------
    # Criterion 5: Feature Summary Report (20 pts)
    # ----------------------------------------------------------------
    report_exists = result.get('report_exists', False)
    report_mtime = int(result.get('report_mtime', 0))
    
    if report_exists and report_mtime >= task_start:
        if local_paths['report'] and os.path.exists(local_paths['report']):
            with open(local_paths['report'], 'r', errors='replace') as f:
                report_content = f.read().upper()
                
            has_lat = "ANALYSIS_LAT" in report_content
            has_lon = "ANALYSIS_LON" in report_content
            
            # Check if summer months are identified as peaks
            summer_months = ["JUN", "JUL", "AUG", "6", "7", "8"]
            
            # We look closely at the lines
            peak_temp = ""
            peak_precip = ""
            for line in report_content.splitlines():
                if "PEAK_TEMP_MONTH:" in line:
                    peak_temp = line.split(":", 1)[1].strip()
                elif "PEAK_PRECIP_MONTH:" in line:
                    peak_precip = line.split(":", 1)[1].strip()
                    
            temp_is_summer = any(sm in peak_temp for sm in summer_months)
            precip_is_summer = any(sm in peak_precip for sm in summer_months)
            
            if has_lat and has_lon and temp_is_summer and precip_is_summer:
                score += 20
                feedback.append("Feature Summary Report is complete and scientifically accurate.")
            else:
                score += 10
                feedback.append("Feature Summary Report exists but is missing required keys or has incorrect peak months.")
    else:
        feedback.append("Feature Summary Report missing or not created during task.")

    # Cleanup temp files
    for path in local_paths.values():
        if path and os.path.exists(path):
            try:
                os.unlink(path)
            except Exception:
                pass

    passed = score >= 80 and temp_data_valid
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback)
    }