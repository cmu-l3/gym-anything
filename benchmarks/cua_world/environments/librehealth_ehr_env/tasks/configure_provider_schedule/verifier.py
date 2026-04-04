#!/usr/bin/env python3
"""
Verifier for configure_provider_schedule task.

Checks database records for:
1. Event existence for the specific provider
2. Correct Category (In Office)
3. Correct Time range (13:00 - 17:00)
4. Correct Recurrence pattern (Weekly, Tue/Thu)
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_provider_schedule(traj, env_info, task_info):
    # Setup
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result file
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

    events = result.get("events", [])
    
    if not events:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "No calendar events found for Dr. Stephen Strange."
        }

    # Scoring Logic
    # We iterate through all events found for this user. 
    # If ANY single event matches all criteria, full score.
    # Otherwise, we take the best matching event.
    
    best_score = 0
    best_feedback = []
    
    for i, evt in enumerate(events):
        score = 0
        feedback = []
        
        # 1. Event Created (Base points)
        score += 20
        feedback.append("Event created")
        
        # 2. Category Check (In Office) - 20 pts
        # Check category name (case insensitive)
        cat = evt.get("category", "").lower()
        if "office" in cat:
            score += 20
            feedback.append("Category correct (In Office)")
        else:
            feedback.append(f"Wrong category: {evt.get('category')}")
            
        # 3. Time Check (13:00 - 17:00) - 20 pts
        start = evt.get("startTime", "")
        end = evt.get("endTime", "")
        
        # Handle variations like "13:00:00" vs "13:00"
        start_valid = start.startswith("13:00")
        end_valid = end.startswith("17:00")
        
        if start_valid and end_valid:
            score += 20
            feedback.append("Time correct (13:00-17:00)")
        else:
            feedback.append(f"Wrong time: {start}-{end}")
            
        # 4. Recurrence Type (Weekly) - 20 pts
        # In PostCalendar, pc_recurrtype 1 usually means Weekly.
        # But we can also infer from the spec or context.
        # Let's assume '1' is weekly (standard OpenEMR).
        r_type = str(evt.get("recurrType", ""))
        
        if r_type == "1":
            score += 20
            feedback.append("Recurrence type correct (Weekly)")
            
            # 5. Recurrence Days (Tue/Thu) - 20 pts
            # pc_recurrspec format varies by version (JSON or serialized PHP or simple string).
            # We look for indicators of days.
            # Tuesday is typically index 2, Thursday index 4 (0-6 Sun-Sat).
            # Or strings "Tue", "Thu".
            r_spec = str(evt.get("recurrSpec", ""))
            
            # Robust check for 2 and 4 in the spec string
            has_tue = ("2" in r_spec) or ("Tue" in r_spec)
            has_thu = ("4" in r_spec) or ("Thu" in r_spec)
            
            # Should NOT have other days ideally, but we check mainly for inclusion
            if has_tue and has_thu:
                score += 20
                feedback.append("Recurrence days correct (Tue/Thu)")
            elif has_tue or has_thu:
                score += 10
                feedback.append("Partial recurrence days (one missing)")
            else:
                feedback.append(f"Wrong days in spec: {r_spec}")
        else:
            # If not type 1, maybe they set it up differently?
            # If recurrence type is '0' (Never), they fail recurrence
            feedback.append(f"Wrong recurrence type: {r_type}")

        # Update best score
        if score > best_score:
            best_score = score
            best_feedback = feedback

    passed = best_score >= 80  # Must get almost everything right
    
    final_feedback = f"Score: {best_score}/100. Best Event details: {', '.join(best_feedback)}"
    
    return {
        "passed": passed,
        "score": best_score,
        "feedback": final_feedback
    }