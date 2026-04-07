#!/usr/bin/env python3
"""
Verifier for export_selected_dives_ssrf task.
"""

import os
import json
import tempfile
import xml.etree.ElementTree as ET
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_export_selected_dives_ssrf(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_dive_count = metadata.get('expected_dive_count', 4)
    expected_date_prefix = metadata.get('expected_date_prefix', '2011-09')
    
    # Read result.json
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    output_exists = result.get('output_exists', False)
    file_created = result.get('file_created_during_task', False)
    
    if not output_exists:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Output file /home/ga/Documents/yellow_house.ssrf does not exist."
        }

    if not file_created:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Output file exists but was not created during the task. (Timestamp anti-gaming)"
        }

    # Copy output file to inspect contents
    temp_xml = tempfile.NamedTemporaryFile(delete=False, suffix='.ssrf')
    try:
        copy_from_env("/home/ga/Documents/yellow_house.ssrf", temp_xml.name)
        
        try:
            tree = ET.parse(temp_xml.name)
            root = tree.getroot()
        except ET.ParseError as e:
            return {
                "passed": False,
                "score": 20,
                "feedback": f"File exists but is not valid XML: {e}"
            }
            
        score = 40  # 20 for file exists, 20 for valid XML format
        feedback_parts = ["File created", "Valid XML"]
        
        # Check dives
        dives = list(root.iter('dive'))
        dive_count = len(dives)
        
        if dive_count == expected_dive_count:
            score += 30
            feedback_parts.append(f"Exactly {expected_dive_count} dives exported")
        else:
            feedback_parts.append(f"Expected {expected_dive_count} dives, found {dive_count} (Did you export all dives instead of just selected?)")
            
        # Check dive dates
        correct_dates = 0
        for dive in dives:
            date = dive.get('date', '')
            if date.startswith(expected_date_prefix):
                correct_dates += 1
                
        if dive_count > 0:
            date_score = int((correct_dates / dive_count) * 30)
            score += date_score
            if correct_dates == dive_count:
                feedback_parts.append(f"All exported dives have correct dates ({expected_date_prefix})")
            else:
                feedback_parts.append(f"{correct_dates}/{dive_count} dives have correct dates")
        
        passed = (score >= 70 and 
                  dive_count == expected_dive_count and 
                  correct_dates == expected_dive_count)

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }
            
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error validating output file: {e}"}
    finally:
        if os.path.exists(temp_xml.name):
            os.unlink(temp_xml.name)