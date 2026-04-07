#!/usr/bin/env python3
import json
import os
import tempfile
import logging
from datetime import datetime, timedelta

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_schedule_from_contact(traj, env_info, task_info):
    """
    Verifies that the agent:
    1. Created a meeting 'Q2 Performance Debrief with CFO'
    2. Included 'Grace Patel' and 'Frank Rivera'
    3. Set correct Location and Description
    4. Scheduled it for 'Next Thursday' at 14:00
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
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

    # Base scoring
    score = 0
    feedback = []
    
    # 1. Check Event Existence (25 pts)
    if not result.get('event_found'):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Event 'Q2 Performance Debrief with CFO' was not found."
        }
    
    score += 25
    feedback.append("Event created.")
    evt = result['event_data']

    # 2. Check Attendees (20 pts Grace, 15 pts Frank)
    attendees = result.get('attendees_found', [])
    if 'Grace Patel' in attendees:
        score += 20
        feedback.append("Grace Patel added.")
    else:
        feedback.append("Grace Patel MISSING.")

    if 'Frank Rivera' in attendees:
        score += 15
        feedback.append("Frank Rivera added.")
    else:
        feedback.append("Frank Rivera MISSING.")

    # 3. Check Location (15 pts)
    # Location might be False/None if empty, or string
    loc = evt.get('location') or ""
    if 'Executive Boardroom' in loc:
        score += 15
        feedback.append("Location correct.")
    else:
        feedback.append(f"Location incorrect ({loc}).")

    # 4. Check Description (10 pts)
    desc = evt.get('description') or ""
    desc_lower = desc.lower()
    keywords = ["q2", "performance", "retention"]
    if any(k in desc_lower for k in keywords):
        score += 10
        feedback.append("Description contains keywords.")
    else:
        feedback.append("Description missing key context.")

    # 5. Check Time (15 pts)
    # Logic: Start time should be 'Next Thursday' at 14:00 UTC (Odoo stores UTC)
    # OR local time depending on config. Odoo standard is UTC in DB.
    # However, env might be simpler. Let's check weekday and hour.
    try:
        start_str = evt.get('start') # Format: YYYY-MM-DD HH:MM:SS
        if start_str:
            start_dt = datetime.strptime(start_str, '%Y-%m-%d %H:%M:%S')
            
            # Check Weekday (Thursday is 3)
            if start_dt.weekday() == 3:
                score += 10
                feedback.append("Day is Thursday.")
            else:
                feedback.append(f"Wrong day (weekday {start_dt.weekday()}).")

            # Check Hour (14:00)
            # Allow slack for Timezone issues (UTC vs Local). 
            # If user inputs 14:00 local, DB might store 14:00 or adjusted.
            # We accept 12-16 range to be robust.
            if 12 <= start_dt.hour <= 16:
                score += 5
                feedback.append("Time is approx 2 PM.")
            else:
                feedback.append(f"Wrong time ({start_dt.hour}:00).")
    except Exception as e:
        feedback.append(f"Time parsing error: {e}")

    # Anti-gaming: Check creation time
    try:
        task_start = result.get('task_start_ts', 0)
        create_date_str = evt.get('create_date')
        if create_date_str:
            create_dt = datetime.strptime(create_date_str, '%Y-%m-%d %H:%M:%S')
            # Assuming Odoo server time is close to system time
            # Just a sanity check it's not from last year
            if create_dt.year < 2023: 
                score = 0
                feedback = ["Anti-gaming: Event appears old."]
    except:
        pass

    passed = (score >= 60)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }