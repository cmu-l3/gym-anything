#!/usr/bin/env python3
import json
import os
import logging
import tempfile
from datetime import datetime
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_schedule_appointment(traj, env_info, task_info):
    """
    Verifies the schedule_appointment task.
    
    Scoring Criteria:
    1. Appointment Record Exists (25 pts)
    2. Correct Patient (20 pts)
    3. Correct Provider (15 pts)
    4. Correct Date/Time (15 pts)
    5. Correct Visit Type (10 pts)
    6. VLM Workflow Verification (15 pts)
    """
    
    # 1. Setup & Load Data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: Copy function unavailable"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result data: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_log = []
    
    # 2. Database Verification
    
    # Criterion 1: Appointment Exists & Count Increased
    # We check if a record was found AND if the count increased (to ensure it's new)
    appt_found = result.get('appointment_found', False)
    count_increased = result.get('count_increased', False)
    
    if appt_found and count_increased:
        score += 25
        feedback_log.append("✅ New appointment record created in database.")
    elif appt_found:
        score += 15 # Partial credit if found but count didn't increase (maybe edited existing?)
        feedback_log.append("⚠️ Appointment record found, but total count did not increase.")
    else:
        feedback_log.append("❌ No appointment record found for target patient.")
        return {"passed": False, "score": 0, "feedback": " ".join(feedback_log)}

    # Extract Data
    actual = result.get('actual', {})
    expected = result.get('expected', {})
    
    # Criterion 2: Correct Patient (Implicitly checked by query in export, but double check PID)
    if str(actual.get('pid')) == str(expected.get('pid')):
        score += 20
        feedback_log.append("✅ Correct patient selected.")
    else:
        feedback_log.append(f"❌ Incorrect patient. Expected PID {expected.get('pid')}, found {actual.get('pid')}.")

    # Criterion 3: Correct Provider (Dr. Carter is ID 2)
    # The expected provider ID for Dr. Carter is 2 (from setup_nosh.sh)
    if str(actual.get('provider_id')) == "2":
        score += 15
        feedback_log.append("✅ Correct provider assigned.")
    else:
        feedback_log.append(f"❌ Incorrect provider. Expected ID 2 (Dr. Carter), found {actual.get('provider_id')}.")

    # Criterion 4: Correct Date/Time
    # Parse datetimes to check equality or tolerance
    try:
        act_dt = datetime.strptime(actual.get('start_datetime'), "%Y-%m-%d %H:%M:%S")
        exp_dt = datetime.strptime(expected.get('datetime'), "%Y-%m-%d %H:%M:%S")
        
        # Check tolerance (e.g. +/- 5 minutes)
        diff = abs((act_dt - exp_dt).total_seconds())
        if diff <= 300: # 5 minutes
            score += 15
            feedback_log.append("✅ Correct date and time.")
        else:
            score += 5 # Minimal credit if date matches but time is wrong
            feedback_log.append(f"❌ Date/Time mismatch. Expected {exp_dt}, found {act_dt}.")
    except Exception as e:
        feedback_log.append(f"⚠️ Could not parse dates: {e}")

    # Criterion 5: Visit Type
    # Case insensitive check
    act_type = actual.get('visit_type', '').lower()
    exp_type = expected.get('visit_type', '').lower()
    
    if exp_type in act_type:
        score += 10
        feedback_log.append("✅ Correct visit type.")
    else:
        feedback_log.append(f"❌ Incorrect visit type. Expected '{expected.get('visit_type')}', found '{actual.get('visit_type')}'.")

    # 3. VLM Verification (Trajectory)
    # We want to see the agent navigating the schedule, not just the result
    frames = sample_trajectory_frames(traj, n=4)
    final_screen = get_final_screenshot(traj)
    
    vlm_score = 0
    if frames:
        prompt = """
        Analyze these screenshots of an agent using an Electronic Health Record (EHR) system.
        I need to verify if the agent performed the following workflow:
        1. Logged into the system.
        2. Viewed a calendar or scheduling screen.
        3. Opened a 'Add Appointment' or similar modal/form.
        
        Return a JSON object:
        {
            "login_visible": boolean,
            "calendar_visible": boolean,
            "appointment_form_visible": boolean,
            "confidence": "high|medium|low"
        }
        """
        
        try:
            vlm_res = query_vlm(images=frames + [final_screen], prompt=prompt)
            if vlm_res and vlm_res.get('success'):
                data = vlm_res.get('parsed', {})
                if data.get('calendar_visible'):
                    vlm_score += 10
                if data.get('appointment_form_visible'):
                    vlm_score += 5
                
                feedback_log.append(f"VLM Analysis: Calendar={data.get('calendar_visible')}, Form={data.get('appointment_form_visible')}")
        except Exception as e:
            logger.error(f"VLM check failed: {e}")
            # Fallback: if database check was perfect, assume UI interaction was okay
            if score >= 80:
                vlm_score = 15
    
    score += vlm_score
    
    # Cap score
    score = min(100, score)
    passed = score >= 60 and appt_found
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_log)
    }