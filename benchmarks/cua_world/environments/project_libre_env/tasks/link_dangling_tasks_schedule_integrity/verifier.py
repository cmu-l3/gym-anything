#!/usr/bin/env python3
"""
Verifier for link_dangling_tasks_schedule_integrity task.

Verifies that the agent has:
1. Exported the project to the correct path.
2. Linked dangling tasks (UID 10 and 11) to the Project Completion milestone (UID 12).
3. Maintained the original dependency (UID 9 -> 12).
"""

import json
import os
import tempfile
import xml.etree.ElementTree as ET
import sys

# Microsoft Project XML Namespace
NS = "http://schemas.microsoft.com/project"

def verify_link_dangling_tasks_schedule_integrity(traj, env_info, task_info):
    """
    Verify the network logic in the exported XML file.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Task parameters
    metadata = task_info.get('metadata', {})
    output_path = metadata.get('expected_output_file', '/home/ga/Projects/renovation_fixed.xml')
    target_milestone_uid = metadata.get('target_milestone_uid', '12')
    dangling_tasks = metadata.get('dangling_task_uids', ['10', '11'])
    original_pred = metadata.get('original_predecessor_uid', '9')

    score = 0
    feedback_parts = []
    passed = False

    # 1. Retrieve Result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # 2. Check File Existence & Creation
    if not result_data.get('output_exists', False):
        return {"passed": False, "score": 0, "feedback": f"Output file not found at {output_path}"}
    
    if not result_data.get('file_created_during_task', False):
        return {"passed": False, "score": 0, "feedback": "Output file timestamp indicates it was not created during the task session."}

    score += 20 # Points for valid file creation
    feedback_parts.append("Output file created")

    # 3. Retrieve and Parse XML Project File
    temp_xml = tempfile.NamedTemporaryFile(delete=False, suffix='.xml')
    try:
        copy_from_env(output_path, temp_xml.name)
        tree = ET.parse(temp_xml.name)
        root = tree.getroot()
    except ET.ParseError:
        return {"passed": False, "score": score, "feedback": "Output file is not valid XML"}
    except Exception as e:
        return {"passed": False, "score": score, "feedback": f"Failed to parse project file: {e}"}
    finally:
        if os.path.exists(temp_xml.name):
            os.unlink(temp_xml.name)

    # 4. Analyze Dependencies
    tasks_elem = root.find(f'{{{NS}}}Tasks')
    if tasks_elem is None:
        return {"passed": False, "score": score, "feedback": "XML does not contain Tasks element"}

    # Find the target milestone task
    target_task = None
    for task in tasks_elem.findall(f'{{{NS}}}Task'):
        uid = task.findtext(f'{{{NS}}}UID', '')
        if uid == target_milestone_uid:
            target_task = task
            break
    
    if target_task is None:
        return {"passed": False, "score": score, "feedback": f"Target milestone (UID {target_milestone_uid}) deleted or not found"}

    # Collect all predecessors for the target task
    # PredecessorLink structure: <PredecessorLink><PredecessorUID>X</PredecessorUID><Type>1</Type></PredecessorLink>
    actual_preds = set()
    for link in target_task.findall(f'{{{NS}}}PredecessorLink'):
        pred_uid = link.findtext(f'{{{NS}}}PredecessorUID', '')
        link_type = link.findtext(f'{{{NS}}}Type', '1') # Default 1 is FS
        
        # Verify it's a Finish-to-Start link (Type 1)
        if link_type == '1':
            actual_preds.add(pred_uid)

    # Verify Logic
    
    # Check Dangling Task 1 (Landscaping - UID 10)
    if dangling_tasks[0] in actual_preds:
        score += 30
        feedback_parts.append("Landscaping linked correctly")
    else:
        feedback_parts.append("Landscaping (Task 10) NOT linked to completion")

    # Check Dangling Task 2 (Security - UID 11)
    if dangling_tasks[1] in actual_preds:
        score += 30
        feedback_parts.append("Security System linked correctly")
    else:
        feedback_parts.append("Security System (Task 11) NOT linked to completion")

    # Check Original Logic Preserved (Flooring - UID 9)
    if original_pred in actual_preds:
        score += 10
        feedback_parts.append("Original dependency preserved")
    else:
        feedback_parts.append("Warning: Original dependency (Task 9) removed")

    # Check for accidental orphans (simplified check: verify we didn't wipe all links)
    if len(actual_preds) >= 3:
        score += 10
        feedback_parts.append("Network logic integrity good")

    # Pass logic
    if score >= 80:
        passed = True
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }