#!/usr/bin/env python3
import json
import re
import math
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_record_benchmark_deviation(traj, env_info, task_info):
    """
    Verifies that the agent correctly calculated the coordinate deviation
    for Cairo and recorded it in a new field observation.
    """
    # 1. Setup and retrieve data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy capability missing"}

    # Benchmark values from metadata (Ground Truth for the calculation)
    metadata = task_info.get('metadata', {})
    benchmark_lat = metadata.get('benchmark_lat', 30.0600)
    benchmark_lon = metadata.get('benchmark_lon', 31.2500)
    
    # Retrieve result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/data/local/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve/parse result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Extract Data
    feature_data = result_data.get('feature_data')
    cairo_data = result_data.get('cairo_data')
    
    # Basic Checks
    if not feature_data:
        return {"passed": False, "score": 0, "feedback": "No new observation feature found matching criteria."}
    
    if not cairo_data:
        # This shouldn't happen if the map is intact, but handle gracefully
        return {"passed": False, "score": 0, "feedback": "Could not locate Cairo in the map data for verification."}

    score = 0
    feedback = []

    # 3. Check Feature Existence and Name (20 pts)
    # feature_data is a dict (from sqlite json) or list of dicts
    if isinstance(feature_data, list): feature_data = feature_data[0]
    if isinstance(cairo_data, list): cairo_data = cairo_data[0]

    name = feature_data.get('name', '')
    if 'QA_Log_Cairo' in name:
        score += 20
        feedback.append("Feature name correct.")
    else:
        feedback.append(f"Feature name incorrect: found '{name}'.")

    # 4. Check Location (10 pts)
    # The point should be roughly at Cairo.
    # Cairo map coords
    map_lat = cairo_data.get('y')
    map_lon = cairo_data.get('x')
    
    # Agent point coords
    agent_lat = feature_data.get('y')
    agent_lon = feature_data.get('x')

    dist = math.sqrt((map_lat - agent_lat)**2 + (map_lon - agent_lon)**2)
    if dist < 0.05: # Approx 5km tolerance, generous
        score += 10
        feedback.append("Feature location correct.")
    else:
        feedback.append("Feature location too far from Cairo.")

    # 5. Verify Calculations (70 pts)
    # Expected Deviations
    expected_dlat = map_lat - benchmark_lat
    expected_dlon = map_lon - benchmark_lon

    # Parse Agent's Description
    # Description might be in 'description' or 'notes' column depending on schema
    desc_text = feature_data.get('description') or feature_data.get('notes') or ""
    
    # Regex to find "dLat: X, dLon: Y"
    # Matches: dLat: -0.0156, dLon: 0.002
    match = re.search(r"dLat:\s*([-\d\.]+),\s*dLon:\s*([-\d\.]+)", desc_text, re.IGNORECASE)
    
    if match:
        try:
            agent_dlat = float(match.group(1))
            agent_dlon = float(match.group(2))
            
            # Check Latitude Deviation (35 pts)
            if abs(agent_dlat - expected_dlat) < 0.0005:
                score += 35
                feedback.append(f"Latitude deviation correct (Expected {expected_dlat:.4f}, Got {agent_dlat}).")
            else:
                feedback.append(f"Latitude deviation incorrect (Expected {expected_dlat:.4f}, Got {agent_dlat}).")
                
            # Check Longitude Deviation (35 pts)
            if abs(agent_dlon - expected_dlon) < 0.0005:
                score += 35
                feedback.append(f"Longitude deviation correct (Expected {expected_dlon:.4f}, Got {agent_dlon}).")
            else:
                feedback.append(f"Longitude deviation incorrect (Expected {expected_dlon:.4f}, Got {agent_dlon}).")
                
        except ValueError:
            feedback.append("Could not parse numeric values from description.")
    else:
        feedback.append(f"Description format incorrect. Found: '{desc_text}'. Expected format: 'dLat: [val], dLon: [val]'.")

    return {
        "passed": score >= 90,
        "score": score,
        "feedback": " ".join(feedback)
    }