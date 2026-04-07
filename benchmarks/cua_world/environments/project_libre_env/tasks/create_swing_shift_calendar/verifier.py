#!/usr/bin/env python3
import json
import os
import tempfile
import xml.etree.ElementTree as ET
from datetime import datetime

def verify_create_swing_shift_calendar(traj, env_info, task_info):
    """
    Verifies the creation of a 'Swing Shift' calendar and its assignment to a resource.
    
    Scoring Criteria:
    1. File Validity (10 pts): Output XML exists and is valid.
    2. Calendar Created (20 pts): 'Swing Shift' calendar exists in XML.
    3. Correct Hours (40 pts): 14:00-22:00 for Mon-Fri.
    4. Resource Assigned (30 pts): 'Carol Williams' assigned to this calendar.
    """
    
    # 1. Setup & Read Result JSON
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env missing"}

    score = 0
    feedback = []
    
    # Load basic execution stats
    temp_result_json = tempfile.NamedTemporaryFile(delete=False).name
    try:
        copy_from_env("/tmp/task_result.json", temp_result_json)
        with open(temp_result_json) as f:
            result_stats = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task stats: {str(e)}"}
    finally:
        if os.path.exists(temp_result_json):
            os.unlink(temp_result_json)

    if not result_stats.get("output_exists"):
        return {"passed": False, "score": 0, "feedback": "Output file not found. Did you save the project?"}

    if not result_stats.get("file_created_during_task"):
        return {"passed": False, "score": 0, "feedback": "Output file timestamp is too old. Please save the file again."}

    score += 10 # File exists and is recent
    feedback.append("Output file created successfully.")

    # 2. Parse XML Content
    metadata = task_info.get("metadata", {})
    output_path = result_stats.get("output_path", "/home/ga/Projects/swing_shift_project.xml")
    
    temp_xml = tempfile.NamedTemporaryFile(delete=False).name
    try:
        copy_from_env(output_path, temp_xml)
        tree = ET.parse(temp_xml)
        root = tree.getroot()
    except ET.ParseError:
        return {"passed": False, "score": score, "feedback": "Output file is not valid XML."}
    except Exception as e:
        return {"passed": False, "score": score, "feedback": f"Failed to retrieve XML: {str(e)}"}
    finally:
        if os.path.exists(temp_xml):
            os.unlink(temp_xml)

    # MSPDI Namespace
    ns = {'p': 'http://schemas.microsoft.com/project'}
    
    # 3. Verify Calendar Creation
    calendar_name = metadata.get("calendar_name", "Swing Shift")
    target_cal_uid = None
    
    calendars = root.findall(".//p:Calendar", ns)
    for cal in calendars:
        name_elem = cal.find("p:Name", ns)
        if name_elem is not None and name_elem.text == calendar_name:
            target_cal_uid = cal.find("p:UID", ns).text
            target_cal_elem = cal
            break
            
    if target_cal_uid:
        score += 20
        feedback.append(f"Calendar '{calendar_name}' found.")
    else:
        return {"passed": False, "score": score, "feedback": f"Calendar named '{calendar_name}' not found in project."}

    # 4. Verify Working Hours (Mon-Fri)
    # DayType: 1=Sun, 2=Mon, ..., 7=Sat
    # We expect Mon(2) - Fri(6) to have WorkingTime 14:00-22:00
    expected_days = [2, 3, 4, 5, 6]
    working_hours_correct = True
    
    weekdays = target_cal_elem.findall("p:WeekDays/p:WeekDay", ns)
    
    # Create a map for easier checking
    day_map = {}
    for wd in weekdays:
        dt = int(wd.find("p:DayType", ns).text)
        day_map[dt] = wd

    for day in expected_days:
        if day not in day_map:
            # If a day isn't explicitly defined in MSPDI, it might inherit. 
            # However, for a NEW Base Calendar with custom hours, it usually lists them.
            # If missing, it implies default (8-5), which is wrong for Swing Shift.
            working_hours_correct = False
            feedback.append(f"Day Type {day} not defined in calendar.")
            break
            
        wd_elem = day_map[day]
        day_working = wd_elem.find("p:DayWorking", ns)
        
        if day_working is None or day_working.text != "1":
            working_hours_correct = False
            feedback.append(f"Day Type {day} is not set as working day.")
            break
            
        # Check WorkingTimes
        # Should have exactly ONE range 14:00-22:00
        wts = wd_elem.findall("p:WorkingTimes/p:WorkingTime", ns)
        if len(wts) != 1:
            working_hours_correct = False
            feedback.append(f"Day Type {day} has {len(wts)} working shifts (expected 1).")
            break
            
        wt = wts[0]
        # MSPDI times are usually HH:MM:SS
        from_time = wt.find("p:FromTime", ns).text # Expect 14:00:00
        to_time = wt.find("p:ToTime", ns).text     # Expect 22:00:00
        
        # Simple string containment check to handle potential seconds variations
        if "14:00" not in from_time or "22:00" not in to_time:
             working_hours_correct = False
             feedback.append(f"Day Type {day} hours incorrect. Found {from_time}-{to_time}, expected 14:00-22:00.")
             break

    if working_hours_correct:
        score += 40
        feedback.append("Working hours are correct (14:00-22:00 M-F).")

    # 5. Verify Resource Assignment
    # Check if Carol Williams (UID usually 3, but find by name to be safe) is assigned this calendar
    resource_name_target = metadata.get("resource_name", "Carol Williams")
    resource_assigned = False
    
    resources = root.findall(".//p:Resource", ns)
    for res in resources:
        r_name = res.find("p:Name", ns)
        if r_name is not None and resource_name_target in r_name.text:
            cal_uid_elem = res.find("p:CalendarUID", ns)
            if cal_uid_elem is not None and cal_uid_elem.text == target_cal_uid:
                resource_assigned = True
            break
    
    if resource_assigned:
        score += 30
        feedback.append(f"Resource '{resource_name_target}' correctly assigned to '{calendar_name}'.")
    else:
        feedback.append(f"Resource '{resource_name_target}' is NOT assigned to the new calendar.")

    # Final Calculation
    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }