#!/usr/bin/env python3
"""
Verifier for biometric_failure_attendance_recovery task.

Checks that the agent successfully created manual attendance records for 
EMP018, EMP019, and EMP020 on March 10, 2026, with the correct times.
Applies VLM to verify trajectory frames for UI interaction to prevent DB-injection gaming.
"""

import os
import json
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def row_matches(row, uid, date_str, time_in, time_out, time_out_alt):
    """
    Check if a TSV database row contains the target UID, date, and times.
    Highly robust to schema variations.
    """
    row_lower = row.lower()
    
    # Must contain the user ID
    if str(uid) not in row.split('\t'):
        return False
        
    # Must contain the target date
    date_variants = [date_str, "mar 10", "03/10/2026", "2026-03-10"]
    if not any(d in row_lower for d in date_variants):
        return False
        
    # Check IN time
    in_variants = [time_in, f"{time_in}:00", f"0{time_in}"]
    in_match = any(i_var in row_lower for i_var in in_variants)
    
    # Check OUT time (could be 24h or AM/PM depending on internal storage)
    out_variants = [time_out, f"{time_out}:00", f"0{time_out}"]
    if time_out_alt:
        out_variants.extend([time_out_alt, f"{time_out_alt}:00", f"0{time_out_alt}"])
        
    out_match = any(o_var in row_lower for o_var in out_variants)
    
    return in_match and out_match

def date_matches(row, uid, date_str):
    """Check if the row has the user ID and the target date (even if times are wrong)."""
    row_lower = row.lower()
    if str(uid) not in row.split('\t'):
        return False
    date_variants = [date_str, "mar 10", "03/10/2026", "2026-03-10"]
    return any(d in row_lower for d in date_variants)

def build_vlm_prompt():
    return """You are verifying an HR administrative task where the agent enters manual attendance times for three employees into the Sentrifugo Time & Attendance system.
Look at these trajectory screenshots. 
Do you see visual evidence of the agent interacting with the Time/Attendance UI, selecting employees from a dropdown/list, or entering time values (e.g., 05:55, 14:00) into a form?

Respond ONLY with a JSON object in this format:
{
    "ui_interaction_visible": true or false,
    "reasoning": "brief explanation"
}
"""

def verify_attendance_recovery(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    pass_threshold = metadata.get('pass_threshold', 65)
    expected_date = metadata.get('expected_date', '2026-03-10')
    
    # Load task results
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    uids = result.get('uids', {})
    db_rows = result.get('db_rows', [])
    
    score = 0
    feedback_parts = []
    
    employees = [
        ('EMP018', metadata.get('emp018'), 10, 20),
        ('EMP019', metadata.get('emp019'), 10, 25), # Extra points for policy application
        ('EMP020', metadata.get('emp020'), 10, 20)
    ]
    
    for empid, emp_meta, pts_exist, pts_time in employees:
        uid = uids.get(empid)
        if not uid:
            feedback_parts.append(f"{empid}: User not found in database (0/{pts_exist+pts_time})")
            continue
            
        time_in = emp_meta.get('in')
        time_out = emp_meta.get('out')
        time_out_alt = emp_meta.get('out_alt')
        
        found_date = False
        found_exact = False
        
        for row in db_rows:
            if row_matches(row, uid, expected_date, time_in, time_out, time_out_alt):
                found_exact = True
                break
            elif date_matches(row, uid, expected_date):
                found_date = True
                
        if found_exact:
            earned = pts_exist + pts_time
            score += earned
            if empid == 'EMP019':
                feedback_parts.append(f"{empid}: Exact match! HR policy successfully applied ({earned}/{earned})")
            else:
                feedback_parts.append(f"{empid}: Exact match ({earned}/{earned})")
        elif found_date:
            score += pts_exist
            feedback_parts.append(f"{empid}: Record exists for {expected_date} but times are missing or incorrect ({pts_exist}/{pts_exist+pts_time})")
        else:
            feedback_parts.append(f"{empid}: No attendance record found for {expected_date} (0/{pts_exist+pts_time})")

    # VLM Verification for UI interaction (anti-gaming)
    query_vlm = env_info.get('query_vlm')
    if query_vlm:
        try:
            from gym_anything.vlm import sample_trajectory_frames
            frames = sample_trajectory_frames(traj, n=4)
            if frames:
                vlm_res = query_vlm(prompt=build_vlm_prompt(), images=frames)
                parsed = vlm_res.get('parsed', {})
                if parsed.get('ui_interaction_visible', False):
                    score += 5
                    feedback_parts.append("VLM: UI interaction confirmed (+5 pts)")
                else:
                    feedback_parts.append("VLM: No clear UI interaction seen (0/5 pts)")
            else:
                feedback_parts.append("VLM: No trajectory frames available")
        except Exception as e:
            logger.warning(f"VLM verification failed: {e}")
            feedback_parts.append("VLM: Verification error")

    passed = score >= pass_threshold
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }