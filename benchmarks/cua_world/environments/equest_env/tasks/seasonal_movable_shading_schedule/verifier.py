#!/usr/bin/env python3
"""
Verifier for seasonal_movable_shading_schedule@1

Validates:
1. Schedule hierarchy (Day -> Week -> Annual)
2. Correct date ranges (May 15 - Sep 15 for Summer)
3. Correct values (1.0 for Summer, 0.0 for Winter)
4. Assignment to Windows in G.South and T.South
5. Simulation run
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_inp_blocks(content):
    """
    Parses DOE-2 INP format to extract objects.
    Returns a dict of {Object_Name: {Type: '...', Properties: {...}}}
    """
    objects = {}
    
    # Regex to find top-level objects: "Name" = TYPE ... ..
    # This is a simplified parser. DOE-2 format is complex.
    # We'll split by ".." which ends a command in DOE-2
    commands = content.split('..')
    
    for cmd in commands:
        cmd = cmd.strip()
        if not cmd:
            continue
            
        # Parse "Name" = TYPE
        match = re.search(r'"([^"]+)"\s*=\s*([A-Z0-9-]+)', cmd)
        if match:
            name = match.group(1)
            obj_type = match.group(2)
            
            # Extract keywords
            props = {}
            # Regex for KEYWORD = VALUE (handling quotes and parens is tricky)
            # We'll look for specific keys we care about
            
            # Helper to find value for a keyword
            def get_val(key):
                # Look for KEY = VALUE or KEY = ( v1, v2 )
                # Basic regex for single line properties
                k_match = re.search(rf'{key}\s*=\s*([^=\r\n]+)', cmd, re.IGNORECASE)
                if k_match:
                    return k_match.group(1).strip()
                return None
            
            # Store raw command for easier regexing later if needed
            props['raw'] = cmd
            
            if obj_type == 'SCHEDULE-PD':
                props['TYPE'] = get_val('TYPE')
                props['MONTH'] = get_val('MONTH')
                props['DAY'] = get_val('DAY')
                props['WEEK-SCHEDULES'] = get_val('WEEK-SCHEDULES')
                props['VALUES'] = get_val('VALUES')
            
            elif obj_type == 'DAY-SCHEDULE-PD':
                props['VALUES'] = get_val('VALUES')
                
            elif obj_type == 'WEEK-SCHEDULE-PD':
                props['DAY-SCHEDULES'] = get_val('DAY-SCHEDULES')
                
            elif obj_type == 'WINDOW':
                props['SHADING-SCHEDULE'] = get_val('SHADING-SCHEDULE')
                # Need to identify parent zone (context is loose in INP flat list)
                # But typically names are G.South.Win1 etc.
            
            objects[name] = {'type': obj_type, 'props': props}
            
    return objects

def resolve_schedule_value(annual_sch_name, date_tuple, objects):
    """
    Trace the value of a schedule for a specific date (month, day).
    Returns value (float) or None if broken chain.
    """
    if annual_sch_name not in objects:
        return None
        
    sch = objects[annual_sch_name]
    if sch['type'] != 'SCHEDULE-PD':
        return None # Referenced object is not a schedule
        
    # 1. Determine Week Schedule from Annual Schedule
    # Parse MONTH/DAY arrays
    # Format: MONTH = ( 5, 9, 12 ) DAY = ( 14, 15, 31 ) WEEK-SCHEDULES = ( "Winter", "Summer", "Winter" )
    
    try:
        months_str = sch['props'].get('MONTH', '').replace('(', '').replace(')', '').replace(',', ' ')
        days_str = sch['props'].get('DAY', '').replace('(', '').replace(')', '').replace(',', ' ')
        weeks_str = sch['props'].get('WEEK-SCHEDULES', '').replace('(', '').replace(')', '').replace(',', ' ')
        
        months = [int(x) for x in months_str.split()]
        days = [int(x) for x in days_str.split()]
        # Weeks might be quoted
        weeks = [x.strip('"') for x in re.findall(r'"([^"]+)"', weeks_str)]
        
        if len(weeks) == 0:
            # Maybe unquoted
             weeks = weeks_str.split()

        target_month, target_day = date_tuple
        
        selected_week = None
        
        # Logic: Find the first period that ends ON or AFTER the target date
        # Assuming dates are chronological blocks
        # Convert all to day-of-year could be easier, but simple comparison works
        
        for i in range(len(months)):
            end_m = months[i]
            end_d = days[i]
            
            if (target_month < end_m) or (target_month == end_m and target_day <= end_d):
                selected_week = weeks[i]
                break
                
        if not selected_week:
            return None
            
        # 2. Determine Day Schedule from Week Schedule
        if selected_week not in objects:
            return None
            
        wk_sch = objects[selected_week]
        # DAY-SCHEDULES = ( "DaySch", "DaySch", ... ) 
        # Standard order: Mon, Tue, Wed, Thu, Fri, Sat, Sun, Hol
        
        day_schs_str = wk_sch['props'].get('DAY-SCHEDULES', '').replace('(', '').replace(')', '').replace(',', ' ')
        day_schs = [x.strip('"') for x in re.findall(r'"([^"]+)"', day_schs_str)]
        if not day_schs:
             day_schs = day_schs_str.split()

        # Just pick the first one (Monday) for simplicity, assuming consistent deployment
        if not day_schs:
            return None
            
        selected_day = day_schs[0]
        
        # 3. Get Value from Day Schedule
        if selected_day not in objects:
            return None
            
        day_obj = objects[selected_day]
        vals_str = day_obj['props'].get('VALUES', '').replace('(', '').replace(')', '').replace(',', ' ')
        vals = [float(x) for x in vals_str.split()]
        
        # Return noon value (index 12 if 0-23, or just average)
        if vals:
            return vals[12] if len(vals) > 12 else vals[0]
            
    except Exception as e:
        logger.error(f"Error resolving schedule: {e}")
        return None
        
    return None

def verify_seasonal_movable_shading_schedule(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:\\Users\\Docker\\task_result.json", temp_result.name)
        with open(temp_result.name, 'r', encoding='utf-8') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        os.unlink(temp_result.name)

    inp_content = result.get('inp_content', '')
    if not inp_content:
        return {"passed": False, "score": 0, "feedback": "INP file is empty or not found."}

    objects = parse_inp_blocks(inp_content)
    
    score = 0
    feedback = []
    
    # 1. Simulation Run (10 pts)
    if result.get('sim_file_is_new'):
        score += 10
        feedback.append("Simulation ran (+10)")
    else:
        feedback.append("Simulation did not run")

    # Identify target windows
    g_south_windows = [n for n in objects if objects[n]['type'] == 'WINDOW' and 'G.South' in n]
    t_south_windows = [n for n in objects if objects[n]['type'] == 'WINDOW' and 'T.South' in n]
    
    if not g_south_windows or not t_south_windows:
        return {"passed": False, "score": score, "feedback": "Could not find South windows in model."}

    # Helper to check a window
    def check_window_group(windows, group_name):
        points = 0
        fb = []
        assigned_count = 0
        correct_dates = 0
        correct_values = 0
        
        for w_name in windows:
            sch_name = objects[w_name]['props'].get('SHADING-SCHEDULE')
            if not sch_name:
                continue
                
            sch_name = sch_name.strip('"')
            assigned_count += 1
            
            # Check Summer Date (July 1st)
            val_summer = resolve_schedule_value(sch_name, (7, 1), objects)
            # Check Winter Date (Jan 1st)
            val_winter = resolve_schedule_value(sch_name, (1, 1), objects)
            # Check Boundary Date (May 14 - Winter)
            val_may14 = resolve_schedule_value(sch_name, (5, 14), objects)
            # Check Boundary Date (May 15 - Summer)
            val_may15 = resolve_schedule_value(sch_name, (5, 15), objects)
            
            # Logic Check
            is_summer_deployed = (val_summer == 1.0)
            is_winter_retracted = (val_winter == 0.0)
            is_dates_correct = (val_may14 == 0.0 and val_may15 == 1.0)
            
            if is_summer_deployed and is_winter_retracted:
                correct_values += 1
            
            if is_dates_correct:
                correct_dates += 1
        
        # Scoring for this group
        if assigned_count == len(windows):
            points += 10 # Assigned
            fb.append(f"All {group_name} windows assigned schedule (+10)")
        elif assigned_count > 0:
            points += 5
            fb.append(f"Some {group_name} windows assigned schedule (+5)")
        else:
            fb.append(f"No {group_name} windows assigned schedule")
            
        if correct_values == len(windows):
            points += 15 # Values correct
            fb.append(f"Values correct for {group_name} (+15)")
        
        if correct_dates == len(windows):
            points += 20 # Dates correct
            fb.append(f"Dates correct for {group_name} (+20)")
            
        return points, fb

    # Check G.South (45 pts max)
    g_score, g_fb = check_window_group(g_south_windows, "G.South")
    score += g_score
    feedback.extend(g_fb)
    
    # Check T.South (45 pts max)
    t_score, t_fb = check_window_group(t_south_windows, "T.South")
    score += t_score
    feedback.extend(t_fb)
    
    # Pass threshold
    passed = (score >= 70) and result.get('sim_file_is_new')
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }