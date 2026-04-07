#!/usr/bin/env python3
"""
Verifier for clean_multipath_gps_errors task.

Checks:
1. Did the agent export a file to C:\\workspace\\data\\fells_cleaned.gpx?
2. Is the track renamed to 'Fells Cleaned'?
3. Are the anomalous coordinate spikes removed?
4. Is the valid data largely preserved? (Preventing "delete all" strategies)
"""

import os
import json
import tempfile
import logging
import xml.etree.ElementTree as ET

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def find_elements(root, tag_name):
    """Safely find XML elements ignoring namespaces."""
    return [elem for elem in root.iter() if elem.tag.endswith(f"}}{tag_name}") or elem.tag == tag_name]

def verify_clean_multipath_gps_errors(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Framework error: copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    spike_lat_threshold = metadata.get('spike_latitude_threshold', 44.0)
    min_points = metadata.get('minimum_preserved_points', 50)
    
    score = 0
    feedback_parts = []
    
    # 1. Retrieve the task result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:\\tmp\\task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read export metadata: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # Validate output exists and was created by the agent
    output_exists = result.get('output_exists', False)
    created_during_task = result.get('file_created_during_task', False)
    
    if not output_exists:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Exported file fells_cleaned.gpx was not found."
        }
        
    if not created_during_task:
        feedback_parts.append("WARNING: File timestamps indicate it may not have been created during this session")
        # Proceed but note it
        
    score += 10
    feedback_parts.append("File exported (+10)")

    # 2. Retrieve the GPX file for analysis
    temp_gpx = tempfile.NamedTemporaryFile(delete=False, suffix='.gpx')
    try:
        copy_from_env("C:\\workspace\\data\\fells_cleaned.gpx", temp_gpx.name)
        
        tree = ET.parse(temp_gpx.name)
        root = tree.getroot()
        
        # Analyze track name
        trks = find_elements(root, 'trk')
        if not trks:
            return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts) + " | No track found in exported GPX"}
            
        trk = trks[0]
        names = find_elements(trk, 'name')
        track_name = names[0].text if names else ""
        
        if track_name.strip() == "Fells Cleaned":
            score += 20
            feedback_parts.append("Track correctly renamed (+20)")
        else:
            feedback_parts.append(f"Track name is '{track_name}', expected 'Fells Cleaned' (+0)")

        # Analyze track points
        trkpts = find_elements(root, 'trkpt')
        num_points = len(trkpts)
        
        spike_count = 0
        for pt in trkpts:
            lat_str = pt.attrib.get('lat', '0')
            try:
                lat = float(lat_str)
                # The normal Fells loop is at ~42.4. The injected spike is at ~44.5.
                if lat > spike_lat_threshold:
                    spike_count += 1
            except ValueError:
                pass
                
        if spike_count == 0:
            score += 40
            feedback_parts.append("Multipath anomaly points successfully removed (+40)")
        else:
            feedback_parts.append(f"FAILED to remove anomaly: {spike_count} spike points remain (+0)")
            
        if num_points >= min_points:
            score += 30
            feedback_parts.append(f"Valid data preserved ({num_points} points remaining) (+30)")
        else:
            feedback_parts.append(f"Too much valid data deleted (Only {num_points} points remaining, min {min_points}) (+0)")
            
    except ET.ParseError:
        feedback_parts.append("Exported GPX file is not valid XML")
    except Exception as e:
        feedback_parts.append(f"Error parsing GPX: {e}")
    finally:
        if os.path.exists(temp_gpx.name):
            os.unlink(temp_gpx.name)

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }