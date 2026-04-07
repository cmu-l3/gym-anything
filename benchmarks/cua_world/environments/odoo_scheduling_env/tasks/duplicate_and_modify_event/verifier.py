#!/usr/bin/env python3
"""
Verifier for duplicate_and_modify_event task.

Criteria:
1. "Q3 Financial Review" event exists.
2. Date is 14 days after "Q2 Financial Review" (+/- 2h tolerance).
3. Location is "Board Room".
4. Description contains required keywords.
5. Attendees include originals + Grace Patel.
6. Original Q2 event is preserved (not modified/moved).
7. Anti-gaming: Event count increased.
"""

import json
import os
import logging
import tempfile
from datetime import datetime, timedelta

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_odoo_datetime(dt_str):
    """Parse Odoo datetime string (UTC) 'YYYY-MM-DD HH:MM:SS'."""
    if not dt_str:
        return None
    # Handle potential microseconds if present, though usually not in Odoo search_read default
    try:
        return datetime.strptime(dt_str, "%Y-%m-%d %H:%M:%S")
    except ValueError:
        return datetime.strptime(dt_str, "%Y-%m-%d %H:%M:%S.%f")

def verify_duplicate_and_modify_event(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result file
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

    if result.get("error"):
        return {"passed": False, "score": 0, "feedback": f"Export error: {result['error']}"}

    score = 0
    feedback_parts = []
    
    q3 = result.get("q3_event")
    q2 = result.get("q2_event")
    q3_attendees = result.get("q3_attendee_names", [])
    q2_baseline = result.get("q2_baseline", {})
    
    # 1. Check Existence (15 pts)
    if not q3:
        return {"passed": False, "score": 0, "feedback": "Event 'Q3 Financial Review' not found."}
    
    score += 15
    feedback_parts.append("'Q3 Financial Review' created")

    # 2. Check Date/Time (20 pts)
    # Start time should be Q2 start + 14 days
    # Allow 2 hours tolerance for potential timezone display confusions
    q2_start = parse_odoo_datetime(q2.get("start"))
    q3_start = parse_odoo_datetime(q3.get("start"))
    q2_stop = parse_odoo_datetime(q2.get("stop"))
    q3_stop = parse_odoo_datetime(q3.get("stop"))

    if q2_start and q3_start:
        delta = q3_start - q2_start
        expected_delta = timedelta(days=14)
        diff_seconds = abs((delta - expected_delta).total_seconds())
        
        if diff_seconds <= 7200: # 2 hours tolerance
            score += 10
            feedback_parts.append("Date correct (+14 days)")
        else:
            feedback_parts.append(f"Date incorrect (Offset was {delta}, expected 14 days)")

        # Duration check
        q3_duration = (q3_stop - q3_start).total_seconds()
        q2_duration = (q2_stop - q2_start).total_seconds()
        if abs(q3_duration - q2_duration) < 300: # 5 min tolerance
            score += 10
            feedback_parts.append("Duration matches Q2")
        else:
            feedback_parts.append("Duration mismatch")
    else:
        feedback_parts.append("Could not verify dates (missing data)")

    # 3. Check Location (10 pts)
    loc = q3.get("location") or ""
    if "Board Room" in loc:
        score += 10
        feedback_parts.append("Location correct")
    else:
        feedback_parts.append(f"Location incorrect ('{loc}')")

    # 4. Check Description (15 pts)
    desc = str(q3.get("description") or "").lower()
    required_keywords = ["q3", "financial performance", "forecasting"]
    missing_kw = [k for k in required_keywords if k not in desc]
    
    if not missing_kw:
        score += 15
        feedback_parts.append("Description content correct")
    elif len(missing_kw) < len(required_keywords):
        score += 7
        feedback_parts.append(f"Description partial match (missing: {missing_kw})")
    else:
        feedback_parts.append("Description missing required keywords")

    # 5. Check Attendees (20 pts)
    # Should contain: Alice Johnson, Bob Williams, Henry Kim, Grace Patel
    required_names = ["Alice Johnson", "Bob Williams", "Henry Kim", "Grace Patel"]
    # Normalize for check
    current_names = [n.lower() for n in q3_attendees]
    missing_attendees = [name for name in required_names if name.lower() not in current_names]
    
    if not missing_attendees:
        score += 20
        feedback_parts.append("All attendees present")
    else:
        # Partial credit
        present_count = len(required_names) - len(missing_attendees)
        partial_score = int((present_count / len(required_names)) * 20)
        score += partial_score
        feedback_parts.append(f"Missing attendees: {missing_attendees}")

    # 6. Check Preservation of Q2 (10 pts)
    if q2 and q2_baseline:
        # ID must match (sanity check)
        # Name, start, partner_ids should match baseline
        same_name = q2["name"] == q2_baseline["name"]
        same_start = q2["start"] == q2_baseline["start"]
        
        # Partner check: IDs in baseline match IDs in current
        base_pids = set(q2_baseline.get("partner_ids", []))
        curr_pids = set(q2.get("partner_ids", []))
        same_partners = (base_pids == curr_pids)
        
        if same_name and same_start and same_partners:
            score += 10
            feedback_parts.append("Original Q2 event preserved")
        else:
            feedback_parts.append("Original Q2 event was modified!")
            if not same_start: feedback_parts.append("(Start time changed)")
            if not same_partners: feedback_parts.append("(Attendees changed)")
    else:
        feedback_parts.append("Could not verify Q2 preservation")

    # 7. Anti-Gaming (10 pts)
    # Check if event count increased
    # Need initial count. Since we can't easily get /tmp/initial_event_count.txt directly via copy_from_env 
    # without another call, we'll assume the python script could have included it or we rely on 'create_date' of Q3
    # Check if Q3 was created during task window
    task_start = result.get("task_start_ts", 0)
    q3_create_str = q3.get("create_date")
    
    created_during_task = False
    if q3_create_str:
        q3_create_dt = parse_odoo_datetime(q3_create_str)
        # Odoo stores create_date in UTC. Task timestamp is UTC unix.
        # Simple check: created after task start
        if q3_create_dt.timestamp() > task_start - 60: # 60s buffer for clock skew
            created_during_task = True
            
    if created_during_task:
        score += 10
        feedback_parts.append("Event created during task session")
    else:
        feedback_parts.append("Event appears stale (created before task start)")

    return {
        "passed": score >= 60,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }