#!/usr/bin/env python3
"""
Verifier for plan_resupply_distances task.

Verification Strategy:
1. Verify `distance_report.txt` exists and was created during the task.
2. Verify `resupply_plan.gpx` exists and was created during the task.
3. Parse GPX to ensure 'Survey-Legs' route exists with multiple points.
4. Calculate distances between route points to find the longest leg.
5. Parse GPX to ensure 'Resupply-Point' waypoint exists.
6. Verify 'Resupply-Point' is located at the midpoint of the longest leg.
7. Use VLM trajectory verification to ensure BaseCamp was used.
"""

import json
import os
import math
import tempfile
import xml.etree.ElementTree as ET
import logging

from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def haversine(lat1, lon1, lat2, lon2):
    """Calculate the great circle distance in kilometers between two points."""
    R = 6371.0  # Earth radius in kilometers
    dlat = math.radians(lat2 - lat1)
    dlon = math.radians(lon2 - lon1)
    a = math.sin(dlat / 2)**2 + math.cos(math.radians(lat1)) * math.cos(math.radians(lat2)) * math.sin(dlon / 2)**2
    return R * 2 * math.asin(math.sqrt(a))

def verify_plan_resupply_distances(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []

    # 1. Fetch Task Result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result JSON: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # Check File Existence & Anti-gaming Timestamps
    if not result.get('report_exists'):
        return {"passed": False, "score": 0, "feedback": "Distance report file not found."}
    if not result.get('gpx_exists'):
        return {"passed": False, "score": 0, "feedback": "GPX export file not found."}
    
    if result.get('report_created_during_task') and result.get('gpx_created_during_task'):
        score += 20
        feedback_parts.append("Output files created during task (+20)")
    else:
        feedback_parts.append("Warning: Files existed before task start (possible gaming).")

    # 2. Fetch and Check Distance Report
    temp_report = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env("/tmp/distance_report.txt", temp_report.name)
        with open(temp_report.name, 'r', encoding='utf-8', errors='ignore') as f:
            report_content = f.read().lower()
            
        if "leg" in report_content and "km" in report_content and "longest" in report_content:
            score += 15
            feedback_parts.append("Distance report contains required details (+15)")
        else:
            feedback_parts.append("Distance report is missing required keywords (leg, km, longest).")
    except Exception as e:
        feedback_parts.append(f"Could not read report: {e}")
    finally:
        if os.path.exists(temp_report.name):
            os.unlink(temp_report.name)

    # 3. Fetch and Parse GPX File
    temp_gpx = tempfile.NamedTemporaryFile(delete=False, suffix='.gpx')
    try:
        copy_from_env("/tmp/resupply_plan.gpx", temp_gpx.name)
        
        tree = ET.parse(temp_gpx.name)
        root = tree.getroot()
        
        # GPX namespace handling
        ns = ""
        if root.tag.startswith("{"):
            ns = root.tag.split("}")[0] + "}"
            
        # Extract waypoints
        waypoints = []
        resupply_wpt = None
        for wpt in root.findall(f'.//{ns}wpt'):
            lat = float(wpt.get('lat', 0))
            lon = float(wpt.get('lon', 0))
            name_elem = wpt.find(f'{ns}name')
            name = name_elem.text if name_elem is not None else ""
            waypoints.append({'name': name, 'lat': lat, 'lon': lon})
            
            if name == 'Resupply-Point':
                resupply_wpt = {'lat': lat, 'lon': lon}

        if resupply_wpt:
            score += 15
            feedback_parts.append("Resupply-Point waypoint found in GPX (+15)")
        else:
            feedback_parts.append("Resupply-Point waypoint not found in GPX.")

        # Extract routes
        route_pts = []
        survey_route_found = False
        for rte in root.findall(f'.//{ns}rte'):
            name_elem = rte.find(f'{ns}name')
            if name_elem is not None and name_elem.text == 'Survey-Legs':
                survey_route_found = True
                for rtept in rte.findall(f'.//{ns}rtept'):
                    lat = float(rtept.get('lat', 0))
                    lon = float(rtept.get('lon', 0))
                    route_pts.append({'lat': lat, 'lon': lon})

        if survey_route_found and len(route_pts) >= 3:
            score += 15
            feedback_parts.append("Survey-Legs route found with points (+15)")
            
            # Calculate longest leg of the agent's route
            max_dist = 0
            longest_leg_midpoint = None
            
            for i in range(len(route_pts) - 1):
                pt1 = route_pts[i]
                pt2 = route_pts[i+1]
                dist = haversine(pt1['lat'], pt1['lon'], pt2['lat'], pt2['lon'])
                
                if dist > max_dist:
                    max_dist = dist
                    longest_leg_midpoint = {
                        'lat': (pt1['lat'] + pt2['lat']) / 2.0,
                        'lon': (pt1['lon'] + pt2['lon']) / 2.0
                    }
                    
            if longest_leg_midpoint and resupply_wpt:
                # Compare agent's Resupply-Point to calculated midpoint
                lat_diff = abs(resupply_wpt['lat'] - longest_leg_midpoint['lat'])
                lon_diff = abs(resupply_wpt['lon'] - longest_leg_midpoint['lon'])
                
                # Allow a tolerance of ~0.005 degrees (approx 500m) for rounding/cursor placement
                if lat_diff < 0.005 and lon_diff < 0.005:
                    score += 20
                    feedback_parts.append("Resupply-Point is at the correct midpoint (+20)")
                else:
                    feedback_parts.append(f"Resupply-Point coordinates ({resupply_wpt['lat']:.4f}, {resupply_wpt['lon']:.4f}) do not match midpoint ({longest_leg_midpoint['lat']:.4f}, {longest_leg_midpoint['lon']:.4f}).")

        else:
            feedback_parts.append("Survey-Legs route missing or has < 3 points.")

    except ET.ParseError:
        feedback_parts.append("Failed to parse GPX XML.")
    except Exception as e:
        feedback_parts.append(f"Error processing GPX: {e}")
    finally:
        if os.path.exists(temp_gpx.name):
            os.unlink(temp_gpx.name)

    # 4. VLM Trajectory Verification
    try:
        frames = sample_trajectory_frames(traj, n=4)
        if frames:
            prompt = """Analyze these screenshots from a Garmin BaseCamp task. 
            Did the user navigate the map, inspect waypoints, and create a new waypoint/route?
            Respond with JSON containing 'workflow_observed' (true/false)."""
            
            vlm_response = query_vlm(images=frames, prompt=prompt)
            if vlm_response and vlm_response.get("parsed", {}).get("workflow_observed"):
                score += 15
                feedback_parts.append("VLM verified workflow (+15)")
            else:
                feedback_parts.append("VLM could not confirm proper BaseCamp usage.")
    except Exception as e:
        logger.error(f"VLM verification error: {e}")
        feedback_parts.append("VLM verification skipped or failed.")

    key_criteria_met = (score >= 65 and result.get('report_exists') and result.get('gpx_exists'))
    passed = key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }