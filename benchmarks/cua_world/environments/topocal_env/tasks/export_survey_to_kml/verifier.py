#!/usr/bin/env python3
"""
Verifier for export_survey_to_kml task in TopoCal.

VERIFICATION METRICS:
1. File Existence & Anti-Gaming: Output KML must exist and be modified during the task.
2. XML/KML Structure: Must contain <coordinates> tags indicating a successful data export.
3. Coordinate Math (The Core Test): Parses the coordinates to ensure the agent changed 
   the UTM zone to 13. If the agent accepted the default Zone 30, the longitudes will map 
   to the Atlantic Ocean/Spain instead of Colorado (-105.2).
4. VLM Trajectory: Verifies the agent actively used the UI (preventing script bypasses).
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_export_to_kml(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_lon_range = metadata.get('expected_longitude_range', [-106.0, -104.0])
    expected_lat_range = metadata.get('expected_latitude_range', [39.0, 41.0])

    feedback_parts = []
    score = 0

    # 1. Read the JSON export results
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:\\temp\\task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result JSON: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    output_exists = result.get('output_exists', False)
    created_during_task = result.get('file_created_during_task', False)

    if not output_exists:
        return {"passed": False, "score": 0, "feedback": "KML export file does not exist at expected path."}

    if created_during_task:
        score += 20
        feedback_parts.append("File created/modified during task (+20)")
    else:
        feedback_parts.append("File existed prior to task and was not updated (0)")

    # 2. Read and parse the KML content
    temp_kml = tempfile.NamedTemporaryFile(delete=False, suffix='.kml')
    kml_content = ""
    try:
        copy_from_env("C:\\Users\\Docker\\Documents\\site_export.kml", temp_kml.name)
        with open(temp_kml.name, 'r', encoding='utf-8', errors='ignore') as f:
            kml_content = f.read()
    except Exception as e:
        feedback_parts.append(f"Could not read KML contents: {e}")
    finally:
        if os.path.exists(temp_kml.name):
            os.unlink(temp_kml.name)

    if kml_content:
        # Check basic KML validity
        if "<kml" in kml_content.lower() and "<Placemark" in kml_content:
            score += 20
            feedback_parts.append("Valid KML structure containing Placemarks (+20)")
        else:
            feedback_parts.append("File is not a valid KML or contains no Placemarks")

        # 3. Coordinate math check (Determines if UTM zone was correct)
        coords = re.findall(r'<coordinates>\s*([^<]+)\s*</coordinates>', kml_content, re.IGNORECASE)
        
        if not coords:
            feedback_parts.append("No <coordinates> tags found in KML")
        else:
            # Parse the first available coordinate: Format is usually lon,lat,elevation
            first_coord = coords[0].strip().split()
            if first_coord:
                parts = first_coord[0].split(',')
                if len(parts) >= 2:
                    try:
                        lon = float(parts[0])
                        lat = float(parts[1])
                        
                        logger.info(f"Extracted KML Coordinate: Lon {lon}, Lat {lat}")
                        
                        lon_correct = expected_lon_range[0] <= lon <= expected_lon_range[1]
                        lat_correct = expected_lat_range[0] <= lat <= expected_lat_range[1]

                        if lon_correct and lat_correct:
                            score += 40
                            feedback_parts.append(f"Coordinates mapped to correct UTM Zone 13 / Colorado (+40)")
                        else:
                            feedback_parts.append(f"Coordinates mapped incorrectly (Lon: {lon:.2f}, Lat: {lat:.2f}). Agent likely failed to change default UTM Zone.")
                    except ValueError:
                        feedback_parts.append("Malformed coordinate data inside tags")
    else:
        feedback_parts.append("KML file was empty")

    # 4. VLM Trajectory check to ensure TopoCal UI was actually used (Anti-scripting)
    if query_vlm and traj:
        from gym_anything.vlm import sample_trajectory_frames
        frames = sample_trajectory_frames(traj, n=4)
        if frames:
            prompt = """
            You are verifying a TopoCal CAD task. 
            Look at these screenshots. Did the agent at any point open the 'Google Earth' export dialog or a settings dialog related to UTM coordinate zones?
            Answer only 'Yes' or 'No'.
            """
            vlm_response = query_vlm(prompt=prompt, images=frames)
            
            if vlm_response.get('success'):
                answer = vlm_response.get('response', '').lower()
                if 'yes' in answer:
                    score += 20
                    feedback_parts.append("VLM verified Export Dialog usage (+20)")
                else:
                    feedback_parts.append("VLM could not confirm Export Dialog usage")

    passed = score >= 70  # Agent must get the coordinates right to pass

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }