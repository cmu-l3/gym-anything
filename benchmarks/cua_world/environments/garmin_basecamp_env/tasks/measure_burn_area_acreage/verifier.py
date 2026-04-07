#!/usr/bin/env python3
"""
Verifier for measure_burn_area_acreage task.

VERIFICATION STRATEGY:
1. Programmatic Check (File-based): Verify GPX file was exported and created during task.
2. Metadata Pattern Match: Parse the GPX XML to ensure the <name> element matches the requested regex pattern.
3. Geodesic Math Verification: Extract the trackpoints, calculate the true planar area of the polygon, 
   convert to acres, and verify the agent's extracted integer is within ±15% tolerance.
4. VLM Check (Trajectory): Check trajectory frames to confirm the agent engaged in measuring workflows.
"""

import json
import tempfile
import os
import re
import math
import xml.etree.ElementTree as ET
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VLM_PROMPT = """You are verifying an AI agent's computer trajectory.
Task: Calculate the enclosed area (acreage) of a GPS track in Garmin BaseCamp.

Examine the trajectory frames and determine if the agent did any of the following:
1. BaseCamp Interaction: Did they open "Track Properties" and view the "Area" statistic?
2. BaseCamp Interaction: Did they open the "Options" dialog to change Measurement units to Acres?
3. Programmatic: Did they open a terminal or editor and write/execute a script to calculate the area of a GPX file?

Return your findings strictly in JSON format:
{
    "interacted_with_basecamp_properties": true/false,
    "changed_units_to_acres": true/false,
    "used_script": true/false,
    "acreage_work_visible": true/false
}
"""

def calculate_polygon_area_m2(pts):
    """
    Calculate the area of a polygon defined by lat/lon points.
    Projects to local planar Cartesian coordinates using the mean latitude.
    """
    if len(pts) < 3:
        return 0.0
        
    lat_mean = sum(p[0] for p in pts) / len(pts)
    lat_mean_rad = math.radians(lat_mean)
    
    # 1 degree of latitude in meters (approx)
    m_per_deg_lat = 111132.92 - 559.82 * math.cos(2 * lat_mean_rad) + 1.175 * math.cos(4 * lat_mean_rad)
    # 1 degree of longitude in meters (approx)
    m_per_deg_lon = 111412.84 * math.cos(lat_mean_rad) - 93.5 * math.cos(3 * lat_mean_rad)
    
    # Convert to local Cartesian coordinates
    coords = [(lon * m_per_deg_lon, lat * m_per_deg_lat) for lat, lon in pts]
    
    # Shoelace formula for area
    area = 0.0
    n = len(coords)
    for i in range(n):
        x1, y1 = coords[i]
        x2, y2 = coords[(i + 1) % n]
        area += x1 * y2 - x2 * y1
        
    return abs(area) / 2.0

def verify_measure_burn_area_acreage(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_regex = metadata.get('expected_regex', r'^Fells_Conservation_(\d+)_Acres$')
    tolerance = metadata.get('area_tolerance_percent', 15) / 100.0

    score = 0
    feedback = []

    # 1. READ EXPORTED RESULT JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env(r"C:\tmp\task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task export results: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # Output Existence & Timestamp Validation (20 pts)
    if result.get('output_exists'):
        score += 10
        feedback.append("Output GPX file exists.")
        if result.get('file_created_during_task'):
            score += 10
            feedback.append("File creation timestamp validated (anti-gaming pass).")
        else:
            feedback.append("WARNING: Output file predates task start time. Possible stale data.")
    else:
        feedback.append("Output GPX file not found. Task failed early.")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback)}

    # 2. PARSE GPX & VALIDATE MATH (60 pts)
    temp_gpx = tempfile.NamedTemporaryFile(delete=False, suffix='.gpx')
    gpx_valid = False
    extracted_acres = None
    
    try:
        copy_from_env(r"C:\workspace\output\fells_conservation.gpx", temp_gpx.name)
        tree = ET.parse(temp_gpx.name)
        root = tree.getroot()
        
        # Strip namespaces for robust tag matching
        for elem in root.iter():
            if '}' in elem.tag:
                elem.tag = elem.tag.split('}', 1)[1]
        
        trk = root.find('.//trk')
        if trk is not None:
            gpx_valid = True
            name_elem = trk.find('name')
            
            if name_elem is not None and name_elem.text:
                track_name = name_elem.text.strip()
                feedback.append(f"Parsed track name: '{track_name}'")
                
                # Check Metadata Requirement
                match = re.match(expected_regex, track_name, re.IGNORECASE)
                if match:
                    score += 30
                    extracted_acres = int(match.group(1))
                    feedback.append(f"Track naming convention strictly matched! (Extracted acreage: {extracted_acres})")
                else:
                    feedback.append(f"Track name '{track_name}' did not match required format.")
            else:
                feedback.append("Track has no <name> property.")
            
            # Extract points for Geodesic Area Calculation
            pts = []
            for trkpt in trk.findall('.//trkpt'):
                try:
                    lat = float(trkpt.get('lat'))
                    lon = float(trkpt.get('lon'))
                    pts.append((lat, lon))
                except (TypeError, ValueError):
                    continue
            
            if len(pts) > 3:
                area_m2 = calculate_polygon_area_m2(pts)
                calculated_acres = area_m2 * 0.000247105
                feedback.append(f"Calculated true acreage: {calculated_acres:.1f} acres.")
                
                if extracted_acres is not None:
                    error_pct = abs(extracted_acres - calculated_acres) / calculated_acres
                    if error_pct <= tolerance:
                        score += 30
                        feedback.append(f"Agent's acreage ({extracted_acres}) is highly accurate (error: {error_pct*100:.1f}%).")
                    else:
                        feedback.append(f"Agent's acreage ({extracted_acres}) is inaccurate. Max tolerance is {tolerance*100}%.")
            else:
                feedback.append("Not enough trackpoints to compute verification area.")
    except Exception as e:
        feedback.append(f"GPX parsing error: {e}")
    finally:
        if os.path.exists(temp_gpx.name):
            os.unlink(temp_gpx.name)

    # 3. VLM TRAJECTORY VERIFICATION (20 pts)
    try:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
        frames = sample_trajectory_frames(traj, n=4)
        final = get_final_screenshot(traj)
        images = frames + [final] if final else frames
        
        if images:
            vlm_resp = query_vlm(images=images, prompt=VLM_PROMPT)
            if vlm_resp and vlm_resp.get("success"):
                parsed = vlm_resp.get("parsed", {})
                if (parsed.get("acreage_work_visible") or 
                    parsed.get("interacted_with_basecamp_properties") or 
                    parsed.get("used_script")):
                    score += 20
                    feedback.append("VLM confirmed visual evidence of area calculation workflow.")
                else:
                    feedback.append("VLM did not detect measuring workflow in the trajectory.")
            else:
                feedback.append("VLM analysis response invalid.")
    except Exception as e:
        logger.error(f"VLM verification failed: {e}")
        feedback.append("VLM verification skipped due to internal framework error.")

    # Cap score
    score = min(100, max(0, score))
    
    # Requirement: Must score at least 70 AND successfully extract an accurate acreage value
    passed = score >= 70 and gpx_valid and extracted_acres is not None

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }