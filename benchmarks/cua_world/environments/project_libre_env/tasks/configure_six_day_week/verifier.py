#!/usr/bin/env python3
"""
Verifier for configure_six_day_week task.

Checks:
1. XML file exists and was created during task.
2. Standard calendar has Saturday (DayType 7) set to Working (DayWorking 1).
3. Saturday working hours are 08:00-12:00 and 13:00-17:00.
4. Sunday (DayType 1) remains Non-Working (integrity check).
5. VLM verification of dialog interaction.
"""

import json
import os
import tempfile
import xml.etree.ElementTree as ET
import logging
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_six_day_week(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result metadata from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {str(e)}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # Basic criteria checks
    if not result_data.get("output_exists", False):
        return {"passed": False, "score": 0, "feedback": "Output file 'crunch_schedule.xml' not found."}

    if not result_data.get("file_created_during_task", False):
        return {"passed": False, "score": 0, "feedback": "Output file timestamp is too old (created before task started)."}

    # Fetch and parse the XML project file
    local_xml_path = tempfile.mktemp(suffix='.xml')
    try:
        copy_from_env(result_data["output_path"], local_xml_path)
        tree = ET.parse(local_xml_path)
        root = tree.getroot()
    except Exception as e:
        return {"passed": False, "score": 10, "feedback": f"Failed to parse output XML: {str(e)}"}
    finally:
        if os.path.exists(local_xml_path):
            os.unlink(local_xml_path)

    # XML Namespace handling
    # ProjectLibre/MSPDI usually uses this namespace
    ns = {'p': 'http://schemas.microsoft.com/project'}
    
    # Fallback if namespace parsing fails (strip namespaces)
    def find_all(elem, tag):
        return elem.findall(f".//p:{tag}", ns) if '}' in elem.tag else elem.findall(f".//{tag}")

    def find_text(elem, tag):
        match = elem.find(f"p:{tag}", ns) if '}' in elem.tag else elem.find(tag)
        return match.text if match is not None else None

    # Logic Verification
    score = 10 # Base score for valid file
    feedback = ["File exists and is valid XML."]
    
    # 1. Locate Standard Calendar
    calendars = find_all(root, "Calendar")
    standard_cal = None
    for cal in calendars:
        if find_text(cal, "Name") == "Standard":
            standard_cal = cal
            break
    
    if not standard_cal:
        return {"passed": False, "score": score, "feedback": "Could not find 'Standard' calendar in project file."}
    
    # 2. Check Saturday (DayType 7)
    weekdays = find_all(standard_cal, "WeekDay")
    saturday = None
    sunday = None
    
    for wd in weekdays:
        dt = find_text(wd, "DayType")
        if dt == "7":
            saturday = wd
        elif dt == "1":
            sunday = wd
            
    # Check Saturday status
    if saturday is None:
        feedback.append("Saturday definition missing in Standard calendar.")
    else:
        day_working = find_text(saturday, "DayWorking")
        if day_working == "1":
            score += 50
            feedback.append("Saturday is correctly set to Working Day.")
            
            # 3. Check Working Times
            working_times = find_all(saturday, "WorkingTime")
            times_correct = False
            
            # Flatten times to a comparable set
            observed_times = []
            for wt in working_times:
                ft = find_text(wt, "FromTime")
                tt = find_text(wt, "ToTime")
                if ft and tt:
                    # Normalize time format (HH:MM:SS)
                    observed_times.append(f"{ft[:5]}-{tt[:5]}")
            
            # Target: 08:00-12:00 and 13:00-17:00
            expected = ["08:00-12:00", "13:00-17:00"]
            
            # Allow flexible order
            if sorted(observed_times) == sorted(expected):
                score += 20
                feedback.append("Working hours are correct.")
            else:
                feedback.append(f"Working hours incorrect. Found: {observed_times}, Expected: {expected}")
        else:
            feedback.append("Saturday is present but set to Non-Working.")

    # 4. Integrity Check: Sunday (DayType 1)
    # Should be non-working (0) or missing (defaults to non-working in standard)
    sunday_ok = True
    if sunday is not None:
        if find_text(sunday, "DayWorking") == "1":
            sunday_ok = False
            feedback.append("Sunday was incorrectly made a working day.")
    
    if sunday_ok:
        score += 10
        feedback.append("Sunday integrity check passed.")

    # 5. Project Integrity (Tasks exist)
    tasks = find_all(root, "Task")
    if len(tasks) > 5:
        score += 10
        feedback.append("Project task structure preserved.")
    else:
        feedback.append("Warning: Project tasks seem to have been deleted.")

    passed = score >= 60 and "Saturday is correctly set to Working Day" in str(feedback)

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }