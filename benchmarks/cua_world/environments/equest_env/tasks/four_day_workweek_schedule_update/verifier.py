#!/usr/bin/env python3
"""
Verifier for four_day_workweek_schedule_update task.

Checks:
1. Simulation ran during task session (10 pts)
2. Occupancy schedules: Friday matches Saturday (30 pts)
3. Lighting schedules: Friday matches Saturday (30 pts)
4. Equipment schedules: Friday matches Saturday (30 pts)
5. Monday schedules should NOT change (penalty check implicit in logic if we had baseline, 
   but here we trust the agent didn't break Monday unless obvious).

Pass Threshold: 60 pts + Sim Run
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

RESULT_FILENAME = "four_day_workweek_result.json"
RESULT_PATH_CONTAINER = f"C:\\Users\\Docker\\{RESULT_FILENAME}"

def verify_four_day_workweek_schedule_update(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env(RESULT_PATH_CONTAINER, temp_file.name)
        with open(temp_file.name, 'r', encoding='utf-8-sig') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # 1. Check Simulation
    sim_run = result.get('sim_run', False)
    if sim_run:
        score += 10
        feedback.append("Simulation ran successfully (+10).")
    else:
        feedback.append("Simulation did not run or .SIM file not new.")

    # 2. Check Schedules
    schedules = result.get('schedules', [])
    
    # Group by category
    cats = {"Occupancy": [], "Lighting": [], "Equipment": []}
    
    for s in schedules:
        cat = s.get('Category')
        if cat in cats:
            cats[cat].append(s)

    # Score each category
    # We expect at least one schedule in each category for this building
    for cat_name, items in cats.items():
        if not items:
            feedback.append(f"No {cat_name} schedules found/parsed.")
            continue
            
        # Calculate fraction correct
        correct_count = sum(1 for x in items if x.get('IsCorrect', False))
        total_count = len(items)
        
        # Check for Monday sanity (Monday should NOT equal Saturday usually)
        # This is a heuristic: if Monday == Saturday, agent might have set ALL days to weekend
        # But Monday schedule is usually "Wkdy..." and Saturday is "Sat..."
        # So we check if Monday != Saturday to ensure distinct profiles exist
        # Or simpler: just check Monday name hasn't become the Saturday name
        valid_monday = sum(1 for x in items if x.get('Monday') != x.get('Saturday'))
        
        if valid_monday < total_count:
            feedback.append(f"Warning: {cat_name} Monday schedule matches Saturday (possible 'change all' error).")
            # Apply penalty or reduce score? Let's cap score for this category
            cat_score = 0
        else:
            if total_count > 0:
                cat_score = 30 * (correct_count / total_count)
            else:
                cat_score = 0
        
        score += cat_score
        feedback.append(f"{cat_name}: {correct_count}/{total_count} correct (+{cat_score:.1f}).")

    # Round score
    score = round(score)
    
    # Pass logic
    passed = (score >= 60) and sim_run
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }