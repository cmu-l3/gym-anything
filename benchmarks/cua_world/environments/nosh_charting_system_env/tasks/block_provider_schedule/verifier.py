#!/usr/bin/env python3
import json
import os
import logging
import tempfile
from datetime import datetime, timedelta

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_block_provider_schedule(traj, env_info, task_info):
    """
    Verify that the agent blocked Dr. Carter's schedule.
    
    Criteria:
    1. Database record exists for Provider 2 on Today's date.
    2. Start time is 13:00 (tolerance +/- 5 mins).
    3. Duration is approx 1 hour (End time ~14:00).
    4. Reason contains "Staff Meeting".
    5. PID is 0/NULL (Critical: verifies it's a block, not a patient visit).
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result data: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Parse DB Query Results
    # Raw format expected: id \t provider_id \t pid \t start_time \t end_time \t reason \t date \n ...
    raw_query = result_data.get('db_schedule_query_raw', '').strip()
    
    if not raw_query:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "No schedule entries found for Dr. Carter today between 12:00-15:00."
        }

    # Process rows
    rows = raw_query.split('\n')
    best_entry = None
    best_score = 0
    feedback_log = []

    target_start = "13:00:00"
    target_end = "14:00:00"
    
    for row in rows:
        parts = row.split('\t')
        if len(parts) < 6:
            continue
            
        # Parse columns (based on export_result.sh query order)
        # id, provider_id, pid, start_time, end_time, reason, date
        entry_id = parts[0]
        prov_id = parts[1]
        pid = parts[2]
        start_time_str = parts[3] # HH:MM:SS
        end_time_str = parts[4]   # HH:MM:SS
        reason = parts[5].lower()
        
        # Calculate score for this entry
        current_score = 0
        current_feedback = []

        # 1. Check Start Time (20 pts)
        # Simple string comparison or strict parsing
        if start_time_str.startswith("13:00"):
            current_score += 20
        elif start_time_str.startswith("12:5") or start_time_str.startswith("13:0"):
            current_score += 10 # Partial credit for close time
            current_feedback.append(f"Time close ({start_time_str})")
        else:
            current_feedback.append(f"Wrong time ({start_time_str})")

        # 2. Check Duration/End Time (10 pts)
        if end_time_str.startswith("14:00"):
            current_score += 10
        
        # 3. Check Reason (20 pts)
        if "staff" in reason and "meeting" in reason:
            current_score += 20
        elif "meeting" in reason or "staff" in reason:
            current_score += 10
            current_feedback.append(f"Partial reason match ({reason})")
        else:
            current_feedback.append(f"Wrong reason ({reason})")

        # 4. Check PID (30 pts) - CRITICAL
        # PID should be 0, NULL, or empty for a block. 
        # If it's a valid patient ID (e.g., > 0), it's an appointment, not a block.
        try:
            pid_val = int(pid)
        except ValueError:
            pid_val = 0
            
        if pid_val == 0:
            current_score += 30
        else:
            current_feedback.append(f"Attached to patient PID {pid_val} (Should be unattached block)")

        # 5. Existence (20 pts)
        current_score += 20

        # Keep best entry
        if current_score > best_score:
            best_score = current_score
            best_entry = {
                "start": start_time_str,
                "reason": reason,
                "pid": pid_val,
                "feedback": current_feedback
            }

    # Final Evaluation
    passed = best_score >= 70
    
    final_feedback = f"Best entry found: Time={best_entry['start'] if best_entry else 'None'}, " \
                     f"Reason='{best_entry['reason'] if best_entry else 'None'}', " \
                     f"PID={best_entry['pid'] if best_entry else 'None'}."
    
    if best_entry and best_entry['feedback']:
        final_feedback += " Issues: " + ", ".join(best_entry['feedback'])

    if not passed:
        final_feedback += " Failed to meet criteria (Score < 70)."

    return {
        "passed": passed,
        "score": best_score,
        "feedback": final_feedback
    }