#!/usr/bin/env python3
"""
Verifier for schedule_new_hire_onboarding task.
Checks if 3 specific events were created with correct details.
"""

import json
import os
import logging
import tempfile
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_odoo_datetime(dt_str):
    """Parses Odoo datetime string 'YYYY-MM-DD HH:MM:SS'."""
    return datetime.strptime(dt_str, "%Y-%m-%d %H:%M:%S")

def verify_schedule_new_hire_onboarding(traj, env_info, task_info):
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
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    if "error" in result:
        return {"passed": False, "score": 0, "feedback": f"Export error: {result['error']}"}

    events = result.get("found_events", [])
    target_date_str = result.get("target_date_str", "")
    
    feedback_parts = []
    score = 0
    
    # Define expected events criteria
    # We look for best matches for each required event
    
    # Event 1: IT Setup
    # Criteria: Name~"IT Setup", Time=09:00, Loc="IT Helpdesk", Attendee="David Chen"
    it_setup = find_best_match(events, ["IT Setup", "IT"], target_date_str, 9, "IT Helpdesk", "David Chen")
    
    # Event 2: HR Benefits
    # Criteria: Name~"HR Benefits", Time=10:00, Loc="HR Office", Attendee="Grace Patel"
    hr_benefits = find_best_match(events, ["HR Benefits", "Benefits"], target_date_str, 10, "HR Office", "Grace Patel")
    
    # Event 3: Welcome Lunch
    # Criteria: Name~"Welcome Lunch", Time=12:00, Loc="Cafeteria", Attendee="Alice Johnson", Duration=1.5h
    lunch = find_best_match(events, ["Welcome Lunch", "Lunch"], target_date_str, 12, "Cafeteria", "Alice Johnson")
    
    # Score IT Setup (30 pts max)
    score += score_event(it_setup, "IT Setup", feedback_parts)
    
    # Score HR Benefits (30 pts max)
    score += score_event(hr_benefits, "HR Benefits", feedback_parts)
    
    # Score Lunch (35 pts max) - Lunch is slightly weighted more for duration check
    lunch_score = score_event(lunch, "Welcome Lunch", feedback_parts)
    if lunch and lunch_score > 0:
        # Check duration for lunch
        start = parse_odoo_datetime(lunch['start'])
        stop = parse_odoo_datetime(lunch['stop'])
        duration_minutes = (stop - start).total_seconds() / 60
        if 85 <= duration_minutes <= 95: # 90 mins +/- 5
            score += 5
            feedback_parts.append("Welcome Lunch duration correct (90m).")
        else:
            feedback_parts.append(f"Welcome Lunch duration incorrect ({duration_minutes}m).")
    score += lunch_score

    # Anti-gaming check (5 pts)
    # If we found events, they are already filtered by timestamp in export_result.sh, 
    # but we give points for actually finding something created during task
    if len(events) >= 3:
        score += 5
        feedback_parts.append("Anti-gaming: All events created during task window.")
    elif len(events) > 0:
        score += 2
        feedback_parts.append("Anti-gaming: Some events created during task window.")

    passed = score >= 85
    
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts)
    }

def find_best_match(events, name_keywords, target_date_str, target_hour, target_loc_keyword, target_attendee):
    """Finds the event that matches criteria best."""
    candidates = []
    for e in events:
        # Check name
        name_match = any(k.lower() in e['name'].lower() for k in name_keywords)
        if not name_match:
            continue
            
        candidates.append(e)
    
    # If multiple candidates, could filter further, but usually one per task execution
    return candidates[0] if candidates else None

def score_event(event, label, feedback):
    """Scores a single event based on correctness of fields."""
    if not event:
        feedback.append(f"{label}: Not found.")
        return 0
    
    pts = 0
    msgs = []
    
    # Base existence (10 pts)
    pts += 10
    
    # Check Date (10 pts)
    # event['start'] is "YYYY-MM-DD HH:MM:SS"
    event_date = event['start'].split(' ')[0]
    # Target date logic is handled in finding, but let's verify exactness if passed
    # In export script we just calculate target_date_str for reference, 
    # finding logic didn't strictly filter by date, so we check here.
    # Note: verifier finds target_date_str from result json
    
    # Getting target date from the event start string itself to compare vs expected
    # But wait, 'target_date_str' passed to this func is what we expect.
    if event['start'].startswith(event.get('target_date_expected', '')[:10]): 
        # The result json doesn't inject target_date_expected into event, 
        # we need to compare event_date with the target_date_str from result root
        pass 

    # Since find_best_match didn't strictly filter by date, let's check it now
    # Accessing target_date_str from outer scope via logic or passed args? 
    # The 'find_best_match' signature didn't use target_date_str for filtering, my bad.
    # Let's assume the verifier passes the correct string.
    
    # Re-checking logic:
    # 1. Date Check
    # 2. Time Check
    # 3. Location Check
    # 4. Attendee Check
    
    # Time check (Hour) - 5 pts
    # Odoo stores UTC. The prompt implies local time input (e.g. 9:00).
    # If Odoo server is UTC, and user puts 9:00 in UI, DB has 09:00 if user TZ is UTC.
    # We assume standard dev config (UTC).
    event_dt = parse_odoo_datetime(event['start'])
    if event_dt.hour == event.get('target_hour_expected', event_dt.hour): 
        # We need to know what the target hour was. 
        # Refactoring: score_event needs expected values.
        # I'll rely on the caller to handle specific checks or hardcode simple heuristics here.
        pass

    # Simplified scoring for this implementation block:
    # I will inline the specific checks in the main function loop instead of generic helper
    # to avoid scope confusion.
    return 0

# REDEFINING score_event to be simpler and used correctly
def score_event_inline(event, label, expected_hour, expected_loc_fragment, expected_attendee, target_date_str):
    if not event:
        return 0, [f"{label}: Not found"]
    
    s = 10 # Found matching name
    f = [f"{label}: Found"]
    
    # Check Date
    event_date = event['start'].split(' ')[0]
    if event_date == target_date_str:
        s += 5
    else:
        f.append(f"Wrong Date ({event_date})")

    # Check Time
    event_dt = parse_odoo_datetime(event['start'])
    if event_dt.hour == expected_hour:
        s += 5
    else:
        f.append(f"Wrong Time ({event_dt.hour}:00)")

    # Check Location
    if expected_loc_fragment.lower() in (event['location'] or '').lower():
        s += 5
    else:
        f.append(f"Wrong Loc ({event['location']})")

    # Check Attendee
    attendees = [n.lower() for n in event.get('attendee_names', [])]
    if any(expected_attendee.lower() in n for n in attendees):
        s += 5
    else:
        f.append(f"Missing Attendee {expected_attendee}")

    return s, f

# PATCHING main function to use the inline scorer
def verify_schedule_new_hire_onboarding(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

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

    if "error" in result:
        return {"passed": False, "score": 0, "feedback": f"Export error: {result['error']}"}

    events = result.get("found_events", [])
    target_date_str = result.get("target_date_str", "")
    
    feedback_parts = []
    score = 0
    
    # Find candidates
    it_setup = find_best_match(events, ["IT Setup", "IT"], target_date_str, 9, "IT Helpdesk", "David Chen")
    hr_benefits = find_best_match(events, ["HR Benefits", "Benefits"], target_date_str, 10, "HR Office", "Grace Patel")
    lunch = find_best_match(events, ["Welcome Lunch", "Lunch"], target_date_str, 12, "Cafeteria", "Alice Johnson")
    
    # Score
    s1, f1 = score_event_inline(it_setup, "IT Setup", 9, "Helpdesk", "David Chen", target_date_str)
    score += s1
    feedback_parts.extend(f1)
    
    s2, f2 = score_event_inline(hr_benefits, "HR Benefits", 10, "HR", "Grace Patel", target_date_str)
    score += s2
    feedback_parts.extend(f2)
    
    s3, f3 = score_event_inline(lunch, "Welcome Lunch", 12, "Cafeteria", "Alice Johnson", target_date_str)
    score += s3
    feedback_parts.extend(f3)
    
    # Duration check for Lunch
    if lunch:
        start = parse_odoo_datetime(lunch['start'])
        stop = parse_odoo_datetime(lunch['stop'])
        duration_minutes = (stop - start).total_seconds() / 60
        if 85 <= duration_minutes <= 95:
            score += 5
            feedback_parts.append("Lunch duration correct")
        else:
            feedback_parts.append(f"Lunch duration wrong ({int(duration_minutes)}m)")

    # Anti-gaming
    if len(events) >= 3:
        score += 5
    elif len(events) > 0:
        score += 2
        
    passed = score >= 85
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts)
    }