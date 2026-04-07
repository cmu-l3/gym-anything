#!/usr/bin/env python3
"""Verifier for Create Group Restricted Chat task in Moodle."""

import json
import tempfile
import os
import logging
import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_group_restricted_chat(traj, env_info, task_info):
    """
    Verify the chat activity creation, schedule, and access restrictions.

    Criteria:
    1. Chat activity exists in BIO101 (20 pts)
    2. Created during task (Anti-gaming) (Pass/Fail check)
    3. Schedule set to "Same time every week" (20 pts)
    4. Save past sessions set to 180 days (20 pts)
    5. Next chat time is a Friday at 14:00 (10 pts)
    6. Access restricted to 'Project Team Alpha' (30 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_group_name = metadata.get('group_name', 'Project Team Alpha')
    target_hour = metadata.get('target_hour', 14)
    target_weekday = metadata.get('target_weekday', 4) # Friday is 4
    expected_schedule = metadata.get('expected_schedule_type', 3) # 3 = Weekly

    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/create_group_restricted_chat_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)

        score = 0
        feedback_parts = []
        
        chat_found = result.get('chat_found', False)
        created_during_task = result.get('created_during_task', False)
        
        # Criterion 1: Activity Exists (20 pts)
        if chat_found:
            score += 20
            feedback_parts.append("Chat activity created")
        else:
            return {"passed": False, "score": 0, "feedback": "Chat activity not found"}

        # Anti-gaming check
        if not created_during_task:
            feedback_parts.append("WARNING: Activity appears to pre-date task start")
            # We might still score it but flag it, or penalize. For now, let's penalize heavily.
            score = 0
            return {"passed": False, "score": 0, "feedback": "Activity was not created during the current task session"}

        # Criterion 3: Schedule Type (20 pts)
        # Moodle mdl_chat.schedule: 0=Don't publish, 1=No repeats, 2=Daily, 3=Weekly
        chat_schedule = int(result.get('chat_schedule', 0))
        if chat_schedule == 3:
            score += 20
            feedback_parts.append("Schedule set to Weekly")
        elif chat_schedule == 2:
            score += 5 # Partial for Daily
            feedback_parts.append("Schedule set to Daily (expected Weekly)")
        else:
            feedback_parts.append(f"Schedule incorrect (value: {chat_schedule})")

        # Criterion 4: Keep Days (20 pts)
        keepdays = int(result.get('chat_keepdays', 0))
        if keepdays == 180:
            score += 20
            feedback_parts.append("Save sessions set to 180 days")
        else:
            feedback_parts.append(f"Save sessions incorrect ({keepdays} days)")

        # Criterion 5: Time Check (10 pts)
        # chattime is unix timestamp
        chat_time_ts = int(result.get('chat_time', 0))
        if chat_time_ts > 0:
            dt = datetime.datetime.fromtimestamp(chat_time_ts)
            # Check Weekday (0=Mon, 6=Sun)
            wd = dt.weekday()
            hr = dt.hour
            mn = dt.minute
            
            if wd == target_weekday and hr == target_hour and 0 <= mn <= 5:
                score += 10
                feedback_parts.append("Chat time correct (Friday 14:00)")
            else:
                days = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
                feedback_parts.append(f"Chat time incorrect: {days[wd]} {hr:02d}:{mn:02d} (expected Fri 14:00)")
        else:
            feedback_parts.append("Chat time not set")

        # Criterion 6: Access Restriction (30 pts)
        # Check availability_json for group ID
        availability_raw = result.get('availability_json', '')
        group_id = str(result.get('group_id', ''))
        
        has_restriction = False
        if availability_raw and group_id:
            try:
                avail_data = json.loads(availability_raw)
                # Structure is typically: {"op":"&", "c": [{"type":"group", "id": 123}], ...}
                # Recursively check or just check string presence for robustness against nested logic
                # For strict verification, we should parse 'c' list.
                
                # Simple robust check first
                if '"type":"group"' in availability_raw and f'"id":{group_id}' in availability_raw:
                    # Check if logic is NOT inverted (i.e. not "must NOT belong")
                    # In Moodle availability, standard positive restriction doesn't usually carry 'd' (delete/not) flags easily visible without deep parse.
                    # We assume standard "Must match" selection.
                    has_restriction = True
                
                # Deep check if json parses
                if not has_restriction and 'c' in avail_data:
                    for condition in avail_data['c']:
                        if condition.get('type') == 'group' and str(condition.get('id')) == group_id:
                            has_restriction = True
                            break
            except json.JSONDecodeError:
                pass
        
        if has_restriction:
            score += 30
            feedback_parts.append("Group restriction correctly applied")
        else:
            feedback_parts.append("Group restriction missing or incorrect")

        passed = score >= 70
        
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Error: {str(e)}"}