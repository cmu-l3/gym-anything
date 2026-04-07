#!/usr/bin/env python3
"""
Verifier for geo_colocation_vector_separation@1

Agent must simulate two geostationary satellites with specific eccentricity and 
inclination vector separation to verify collision avoidance over 14 days.

Scoring (total 100 pts, pass >= 60):
  - Script Created (10): Script was created during the task window.
  - Report Generated (10): Ephemeris report file exists and is non-empty.
  - Data Completeness (15): Ephemeris file has at least 330 rows containing X, Y, Z for both sats.
  - Propagation Sync (25): Max distance <= 150 km (proves simultaneous propagation).
  - Collision Avoidance (40): Min distance >= 15 km (proves exact Keplerian element alignment).

Pass condition: score >= 60 AND propagation sync AND collision avoidance.
"""

import json
import math
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_ephemeris(filepath):
    """
    Parses the GMAT ephemeris report to extract distances between the two satellites.
    Handles variable formatting and headers by matching column names or falling back
    to numeric position heuristics.
    """
    distances = []
    
    with open(filepath, 'r') as f:
        lines = f.readlines()
        
    if not lines:
        return []
        
    header = []
    data_lines = []
    
    for line in lines:
        line_stripped = line.strip()
        if not line_stripped:
            continue
            
        parts = line_stripped.split()
        
        # Check if the line is numeric (ignoring signs and scientific notation on the first token)
        first_token = parts[0].replace('.', '', 1).replace('e', '', 1).replace('E', '', 1).replace('-', '', 1).replace('+', '', 1)
        
        if line_stripped.startswith('%') or not first_token.isdigit():
            # Treat as header if it has X, Y, Z
            if 'X' in line_stripped.upper() or 'Y' in line_stripped.upper():
                # Remove % if present
                header_line = line_stripped.lstrip('%').strip()
                header = header_line.split()
        else:
            data_lines.append(parts)
            
    # Identify indices
    e4_idx = {'X': -1, 'Y': -1, 'Z': -1}
    e8_idx = {'X': -1, 'Y': -1, 'Z': -1}
    
    for i, col in enumerate(header):
        col_up = col.upper()
        # Look for indicators of EuroSat4 / Sat1
        if 'EUROSAT4' in col_up or 'EUROSAT_4' in col_up or 'SAT1' in col_up or 'SAT4' in col_up:
            if '.X' in col_up: e4_idx['X'] = i
            elif '.Y' in col_up: e4_idx['Y'] = i
            elif '.Z' in col_up: e4_idx['Z'] = i
            # Handle headers that are just X, Y, Z grouped under a name
            elif 'X' == col_up: e4_idx['X'] = i
            elif 'Y' == col_up: e4_idx['Y'] = i
            elif 'Z' == col_up: e4_idx['Z'] = i
        # Look for indicators of EuroSat8 / Sat2
        elif 'EUROSAT8' in col_up or 'EUROSAT_8' in col_up or 'SAT2' in col_up or 'SAT8' in col_up:
            if '.X' in col_up: e8_idx['X'] = i
            elif '.Y' in col_up: e8_idx['Y'] = i
            elif '.Z' in col_up: e8_idx['Z'] = i
            elif 'X' == col_up: e8_idx['X'] = i
            elif 'Y' == col_up: e8_idx['Y'] = i
            elif 'Z' == col_up: e8_idx['Z'] = i
            
    # Fallback heuristic if headers didn't clearly distinguish columns
    if any(idx == -1 for idx in e4_idx.values()) or any(idx == -1 for idx in e8_idx.values()):
        if len(data_lines) > 0:
            cols = len(data_lines[0])
            if cols >= 7:
                # Assume Col 0 is Time, Col 1-3 is Sat1, Col 4-6 is Sat2
                e4_idx = {'X': 1, 'Y': 2, 'Z': 3}
                e8_idx = {'X': 4, 'Y': 5, 'Z': 6}
            elif cols == 6:
                # Assume Col 0-2 is Sat1, Col 3-5 is Sat2
                e4_idx = {'X': 0, 'Y': 1, 'Z': 2}
                e8_idx = {'X': 3, 'Y': 4, 'Z': 5}
                
    # If still not found, we can't parse it
    if any(idx == -1 for idx in e4_idx.values()) or any(idx == -1 for idx in e8_idx.values()):
        return []
        
    for row in data_lines:
        try:
            x1, y1, z1 = float(row[e4_idx['X']]), float(row[e4_idx['Y']]), float(row[e4_idx['Z']])
            x2, y2, z2 = float(row[e8_idx['X']]), float(row[e8_idx['Y']]), float(row[e8_idx['Z']])
            
            # Simple sanity check: GEO altitude is ~42164 km, elements should be somewhat large
            # (unless it's delta/relative state, but standard output is EarthMJ2000Eq)
            dist = math.sqrt((x2-x1)**2 + (y2-y1)**2 + (z2-z1)**2)
            distances.append(dist)
        except (ValueError, IndexError):
            continue
            
    return distances

def verify_geo_colocation(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    report_path = metadata.get('report_path', '/home/ga/GMAT_output/colocation_ephem.txt')
    max_dist_limit = metadata.get('max_distance_km', 150.0)
    min_dist_limit = metadata.get('min_distance_km', 15.0)
    min_rows = metadata.get('min_rows', 330)

    scores = {
        "script_created": 10,
        "report_generated": 10,
        "data_completeness": 15,
        "propagation_sync": 25,
        "collision_avoidance": 40,
    }

    total_score = 0
    feedback = []
    sync_ok = False
    collision_ok = False

    # Load task result
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # 1. Script Created
    script_file = task_result.get('script_file', {})
    if isinstance(script_file, dict) and script_file.get('created_during_task'):
        total_score += scores["script_created"]
        feedback.append("Script created during task window.")
    else:
        feedback.append("Script not created during task window.")

    # 2. Report Generated
    report_file = task_result.get('report_file', {})
    if isinstance(report_file, dict) and report_file.get('exists') and report_file.get('size', 0) > 100:
        total_score += scores["report_generated"]
        feedback.append("Report file generated and populated.")
    else:
        feedback.append("Report file missing or empty.")

    # Parse Ephemeris
    distances = []
    if isinstance(report_file, dict) and report_file.get('exists'):
        temp_report = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        try:
            copy_from_env(report_path, temp_report.name)
            distances = parse_ephemeris(temp_report.name)
        except Exception as e:
            logger.error(f"Failed to copy/parse report: {e}")
        finally:
            if os.path.exists(temp_report.name):
                os.unlink(temp_report.name)

    num_rows = len(distances)
    
    # 3. Data Completeness
    if num_rows >= min_rows:
        total_score += scores["data_completeness"]
        feedback.append(f"Data is complete ({num_rows} rows parsed).")
    elif num_rows > 0:
        # Partial credit if some rows exist but not enough for 14 days at 1 hour steps
        total_score += scores["data_completeness"] // 2
        feedback.append(f"Data is incomplete (only {num_rows} rows parsed, expected >= {min_rows}).")
    else:
        feedback.append("Could not extract X, Y, Z columns for two spacecraft from report.")

    # 4 & 5. Kinematic analysis (Sync & Collision Avoidance)
    if distances:
        max_dist = max(distances)
        min_dist = min(distances)
        
        # 4. Propagation Sync (Max distance <= 150 km)
        # If the agent propagated sequentially instead of simultaneously, 
        # the orbital paths will desync drastically, and max distance will be huge (e.g., thousands of km).
        if max_dist <= max_dist_limit:
            total_score += scores["propagation_sync"]
            sync_ok = True
            feedback.append(f"Simultaneous propagation verified (Max dist: {max_dist:.2f} km <= {max_dist_limit} km).")
        else:
            feedback.append(f"Propagation desynced or orbits incorrect (Max dist: {max_dist:.2f} km > {max_dist_limit} km).")
            
        # 5. Collision Avoidance (Min distance >= 15 km)
        # If the agent set identical parameters without the correct RAAN/TA offset, 
        # min distance will be 0 km. Proper e/i separation keeps them ~30 km apart minimum.
        if min_dist >= min_dist_limit:
            total_score += scores["collision_avoidance"]
            collision_ok = True
            feedback.append(f"Collision avoidance verified (Min dist: {min_dist:.2f} km >= {min_dist_limit} km).")
        else:
            feedback.append(f"Collision risk detected (Min dist: {min_dist:.2f} km < {min_dist_limit} km). Check RAAN and TA offsets.")
            
    else:
        feedback.append("Kinematic analysis skipped due to missing or unparseable data.")

    passed = (total_score >= 60) and sync_ok and collision_ok

    return {
        "passed": passed,
        "score": total_score,
        "feedback": " | ".join(feedback)
    }