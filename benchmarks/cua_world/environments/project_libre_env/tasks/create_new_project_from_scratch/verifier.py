#!/usr/bin/env python3
"""
Verifier for create_new_project_from_scratch task.
Verifies XML output file existence, creation time, and content (tasks, durations, dependencies).
"""

import os
import sys
import json
import logging
import tempfile
import xml.etree.ElementTree as ET

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_duration_to_days(dur_text):
    """
    Parse MSPDI duration (PT{X}H{Y}M{Z}S) to days (assuming 8h/day).
    Example: PT16H0M0S -> 2.0 days
    """
    if not dur_text:
        return 0.0
    dur_text = dur_text.strip()
    
    # Simple regex-free parsing for standard MSPDI format
    # Format: PT{hours}H{minutes}M{seconds}S
    hours = 0.0
    try:
        if "PT" in dur_text and "H" in dur_text:
            h_part = dur_text.split("PT")[-1].split("H")[0]
            hours = float(h_part)
        # Handle minutes/seconds if needed, but ProjectLibre usually outputs hours for days
    except ValueError:
        return 0.0
        
    return hours / 8.0  # Convert to days (standard 8h work day)

def fuzzy_match(expected, actual):
    """Case-insensitive substring match."""
    e = expected.lower().strip()
    a = actual.lower().strip()
    return e == a or e in a or a in e

def verify_create_new_project_from_scratch(traj, env_info, task_info):
    """
    Verify the solar installation project creation.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_tasks = metadata.get('tasks', [])
    output_path = metadata.get('expected_file_path', '/home/ga/Projects/solar_installation.xml')
    
    score = 0
    max_score = 100
    feedback_parts = []
    
    # 1. Retrieve Result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # 2. Check File Existence & Timestamp (Anti-Gaming) (15 pts)
    output_exists = result_data.get('output_exists', False)
    file_created_during_task = result_data.get('file_created_during_task', False)
    output_size = result_data.get('output_size_bytes', 0)

    if not output_exists:
        return {"passed": False, "score": 0, "feedback": "Output XML file not found"}
    
    if output_size < 200:
        return {"passed": False, "score": 0, "feedback": "Output file is too small to be a valid project"}

    if file_created_during_task:
        score += 15
        feedback_parts.append("File created/modified during task (15/15)")
    else:
        feedback_parts.append("Warning: File timestamp indicates it wasn't modified during task")
        # Continue verification but with penalty/risk of failing

    # 3. Retrieve and Parse XML Content
    temp_xml = tempfile.NamedTemporaryFile(delete=False, suffix='.xml')
    try:
        copy_from_env(output_path, temp_xml.name)
        
        # Parse XML
        try:
            tree = ET.parse(temp_xml.name)
            root = tree.getroot()
        except ET.ParseError as e:
            return {"passed": False, "score": score, "feedback": f"Invalid XML format: {e}"}

        # Handle namespaces (Microsoft Project XML usually has one)
        # We'll strip namespaces for easier parsing in this verifier
        def get_local_tag(tag):
            return tag.split('}')[-1] if '}' in tag else tag

        # Extract Tasks
        # Map UID -> Name and Name -> Data
        uid_to_name = {}
        task_data = {} # Name -> {duration, predecessors_uids}

        # Find the Tasks collection
        tasks_elem = None
        for elem in root.iter():
            if get_local_tag(elem.tag) == 'Tasks':
                tasks_elem = elem
                break
        
        if tasks_elem is None:
            return {"passed": False, "score": score, "feedback": "No <Tasks> element found in XML"}

        for task in tasks_elem:
            if get_local_tag(task.tag) != 'Task':
                continue
            
            t_uid = None
            t_name = None
            t_duration_txt = None
            t_preds = []
            t_summary = "0"
            t_id = None

            for child in task:
                tag = get_local_tag(child.tag)
                if tag == 'UID': t_uid = child.text
                elif tag == 'ID': t_id = child.text
                elif tag == 'Name': t_name = child.text
                elif tag == 'Duration': t_duration_txt = child.text
                elif tag == 'Summary': t_summary = child.text
                elif tag == 'PredecessorLink':
                    for sub in child:
                        if get_local_tag(sub.tag) == 'PredecessorUID':
                            t_preds.append(sub.text)

            # Skip project summary task (usually ID 0) or empty names
            if not t_name: continue
            if t_summary == "1" and t_id == "0": continue 

            if t_uid:
                uid_to_name[t_uid] = t_name
                
            task_data[t_name] = {
                "duration_txt": t_duration_txt,
                "pred_uids": t_preds
            }

        # 4. Verify Content
        
        # A. Task Names (30 pts - 5 pts each)
        tasks_found = 0
        matched_map = {} # Expected Name -> Actual Name
        
        for exp in expected_tasks:
            found = False
            for act_name in task_data:
                if fuzzy_match(exp['name'], act_name):
                    matched_map[exp['name']] = act_name
                    tasks_found += 1
                    found = True
                    break
            if not found:
                feedback_parts.append(f"Missing task: {exp['name']}")

        name_score = min(30, tasks_found * 5)
        score += name_score
        feedback_parts.append(f"Tasks found: {tasks_found}/6 ({name_score}/30)")

        # B. Durations (25 pts - ~4 pts each)
        durations_correct = 0
        for exp in expected_tasks:
            if exp['name'] in matched_map:
                act_name = matched_map[exp['name']]
                act_dur_days = parse_duration_to_days(task_data[act_name]['duration_txt'])
                exp_dur = exp['duration_days']
                
                # Tolerance of 0.5 days
                if abs(act_dur_days - exp_dur) <= 0.5:
                    durations_correct += 1
                else:
                    feedback_parts.append(f"Wrong duration for '{exp['name']}': got {act_dur_days}d, expected {exp_dur}d")

        dur_score = min(25, int(durations_correct * (25/6)))
        score += dur_score
        feedback_parts.append(f"Durations correct: {durations_correct}/6 ({dur_score}/25)")

        # C. Dependencies (30 pts - 5 pts each)
        deps_correct = 0
        for exp in expected_tasks:
            if exp['name'] in matched_map:
                act_name = matched_map[exp['name']]
                act_pred_uids = task_data[act_name]['pred_uids']
                
                # Convert actual pred UIDs to names
                act_pred_names = [uid_to_name.get(u, u) for u in act_pred_uids]
                
                exp_preds = exp['predecessors']
                
                # Check if matches
                if len(exp_preds) == 0 and len(act_pred_uids) == 0:
                    deps_correct += 1
                else:
                    # Check if all expected preds are present
                    all_found = True
                    for ep in exp_preds:
                        found_pred = False
                        for ap in act_pred_names:
                            if fuzzy_match(ep, ap):
                                found_pred = True
                                break
                        if not found_pred:
                            all_found = False
                            break
                    
                    # Also check no extra preds roughly (len check)
                    if all_found and len(act_pred_uids) == len(exp_preds):
                        deps_correct += 1
                    else:
                        feedback_parts.append(f"Wrong deps for '{exp['name']}': expected {exp_preds}, got {act_pred_names}")

        dep_score = min(30, deps_correct * 5)
        score += dep_score
        feedback_parts.append(f"Dependencies correct: {deps_correct}/6 ({dep_score}/30)")

    finally:
        if os.path.exists(temp_xml.name):
            os.unlink(temp_xml.name)

    passed = score >= 50
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }