#!/usr/bin/env python3
"""
Verifier for replicate_training_schedule task.
"""

import json
import logging
import os
import tempfile
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_odoo_date(date_str):
    """Parse Odoo datetime string (YYYY-MM-DD HH:MM:SS)"""
    if not date_str:
        return None
    try:
        return datetime.strptime(date_str, "%Y-%m-%d %H:%M:%S")
    except ValueError:
        return None

def verify_replicate_training_schedule(traj, env_info, task_info):
    """
    Verify that the 3 Monday events were duplicated to Tuesday.
    
    Criteria:
    1. Total 6 "Security Workshop" events (3 original + 3 new).
    2. 3 events on Target Monday.
    3. 3 events on Target Tuesday.
    4. Tuesday events must match Monday events in start time (HH:MM), duration, name, location.
    5. Tuesday events must be newly created (create_date > task_start).
    6. No recurrence used.
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

    events = result.get('events', [])
    target_monday_str = result.get('target_monday')
    target_tuesday_str = result.get('target_tuesday')
    task_start_ts = result.get('task_start_ts', 0)

    if not events:
        return {"passed": False, "score": 0, "feedback": "No 'Security Workshop' events found."}

    # buckets for analysis
    monday_events = []
    tuesday_events = []
    other_events = []
    
    score = 0
    feedback = []

    # 1. Analyze events
    for evt in events:
        start_dt = parse_odoo_date(evt.get('start'))
        if not start_dt:
            continue
            
        date_str = start_dt.strftime("%Y-%m-%d")
        
        if date_str == target_monday_str:
            monday_events.append(evt)
        elif date_str == target_tuesday_str:
            tuesday_events.append(evt)
        else:
            other_events.append(evt)

    # Criterion: Event Counts
    if len(monday_events) == 3:
        score += 15
        feedback.append("Original Monday events preserved.")
    else:
        feedback.append(f"Expected 3 Monday events, found {len(monday_events)}.")

    if len(tuesday_events) == 3:
        score += 30
        feedback.append("3 events created on Tuesday.")
    else:
        feedback.append(f"Expected 3 Tuesday events, found {len(tuesday_events)}.")

    # Criterion: New Creation (Anti-gaming)
    new_events_valid = True
    for evt in tuesday_events:
        c_date = parse_odoo_date(evt.get('create_date'))
        if c_date and c_date.timestamp() < task_start_ts:
            new_events_valid = False
            feedback.append(f"Event {evt.get('name')} on Tuesday seems to pre-date the task.")
    
    if len(tuesday_events) > 0 and new_events_valid:
        score += 10
        feedback.append("Tuesday events were created during the task.")

    # Criterion: Matching Details
    matches_found = 0
    recurrence_used = False
    
    # We expect 3 distinct time slots: 09:00, 11:00, 13:30
    # Map Monday events by time
    mon_map = {} # "HH:MM" -> event
    for evt in monday_events:
        dt = parse_odoo_date(evt.get('start'))
        time_key = dt.strftime("%H:%M")
        mon_map[time_key] = evt

    for evt in tuesday_events:
        dt = parse_odoo_date(evt.get('start'))
        time_key = dt.strftime("%H:%M")
        
        # Check recurrence
        if evt.get('recurrency'):
            recurrence_used = True
        
        if time_key in mon_map:
            match = mon_map[time_key]
            
            # Check Name
            if evt.get('name') == match.get('name'):
                matches_found += 1
            
            # Check Location
            if evt.get('location') != "Training Room B":
                feedback.append(f"Location mismatch for {evt.get('name')}")
            
            # Check Description (loose check: not empty/False)
            if not evt.get('description'):
                feedback.append(f"Description missing for {evt.get('name')}")

    # Scoring matches
    # We want 3 perfect time matches
    if matches_found == 3:
        score += 20
        feedback.append("All Tuesday events match Monday times and names.")
    elif matches_found > 0:
        score += (matches_found * 5)
        feedback.append(f"{matches_found}/3 events match times and names.")

    # Check Location consistency
    loc_correct = sum(1 for e in tuesday_events if e.get('location') == "Training Room B")
    if loc_correct == 3:
        score += 5
        feedback.append("Locations correct.")

    # Check Recurrence constraint
    if not recurrence_used and len(tuesday_events) > 0:
        score += 20
        feedback.append("Events created independently (no recurrence).")
    elif recurrence_used:
        feedback.append("Penalty: Recurrence feature was used (independent records required).")

    # Pass threshold
    passed = (score >= 70) and (len(tuesday_events) == 3)

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }