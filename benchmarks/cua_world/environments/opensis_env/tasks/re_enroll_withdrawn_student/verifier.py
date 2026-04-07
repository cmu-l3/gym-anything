#!/usr/bin/env python3
import json
import datetime
import logging
import os

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_re_enrollment(traj, env_info, task_info):
    """
    Verifies that the student was correctly re-enrolled.
    
    Criteria:
    1. Student must have an ACTIVE enrollment record (end_date is None/Null).
    2. The active enrollment must have started TODAY.
    3. The PREVIOUS withdrawal record must still exist (history preservation).
    4. The grade level must be 11.
    5. The enrollment code should be 'Re-Enrollment' (or similar).
    """
    # 1. Load result data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: Copy function missing"}
        
    local_result_path = "task_result.json"
    try:
        copy_from_env("/tmp/task_result.json", local_result_path)
        with open(local_result_path, 'r') as f:
            data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result data: {str(e)}"}
    finally:
        if os.path.exists(local_result_path):
            os.remove(local_result_path)
            
    # Check for extraction errors
    if "error" in data:
        return {"passed": False, "score": 0, "feedback": f"Database Extraction Error: {data['error']}"}
        
    records = data.get("enrollment_records", [])
    task_start_ts = data.get("task_start_ts", 0)
    
    score = 0
    feedback = []
    
    # --- Analysis ---
    
    # Find active record (no end_date or end_date in future)
    active_record = None
    historical_records = []
    
    # Today's date for comparison
    today_str = datetime.date.today().isoformat()
    
    for r in records:
        end_date = r.get("end_date")
        # Check if record is active (end_date is None OR end_date is '0000-00-00' depends on DB config, usually None in python from mysql)
        if end_date is None or end_date == "" or str(end_date).startswith("0000"):
            active_record = r
        else:
            historical_records.append(r)
            
    # CRITERION 1: Student is Active (30 pts)
    if active_record:
        score += 30
        feedback.append("Success: Student has an active enrollment record.")
    else:
        feedback.append("Failure: Student is not currently active (no open enrollment record found).")
        return {"passed": False, "score": score, "feedback": "\n".join(feedback)}

    # CRITERION 2: History Preserved (20 pts)
    # We expect at least 1 historical record (the one created in setup)
    if len(historical_records) >= 1:
        score += 20
        feedback.append("Success: Previous withdrawal history preserved.")
    else:
        feedback.append("Failure: Previous enrollment history seems to be deleted/overwritten.")
        
    # CRITERION 3: Correct Start Date (20 pts)
    # The active record should have start_date == today
    act_start = str(active_record.get("start_date"))
    if act_start == today_str:
        score += 20
        feedback.append(f"Success: Re-enrollment date is correct ({today_str}).")
    else:
        feedback.append(f"Partial Failure: Re-enrollment date is {act_start}, expected {today_str}.")
        
    # CRITERION 4: Grade Level (10 pts)
    # Check target grade (11)
    grade = str(active_record.get("grade_level", ""))
    # Handle "11" or "Grade 11"
    if "11" in grade:
        score += 10
        feedback.append("Success: Grade level is 11.")
    else:
        feedback.append(f"Failure: Grade level is {grade}, expected 11.")

    # CRITERION 5: Enrollment Code (10 pts)
    # Should be "Re-Enrollment" (ID 3 from setup) or contain "Re-Enroll"
    code_title = active_record.get("enroll_code_title", "").lower()
    if "re-enroll" in code_title or "return" in code_title:
        score += 10
        feedback.append(f"Success: Enrollment code is '{code_title}'.")
    else:
        # If they used "New Enrollment" instead, partial credit or fail? 
        # Description explicitly asked for "Re-Enrollment".
        feedback.append(f"Warning: Enrollment code is '{code_title}', expected 'Re-Enrollment'.")
        
    # CRITERION 6: Anti-Gaming / No Data Destruction (10 pts)
    # Check that historical record wasn't modified today?
    # Simplified: Just ensure we have records.
    if len(records) >= 2:
        score += 10
        
    passed = score >= 70 and (active_record is not None)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback)
    }