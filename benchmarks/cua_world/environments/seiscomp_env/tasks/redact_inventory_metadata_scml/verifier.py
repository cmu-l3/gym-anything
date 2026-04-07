#!/usr/bin/env python3
"""
Verifier for redact_inventory_metadata_scml task.
Parses the SCML XML and strictly checks if specific station/sensor coordinates were redacted.
"""

import os
import json
import tempfile
import logging
import xml.etree.ElementTree as ET

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_scml_coordinates(file_path):
    """
    Parses SCML and returns a dictionary of station and sensor coordinates.
    Robust against namespace variations.
    """
    try:
        tree = ET.parse(file_path)
        root = tree.getroot()
    except Exception as e:
        logger.error(f"Failed to parse XML: {e}")
        return None

    def strip_ns(tag):
        return tag.split('}')[-1] if '}' in tag else tag

    def get_value(parent, target_tag):
        for child in parent:
            if strip_ns(child.tag) == target_tag:
                for v in child:
                    if strip_ns(v.tag) == 'value':
                        try:
                            return float(v.text)
                        except (ValueError, TypeError):
                            return None
        return None

    results = {}
    
    # Iterate through all elements to find stations (handles any/no namespace)
    for elem in root.iter():
        if strip_ns(elem.tag) == 'station':
            code = elem.get('code', '')
            if not code:
                continue
                
            stat_coords = {
                'lat': get_value(elem, 'latitude'),
                'lon': get_value(elem, 'longitude'),
                'elev': get_value(elem, 'elevation')
            }
            
            sensors = []
            for child in elem:
                if strip_ns(child.tag) == 'sensorLocation':
                    sensors.append({
                        'code': child.get('code', ''),
                        'lat': get_value(child, 'latitude'),
                        'lon': get_value(child, 'longitude'),
                        'elev': get_value(child, 'elevation')
                    })
                    
            results[code] = {
                'station': stat_coords,
                'sensors': sensors
            }
            
    return results

def verify_redacted_inventory(traj, env_info, task_info):
    """
    Verifies the SCML file contains redacted coordinates for SANI and BKB
    while preserving TOLI, GSI, and KWP.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    redact_stations = metadata.get('redact_stations', ['SANI', 'BKB'])
    keep_stations = metadata.get('keep_stations', ['TOLI', 'GSI', 'KWP'])

    score = 0
    feedback_parts = []
    
    # 1. Copy metadata result
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read metadata: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    output_exists = result.get('output_exists', False)
    file_created = result.get('file_created_during_task', False)
    
    if not output_exists:
        return {"passed": False, "score": 0, "feedback": "Output SCML file not found."}
        
    if not file_created:
        feedback_parts.append("Warning: File timestamp indicates it was not created during this task sequence.")

    # 2. Copy the exported SCML file
    temp_scml = tempfile.NamedTemporaryFile(delete=False, suffix='.scml')
    try:
        copy_from_env("/tmp/redacted_inventory.scml", temp_scml.name)
        parsed_data = parse_scml_coordinates(temp_scml.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve/parse SCML file: {e}"}
    finally:
        if os.path.exists(temp_scml.name):
            os.unlink(temp_scml.name)

    if parsed_data is None:
        return {"passed": False, "score": 0, "feedback": "Output file exists but is not valid XML."}

    score += 10
    feedback_parts.append("Valid XML file parsed")

    # 3. Check network preservation (all 5 stations must be present)
    all_required = redact_stations + keep_stations
    missing = [st for st in all_required if st not in parsed_data]
    
    if not missing:
        score += 20
        feedback_parts.append("Network preserved (all stations present)")
    else:
        feedback_parts.append(f"Network corrupted! Missing stations: {missing}")
        # Severe penalty if stations are missing
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    # Helper to check if coordinates are exactly zero
    def is_zero(coords):
        if coords is None: return False
        return coords.get('lat') == 0.0 and coords.get('lon') == 0.0 and coords.get('elev') == 0.0
        
    def is_not_zero(coords):
        if coords is None: return False
        lat = coords.get('lat')
        lon = coords.get('lon')
        # A true coordinate will have absolute value > 0.001
        return lat is not None and lon is not None and (abs(lat) > 0.001 or abs(lon) > 0.001)

    # 4. Check Redacted Stations (SANI, BKB)
    for st in redact_stations:
        st_data = parsed_data.get(st, {})
        
        # Check parent <station>
        if is_zero(st_data.get('station')):
            score += 15
            feedback_parts.append(f"{st} parent station redacted")
        else:
            feedback_parts.append(f"{st} parent station NOT properly redacted")
            
        # Check child <sensorLocation> elements
        sensors = st_data.get('sensors', [])
        if sensors and all(is_zero(s) for s in sensors):
            score += 10
            feedback_parts.append(f"{st} sensor locations redacted")
        else:
            feedback_parts.append(f"{st} sensor locations missing or NOT properly redacted")

    # 5. Check Intact Stations (TOLI, GSI, KWP)
    intact_correct = True
    for st in keep_stations:
        st_data = parsed_data.get(st, {})
        if not is_not_zero(st_data.get('station')):
            intact_correct = False
            feedback_parts.append(f"{st} coordinates were zeroed out (collateral damage!)")
            
    if intact_correct:
        score += 20
        feedback_parts.append("Other stations preserved completely intact")

    # 6. Check Trajectory (VLM) for Anti-Gaming
    # While programmatic validation of the output file is 100% definitive of success,
    # adding a trajectory process check to ensure they didn't just curl a premade file.
    vlm_feedback = "No VLM check requested."
    try:
        from gym_anything.vlm import sample_trajectory_frames
        frames = sample_trajectory_frames(traj, n=4)
        if frames and 'query_vlm' in env_info:
            query_vlm = env_info['query_vlm']
            prompt = "Do these screenshots show a user working in a terminal or text editor to process XML data? Respond with a JSON containing a boolean 'terminal_used'."
            vlm_res = query_vlm(prompt=prompt, images=frames)
            if vlm_res and getattr(vlm_res, 'get', lambda k: None)("success"):
                parsed = vlm_res.get("parsed", {})
                if parsed.get("terminal_used"):
                    vlm_feedback = "VLM verified terminal activity."
                else:
                    vlm_feedback = "VLM did not detect clear terminal activity."
    except Exception as e:
        logger.warning(f"Optional VLM verification skipped/failed: {e}")

    # Determine Pass/Fail
    # To pass, must have valid XML, network preserved, SANI/BKB mostly redacted, and TOLI/GSI/KWP intact.
    # Score max = 10 (XML) + 20 (Preserve) + 15x2 (Stat Redact) + 10x2 (Sens Redact) + 20 (Intact) = 100
    passed = (score >= 80 and file_created)

    if not file_created:
        feedback_parts.insert(0, "FAILED: File timestamp shows it was NOT created/modified during task.")

    feedback_parts.append(vlm_feedback)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }