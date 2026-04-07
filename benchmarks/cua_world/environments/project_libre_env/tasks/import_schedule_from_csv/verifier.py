#!/usr/bin/env python3
"""
Verifier for import_schedule_from_csv task.

Checks:
1. XML Output file exists and was created during task.
2. Tasks from CSV are present in the XML.
3. Specific task duration is correct (verifies mapping).
4. Dependency exists between Stage Construction and Sound Check.
"""

import json
import os
import tempfile
import xml.etree.ElementTree as ET
import logging

# Configure logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

NS = "http://schemas.microsoft.com/project"

def verify_import_schedule_from_csv(traj, env_info, task_info):
    # 1. Setup and read result JSON
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_tasks = metadata.get('expected_tasks', [])
    
    # Copy result.json
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result data: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # 2. Check file existence and timestamp (Anti-gaming)
    if not result_data.get('output_exists', False):
        return {"passed": False, "score": 0, "feedback": "Output XML file not found at expected path."}
    
    if not result_data.get('file_created_during_task', False):
        return {"passed": False, "score": 0, "feedback": "Output file was not created/modified during the task session."}

    # 3. Retrieve and Parse XML
    output_path = result_data.get('output_path')
    temp_xml = tempfile.NamedTemporaryFile(delete=False, suffix='.xml')
    try:
        copy_from_env(output_path, temp_xml.name)
        tree = ET.parse(temp_xml.name)
        root = tree.getroot()
    except Exception as e:
        return {"passed": False, "score": 10, "feedback": f"Failed to parse output XML: {e}"}
    finally:
        if os.path.exists(temp_xml.name):
            os.unlink(temp_xml.name)

    # 4. Analyze XML Content
    score = 10 # Base score for valid file
    feedback = ["File created and valid XML."]
    
    tasks_elem = root.find(f"{{{NS}}}Tasks")
    if tasks_elem is None:
        return {"passed": False, "score": score, "feedback": "Invalid Project XML: No <Tasks> element found."}

    # Map Names to Task Objects for easy lookup
    # Note: ProjectLibre sometimes adds a root summary task, so we look for our specific names
    found_tasks = {}
    for task in tasks_elem.findall(f"{{{NS}}}Task"):
        name = task.findtext(f"{{{NS}}}Name", "")
        uid = task.findtext(f"{{{NS}}}UID", "")
        duration_fmt = task.findtext(f"{{{NS}}}Duration", "")
        
        if name:
            found_tasks[name] = {
                'uid': uid,
                'duration': duration_fmt,
                'element': task
            }

    # Criterion A: Verify all expected tasks are present (40 pts)
    missing_tasks = [t for t in expected_tasks if t not in found_tasks]
    if not missing_tasks:
        score += 40
        feedback.append("All expected tasks found.")
    else:
        # Partial credit
        hit_rate = (len(expected_tasks) - len(missing_tasks)) / len(expected_tasks)
        score += int(40 * hit_rate)
        feedback.append(f"Missing tasks: {', '.join(missing_tasks)}")

    # Criterion B: Verify duration mapping (20 pts)
    # "Stage Construction" should be 3 days.
    # MSPDI duration format: PT24H0M0S (3 days * 8 hours) or similar
    check_task = metadata.get('check_duration_task', 'Stage Construction')
    if check_task in found_tasks:
        dur_str = found_tasks[check_task]['duration']
        # Simple check for '24H' (3 days * 8 hours) or '3D' depending on how it saves
        # ProjectLibre usually uses PTxxH
        if 'PT24H' in dur_str or 'PT24.0H' in dur_str: 
            score += 20
            feedback.append(f"Duration for '{check_task}' is correct (3 days).")
        else:
            feedback.append(f"Duration for '{check_task}' incorrect. Expected ~PT24H, got '{dur_str}'. Check column mapping.")
    else:
        feedback.append(f"Cannot verify duration: '{check_task}' not found.")

    # Criterion C: Verify Dependency (30 pts)
    # Sound Check (Successor) -> Stage Construction (Predecessor)
    pred_name = metadata.get('predecessor_name', 'Stage Construction')
    succ_name = metadata.get('successor_name', 'Sound Check')
    
    dependency_found = False
    
    if pred_name in found_tasks and succ_name in found_tasks:
        pred_uid = found_tasks[pred_name]['uid']
        succ_task_elem = found_tasks[succ_name]['element']
        
        # Look for PredecessorLink in the successor task
        for link in succ_task_elem.findall(f"{{{NS}}}PredecessorLink"):
            link_pred_uid = link.findtext(f"{{{NS}}}PredecessorUID")
            if link_pred_uid == pred_uid:
                dependency_found = True
                break
    
    if dependency_found:
        score += 30
        feedback.append(f"Correct dependency found: {succ_name} depends on {pred_name}.")
    else:
        if pred_name in found_tasks and succ_name in found_tasks:
            feedback.append(f"Dependency missing: {succ_name} does not link to {pred_name}.")
        else:
            feedback.append("Cannot verify dependency due to missing tasks.")

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " ".join(feedback)
    }