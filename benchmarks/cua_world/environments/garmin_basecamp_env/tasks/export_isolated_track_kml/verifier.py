#!/usr/bin/env python3
import json
import tempfile
import os
import xml.etree.ElementTree as ET
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_export_isolated_track_kml(traj, env_info, task_info):
    """
    Verify the user renamed and exported solely the track as a KML file.
    Checks:
    1. KML Output Exists and was created during the task
    2. Track correctly renamed (parses XML for <name>Official Survey Path</name>)
    3. Export is isolated (No <Point> geometry nodes indicating waypoints are exported)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Read task_result.json meta data exported
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:\\tmp\\task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to read result JSON: {e}")
        result = {}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
            
    output_exists = result.get('output_exists', False)
    file_created_during_task = result.get('file_created_during_task', False)
    
    score = 0
    feedback_parts = []
    
    if not output_exists:
        return {
            "passed": False,
            "score": 0,
            "feedback": "KML output file was not found.",
            "details": {"file_exists": False}
        }
        
    score += 20
    feedback_parts.append("KML file exists")
    
    if file_created_during_task:
        feedback_parts.append("File created during task")
    else:
        feedback_parts.append("File was not newly created (possible gaming)")
        
    # 2. Analyze KML file XML structure
    temp_kml = tempfile.NamedTemporaryFile(delete=False, suffix='.kml')
    track_renamed = False
    data_isolated = False
    
    try:
        copy_from_env("C:\\Users\\Docker\\Documents\\survey_path.kml", temp_kml.name)
        
        tree = ET.parse(temp_kml.name)
        root = tree.getroot()
        
        # Handle BaseCamp KML namespaces effectively
        namespace = ''
        if '}' in root.tag:
            namespace = root.tag.split('}')[0] + '}'
            
        placemarks = list(root.iter(f'{namespace}Placemark'))
        
        point_count = 0
        linestring_count = 0
        
        for pm in placemarks:
            name_el = pm.find(f'{namespace}name')
            if name_el is not None and name_el.text and "Official Survey Path" in name_el.text:
                track_renamed = True
                
            # Waypoints export as points; Tracks export as LineStrings (or inside MultiGeometry)
            points = list(pm.iter(f'{namespace}Point'))
            linestrings = list(pm.iter(f'{namespace}LineString'))
            
            point_count += len(points)
            linestring_count += len(linestrings)
            
        if track_renamed:
            score += 30
            feedback_parts.append("Track correctly renamed")
        else:
            feedback_parts.append("Track was NOT correctly renamed")
            
        if point_count == 0 and linestring_count > 0:
            data_isolated = True
            score += 30
            feedback_parts.append("Data correctly isolated (no waypoints)")
        elif point_count > 0:
            feedback_parts.append(f"Data NOT isolated: Found {point_count} waypoint(s) in export")
        elif linestring_count == 0:
            feedback_parts.append("No track found in export")

    except ET.ParseError:
        feedback_parts.append("KML file is not valid XML")
    except Exception as e:
        logger.error(f"Failed to analyze KML: {e}")
        feedback_parts.append(f"Error analyzing KML: {str(e)}")
    finally:
        if os.path.exists(temp_kml.name):
            os.unlink(temp_kml.name)

    # 3. Trajectory & Final Screenshot VLM Logic 
    try:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
        frames = sample_trajectory_frames(traj, n=3)
        final = get_final_screenshot(traj)
        
        prompt = (
            "Did the user interact with Garmin BaseCamp to rename a track to 'Official Survey Path' "
            "and export ONLY the track as a KML file? Answer in JSON format: {'completed': true/false}"
        )

        vlm_res = query_vlm(images=frames + [final], prompt=prompt)
        parsed = vlm_res.get("parsed", {})
        if parsed.get("completed"):
            score += 20
            feedback_parts.append("VLM visual verification passed")
        else:
            feedback_parts.append("VLM visual verification did not find full workflow")
    except Exception as e:
        logger.error(f"VLM verification error: {e}")
        # As a fallback, reward points based on impeccable programmatic data checking 
        if track_renamed and data_isolated:
            score += 20
            feedback_parts.append("VLM fallback: assuming success based on perfect data")
            
    passed = (score >= 80) and track_renamed and data_isolated and file_created_during_task
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }