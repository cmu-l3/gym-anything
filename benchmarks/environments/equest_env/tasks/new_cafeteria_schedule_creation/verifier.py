#!/usr/bin/env python3
"""
Verifier for new_cafeteria_schedule_creation task.

Checks:
1. Day Schedule 'Lunch-Rush-Day' created with 1.0 occupancy at 11am-2pm (hrs 12,13,14).
2. Week Schedule 'Lunch-Rush-Week' created linking to Day schedule.
3. Annual Schedule 'Lunch-Rush-Annual' created linking to Week schedule.
4. Zone 'G.E02' updated to use 'Lunch-Rush-Annual'.
5. Simulation ran.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

RESULT_PATH = "C:\\Users\\Docker\\task_result.json"

def verify_new_cafeteria_schedule_creation(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env(RESULT_PATH, temp_file.name)
        with open(temp_file.name, 'r', encoding='utf-8-sig') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result file: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []

    # 1. Verify Day Schedule (20 pts)
    # Expected: Hours 1-11=0, 12-14=1, 15-24=0
    # Note: eQUEST INP arrays often omit trailing zeros or use run-length encoding logic in UI,
    # but raw INP usually lists them. The PowerShell extractor returns an array of strings.
    day_values = result.get('day_schedule_values', [])
    
    # Convert to floats
    try:
        vals = [float(v) for v in day_values]
    except:
        vals = []

    day_correct = False
    if result.get('day_schedule_found'):
        # Check specific hours. eQUEST is 1-based index in documentation usually, 
        # but the array is just a list of 24 values.
        # 11:00 AM is the 12th hour? 
        # In eQUEST, hour 1 is 1am-2am? Or 00:00-01:00?
        # Usually it's 1-24. 11am-12pm is hour 12. 12pm-1pm is 13. 1pm-2pm is 14.
        # Task asks for 11:00 AM to 2:00 PM. That covers hours ending at 12, 13, 14.
        
        # We look for the pattern [..., 0, 1, 1, 1, 0, ...]
        # We allow some flexibility in exact indices (+/- 1 hour) as long as the shape is right (3 hours of 1.0)
        
        ones_indices = [i for i, x in enumerate(vals) if abs(x - 1.0) < 0.01]
        
        # Expecting 3 hours of peak
        if len(ones_indices) == 3:
            # Check if they are contiguous
            if ones_indices[-1] - ones_indices[0] == 2:
                # Check approximate time (indices 10-14 roughly)
                if 10 <= ones_indices[0] <= 12:
                    score += 20
                    day_correct = True
                    feedback_parts.append("Day schedule created correctly (+20)")
                else:
                    score += 10
                    feedback_parts.append("Day schedule has correct shape but wrong hours (+10)")
            else:
                feedback_parts.append("Day schedule has split peak hours")
        elif len(vals) > 0:
            feedback_parts.append(f"Day schedule created but values incorrect (Peak hours found: {len(ones_indices)})")
        else:
            feedback_parts.append("Day schedule created but has no values")
    else:
        feedback_parts.append("Day schedule 'Lunch-Rush-Day' not found")

    # 2. Verify Week Schedule (20 pts)
    # Must contain "Lunch-Rush-Day"
    week_assign = result.get('week_schedule_assignment', "")
    if result.get('week_schedule_found') and "Lunch-Rush-Day" in week_assign:
        score += 20
        feedback_parts.append("Week schedule created and links to Day schedule (+20)")
    elif result.get('week_schedule_found'):
        score += 5
        feedback_parts.append("Week schedule created but does not link to Day schedule (+5)")
    else:
        feedback_parts.append("Week schedule 'Lunch-Rush-Week' not found")

    # 3. Verify Annual Schedule (20 pts)
    # Must contain "Lunch-Rush-Week"
    annual_assign = result.get('annual_schedule_assignment', "")
    if result.get('annual_schedule_found') and "Lunch-Rush-Week" in annual_assign:
        score += 20
        feedback_parts.append("Annual schedule created and links to Week schedule (+20)")
    elif result.get('annual_schedule_found'):
        score += 5
        feedback_parts.append("Annual schedule created but does not link to Week schedule (+5)")
    else:
        feedback_parts.append("Annual schedule 'Lunch-Rush-Annual' not found")

    # 4. Verify Zone Assignment (25 pts)
    zone_sched = result.get('zone_assigned_schedule', "")
    if zone_sched and "Lunch-Rush-Annual" in zone_sched:
        score += 25
        feedback_parts.append("Zone G.E02 assigned to new schedule (+25)")
    elif zone_sched:
        feedback_parts.append(f"Zone G.E02 assigned to '{zone_sched}' instead of 'Lunch-Rush-Annual'")
    else:
        feedback_parts.append("Zone G.E02 schedule not assigned or not found")

    # 5. Verify Simulation (15 pts)
    if result.get('sim_ran'):
        score += 15
        feedback_parts.append("Simulation ran successfully (+15)")
    else:
        feedback_parts.append("Simulation did not run during task session")

    passed = score >= 70 and day_correct and "Lunch-Rush-Annual" in zone_sched

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }