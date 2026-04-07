#!/usr/bin/env python3
"""
Verifier for the query_event_inventory_report task.

Verification Strategy:
1. File Existence & Timestamps (Anti-gaming)
2. Content parsing for required section headers
3. Programmatic checks against Extracted Earthquake Parameters
4. Geospatial calculation verification (Haversine distance)
5. VLM verification to ensure terminal/scripting was utilized.
"""

import json
import os
import tempfile
import logging
import math
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def haversine(lat1, lon1, lat2, lon2):
    """Calculate the great-circle distance between two points on Earth in km."""
    R = 6371.0 # Radius of Earth in kilometers
    phi1, phi2 = math.radians(lat1), math.radians(lat2)
    dphi = math.radians(lat2 - lat1)
    dlambda = math.radians(lon2 - lon1)
    a = math.sin(dphi/2)**2 + math.cos(phi1)*math.cos(phi2)*math.sin(dlambda/2)**2
    return R * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))

def verify_query_event_inventory_report(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_eq = metadata.get('earthquake', {})
    expected_stations = metadata.get('stations', {})
    tolerances = metadata.get('tolerances', {})

    score = 0
    feedback_parts = []

    # 1. Fetch File
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read exported results: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # 2. File Metadata verification
    if not result.get("file_exists"):
        return {"passed": False, "score": 0, "feedback": "Output file /home/ga/noto_earthquake_report.txt does not exist."}
    
    if not result.get("file_created_during_task"):
        feedback_parts.append("WARNING: File was not created/modified during task timeframe (possible gaming).")
    else:
        score += 5
        feedback_parts.append("File created correctly.")

    content = result.get("report_content", "")
    lines = [line.strip() for line in content.split('\n') if line.strip()]

    # 3. Parse Content
    eq_params = {}
    stations = {}
    
    current_section = None
    for line in lines:
        if "=== EARTHQUAKE PARAMETERS ===" in line:
            current_section = "eq"
            score += 2.5
            continue
        elif "=== STATION DISTANCES ===" in line:
            current_section = "sta"
            score += 2.5
            continue
            
        if current_section == "eq":
            if ":" in line:
                key, val = line.split(":", 1)
                eq_params[key.strip().lower()] = val.strip()
                
        elif current_section == "sta":
            # Skip header
            if "Network" in line and "Station" in line:
                continue
            parts = line.split()
            if len(parts) >= 5 and parts[0] == "GE":
                sta_code = parts[1]
                try:
                    sta_lat = float(parts[2])
                    sta_lon = float(parts[3])
                    sta_dist = float(parts[4])
                    stations[sta_code] = {"lat": sta_lat, "lon": sta_lon, "dist": sta_dist}
                except ValueError:
                    continue

    # 4. Evaluate Earthquake Parameters (Max 40 points)
    try:
        lat = float(eq_params.get("latitude", 0))
        lon = float(eq_params.get("longitude", 0))
        depth = float(eq_params.get("depth_km", 0))
        mag = float(eq_params.get("magnitude", 0))
        mag_type = eq_params.get("magnitudetype", "").lower()

        if abs(lat - expected_eq["latitude"]) <= tolerances["coord_deg"]:
            score += 8
        else:
            feedback_parts.append(f"Latitude incorrect (Expected ~{expected_eq['latitude']}, Got {lat})")

        if abs(lon - expected_eq["longitude"]) <= tolerances["coord_deg"]:
            score += 8
        else:
            feedback_parts.append(f"Longitude incorrect (Expected ~{expected_eq['longitude']}, Got {lon})")

        if abs(depth - expected_eq["depth_km"]) <= tolerances["depth_km"]:
            score += 8

        if abs(mag - expected_eq["magnitude"]) <= tolerances["mag"]:
            score += 8

        if mag_type == expected_eq["magnitude_type"].lower():
            score += 8
    except ValueError:
        feedback_parts.append("Failed to parse numerical earthquake parameters.")

    # 5. Evaluate Stations & Distances (Max 35 points)
    expected_sta_codes = set(expected_stations.keys())
    found_sta_codes = set(stations.keys())
    
    if expected_sta_codes.issubset(found_sta_codes):
        score += 10
        feedback_parts.append("All required GE stations found.")
    else:
        missing = expected_sta_codes - found_sta_codes
        feedback_parts.append(f"Missing stations: {', '.join(missing)}")
        score += len(found_sta_codes.intersection(expected_sta_codes)) * 2

    # Check distances
    dist_correct = 0
    for sta, data in stations.items():
        if sta in expected_stations:
            # Expected distance from TRUE epicenter to TRUE station coords
            true_dist = haversine(
                expected_eq["latitude"], expected_eq["longitude"], 
                expected_stations[sta]["lat"], expected_stations[sta]["lon"]
            )
            
            if abs(data["dist"] - true_dist) <= tolerances["distance_km"]:
                dist_correct += 1
                
    if len(expected_stations) > 0:
        score += int((dist_correct / len(expected_stations)) * 25)
        if dist_correct == len(expected_stations):
            feedback_parts.append("All station distances calculated correctly.")
        else:
            feedback_parts.append(f"{dist_correct}/{len(expected_stations)} distances correct.")

    # 6. VLM Trajectory Verification (Max 15 points)
    # Proves the agent actually used the terminal/scripts to fetch the data
    from gym_anything.vlm import sample_trajectory_frames, query_vlm
    
    frames = sample_trajectory_frames(traj, n=4)
    if frames:
        prompt = """
        Review these chronologically sampled trajectory frames of a Linux desktop.
        Did the agent actively use the terminal (e.g. typing commands, executing python/bash scripts, running SQL queries) 
        to extract data or compute mathematical equations?
        
        Respond ONLY with a JSON dictionary:
        {"terminal_used": true/false}
        """
        try:
            vlm_res = query_vlm(images=frames, prompt=prompt)
            if vlm_res and vlm_res.get("success") and vlm_res.get("parsed", {}).get("terminal_used"):
                score += 15
                feedback_parts.append("VLM confirmed terminal usage.")
            else:
                feedback_parts.append("VLM did not detect terminal usage.")
        except Exception as e:
            logger.warning(f"VLM error: {e}")
            feedback_parts.append("VLM verification failed to run.")

    # 7. Final Scoring
    passed = score >= 60 and result.get("file_created_during_task")
    
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts)
    }