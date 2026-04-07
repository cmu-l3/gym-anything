#!/usr/bin/env python3
"""
Verifier for merge_project_phases task.

Verifies that the agent has consolidated two project XML files into one,
preserving the tasks from both and ensuring the correct order (Frontend before Backend).
"""

import json
import os
import tempfile
import xml.etree.ElementTree as ET
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# MSPDI Namespace
NS = "{http://schemas.microsoft.com/project}"

def verify_merge_project_phases(traj, env_info, task_info):
    """
    Verify the merged project file.
    
    Criteria:
    1. Output file exists and is valid XML.
    2. File was created during the task (anti-gaming).
    3. Contains tasks from Frontend phase (e.g. "Login UI Component").
    4. Contains tasks from Backend phase (e.g. "Auth API Endpoint").
    5. Frontend tasks appear BEFORE Backend tasks in the task list.
    """
    
    # 1. Setup and Environment Access
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    output_path = metadata.get('output_file', '/home/ga/Projects/output/full_release.xml')
    frontend_marker = metadata.get('frontend_marker_task', 'Login UI Component')
    backend_marker = metadata.get('backend_marker_task', 'Auth API Endpoint')
    
    # 2. Get Result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # 3. Basic Validation (Existence & Freshness)
    if not result_data.get('output_exists', False):
        return {"passed": False, "score": 0, "feedback": "Output file full_release.xml not found."}
    
    if not result_data.get('file_created_during_task', False):
        return {"passed": False, "score": 0, "feedback": "Output file was not created/modified during the task."}

    # 4. Content Validation (Parse XML)
    score = 20 # Base points for creating the file
    feedback_parts = ["File created"]
    
    temp_xml = tempfile.NamedTemporaryFile(delete=False, suffix='.xml')
    try:
        copy_from_env(output_path, temp_xml.name)
        
        # Parse XML
        try:
            tree = ET.parse(temp_xml.name)
            root = tree.getroot()
        except ET.ParseError:
            return {"passed": False, "score": 20, "feedback": "Output file is not valid XML."}

        # Check for Tasks
        tasks_found = []
        
        # Namespace handling
        # Root is <Project xmlns="..."> so we need namespace for findall
        
        tasks_elem = root.find(f'{NS}Tasks')
        if tasks_elem is None:
             # Try without namespace if explicit namespace fails (some exports might strip it)
             tasks_elem = root.find('Tasks')
             ns_prefix = ""
        else:
             ns_prefix = NS

        if tasks_elem is None:
            return {"passed": False, "score": 20, "feedback": "No <Tasks> element found in project file."}
        
        # Find all tasks and their names
        task_list = []
        for task in tasks_elem.findall(f'{ns_prefix}Task'):
            name_elem = task.find(f'{ns_prefix}Name')
            uid_elem = task.find(f'{ns_prefix}UID')
            
            if name_elem is not None and name_elem.text:
                task_list.append({
                    'name': name_elem.text,
                    'uid': uid_elem.text if uid_elem is not None else "0"
                })

        # Check existence of marker tasks
        has_frontend = False
        frontend_idx = -1
        
        has_backend = False
        backend_idx = -1
        
        for idx, t in enumerate(task_list):
            if frontend_marker.lower() in t['name'].lower():
                has_frontend = True
                frontend_idx = idx
            if backend_marker.lower() in t['name'].lower():
                has_backend = True
                backend_idx = idx

        # Score calculations
        if has_frontend:
            score += 25
            feedback_parts.append("Frontend tasks found")
        else:
            feedback_parts.append(f"Missing frontend task '{frontend_marker}'")
            
        if has_backend:
            score += 25
            feedback_parts.append("Backend tasks found")
        else:
            feedback_parts.append(f"Missing backend task '{backend_marker}'")

        # Check Ordering
        ordering_correct = False
        if has_frontend and has_backend:
            if frontend_idx < backend_idx:
                score += 30
                ordering_correct = True
                feedback_parts.append("Tasks in correct order (Frontend -> Backend)")
            else:
                feedback_parts.append("Tasks in WRONG order (Backend -> Frontend)")
        
    except Exception as e:
        return {"passed": False, "score": score, "feedback": f"Error verifying content: {e}"}
    finally:
        if os.path.exists(temp_xml.name):
            os.unlink(temp_xml.name)

    passed = (score >= 70) and ordering_correct
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }