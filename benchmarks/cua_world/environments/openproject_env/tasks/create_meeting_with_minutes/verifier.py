#!/usr/bin/env python3
"""
Verifier for create_meeting_with_minutes task.
Reads the JSON result exported from OpenProject and scores the task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_meeting_with_minutes(traj, env_info, task_info):
    """
    Verify that the meeting was created with the correct details.
    
    Criteria:
    1. Meeting exists with correct title (20 pts)
    2. Location matches (10 pts)
    3. Start time matches (10 pts)
    4. Duration matches (5 pts)
    5. Agenda items present (20 pts)
    6. Participants invited (15 pts)
    7. Notes recorded correctly (20 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Get expected values from metadata
    metadata = task_info.get('metadata', {})
    expected_title_frag = metadata.get('expected_title_fragment', 'sprint 1 retrospective')
    
    # 1. Load result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Check if meeting found
    if not result.get('found'):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "No meeting found with title containing 'Sprint 1 Retrospective' in the E-Commerce Platform project."
        }
    
    score = 0
    feedback_parts = []
    
    # Anti-gaming check: Creation time
    task_start = int(result.get('task_start_timestamp', 0))
    meeting_created = int(result.get('created_at_ts', 0))
    
    if meeting_created < task_start:
        feedback_parts.append("WARN: Meeting appears to have been created before task start.")
        # We don't fail immediately but this is suspicious
    
    meta = result.get('metadata', {})
    
    # --- Criterion 1: Title (20 pts) ---
    # Already checked loosely by export script to find the meeting, but double check
    title = meta.get('title', '').lower()
    if expected_title_frag in title:
        score += 20
        feedback_parts.append("Title correct (20/20)")
    else:
        feedback_parts.append(f"Title mismatch: '{meta.get('title')}'")

    # --- Criterion 2: Location (10 pts) ---
    loc = meta.get('location', '').lower()
    if 'room 4b' in loc or '4b' in loc:
        score += 10
        feedback_parts.append("Location correct (10/10)")
    else:
        feedback_parts.append(f"Location mismatch: '{meta.get('location')}'")

    # --- Criterion 3: Start Time (10 pts) ---
    start_time = meta.get('start_time', '')
    if '2025-02-10' in start_time and ('14:00' in start_time or 'T14:' in start_time):
        score += 10
        feedback_parts.append("Start time correct (10/10)")
    elif '2025-02-10' in start_time:
        score += 5
        feedback_parts.append("Date correct, time incorrect (5/10)")
    else:
        feedback_parts.append(f"Start time mismatch: '{start_time}'")

    # --- Criterion 4: Duration (5 pts) ---
    duration = float(meta.get('duration', 0))
    if abs(duration - 1.5) < 0.1:
        score += 5
        feedback_parts.append("Duration correct (5/5)")
    else:
        feedback_parts.append(f"Duration mismatch: {duration}")

    # --- Criterion 5: Agenda Items (20 pts) ---
    agenda_list = result.get('agenda', [])
    agenda_titles = [item.get('title', '').lower() for item in agenda_list]
    notes_text = result.get('notes_text', '').lower() # Fallback if items are in notes
    
    expected_items = ["velocity", "went well", "needs improvement", "action items"]
    found_count = 0
    
    for item in expected_items:
        # Check structured titles first
        if any(item in title for title in agenda_titles):
            found_count += 1
        # Fallback: check if they typed it all in the notes/description
        elif item in notes_text:
            found_count += 1
            
    if found_count >= 4:
        score += 20
        feedback_parts.append(f"All agenda items found (20/20)")
    elif found_count >= 3:
        score += 15
        feedback_parts.append(f"3/4 agenda items found (15/20)")
    elif found_count >= 1:
        score += 5
        feedback_parts.append(f"Only {found_count}/4 agenda items found (5/20)")
    else:
        feedback_parts.append("No agenda items found (0/20)")

    # --- Criterion 6: Participants (15 pts) ---
    participants = result.get('participants', [])
    p_names = [p.get('name', '').lower() for p in participants]
    
    expected_p = ["alice", "bob", "carol"]
    p_found = 0
    for name_frag in expected_p:
        if any(name_frag in p for p in p_names):
            p_found += 1
            
    if p_found >= 3:
        score += 15
        feedback_parts.append("All participants invited (15/15)")
    elif p_found >= 1:
        score += 5
        feedback_parts.append(f"Only {p_found}/3 participants found (5/15)")
    else:
        feedback_parts.append("No correct participants found (0/15)")

    # --- Criterion 7: Notes Content (20 pts) ---
    # Notes might be attached to agenda items or in the minutes field
    all_text = result.get('notes_text', '').lower()
    
    has_points = "34 story points" in all_text or "34 points" in all_text
    has_elastic = "elasticsearch" in all_text
    
    if has_points and has_elastic:
        score += 20
        feedback_parts.append("Meeting minutes content correct (20/20)")
    elif has_points or has_elastic:
        score += 10
        feedback_parts.append("Partial minutes content found (10/20)")
    else:
        feedback_parts.append("Meeting minutes content missing (0/20)")

    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": f"Score: {score}/100. " + "; ".join(feedback_parts)
    }