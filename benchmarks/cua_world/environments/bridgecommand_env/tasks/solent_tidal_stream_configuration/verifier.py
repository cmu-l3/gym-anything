#!/usr/bin/env python3
"""
Verifier for Solent Tidal Stream Configuration task.
Parses the INI file created by the agent and verifies numerical correctness against the spec.
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_bc_ini(content):
    """
    Parses Bridge Command INI format.
    Handles flat keys like 'Number=1' and indexed keys like 'Direction(1,-6)=86'.
    """
    data = {}
    lines = content.splitlines()
    for line in lines:
        line = line.strip()
        if not line or line.startswith(';'):
            continue
        
        if '=' in line:
            key, value = line.split('=', 1)
            key = key.strip()
            value = value.strip()
            
            # Check for indexed format: Key(Index,Time)
            # e.g., Direction(1,-6) or SpeedS(1,0)
            indexed_match = re.match(r'(\w+)\((\d+)(?:,([-\d]+))?\)', key)
            if indexed_match:
                param = indexed_match.group(1).lower()
                idx = int(indexed_match.group(2))
                time = indexed_match.group(3)
                
                if param not in data:
                    data[param] = {}
                
                if time is not None:
                    # It's time-series data: Direction(1,-6)
                    time = int(time)
                    if idx not in data[param]:
                        data[param][idx] = {}
                    data[param][idx][time] = value
                else:
                    # It's simple indexed data: Lat(1)
                    data[param][idx] = value
            else:
                # Flat key
                data[key.lower()] = value
    return data

def verify_solent_tidal_stream_configuration(traj, env_info, task_info):
    """
    Verifies the tidalstream.ini file content.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_data = metadata.get('data_points', {})

    # Copy result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Basic checks
    if not result.get('file_exists'):
        return {"passed": False, "score": 0, "feedback": "tidalstream.ini file was not created in the correct location."}
    
    if not result.get('newly_created'):
        return {"passed": False, "score": 0, "feedback": "File exists but was not modified during the task."}

    content = result.get('file_content', '')
    parsed = parse_bc_ini(content)
    
    score = 0
    feedback = []
    
    # 1. Header Verification (10 pts)
    # Number=1, MeanRangeSprings=4.2, MeanRangeNeaps=2.1
    try:
        num = int(parsed.get('number', 0))
        mrs = float(parsed.get('meanrangesprings', 0))
        mrn = float(parsed.get('meanrangeneaps', 0))
        
        if num == 1: score += 4
        else: feedback.append(f"Number={num} (expected 1)")
        
        if abs(mrs - 4.2) < 0.1: score += 3
        else: feedback.append(f"MeanRangeSprings={mrs} (expected 4.2)")
        
        if abs(mrn - 2.1) < 0.1: score += 3
        else: feedback.append(f"MeanRangeNeaps={mrn} (expected 2.1)")
        
    except (ValueError, TypeError):
        feedback.append("Header values missing or invalid format")

    # 2. Location Verification (10 pts)
    # Lat(1)=50.7167, Long(1)=-0.9500
    try:
        lat = float(parsed.get('lat', {}).get(1, 0))
        lon = float(parsed.get('long', {}).get(1, 0))
        
        if abs(lat - 50.7167) < 0.001: score += 5
        else: feedback.append(f"Lat={lat} (expected 50.7167)")
        
        if abs(lon - -0.9500) < 0.001: score += 5
        else: feedback.append(f"Long={lon} (expected -0.9500)")
    except (ValueError, TypeError):
        feedback.append("Location values missing or invalid format")

    # 3. Tidal Data Verification (80 pts)
    # 13 hours * 3 params = 39 checks roughly.
    # Group into chunks for cleaner scoring.
    
    data_correct_count = 0
    total_data_points = 13 * 3 # 39
    
    # Map from metadata keys (string '-6') to integers
    # And map internal param names
    param_map = {
        'direction': 0, # Index in expected array
        'speeds': 1,
        'speedn': 2
    }

    for t_str, vals in expected_data.items():
        t = int(t_str)
        
        # Check Direction
        try:
            val = float(parsed.get('direction', {}).get(1, {}).get(t, -999))
            if abs(val - vals[0]) <= 1.0: data_correct_count += 1
        except: pass
            
        # Check SpeedSprings
        try:
            val = float(parsed.get('speeds', {}).get(1, {}).get(t, -999))
            if abs(val - vals[1]) <= 0.1: data_correct_count += 1
        except: pass
        
        # Check SpeedNeaps
        try:
            val = float(parsed.get('speedn', {}).get(1, {}).get(t, -999))
            if abs(val - vals[2]) <= 0.1: data_correct_count += 1
        except: pass

    # Calculate data score
    # 39 points total. 80 points allocated. ~2 pts per correct value.
    data_score = int((data_correct_count / total_data_points) * 80)
    score += data_score
    
    if data_correct_count < total_data_points:
        feedback.append(f"Tidal data incomplete or inaccurate: {data_correct_count}/{total_data_points} values correct.")
    else:
        feedback.append("All tidal data points correct.")

    passed = score >= 80
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback)
    }