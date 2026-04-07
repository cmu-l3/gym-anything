#!/usr/bin/env python3
import json
import os
import tempfile
import xml.etree.ElementTree as ET
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_assign_vendor_calendar(traj, env_info, task_info):
    """
    Verify that the agent created the 'SecuriCorp Schedule' calendar
    with correct working days (Tue, Thu only) and assigned it to the 'Security Audit' task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_calendar_name = metadata.get('calendar_name', 'SecuriCorp Schedule')
    target_task_name = metadata.get('target_task_name', 'Security Audit')
    
    # DayType mapping in MSPDI: 1=Sun, 2=Mon, 3=Tue, 4=Wed, 5=Thu, 6=Fri, 7=Sat
    # Expected: Tue(3) and Thu(5) are working (1), others are non-working (0)
    expected_working_days = {3, 5} 
    
    score = 0
    feedback = []
    
    # 1. Load result JSON from export_result.sh
    try:
        with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as f:
            copy_from_env("/tmp/task_result.json", f.name)
            with open(f.name) as jf:
                result_data = json.load(jf)
            os.unlink(f.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {str(e)}"}

    if not result_data.get("output_exists", False):
        return {"passed": False, "score": 0, "feedback": "Output XML file not found."}

    if not result_data.get("file_created_during_task", False):
        feedback.append("Warning: Output file timestamp indicates it wasn't saved during this session.")
        # We continue checking but penalty might apply or fail anti-gaming check
        return {"passed": False, "score": 0, "feedback": "Anti-gaming: Output file not modified during task."}

    # 2. Parse the XML Output
    try:
        with tempfile.NamedTemporaryFile(suffix=".xml", delete=False) as f:
            copy_from_env(result_data["output_path"], f.name)
            tree = ET.parse(f.name)
            root = tree.getroot()
            os.unlink(f.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to parse output XML: {str(e)}"}

    # Handle Namespace
    # MSPDI often has a default namespace like xmlns="http://schemas.microsoft.com/project"
    # We strip namespaces for easier parsing or register it.
    # Simple strategy: iterate elements and ignore namespace in tag matching
    
    def find_all_tags(parent, tag_name):
        return [child for child in parent if child.tag.endswith(tag_name)]

    def find_tag_text(parent, tag_name):
        for child in parent:
            if child.tag.endswith(tag_name):
                return child.text
        return None

    # Step A: Verify File Validity (10 pts)
    score += 10
    feedback.append("Valid XML file produced.")

    # Step B: Find and Verify Calendar (20 pts for existence, 30 pts for correctness)
    calendars_root = None
    for child in root:
        if child.tag.endswith("Calendars"):
            calendars_root = child
            break
            
    target_cal_uid = None
    cal_correct = False
    
    if calendars_root is not None:
        calendars = find_all_tags(calendars_root, "Calendar")
        for cal in calendars:
            name = find_tag_text(cal, "Name")
            if name == expected_calendar_name:
                score += 20
                feedback.append(f"Calendar '{expected_calendar_name}' found.")
                target_cal_uid = find_tag_text(cal, "UID")
                
                # Verify Working Days (30 pts)
                # We need to check WeekDays elements
                # Logic: Check if Mon(2), Wed(4), Fri(6) are explicitly set to DayWorking=0
                # OR if the calendar only lists Tue(3)/Thu(5) as DayWorking=1
                # MSPDI is verbose. We check the exceptions defined in WeekDays.
                
                weekdays_root = None
                for child in cal:
                    if child.tag.endswith("WeekDays"):
                        weekdays_root = child
                        break
                
                if weekdays_root:
                    weekdays = find_all_tags(weekdays_root, "WeekDay")
                    
                    # Store DayWorking status: DayType -> bool
                    # Default in standard calendars is usually Mon-Fri working.
                    # We look for explicit configuration.
                    day_config = {}
                    
                    for wd in weekdays:
                        dt = find_tag_text(wd, "DayType")
                        dw = find_tag_text(wd, "DayWorking")
                        if dt and dw:
                            day_config[int(dt)] = (dw == "1")

                    # Check Logic:
                    # Tue(3) and Thu(5) must be WORKING (1)
                    # Mon(2), Wed(4), Fri(6) must be NON-WORKING (0)
                    
                    # Note: If not explicitly present, it might inherit parent calendar settings.
                    # However, a newly created calendar usually dumps its overrides.
                    # We give points if the specific constraints are met in the definition.
                    
                    tue_ok = day_config.get(3, False) == True
                    thu_ok = day_config.get(5, False) == True
                    mon_off = day_config.get(2, True) == False
                    wed_off = day_config.get(4, True) == False
                    fri_off = day_config.get(6, True) == False
                    
                    if tue_ok and thu_ok and mon_off and wed_off and fri_off:
                        score += 30
                        cal_correct = True
                        feedback.append("Calendar working days configured correctly (Tue/Thu only).")
                    else:
                        feedback.append(f"Calendar found but days incorrect. Config: {day_config}")
                break

    if target_cal_uid is None:
        feedback.append(f"Calendar '{expected_calendar_name}' NOT found in XML.")

    # Step C: Verify Task Assignment (40 pts)
    # Task "Security Audit" should have CalendarUID = target_cal_uid
    tasks_root = None
    for child in root:
        if child.tag.endswith("Tasks"):
            tasks_root = child
            break
    
    task_assigned = False
    if tasks_root is not None and target_cal_uid:
        tasks = find_all_tags(tasks_root, "Task")
        for task in tasks:
            name = find_tag_text(task, "Name")
            if name == target_task_name:
                cal_uid = find_tag_text(task, "CalendarUID")
                if cal_uid == target_cal_uid:
                    score += 40
                    task_assigned = True
                    feedback.append(f"Task '{target_task_name}' is correctly assigned to the new calendar.")
                else:
                    feedback.append(f"Task '{target_task_name}' found, but CalendarUID does not match (Found: {cal_uid}, Expected: {target_cal_uid}).")
                break
    elif not target_cal_uid:
        feedback.append("Cannot verify task assignment because calendar was not found.")

    # VLM Verification (Bonus/Confirmation)
    # Check if they opened the "Change Working Time" or "Task Information" dialogs
    frames = sample_trajectory_frames(traj, n=4)
    final_shot = get_final_screenshot(traj)
    
    vlm_score = 0
    if frames:
        prompt = """
        I am verifying a ProjectLibre task. Look at these screenshots.
        Did the user:
        1. Open a dialog titled "Change Working Time" or similar (calendar icon)?
        2. Open a "Task Information" dialog (with tabs like General, Predecessors, Advanced)?
        3. Is there a "Calendar" dropdown visible in the Task Information dialog?
        
        Answer with JSON: {"opened_calendar_dialog": bool, "opened_task_info": bool}
        """
        try:
            vlm_res = query_vlm(images=frames + [final_shot], prompt=prompt)
            parsed = vlm_res.get('parsed', {})
            if parsed.get('opened_calendar_dialog') or parsed.get('opened_task_info'):
                # Add a small buffer to score if they missed exact XML syntax but tried UI correctly
                # But strict requirements say 70 pts pass.
                feedback.append("VLM confirms UI interaction with Calendar/Task dialogs.")
        except Exception:
            pass

    passed = (score >= 70) and cal_correct and task_assigned

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }