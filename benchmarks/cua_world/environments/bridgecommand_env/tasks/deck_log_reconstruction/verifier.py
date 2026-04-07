#!/usr/bin/env python3
"""
Verifier for deck_log_reconstruction task.
"""

import json
import math
import re
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def haversine_nm(lat1, lon1, lat2, lon2):
    """
    Calculate the great circle distance in nautical miles between two points 
    on the earth (specified in decimal degrees).
    """
    # Convert decimal degrees to radians
    lat1, lon1, lat2, lon2 = map(math.radians, [lat1, lon1, lat2, lon2])

    # Haversine formula
    dlon = lon2 - lon1
    dlat = lat2 - lat1
    a = math.sin(dlat/2)**2 + math.cos(lat1) * math.cos(lat2) * math.sin(dlon/2)**2
    c = 2 * math.asin(math.sqrt(a))
    r = 3440.065  # Radius of earth in nautical miles
    return c * r

def decimal_to_ddm(deg, is_lat):
    """
    Convert decimal degrees to Degrees Decimal Minutes string.
    Lat: N/S, Long: E/W.
    Format: 50° 47.3'N
    """
    try:
        deg = float(deg)
    except:
        return None
        
    absolute = abs(deg)
    degrees = int(absolute)
    minutes = (absolute - degrees) * 60
    
    if is_lat:
        suffix = 'N' if deg >= 0 else 'S'
    else:
        suffix = 'E' if deg >= 0 else 'W'
        
    # Standard format: DDD° MM.M'X or DD° MM.M'X
    # We will be lenient on padding, strict on values
    return degrees, minutes, suffix

def parse_ddm_string(s):
    """
    Parse a DDM string from agent output back to values for comparison.
    Expected: "50° 47.3'N" or similar.
    Returns: (degrees, minutes, suffix)
    """
    # Regex to capture: numbers, degree symbol (optional), numbers, ' or nothing, letter
    match = re.search(r"(\d+)[°\s]+(\d+\.?\d*)['\s]*([NSEW])", s, re.IGNORECASE)
    if match:
        return int(match.group(1)), float(match.group(2)), match.group(3).upper()
    return None

def verify_deck_log_reconstruction(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result JSON
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

    score = 0
    feedback = []
    
    # Check File Existence & Creation
    if not result.get('deck_log_exists') or not result.get('stats_exists'):
        return {"passed": False, "score": 0, "feedback": "Required output files missing."}
        
    if not result.get('deck_log_modified') or not result.get('stats_modified'):
         return {"passed": False, "score": 0, "feedback": "Files were not created/modified during the task window."}

    score += 8  # Files exist
    score += 8  # Anti-gaming check passed (modified during task)

    # Load Content
    log_content = result.get('agent_deck_log_content', '')
    stats_content = result.get('agent_stats_content', '')
    ground_truth = result.get('scenarios_ground_truth', [])

    if not ground_truth:
         return {"passed": False, "score": score, "feedback": "Error: Ground truth extraction failed."}

    # --- Verify Deck Log ---
    
    # Check sorting: The ground truth list is sorted by directory name.
    # The agent's log should follow this order.
    
    # 1. Parse Agent Log
    # We split by something that looks like a header or entry separator
    # Assuming standard format: "Entry No: ..." or "Scenario: ..."
    
    # Normalize newlines
    log_lines = log_content.splitlines()
    agent_entries = []
    current_entry = {}
    
    for line in log_lines:
        line = line.strip()
        if not line: continue
        if line.startswith("==="): continue # Skip separators
        
        if line.lower().startswith("entry no") or line.lower().startswith("scenario:"):
            # New entry heuristic: if we already have a scenario name in current_entry, save it
            if 'scenario' in current_entry:
                agent_entries.append(current_entry)
                current_entry = {}
        
        # Simple Key-Value parsing
        if ':' in line:
            key, val = line.split(':', 1)
            current_entry[key.strip().lower()] = val.strip()
            
    if 'scenario' in current_entry:
        agent_entries.append(current_entry)
        
    # Check count
    if len(agent_entries) == len(ground_truth):
        score += 10
        feedback.append(f"Correct entry count: {len(agent_entries)}")
    else:
        feedback.append(f"Entry count mismatch: Agent {len(agent_entries)} vs Truth {len(ground_truth)}")

    # Verify Data for Sample Entries (verify up to 5 random ones to save time/logic complexity, or all)
    # We'll check all of them in order to verify sorting simultaneously.
    
    sorting_correct = True
    position_correct_count = 0
    distance_correct_count = 0
    traffic_correct_count = 0
    
    correct_entries_processed = 0
    
    for i, gt in enumerate(ground_truth):
        if i >= len(agent_entries): break
        
        agent_entry = agent_entries[i]
        gt_dir = gt['directory_name']
        gt_own = gt['ownship']
        gt_env = gt['environment']
        gt_other = gt['othership']
        
        # 1. Check Scenario Name (Sorting)
        # Agent might write "Portsmouth" vs "m) Portsmouth..."
        # We check if GT directory name is contained in Agent Scenario field
        if gt_dir.lower() not in agent_entry.get('scenario', '').lower():
            sorting_correct = False
            # Try to find the correct entry to continue scoring other metrics?
            # For simplicity, we assume strict order. If sorting is wrong, it fails this check.
        
        # 2. Check Position (DDM Conversion)
        # GT: Decimal Degrees
        gt_lat = float(gt_own.get('InitialLat', 0))
        gt_long = float(gt_own.get('InitialLong', 0))
        
        agent_pos_str = agent_entry.get('position', '')
        # Expecting something like "50° 47.3'N, 001° 06.8'W"
        # We need to parse two DDM components
        parts = re.split(r'[,;]', agent_pos_str)
        if len(parts) >= 2:
            lat_parsed = parse_ddm_string(parts[0])
            long_parsed = parse_ddm_string(parts[1])
            
            if lat_parsed and long_parsed:
                # Check Lat
                gt_ddm_lat = decimal_to_ddm(gt_lat, True) # (deg, min, suffix)
                lat_ok = (lat_parsed[0] == gt_ddm_lat[0] and 
                          abs(lat_parsed[1] - gt_ddm_lat[1]) < 0.2 and 
                          lat_parsed[2] == gt_ddm_lat[2])
                          
                # Check Long
                gt_ddm_long = decimal_to_ddm(gt_long, False)
                long_ok = (long_parsed[0] == gt_ddm_long[0] and 
                           abs(long_parsed[1] - gt_ddm_long[1]) < 0.2 and 
                           long_parsed[2] == gt_ddm_long[2])
                           
                if lat_ok and long_ok:
                    position_correct_count += 1
        
        # 3. Check Traffic Count
        gt_traffic = int(gt_other.get('Number', 0))
        # Agent string: "1 other vessel" or just "1"
        agent_traffic_str = agent_entry.get('traffic', '0')
        match = re.search(r'(\d+)', agent_traffic_str)
        if match:
            if int(match.group(1)) == gt_traffic:
                traffic_correct_count += 1
                
        # 4. Check Distance (Haversine)
        # Does this scenario have waypoints?
        has_legs = False
        legs = []
        # Find legs
        for key in gt_own:
            if key.startswith('Leg(') and 'Lat' in key:
                # Extract index
                idx_match = re.search(r'Leg\((\d+)\)Lat', key)
                if idx_match:
                    idx = int(idx_match.group(1))
                    lat = float(gt_own[key])
                    # Find corresponding long
                    long_key = f"Leg({idx})Long"
                    if long_key in gt_own:
                        lon = float(gt_own[long_key])
                        legs.append((idx, lat, lon))
        
        legs.sort() # sort by index
        
        if legs:
            # Calculate total distance: Start -> Leg1 -> Leg2 ...
            current_lat = gt_lat
            current_lon = gt_long
            total_dist = 0.0
            for leg in legs:
                dist = haversine_nm(current_lat, current_lon, leg[1], leg[2])
                total_dist += dist
                current_lat = leg[1]
                current_lon = leg[2]
                
            # Compare with agent output
            agent_dist_str = agent_entry.get('planned distance', '')
            match = re.search(r'([\d\.]+)', agent_dist_str)
            if match:
                try:
                    agent_dist = float(match.group(1))
                    if abs(agent_dist - total_dist) < 1.0: # 1nm tolerance
                        distance_correct_count += 1
                except: pass
        else:
            # If no legs, maybe check if agent said "N/A" or "0"
            pass
            
    # Scoring Breakdown
    # Sorting (5 pts)
    if sorting_correct and len(agent_entries) > 0:
        score += 5
    else:
        feedback.append("Sorting or scenario naming incorrect")
        
    # Position (15 pts) - prorated
    if len(ground_truth) > 0:
        pos_score = 15 * (position_correct_count / len(ground_truth))
        score += pos_score
        
    # Traffic (8 pts) - prorated
    if len(ground_truth) > 0:
        traf_score = 8 * (traffic_correct_count / len(ground_truth))
        score += traf_score
        
    # Distance (12 pts) - based on scenarios that actually HAVE waypoints
    # We know we created at least one sample scenario with waypoints
    # We'll just give points if we found ANY correct distance calc
    if distance_correct_count > 0:
        score += 12
        feedback.append(f"Correct distance calculations found: {distance_correct_count}")
    else:
        feedback.append("No correct distance calculations found")
        
    # --- Verify Statistics File ---
    # We look for keywords and plausible values
    
    stats_lower = stats_content.lower()
    
    # 1. Total Scenarios Count (7 pts)
    if str(len(ground_truth)) in stats_content:
        score += 7
    
    # 2. Mean Speed (8 pts)
    # Calculate GT mean speed
    total_speed = sum([float(s['ownship'].get('InitialSpeed', 0)) for s in ground_truth])
    mean_speed = total_speed / len(ground_truth) if ground_truth else 0
    
    if f"{mean_speed:.1f}" in stats_content or f"{mean_speed:.2f}" in stats_content:
        score += 8
    else:
        # Allow integer match if close
        if f"{int(mean_speed)}" in stats_content:
            score += 4
            
    # 3. Unique Settings List (7 pts)
    # Just check if a few known settings appear
    settings_found = True
    for gt in ground_truth:
        setting = gt['environment'].get('Setting', '')
        if setting and setting not in stats_content:
            # Strict check might fail on formatting, let's just check for 'Solent' or 'Open Sea'
            if setting in ['Solent', 'Open Sea', 'English Channel']:
                if setting not in stats_content:
                    settings_found = False
    
    if settings_found:
        score += 7

    # 4. Table structure (7 pts)
    if "scenario" in stats_lower and "vessel" in stats_lower and "position" in stats_lower:
        score += 7
    
    # Final Tally
    score = min(100, int(score))
    
    return {
        "passed": score >= 60,
        "score": score,
        "feedback": " | ".join(feedback)
    }