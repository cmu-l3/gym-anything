#!/usr/bin/env python3
import json
import os
import tempfile
import xml.etree.ElementTree as ET
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_track_work_slippage(traj, env_info, task_info):
    """
    Verifies that the agent updated the 'Database Implementation' task 
    with Actual Work = 40h and Remaining Work = 40h.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Check basic file existence via export result
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            export_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load export result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    if not export_data.get("output_exists", False):
        return {"passed": False, "score": 0, "feedback": "Output file 'work_slippage.xml' not found."}

    if not export_data.get("file_created_during_task", False):
        return {"passed": False, "score": 0, "feedback": "Output file was not created/modified during the task session."}

    # 2. Parse the XML file
    output_xml_path = task_info['metadata']['output_file']
    temp_xml = tempfile.NamedTemporaryFile(delete=False, suffix='.xml')
    try:
        copy_from_env(output_xml_path, temp_xml.name)
        tree = ET.parse(temp_xml.name)
        root = tree.getroot()
    except Exception as e:
        return {"passed": False, "score": 10, "feedback": f"Failed to parse output XML: {e}"}
    finally:
        if os.path.exists(temp_xml.name):
            os.unlink(temp_xml.name)

    # 3. Analyze content
    # XML Namespace handling for MSPDI
    ns = {'p': 'http://schemas.microsoft.com/project'}
    
    target_uid = task_info['metadata']['target_task_uid']
    
    # Locate task
    task_elem = None
    tasks = root.find('p:Tasks', ns)
    if tasks is not None:
        for t in tasks.findall('p:Task', ns):
            uid = t.find('p:UID', ns)
            if uid is not None and uid.text == target_uid:
                task_elem = t
                break
    
    if task_elem is None:
        return {"passed": False, "score": 10, "feedback": f"Task UID {target_uid} not found in output file."}

    # Helper to clean duration strings (e.g., "PT40H0M0S" -> 40.0)
    def parse_pt_hours(pt_str):
        if not pt_str or not pt_str.startswith('PT'):
            return 0.0
        try:
            # Simple parser for "PTxxHxxMxxS" format often used in MSPDI
            # Remove PT
            s = pt_str[2:]
            h = 0.0
            if 'H' in s:
                parts = s.split('H')
                h = float(parts[0])
            return h
        except:
            return 0.0

    # Extract values
    actual_work_str = task_elem.find('p:ActualWork', ns).text if task_elem.find('p:ActualWork', ns) is not None else ""
    remaining_work_str = task_elem.find('p:RemainingWork', ns).text if task_elem.find('p:RemainingWork', ns) is not None else ""
    work_str = task_elem.find('p:Work', ns).text if task_elem.find('p:Work', ns) is not None else ""
    
    actual_work_h = parse_pt_hours(actual_work_str)
    remaining_work_h = parse_pt_hours(remaining_work_str)
    total_work_h = parse_pt_hours(work_str)

    score = 10 # Baseline for valid file
    feedback = []

    # Check Actual Work (Target 40h)
    if abs(actual_work_h - 40.0) < 0.1:
        score += 30
        feedback.append("Actual Work correctly updated to 40h.")
    else:
        feedback.append(f"Actual Work incorrect. Expected 40h, got {actual_work_h}h.")

    # Check Remaining Work (Target 40h)
    if abs(remaining_work_h - 40.0) < 0.1:
        score += 30
        feedback.append("Remaining Work correctly updated to 40h.")
    else:
        feedback.append(f"Remaining Work incorrect. Expected 40h, got {remaining_work_h}h.")

    # Check Total Work/Duration Impact (Target 80h total)
    # The task started with 64h (8 days). Adding 40h actual + 40h remaining = 80h.
    if abs(total_work_h - 80.0) < 0.1:
        score += 20
        feedback.append("Total Work reflects slippage (80h).")
    elif total_work_h > 64.0:
        score += 10
        feedback.append(f"Total Work increased ({total_work_h}h), but not to expected 80h.")
    else:
        feedback.append(f"Total Work did not increase ({total_work_h}h).")

    # Correct Task Targeted
    # We found the task by UID, so this is implicit, giving points
    score += 10

    passed = (score >= 80)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }