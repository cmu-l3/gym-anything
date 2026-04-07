#!/usr/bin/env python3
"""
Verifier for configure_backward_scheduling_jit task.
Checks if the output XML file:
1. Exists and was created during the task.
2. Has ScheduleFromStart set to 0 (False).
3. Has FinishDate set to 2025-06-20.
4. Has tasks updated to ALAP constraint (ConstraintType 1).
"""

import json
import os
import tempfile
import xml.etree.ElementTree as ET
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_backward_scheduling(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env missing"}

    # 1. Retrieve Result JSON from Export Script
    metadata = task_info.get('metadata', {})
    expected_path = metadata.get('expected_path', '/home/ga/Projects/jit_schedule.xml')
    target_date_str = metadata.get('target_date', '2025-06-20')
    
    # Load the shell script's result JSON
    result_json_path = "/tmp/task_result.json"
    local_result_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json').name
    
    try:
        copy_from_env(result_json_path, local_result_json)
        with open(local_result_json, 'r') as f:
            shell_result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not retrieve task status: {str(e)}"}
    finally:
        if os.path.exists(local_result_json):
            os.unlink(local_result_json)

    # 2. Check File Existence & Freshness (Anti-Gaming)
    if not shell_result.get("file_exists"):
        return {"passed": False, "score": 0, "feedback": f"Output file {os.path.basename(expected_path)} not found."}
    
    if not shell_result.get("is_fresh"):
        return {"passed": False, "score": 0, "feedback": "Output file exists but was not modified during the task session."}

    # 3. Retrieve and Parse the XML Project File
    local_xml_path = tempfile.NamedTemporaryFile(delete=False, suffix='.xml').name
    try:
        copy_from_env(expected_path, local_xml_path)
        tree = ET.parse(local_xml_path)
        root = tree.getroot()
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to parse output XML: {str(e)}"}
    finally:
        if os.path.exists(local_xml_path):
            os.unlink(local_xml_path)

    # 4. Verify Project Settings
    # Namespace handling for MSPDI (often http://schemas.microsoft.com/project)
    # We'll search with and without namespace or use wildcard logic for robustness
    ns = {'p': 'http://schemas.microsoft.com/project'}
    
    # Helper to find text safely
    def find_text(element, tag):
        # Try with namespace
        res = element.find(f"p:{tag}", ns)
        if res is not None: return res.text
        # Try without namespace (if XML doesn't use it strictly)
        res = element.find(tag)
        if res is not None: return res.text
        return None

    score = 20 # Points for valid file existing
    feedback = ["File saved successfully."]

    # Check 1: Schedule From Start (Should be 0 or 'false')
    sched_from_start = find_text(root, "ScheduleFromStart")
    is_backward = sched_from_start in ['0', 'false', 'False']
    
    if is_backward:
        score += 40
        feedback.append("Correctly set to Schedule from Finish.")
    else:
        feedback.append(f"Incorrect scheduling mode. <ScheduleFromStart> is '{sched_from_start}', expected '0'.")

    # Check 2: Finish Date
    finish_date = find_text(root, "FinishDate") # Format: 2025-06-20T17:00:00
    if finish_date and target_date_str in finish_date:
        score += 20
        feedback.append(f"Correct finish date: {target_date_str}.")
    else:
        feedback.append(f"Incorrect finish date. Found '{finish_date}', expected '{target_date_str}'.")

    # Check 3: Task Constraints (Logic Verification)
    # When switching to Backward Scheduling, ProjectLibre usually updates tasks 
    # from ASAP (0) to ALAP (1). We check a standard task.
    tasks = root.findall("p:Tasks/p:Task", ns) or root.findall("Tasks/Task")
    
    # We check a few tasks to ensure the engine propagated the logic
    alap_count = 0
    checked_tasks = 0
    
    for task in tasks:
        # Skip summary tasks if needed, but ALAP usually applies to leaf tasks
        constraint_type = find_text(task, "ConstraintType")
        # 0=ASAP, 1=ALAP
        if constraint_type == '1': 
            alap_count += 1
        checked_tasks += 1
    
    # If a significant portion of tasks are ALAP, the engine worked.
    # In a forward schedule, almost all are 0. In backward, they become 1.
    if alap_count > 0:
        score += 20
        feedback.append("Task constraints successfully updated to 'As Late As Possible'.")
    else:
        feedback.append("Task constraints did not update (still ASAP). Did you click OK in the dialog?")

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " ".join(feedback)
    }