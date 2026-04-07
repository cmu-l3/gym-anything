#!/usr/bin/env python3
"""
Verifier for TSS Buoy Deployment Task
"""

import json
import math
import os
import sys
import tempfile

def calculate_distance_km(lat1, lon1, lat2, lon2):
    """
    Calculate the Haversine distance between two points in kilometers.
    """
    R = 6371  # Earth radius in km
    
    d_lat = math.radians(lat2 - lat1)
    d_lon = math.radians(lon2 - lon1)
    
    a = (math.sin(d_lat / 2) * math.sin(d_lat / 2) +
         math.cos(math.radians(lat1)) * math.cos(math.radians(lat2)) *
         math.sin(d_lon / 2) * math.sin(d_lon / 2))
    
    c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))
    
    return R * c

def verify_tss_buoy_deployment(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
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

    # Metadata
    metadata = task_info.get('metadata', {})
    ground_truth = metadata.get('ground_truth', [])
    tolerance_deg = metadata.get('tolerance_deg', 0.0005) # ~55m
    
    score = 0
    feedback = []
    
    # 1. Basic Structure Checks (20 pts)
    if result.get('scenario_exists'):
        score += 10
        feedback.append("Scenario directory created.")
    else:
        feedback.append("Scenario directory NOT found.")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback)}

    if result.get('environment_exists'):
        score += 10
        feedback.append("Environment file exists.")
    else:
        feedback.append("Environment file missing.")

    # 2. Buoy Count & Config (20 pts)
    buoys = result.get('buoy_data', [])
    
    if len(buoys) == 6:
        score += 10
        feedback.append("Exactly 6 targets found.")
    else:
        feedback.append(f"Found {len(buoys)} targets (expected 6).")

    # Check static speed
    static_count = sum(1 for b in buoys if b.get('speed', -1) == 0)
    if static_count == len(buoys) and len(buoys) > 0:
        score += 10
        feedback.append("All targets are static (Speed=0).")
    elif len(buoys) > 0:
        feedback.append(f"Only {static_count}/{len(buoys)} targets are static.")

    # 3. Coordinate Accuracy (60 pts)
    # Strategy: Match buoys to ground truth.
    # Since strict ordering is preferred but not strictly enforced by file format (INI indices can be arbitrary),
    # we will attempt to match by index first (1-1, 2-2), if that fails, we try best match.
    # Actually, the memo numbers them 1-6, so we assume index 1 = Buoy 1.
    
    coord_score = 0
    matches = 0
    
    # Create a map of index to buoy
    buoy_map = {b['index']: b for b in buoys}
    
    for i, truth in enumerate(ground_truth):
        idx = i + 1  # 1-based index
        target_name = truth['name']
        
        # Try to find corresponding buoy
        candidate = buoy_map.get(idx)
        
        if not candidate:
            feedback.append(f"Missing Buoy {idx} ({target_name}).")
            continue
            
        lat_diff = abs(candidate['lat'] - truth['lat'])
        long_diff = abs(candidate['long'] - truth['long'])
        
        # Calculate distance for better feedback
        dist_km = calculate_distance_km(candidate['lat'], candidate['long'], truth['lat'], truth['long'])
        dist_m = dist_km * 1000
        
        if lat_diff <= tolerance_deg and long_diff <= tolerance_deg:
            coord_score += 10
            matches += 1
            # feedback.append(f"Buoy {idx} OK.") # Too verbose
        else:
            feedback.append(f"Buoy {idx} ({target_name}) OFF by {dist_m:.1f}m. (Got {candidate['lat']:.4f}, {candidate['long']:.4f})")

    score += coord_score
    feedback.append(f"Coordinate Accuracy: {matches}/6 correct.")

    passed = (score >= 70)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }