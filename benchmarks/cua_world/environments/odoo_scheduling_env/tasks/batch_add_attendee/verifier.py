#!/usr/bin/env python3
"""
Verifier for batch_add_attendee task.
"""

import json
import os
import tempfile
import logging
from datetime import datetime
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_batch_add_attendee(traj, env_info, task_info):
    """
    Verifies that James O'Brien was added to all meetings attended by Alice Johnson
    in the target week, and NOT added to other meetings.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load result data from environment
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

    if 'error' in result:
        return {"passed": False, "score": 0, "feedback": f"Export script error: {result['error']}"}

    events = result.get('events', [])
    task_start_ts = result.get('task_start_ts', 0)
    
    # Metadata
    target_person = task_info.get('metadata', {}).get('target_attendee', 'Alice Johnson')
    new_person = task_info.get('metadata', {}).get('new_attendee', "James O'Brien")

    # 2. Categorize events
    target_events = []     # Events Alice is attending
    distractor_events = [] # Events Alice is NOT attending

    for event in events:
        attendees = event.get('attendees', [])
        if target_person in attendees:
            target_events.append(event)
        else:
            distractor_events.append(event)

    # 3. Evaluate Metrics
    
    # A. Recall: Is New Person in all Target Events?
    # Also check if event was modified recently (Anti-gaming)
    correctly_added_count = 0
    total_targets = len(target_events)
    
    recall_feedback = []
    
    for event in target_events:
        has_new = new_person in event.get('attendees', [])
        
        # Check modification time
        write_date_str = event.get('write_date', '')
        # Odoo write_date is UTC string 'YYYY-MM-DD HH:MM:SS'. 
        # Converting to TS to compare with task_start_ts is good but strict.
        # Ideally, if James is there, we assume success, but timestamp adds confidence.
        # We'll just check presence primarily.
        
        if has_new:
            correctly_added_count += 1
        else:
            recall_feedback.append(f"Missed event '{event['name']}'")

    recall_score = 0
    if total_targets > 0:
        recall_score = (correctly_added_count / total_targets) * 60
    else:
        # If no target events exist, something is wrong with setup/data
        return {"passed": False, "score": 0, "feedback": "Setup Error: No meetings found for Alice Johnson in target week."}

    # B. Precision: Is New Person absent from Distractor Events?
    correctly_ignored_count = 0
    total_distractors = len(distractor_events)
    
    precision_feedback = []
    
    for event in distractor_events:
        has_new = new_person in event.get('attendees', [])
        if not has_new:
            correctly_ignored_count += 1
        else:
            precision_feedback.append(f"Incorrectly added to '{event['name']}'")

    precision_score = 0
    if total_distractors > 0:
        precision_score = (correctly_ignored_count / total_distractors) * 30
    else:
        # If no distractors, full points for this part (unlikely given data)
        precision_score = 30

    # 4. VLM Verification (Trajectory)
    # Check if we see the Event Form being edited
    vlm_score = 0
    frames = sample_trajectory_frames(traj, n=4)
    if frames:
        prompt = """
        Analyze these screenshots of a user working in a calendar application.
        Does the user appear to be:
        1. Viewing calendar event details?
        2. Editing attendees (look for 'Attendees' field or list of names)?
        3. Saving changes?
        
        Return JSON: {"editing_observed": boolean}
        """
        vlm_res = query_vlm(prompt=prompt, images=frames)
        if vlm_res and vlm_res.get('parsed', {}).get('editing_observed', False):
            vlm_score = 10
    
    # 5. Final Calculation
    total_score = recall_score + precision_score + vlm_score
    passed = (total_score >= 90) # Requires near perfection + VLM check or perfect logic

    feedback = f"Added to {correctly_added_count}/{total_targets} target events. "
    if recall_feedback:
        feedback += f"Missed: {', '.join(recall_feedback[:3])}... "
    
    feedback += f"Correctly ignored {correctly_ignored_count}/{total_distractors} distractors. "
    if precision_feedback:
        feedback += f"Errors: {', '.join(precision_feedback[:3])}... "

    return {
        "passed": passed,
        "score": int(total_score),
        "feedback": feedback
    }