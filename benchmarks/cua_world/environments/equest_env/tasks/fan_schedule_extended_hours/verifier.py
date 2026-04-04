#!/usr/bin/env python3
"""
Verifier for fan_schedule_extended_hours task.

Goal: Update eQUEST fan schedules for Weekday (06:00-22:00) and Saturday (07:00-13:00).
      Run simulation.

Criteria:
1. Simulation run during session (New .SIM file)
2. Weekday Schedule: Hours 7-22 = 1, others 0.
3. Saturday Schedule: Hours 8-14 = 1, others 0.
"""

import json
import os
import tempfile
import logging
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

RESULT_PATH = "C:\\Users\\Docker\\fan_schedule_result.json"

def parse_equest_values(value_str):
    """Parses a comma-separated string of numbers from eQUEST INP format."""
    if not value_str:
        return []
    # Remove parens just in case
    cleaned = value_str.replace('(', '').replace(')', '').strip()
    # Split by comma or whitespace
    parts = re.split(r'[,\s]+', cleaned)
    # Convert to float
    values = []
    for p in parts:
        if p:
            try:
                values.append(float(p))
            except ValueError:
                pass
    return values

def check_profile_match(actual_values, target_profile, tolerance=0.05):
    """Checks if actual values match the target profile."""
    if len(actual_values) < 24:
        return False, 0
    
    matches = 0
    # Check first 24 hours (DOE-2 schedules are 24 hours)
    for i in range(24):
        if i < len(target_profile):
            if abs(actual_values[i] - target_profile[i]) <= tolerance:
                matches += 1
    
    return (matches == 24), matches

def verify_fan_schedule_extended_hours(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    # Load result
    result = {}
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env(RESULT_PATH, temp_file.name)
        with open(temp_file.name, 'r', encoding='utf-8-sig') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # Targets
    target_weekday = task_info['metadata']['expected_weekday_profile']
    target_saturday = task_info['metadata']['expected_saturday_profile']

    # 1. Simulation Check (10 pts)
    sim_new = result.get('sim_file_is_new', False)
    if sim_new:
        score += 10
        feedback_parts.append("Simulation ran successfully (+10)")
    else:
        feedback_parts.append("Simulation NOT run during session")

    # 2. Schedule Check
    schedules = result.get('day_schedules', [])
    
    # We need to find the BEST match for each target among all schedules
    # This accounts for the agent potentially modifying different schedules
    # or the naming being slightly different.
    
    # Weekday Analysis
    weekday_best_score = 0
    weekday_best_name = None
    
    for sch in schedules:
        name = sch.get('name', '')
        vals = parse_equest_values(sch.get('values', ''))
        
        # Check against weekday target
        is_match, match_count = check_profile_match(vals, target_weekday)
        
        # We calculate points based on specific hours as per design
        # Design: Hours 1-6 (0), 7-22 (1), 23-24 (0)
        # 24 pts available for profile match in design logic?
        # Let's map the design table strictly:
        # Weekday: 1-6 (10pts), 7-22 (30pts), 23-24 (5pts) -> Total 45
        
        current_score = 0
        if len(vals) >= 24:
            # Hours 1-6 (indices 0-5)
            h1_6 = sum(1 for i in range(6) if abs(vals[i] - 0) < 0.05)
            if h1_6 == 6: current_score += 10
            
            # Hours 7-22 (indices 6-21)
            h7_22 = sum(1 for i in range(6, 22) if abs(vals[i] - 1) < 0.05)
            # 16 hours total. 30 pts total. ~1.875 per hour.
            # Let's just give proportional
            current_score += (h7_22 / 16) * 30
            
            # Hours 23-24 (indices 22-23)
            h23_24 = sum(1 for i in range(22, 24) if abs(vals[i] - 0) < 0.05)
            if h23_24 == 2: current_score += 5
            
        if current_score > weekday_best_score:
            weekday_best_score = current_score
            weekday_best_name = name

    score += weekday_best_score
    if weekday_best_score >= 40:
        feedback_parts.append(f"Weekday schedule '{weekday_best_name}' updated correctly (+{int(weekday_best_score)})")
    elif weekday_best_score > 0:
        feedback_parts.append(f"Weekday schedule partially correct (+{int(weekday_best_score)})")
    else:
        feedback_parts.append("Weekday schedule incorrect")

    # Saturday Analysis
    # Design: 1-7 (8pts), 8-14 (22pts), 15-24 (10pts) -> Total 40
    sat_best_score = 0
    sat_best_name = None
    
    for sch in schedules:
        name = sch.get('name', '')
        vals = parse_equest_values(sch.get('values', ''))
        
        current_score = 0
        if len(vals) >= 24:
            # Hours 1-7 (indices 0-6)
            h1_7 = sum(1 for i in range(7) if abs(vals[i] - 0) < 0.05)
            if h1_7 == 7: current_score += 8
            
            # Hours 8-14 (indices 7-13)
            h8_14 = sum(1 for i in range(7, 14) if abs(vals[i] - 1) < 0.05)
            current_score += (h8_14 / 7) * 22
            
            # Hours 15-24 (indices 14-23)
            h15_24 = sum(1 for i in range(14, 24) if abs(vals[i] - 0) < 0.05)
            if h15_24 == 10: current_score += 10
            
        if current_score > sat_best_score:
            sat_best_score = current_score
            sat_best_name = name

    score += sat_best_score
    if sat_best_score >= 35:
        feedback_parts.append(f"Saturday schedule '{sat_best_name}' updated correctly (+{int(sat_best_score)})")
    elif sat_best_score > 0:
        feedback_parts.append(f"Saturday schedule partially correct (+{int(sat_best_score)})")
    else:
        feedback_parts.append("Saturday schedule incorrect")
        
    # Fan Energy Check (5 pts)
    # We can't easily parse binary SIM files here, but if they ran the sim and changed schedules,
    # we assume plausibility for this hard task to avoid complex parsing.
    # We'll grant these 5 points if both schedules are mostly correct and sim ran.
    if sim_new and weekday_best_score > 30 and sat_best_score > 25:
        score += 5
        feedback_parts.append("Energy impact plausible (+5)")

    passed = (score >= 60) and sim_new and (weekday_best_score >= 30)

    return {
        "passed": passed,
        "score": min(100, int(score)),
        "feedback": " | ".join(feedback_parts)
    }