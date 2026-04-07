#!/usr/bin/env python3
import json
import os
import sys
import tempfile
import xml.etree.ElementTree as ET
import datetime

def verify_schedule_recurring_inspections(traj, env_info, task_info):
    """
    Verifies that the agent created a recurring task series for 'Site Safety Walk'
    on Fridays between the specified dates.
    """
    # 1. Setup and Environment Check
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result metadata from export_result.sh
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_meta = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result metadata: {str(e)}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # Basic Checks
    if not result_meta.get("output_exists", False):
        return {"passed": False, "score": 0, "feedback": "Output XML file not found at /home/ga/Projects/safety_schedule.xml"}

    if not result_meta.get("file_created_during_task", False):
        return {"passed": False, "score": 0, "feedback": "Output file exists but was not created/modified during the task session (anti-gaming check failed)."}

    # 2. Parse XML Content
    temp_xml = tempfile.NamedTemporaryFile(delete=False, suffix='.xml')
    try:
        copy_from_env("/home/ga/Projects/safety_schedule.xml", temp_xml.name)
        
        try:
            tree = ET.parse(temp_xml.name)
            root = tree.getroot()
        except ET.ParseError:
            return {"passed": False, "score": 10, "feedback": "Output file is not valid XML."}

    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve output XML: {str(e)}"}
    finally:
        if os.path.exists(temp_xml.name):
            os.unlink(temp_xml.name)

    # Handle XML Namespace (MSPDI usually has one)
    # ProjectLibre exports often use http://schemas.microsoft.com/project
    ns = {}
    if '}' in root.tag:
        ns_url = root.tag.split('}')[0].strip('{')
        ns = {'p': ns_url}
        task_xpath = ".//p:Task"
        name_xpath = "p:Name"
        start_xpath = "p:Start"
    else:
        task_xpath = ".//Task"
        name_xpath = "Name"
        start_xpath = "Start"

    # 3. Analyze Tasks
    inspection_dates = []
    task_name_substring = task_info.get("metadata", {}).get("task_name_substring", "Site Safety Walk")
    
    # Filter dates
    start_filter_str = task_info.get("metadata", {}).get("start_date_filter", "2025-02-01")
    end_filter_str = task_info.get("metadata", {}).get("end_date_filter", "2025-04-01")
    start_filter = datetime.datetime.strptime(start_filter_str, "%Y-%m-%d")
    end_filter = datetime.datetime.strptime(end_filter_str, "%Y-%m-%d")

    found_tasks_count = 0

    for task in root.findall(task_xpath, ns):
        name_elem = task.find(name_xpath, ns)
        start_elem = task.find(start_xpath, ns)
        
        if name_elem is not None and start_elem is not None and name_elem.text:
            if task_name_substring.lower() in name_elem.text.lower():
                found_tasks_count += 1
                try:
                    # Format usually: 2025-02-07T08:00:00
                    dt_str = start_elem.text.split('.')[0] # Remove potential milliseconds
                    dt = datetime.datetime.strptime(dt_str, "%Y-%m-%dT%H:%M:%S")
                    
                    # Only consider tasks within the relevant range (ignores summary container start date if way off)
                    if start_filter <= dt <= end_filter:
                        inspection_dates.append(dt)
                except ValueError:
                    continue

    inspection_dates.sort()
    unique_dates = sorted(list(set([d.date() for d in inspection_dates])))
    
    # 4. Scoring Logic
    score = 10 # Base for valid file
    feedback = []

    # Criterion: Task Series Found
    if len(inspection_dates) > 0:
        score += 20
        feedback.append(f"Found {len(inspection_dates)} '{task_name_substring}' tasks.")
    else:
        feedback.append(f"No tasks found with name containing '{task_name_substring}'.")
        return {"passed": False, "score": score, "feedback": " ".join(feedback)}

    # Criterion: Minimum Count (Evidence of recurrence)
    min_occurrences = task_info.get("metadata", {}).get("min_occurrences", 5)
    if len(unique_dates) >= min_occurrences:
        score += 20
        feedback.append("Sufficient number of task occurrences found.")
    else:
        feedback.append(f"Found only {len(unique_dates)} unique occurrences, expected at least {min_occurrences}. Did you use the recurring task feature?")

    # Criterion: Day of Week (Friday = 4)
    expected_dow = task_info.get("metadata", {}).get("expected_day_of_week", 4) # Friday
    days_map = {0:"Mon", 1:"Tue", 2:"Wed", 3:"Thu", 4:"Fri", 5:"Sat", 6:"Sun"}
    
    correct_days = [d for d in unique_dates if d.weekday() == expected_dow]
    if len(unique_dates) > 0 and len(correct_days) == len(unique_dates):
        score += 25
        feedback.append("All tasks correctly scheduled on Fridays.")
    elif len(correct_days) > len(unique_dates) * 0.8: # Allow slight error (e.g. 1 wrong)
        score += 15
        feedback.append(f"Most tasks are on Fridays ({len(correct_days)}/{len(unique_dates)}).")
    else:
        # Check what day they used
        if len(unique_dates) > 0:
            actual_day = unique_dates[0].weekday()
            feedback.append(f"Tasks appear to be scheduled on {days_map.get(actual_day, 'Unknown')}, expected {days_map.get(expected_dow)}.")

    # Criterion: Weekly Interval (7 days)
    expected_interval = task_info.get("metadata", {}).get("expected_interval_days", 7)
    intervals_correct = 0
    total_intervals = len(unique_dates) - 1
    
    if total_intervals > 0:
        for i in range(total_intervals):
            delta = (unique_dates[i+1] - unique_dates[i]).days
            if delta == expected_interval:
                intervals_correct += 1
        
        if intervals_correct == total_intervals:
            score += 25
            feedback.append("Recurrence interval is exactly weekly.")
        elif intervals_correct >= total_intervals - 1:
            score += 20
            feedback.append("Recurrence interval is mostly weekly.")
        else:
            feedback.append("Recurrence interval is inconsistent or incorrect.")

    passed = score >= 75
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }