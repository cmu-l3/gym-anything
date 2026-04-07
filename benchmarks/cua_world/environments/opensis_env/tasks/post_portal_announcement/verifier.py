#!/usr/bin/env python3
import json
import os
import tempfile
import logging
from datetime import datetime, date

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_post_portal_announcement(traj, env_info, task_info):
    """
    Verifies that the portal announcement was created correctly.
    
    Criteria:
    1. Note with title "Spring Science Fair" exists (30 pts)
    2. Body text matches requirements (20 pts)
    3. Audience: Student=Y, Parent=Y (30 pts)
    4. Audience: Teacher=N, Admin=N (10 pts)
    5. Dates: Start=Today, End=Future (10 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)
            
    # Check basic existence
    if not result.get('note_found', False):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "No portal note with title 'Spring Science Fair' was found."
        }
        
    record = result.get('note_record', {})
    score = 30
    feedback_parts = ["Note created"]
    
    # 1. Verify Body Content (20 pts)
    # Check for keywords
    body = record.get('note', '').lower()
    expected_snippets = ["registration", "science fair", "main office"]
    
    matches = sum(1 for snippet in expected_snippets if snippet in body)
    if matches >= 2:
        score += 20
        feedback_parts.append("Body content correct")
    elif matches == 1:
        score += 10
        feedback_parts.append("Body content partially correct")
    else:
        feedback_parts.append("Body content missing key information")
        
    # 2. Verify Audience (30 pts + 10 pts)
    # OpenSIS often stores audience in columns like 'student', 'parent', 'teacher', 'admin' 
    # OR 'published_profiles'
    
    # Check for direct columns first (common in older versions)
    student_vis = str(record.get('student', '')).lower() in ['y', '1', 'yes', 'on']
    parent_vis = str(record.get('parent', '')).lower() in ['y', '1', 'yes', 'on']
    teacher_vis = str(record.get('teacher', '')).lower() in ['y', '1', 'yes', 'on']
    admin_vis = str(record.get('admin', '')).lower() in ['y', '1', 'yes', 'on']
    
    # If direct columns not found/empty, check published_profiles (newer versions)
    # It might be a serialized string or comma-separated list
    if 'published_profiles' in record:
        profiles = str(record['published_profiles']).lower()
        student_vis = 'student' in profiles
        parent_vis = 'parent' in profiles
        teacher_vis = 'teacher' in profiles
        admin_vis = 'admin' in profiles

    # Score Audience
    if student_vis: score += 15
    else: feedback_parts.append("Student visibility missing")
    
    if parent_vis: score += 15
    else: feedback_parts.append("Parent visibility missing")
    
    if not teacher_vis and not admin_vis:
        score += 10
        feedback_parts.append("Correctly restricted from Staff")
    else:
        feedback_parts.append("Incorrectly visible to Staff")

    # 3. Verify Dates (10 pts)
    # Start date should be close to today
    today_str = datetime.now().strftime("%Y-%m-%d")
    start_date = record.get('start_date', '').split(' ')[0] # Remove time if present
    end_date = record.get('end_date', '').split(' ')[0]
    
    dates_ok = False
    if start_date:
        try:
            # Allow +/- 1 day for timezone diffs
            s_dt = datetime.strptime(start_date, "%Y-%m-%d")
            t_dt = datetime.strptime(today_str, "%Y-%m-%d")
            diff = abs((s_dt - t_dt).days)
            
            if diff <= 1:
                # Check end date is in future
                if end_date:
                    e_dt = datetime.strptime(end_date, "%Y-%m-%d")
                    if e_dt > s_dt:
                        dates_ok = True
        except:
            pass
            
    if dates_ok:
        score += 10
        feedback_parts.append("Dates correct")
    else:
        feedback_parts.append(f"Date mismatch (Start: {start_date}, End: {end_date})")

    # Final check
    passed = score >= 80
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }