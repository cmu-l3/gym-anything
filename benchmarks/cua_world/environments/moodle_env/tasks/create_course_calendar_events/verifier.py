#!/usr/bin/env python3
"""Verifier for Create Course Calendar Events task in Moodle."""

import json
import tempfile
import os
import logging
import time
from datetime import datetime, timezone

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_course_calendar_events(traj, env_info, task_info):
    """
    Verify that three specific course calendar events were created in Moodle.

    Criteria (100 points total):
    1. Event 1 (Guest Lecture) exists, correct course, time, duration (25 pts)
    2. Event 2 (Midterm) exists, correct course, time, duration (25 pts)
    3. Event 3 (Field Trip) exists, correct course, time, duration (25 pts)
    4. Anti-gaming: At least 3 new events created during task (15 pts)
    5. Anti-gaming: Events are proper 'course' type events (10 pts)

    Pass threshold: 60 points (must get at least 2 events fully correct)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_events = metadata.get('events', [])

    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/create_course_calendar_events_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)

        score = 0
        feedback_parts = []
        
        found_events = result.get('events', [])
        task_start = int(result.get('task_start_timestamp', 0))
        initial_count = int(result.get('initial_event_count', 0))
        current_count = int(result.get('current_event_count', 0))

        # Check net increase in events
        new_event_count = current_count - initial_count
        if new_event_count >= 3:
            score += 15
            feedback_parts.append(f"Count check passed (+{new_event_count} events)")
        elif new_event_count > 0:
            score += 5 * new_event_count
            feedback_parts.append(f"Count check partial (+{new_event_count} events)")
        else:
            feedback_parts.append("No new events created")

        # Process each expected event
        events_correct = 0
        events_type_correct = 0

        for i, expected in enumerate(expected_events):
            exp_name_pat = expected['name_pattern'].lower()
            # Convert ISO string to unix timestamp
            # Assuming task description implies UTC/Server time for simplicity, 
            # or we allow a wide window (±24h) if user sets local time.
            dt = datetime.fromisoformat(expected['timestamp_iso'])
            exp_ts = dt.replace(tzinfo=timezone.utc).timestamp()
            exp_duration = expected['duration_mins'] * 60
            
            # Find best match in found_events
            match = None
            best_score = 0
            
            for ev in found_events:
                # Similarity check
                ev_name = str(ev.get('name', '')).lower()
                ev_ts = int(ev.get('timestart', 0))
                ev_dur = int(ev.get('timeduration', 0))
                ev_type = str(ev.get('eventtype', ''))
                ev_mod = int(ev.get('timemodified', 0))
                
                # Filter: Must be created/modified after task start (approx)
                # Allow a small buffer before task start in case of clock drift, 
                # but mainly ensure it's not an old event.
                if ev_mod < task_start - 60:
                    continue

                # Check name match
                if exp_name_pat in ev_name:
                    # Score this match candidate
                    current_match_score = 0
                    
                    # Time check (±24 hours to handle timezone confusion)
                    if abs(ev_ts - exp_ts) <= 86400:
                        current_match_score += 1
                        
                        # Tighten time check for perfection (±1 hour)
                        if abs(ev_ts - exp_ts) <= 3600:
                            current_match_score += 1

                    # Duration check (±5 mins)
                    if abs(ev_dur - exp_duration) <= 300:
                        current_match_score += 1
                    
                    # Type check
                    if ev_type == 'course':
                        current_match_score += 1

                    if current_match_score > best_score:
                        best_score = current_match_score
                        match = ev

            # Grade the best match found
            if match:
                ev_name = match.get('name')
                ev_type = match.get('eventtype')
                ev_ts = int(match.get('timestart'))
                ev_dur = int(match.get('timeduration'))
                
                item_score = 0
                item_feedback = []
                
                # Name matched (implied by finding it) - 5 pts
                item_score += 5
                
                # Date/Time (10 pts)
                time_diff = abs(ev_ts - exp_ts)
                if time_diff <= 3600: # Within hour
                    item_score += 10
                elif time_diff <= 86400: # Within day
                    item_score += 5
                    item_feedback.append("Date OK but time off")
                else:
                    item_feedback.append(f"Wrong date/time (diff {time_diff}s)")
                
                # Duration (5 pts)
                if abs(ev_dur - exp_duration) <= 300:
                    item_score += 5
                else:
                    item_feedback.append(f"Wrong duration ({ev_dur/60}m vs {exp_duration/60}m)")
                
                # Type (5 pts)
                if ev_type == 'course':
                    item_score += 5
                    events_type_correct += 1
                else:
                    item_feedback.append(f"Wrong type ({ev_type})")
                
                score += item_score
                feedback_parts.append(f"Event {i+1} ('{exp_name_pat[:15]}...'): {item_score}/25 pts. " + "; ".join(item_feedback))
                
                if item_score >= 20:
                    events_correct += 1
            else:
                feedback_parts.append(f"Event {i+1} ('{exp_name_pat[:15]}...') NOT FOUND")

        # Bonus for correct type across the board (part of criteria 5)
        # We tracked individual type correctness above. 
        # If we found matches for all and they were course type, we effectively gave points there.
        # We allocate the remaining 10 points for "Events are proper course type" 
        # by checking if we have at least 2 course events correctly identified.
        if events_type_correct >= 2:
            score += 10
            feedback_parts.append("Course event type usage verified")

        passed = score >= 60 and events_correct >= 2

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}