#!/usr/bin/env python3
"""
Verifier for reconfigure_server_topology task.
Checks if the server was renamed via API and if the documentation files were generated correctly.
"""

import json
import os
import tempfile
import logging
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_reconfigure_server_topology(traj, env_info, task_info):
    """
    Verify the server reconfiguration and documentation task.
    """
    # 1. Setup
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    target_server_name = metadata.get('target_server_name', 'CORP-WH07-NVR01')
    target_location_fragment = "Warehouse 07"
    
    # 2. Retrieve result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result file: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    api_state = result.get('api_state', {})
    files = result.get('files', {})
    
    # =========================================================
    # CRITERION 1: Server Rename (API Check) - 30 Points
    # =========================================================
    current_server_name = api_state.get('server_name', '')
    if current_server_name == target_server_name:
        score += 30
        feedback.append("✅ Server successfully renamed via API.")
    else:
        feedback.append(f"❌ Server name is '{current_server_name}', expected '{target_server_name}'.")

    # =========================================================
    # CRITERION 2: Server Metadata/Parameters (API Check) - 10 Points
    # =========================================================
    # We check the full server info object for the location string
    full_info_str = json.dumps(api_state.get('full_server_info', {}))
    if target_location_fragment in full_info_str:
        score += 10
        feedback.append("✅ Location metadata found in server configuration.")
    else:
        feedback.append("❌ Location metadata not found in server API response.")

    # =========================================================
    # CRITERION 3: JSON Documentation File (File Check) - 40 Points
    # =========================================================
    json_exists = files.get('json_exists', False)
    json_content_str = files.get('json_content', '{}')
    
    if json_exists:
        try:
            doc = json.loads(json_content_str)
            score += 5  # File exists and parses
            
            # Check Schema Structure
            has_system = 'system' in doc
            has_servers = 'servers' in doc and isinstance(doc['servers'], list)
            has_summary = 'summary' in doc
            
            if has_system and has_servers and has_summary:
                score += 10
                feedback.append("✅ JSON structure is correct.")
                
                # Check Content Accuracy
                server_entry = doc['servers'][0] if doc['servers'] else {}
                
                # Check Name in JSON
                if server_entry.get('name') == target_server_name:
                    score += 10
                    feedback.append("✅ JSON correctly lists new server name.")
                
                # Check Location in JSON
                if target_location_fragment in server_entry.get('locationDescription', ''):
                    score += 5
                    feedback.append("✅ JSON correctly lists location description.")
                    
                # Check Cameras
                cameras = server_entry.get('cameras', [])
                real_cam_count = api_state.get('camera_count', 0)
                
                if len(cameras) == real_cam_count and real_cam_count > 0:
                    score += 10
                    feedback.append(f"✅ JSON correctly lists all {real_cam_count} cameras.")
                elif len(cameras) > 0:
                    score += 5
                    feedback.append(f"⚠️ JSON lists {len(cameras)} cameras, expected {real_cam_count}.")
                else:
                    feedback.append("❌ JSON camera list is empty.")
                    
            else:
                feedback.append("❌ JSON missing required top-level keys (system, servers, summary).")
                
        except json.JSONDecodeError:
            feedback.append("❌ Architecture document is not valid JSON.")
    else:
        feedback.append("❌ Architecture JSON file not found.")

    # =========================================================
    # CRITERION 4: Text Summary (File Check) - 20 Points
    # =========================================================
    text_exists = files.get('text_exists', False)
    text_content = files.get('text_content', '')
    
    if text_exists:
        score += 5
        if target_server_name in text_content:
            score += 5
            feedback.append("✅ Text summary contains correct server name.")
        
        if target_location_fragment in text_content:
            score += 5
            feedback.append("✅ Text summary contains location info.")
            
        # Check for camera count number presence
        real_cam_count = api_state.get('camera_count', 0)
        if str(real_cam_count) in text_content:
            score += 5
            feedback.append("✅ Text summary mentions camera count.")
    else:
        feedback.append("❌ Text summary file not found.")

    # =========================================================
    # Final Result
    # =========================================================
    passed = score >= 60 and (current_server_name == target_server_name)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }