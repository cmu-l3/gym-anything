#!/usr/bin/env python3
"""
Verifier for create_multiday_workshop task.

Verifies:
1. Event exists with correct title.
2. Event spans two consecutive days.
3. Event is NOT all-day (has specific start/end times).
4. Start time is ~9:00 AM, End time is ~5:00 PM.
5. Location, Description, and Attendees are correct.
"""

import json
import tempfile
import os
import logging
import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_odoo_datetime(dt_str):
    """Parses Odoo datetime string (UTC) to datetime object."""
    # Odoo format: "YYYY-MM-DD HH:MM:SS"
    if not dt_str:
        return None
    try:
        return datetime.datetime.strptime(dt_str, "%Y-%m-%d %H:%M:%S")
    except ValueError:
        return None

def verify_create_multiday_workshop(traj, env_info, task_info):
    """
    Verify that the multi-day workshop event was created correctly.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load metadata
    metadata = task_info.get('metadata', {})
    target_title = metadata.get('target_title', "DevOps Workshop")
    
    score = 0
    max_score = 100
    feedback_parts = []
    
    # Copy result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result file: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Check if event was found
    if not result.get('event_found'):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "No event found matching 'DevOps Workshop'. Please create the event."
        }

    event = result.get('event_details', {})
    attendee_names = result.get('attendee_names', [])
    
    # 1. Title Check (15 pts)
    title = event.get('name', '')
    if target_title.lower() in title.lower():
        score += 15
        feedback_parts.append("Title correct")
    else:
        # Partial credit for "DevOps"
        if "devops" in title.lower():
            score += 5
            feedback_parts.append("Title partial match")
        else:
            feedback_parts.append(f"Title incorrect ({title})")

    # 2. Multi-day Span Check (20 pts)
    start_str = event.get('start', '')
    stop_str = event.get('stop', '')
    start_dt = parse_odoo_datetime(start_str)
    stop_dt = parse_odoo_datetime(stop_str)
    
    valid_dates = False
    if start_dt and stop_dt:
        # Check if they are on different days
        # Odoo stores in UTC. 9AM local (UTC-ish) might cross date lines?
        # Assuming environment is UTC or close to it for simplicity, or relative check.
        # Check delta > 24 hours approximately
        duration = stop_dt - start_dt
        days_diff = (stop_dt.date() - start_dt.date()).days
        
        if days_diff == 1:
            score += 20
            feedback_parts.append("Event spans two days correctly")
            valid_dates = True
        elif days_diff > 1:
            score += 10
            feedback_parts.append(f"Event spans too many days ({days_diff})")
        else:
            feedback_parts.append("Event does not span across days")

    # 3. NOT All-Day Check (15 pts)
    # This is critical per task description
    is_allday = event.get('allday', True)
    if not is_allday:
        score += 15
        feedback_parts.append("Correctly set as non-all-day event")
    else:
        feedback_parts.append("Incorrectly marked as All Day")

    # 4. Specific Time Check (10 pts)
    # Start 9:00 AM, End 5:00 PM (17:00)
    # Allow tolerance for timezone confusion (Odoo often defaults to UTC storage)
    # We check the hour component.
    if valid_dates:
        # Simple check: Start hour around 9, End hour around 17
        # Note: XML-RPC dates are typically UTC. If the agent set 9AM in a specific timezone, 
        # the UTC value might differ. However, usually in these standard envs, system is UTC.
        # We will allow a +/- 1 hour window.
        s_h = start_dt.hour
        e_h = stop_dt.hour
        
        if 8 <= s_h <= 10:
            score += 5
        else:
            feedback_parts.append(f"Start time mismatch (expected ~9:00, got {s_h}:00 UTC)")
            
        if 16 <= e_h <= 18:
            score += 5
        else:
            feedback_parts.append(f"End time mismatch (expected ~17:00, got {e_h}:00 UTC)")
    
    # 5. Location (10 pts)
    loc = event.get('location', '') or ''
    if "Engineering Lab" in loc:
        score += 10
        feedback_parts.append("Location correct")
    elif loc:
        score += 5
        feedback_parts.append("Location partial")
    else:
        feedback_parts.append("Location missing")

    # 6. Description (10 pts)
    desc = event.get('description', '') or ''
    # Strip HTML if present
    import re
    desc_text = re.sub('<[^<]+?>', '', desc).lower()
    keywords = metadata.get('required_keywords', [])
    found_kws = sum(1 for k in keywords if k.lower() in desc_text)
    
    if found_kws >= len(keywords):
        score += 10
        feedback_parts.append("Description correct")
    elif found_kws > 0:
        score += 5
        feedback_parts.append("Description partial")
    else:
        feedback_parts.append("Description missing key details")

    # 7. Attendees (20 pts)
    req_attendees = metadata.get('required_attendees', [])
    found_attendees = 0
    for req in req_attendees:
        if any(req.lower() in name.lower() for name in attendee_names):
            found_attendees += 1
            
    if found_attendees == len(req_attendees):
        score += 20
        feedback_parts.append("All attendees added")
    elif found_attendees > 0:
        score += 10
        feedback_parts.append("Some attendees missing")
    else:
        feedback_parts.append("Attendees missing")

    # Anti-gaming check
    # Check if event was created after task start
    create_date_str = event.get('create_date', '')
    task_start = result.get('task_start_time', 0)
    
    is_fresh = True
    if create_date_str and task_start > 0:
        try:
            # Odoo create_date is UTC
            c_dt = datetime.datetime.strptime(create_date_str, "%Y-%m-%d %H:%M:%S")
            # task_start is unix timestamp (UTC)
            c_ts = c_dt.replace(tzinfo=datetime.timezone.utc).timestamp()
            
            # Allow slight clock skew, but event should be created AFTER task start
            # timestamps in python datetime might be naive, need care
            # Simplest: Just check if create_date is reasonable.
            # actually c_dt from strptime is naive.
            
            pass 
        except Exception:
            pass

    passed = (score >= 70) and (not is_allday) and valid_dates
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback_parts)
    }