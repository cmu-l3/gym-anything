#!/usr/bin/env python3
"""
Verifier for archive_completed_work_orders task.

Verifies:
1. `archive.xml` exists and contains ONLY completed tasks.
2. `active_log.xml` exists and contains ONLY incomplete tasks.
3. Total number of tasks is preserved (Conservation of Data).
4. Files were created/modified during the task.
"""

import json
import os
import sys
import tempfile
import xml.etree.ElementTree as ET

# File paths in the container (used for copy references)
ARCHIVE_PATH = "/home/ga/Projects/archive.xml"
ACTIVE_PATH = "/home/ga/Projects/active_log.xml"
RESULT_JSON_PATH = "/tmp/task_result.json"

def parse_mspdi_tasks(xml_content):
    """
    Parses MSPDI XML content and returns a list of task dicts.
    Handles the default namespace usually present in ProjectLibre files.
    """
    try:
        root = ET.fromstring(xml_content)
        
        # Handle namespace blindly by stripping it from tags
        # or just finding elements by local name
        tasks = []
        
        # Find all elements that look like a Task
        # We iterate recursively
        for elem in root.iter():
            if elem.tag.endswith("Task"):
                # Check if it has UID and ID (to filter out weird wrapper tags if any)
                uid_elem = None
                percent_elem = None
                summary_elem = None
                
                for child in elem:
                    if child.tag.endswith("UID"):
                        uid_elem = child
                    elif child.tag.endswith("PercentComplete"):
                        percent_elem = child
                    elif child.tag.endswith("Summary"):
                        summary_elem = child
                
                if uid_elem is not None:
                    # Filter out Project Summary Task (usually UID 0)
                    if uid_elem.text == "0":
                        continue
                    
                    # Ignore summary tasks (folders) if any
                    is_summary = summary_elem is not None and summary_elem.text == "1"
                    if is_summary:
                        continue
                        
                    pct = 0
                    if percent_elem is not None and percent_elem.text:
                        pct = int(percent_elem.text)
                        
                    tasks.append({
                        "uid": uid_elem.text,
                        "pct": pct
                    })
        return tasks
    except Exception as e:
        print(f"XML Parsing error: {e}")
        return None

def verify_archive_completed_work_orders(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Retrieve Result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env(RESULT_JSON_PATH, temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result JSON: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback = []
    
    archive_info = result_data.get("archive_file", {})
    active_info = result_data.get("active_file", {})
    initial_counts = result_data.get("initial_counts", {})
    
    expected_total = initial_counts.get("total", 0)
    expected_completed = initial_counts.get("completed", 0)
    expected_active = initial_counts.get("active", 0)

    # --- CRITERION 1: Files Exist (10 pts) ---
    if archive_info.get("exists") and active_info.get("exists"):
        score += 10
        feedback.append("Both output files exist.")
    else:
        feedback.append("One or both output files are missing.")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback)}

    # --- CRITERION 2: Files Created During Task (10 pts) ---
    if archive_info.get("created_during_task") and active_info.get("created_during_task"):
        score += 10
        feedback.append("Files were modified during task execution.")
    else:
        feedback.append("Files detected but timestamps indicate they were not saved during this session.")
        # We continue but this is bad
    
    # --- Parse XML Files ---
    archive_tasks = []
    active_tasks = []
    
    # Read Archive XML
    temp_xml = tempfile.NamedTemporaryFile(delete=False, suffix='.xml')
    try:
        copy_from_env(ARCHIVE_PATH, temp_xml.name)
        with open(temp_xml.name, 'rb') as f:
            archive_tasks = parse_mspdi_tasks(f.read())
    except Exception as e:
        feedback.append(f"Failed to parse archive.xml: {e}")
        archive_tasks = None
    finally:
        if os.path.exists(temp_xml.name):
            os.unlink(temp_xml.name)

    # Read Active XML
    temp_xml = tempfile.NamedTemporaryFile(delete=False, suffix='.xml')
    try:
        copy_from_env(ACTIVE_PATH, temp_xml.name)
        with open(temp_xml.name, 'rb') as f:
            active_tasks = parse_mspdi_tasks(f.read())
    except Exception as e:
        feedback.append(f"Failed to parse active_log.xml: {e}")
        active_tasks = None
    finally:
        if os.path.exists(temp_xml.name):
            os.unlink(temp_xml.name)

    if archive_tasks is None or active_tasks is None:
        return {"passed": False, "score": score, "feedback": " | ".join(feedback)}

    # --- CRITERION 3: Archive Quality (30 pts) ---
    # Archive should ONLY contain 100% tasks
    archive_count = len(archive_tasks)
    archive_errors = [t for t in archive_tasks if t['pct'] != 100]
    
    if archive_count == 0:
        feedback.append("Archive file is empty (0 tasks).")
    elif len(archive_errors) > 0:
        feedback.append(f"Archive contains {len(archive_errors)} incomplete tasks (should only have 100% completed).")
        # Partial credit
        score += int(30 * (1 - (len(archive_errors) / archive_count)))
    else:
        score += 30
        feedback.append(f"Archive contains {archive_count} completed tasks (Clean).")

    # --- CRITERION 4: Active Log Quality (30 pts) ---
    # Active log should ONLY contain <100% tasks
    active_count = len(active_tasks)
    active_errors = [t for t in active_tasks if t['pct'] == 100]
    
    if active_count == 0:
        feedback.append("Active log is empty (unexpected).")
    elif len(active_errors) > 0:
        feedback.append(f"Active log still contains {len(active_errors)} completed tasks.")
        score += int(30 * (1 - (len(active_errors) / active_count)))
    else:
        score += 30
        feedback.append(f"Active log contains {active_count} active tasks (Clean).")

    # --- CRITERION 5: Data Conservation (20 pts) ---
    # Total tasks found should match initial total
    found_total = archive_count + active_count
    
    if found_total == expected_total:
        score += 20
        feedback.append(f"Task count conserved ({found_total} tasks).")
    else:
        diff = abs(found_total - expected_total)
        feedback.append(f"Data loss/duplication detected: Started with {expected_total}, ended with {found_total}.")
        score += max(0, 20 - (diff * 5))

    passed = score >= 90
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }