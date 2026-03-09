#!/usr/bin/env python3
"""
Verifier for server_room_247_cooling_retrofit.

Task Goal:
1.  Zone M.C25 must have a COOLING schedule that is 72°F (approx) for all 24 hours.
2.  Zone M.S21 (reference) must have a COOLING schedule that has setback (e.g. >75°F) at night.
3.  Simulation must have run.

Verification Logic:
1.  Retrieve `task_result.json` and `4StoreyBuilding.inp` from the container.
2.  Parse the INP file to traverse the schedule hierarchy:
    Zone -> Cool-Temp-Sch (Annual) -> Week-Schedule -> Day-Schedule -> Values.
3.  Check values for M.C25 (Target) and M.S21 (Reference).
4.  Verify simulation ran.
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_inp_schedules(inp_content):
    """
    Parses DOE-2 .inp content to build a lookup of schedules and zones.
    Returns a dictionary of objects.
    """
    objects = {}
    current_obj_name = None
    current_obj_type = None
    current_props = {}
    
    # Regex to identify object definitions: "Name" = TYPE
    obj_def_pattern = re.compile(r'^\s*"([^"]+)"\s*=\s*([A-Z0-9-]+)\s*(\.\.|$)')
    
    lines = inp_content.splitlines()
    for line in lines:
        line = line.split('..')[0].strip() # Remove comments and trailing '..'
        if not line:
            continue
            
        # Check for new object start
        match = obj_def_pattern.match(line)
        if match:
            # Save previous object
            if current_obj_name:
                objects[current_obj_name] = {'type': current_obj_type, 'props': current_props}
            
            current_obj_name = match.group(1)
            current_obj_type = match.group(2)
            current_props = {}
        elif current_obj_name:
            # Parse property assignments: KEY = VALUE or KEY = ( v1, v2 )
            # Simple parser: just grab key = value pairs
            # This is not a full BDL parser but sufficient for schedule scraping
            if '=' in line:
                parts = line.split('=', 1)
                key = parts[0].strip()
                val = parts[1].strip()
                current_props[key] = val
                
    # Save last object
    if current_obj_name:
        objects[current_obj_name] = {'type': current_obj_type, 'props': current_props}
        
    return objects

def resolve_schedule_values(sch_name, objects):
    """
    Recursively resolves a schedule name to its 24-hour values for a standard design day.
    Returns list of 24 floats or None if failed.
    """
    if sch_name not in objects:
        return None
        
    obj = objects[sch_name]
    obj_type = obj['type']
    
    if obj_type == 'DAY-SCHEDULE-PD':
        # Extract values
        # Format: VALUES = ( v1, v2, ... )
        val_str = obj['props'].get('VALUES', '')
        # clean up parens and commas
        val_str = val_str.replace('(', '').replace(')', '').replace(',', ' ')
        try:
            values = [float(x) for x in val_str.split()]
            return values
        except:
            return None
            
    elif obj_type == 'WEEK-SCHEDULE-PD':
        # Get Monday schedule (usually safe for verification)
        # Format: DAY-SCHEDULES = ( "DaySch", "DaySch", ... )
        # or separate keys like DAY-SCHEDULES(1)
        # Simplified: Look for list
        day_schs_str = obj['props'].get('DAY-SCHEDULES', '')
        day_sch_names = re.findall(r'"([^"]+)"', day_schs_str)
        if day_sch_names:
            return resolve_schedule_values(day_sch_names[0], objects)
        return None
        
    elif obj_type == 'SCHEDULE-PD':
        # Annual schedule
        # WEEK-SCHEDULES = ( "WeekSch", ... )
        week_schs_str = obj['props'].get('WEEK-SCHEDULES', '')
        week_sch_names = re.findall(r'"([^"]+)"', week_schs_str)
        if week_sch_names:
            return resolve_schedule_values(week_sch_names[0], objects)
        return None
        
    return None

def verify_server_room_cooling(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    target_zone = metadata.get('target_zone', "M.C25")
    ref_zone = metadata.get('reference_zone', "M.S21")
    target_temp = metadata.get('target_temp', 72.0)
    
    # Files
    result_json_path = "C:\\Users\\Docker\\task_result.json"
    inp_path = metadata.get('project_path', "C:\\Users\\Docker\\Documents\\eQUEST 3-65 Projects\\4StoreyBuilding\\4StoreyBuilding.inp")
    
    # 1. Fetch Result JSON
    task_result = {}
    with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as f:
        tmp_json = f.name
    
    try:
        copy_from_env(result_json_path, tmp_json)
        with open(tmp_json, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {str(e)}"}
    finally:
        if os.path.exists(tmp_json):
            os.remove(tmp_json)
            
    # 2. Fetch INP File
    inp_content = ""
    with tempfile.NamedTemporaryFile(suffix=".inp", delete=False) as f:
        tmp_inp = f.name
        
    try:
        copy_from_env(inp_path, tmp_inp)
        with open(tmp_inp, 'r', encoding='latin-1') as f: # INP files often legacy encoding
            inp_content = f.read()
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve project file: {str(e)}"}
    finally:
        if os.path.exists(tmp_inp):
            os.remove(tmp_inp)

    # 3. Parse INP
    objects = parse_inp_schedules(inp_content)
    
    score = 0
    feedback = []
    
    # Check Simulation
    if task_result.get('sim_file_is_new'):
        score += 10
        feedback.append("Simulation ran successfully (+10).")
    else:
        feedback.append("Simulation did not run.")

    # Check Target Zone (M.C25)
    t_zone_obj = objects.get(target_zone)
    t_sch_name = None
    t_values = None
    
    if t_zone_obj:
        # Key name is quoted in lookup
        t_sch_raw = t_zone_obj['props'].get('COOL-TEMP-SCH', '')
        match = re.search(r'"([^"]+)"', t_sch_raw)
        if match:
            t_sch_name = match.group(1)
            t_values = resolve_schedule_values(t_sch_name, objects)
    
    if t_values and len(t_values) >= 24:
        # Check if all values are approx 72
        is_constant_cool = all(abs(v - target_temp) < 1.0 for v in t_values)
        if is_constant_cool:
            score += 40
            feedback.append(f"Target zone {target_zone} correctly set to constant {target_temp}F (+40).")
        else:
            avg_temp = sum(t_values)/len(t_values)
            feedback.append(f"Target zone {target_zone} schedule avg temp is {avg_temp:.1f}F, expected constant {target_temp}F.")
    else:
        feedback.append(f"Could not resolve schedule for {target_zone}.")

    # Check Reference Zone (M.S21) - Anti-Gaming / Isolation Check
    r_zone_obj = objects.get(ref_zone)
    r_sch_name = None
    r_values = None
    
    if r_zone_obj:
        r_sch_raw = r_zone_obj['props'].get('COOL-TEMP-SCH', '')
        match = re.search(r'"([^"]+)"', r_sch_raw)
        if match:
            r_sch_name = match.group(1)
            r_values = resolve_schedule_values(r_sch_name, objects)

    if r_values and len(r_values) >= 24:
        # Check night setback (usually > 80F or 99F for off)
        # Just check that it is NOT constant 72
        is_constant_72 = all(abs(v - target_temp) < 1.0 for v in r_values)
        if not is_constant_72:
            # Check if it has high values (setback)
            max_val = max(r_values)
            if max_val > 74.0:
                score += 40
                feedback.append(f"Reference zone {ref_zone} correctly maintained night setback (+40).")
            else:
                feedback.append(f"Reference zone {ref_zone} has low max temp ({max_val}F), setback may be lost.")
        else:
            feedback.append(f"FAIL: Reference zone {ref_zone} was also changed to constant 72F! You modified the global schedule instead of creating a new one.")
            score = 0 # Penalty for breaking global settings
    else:
        feedback.append(f"Could not resolve schedule for {ref_zone}.")

    # Check for object creation (Bonus/Sanity)
    if t_sch_name and r_sch_name and t_sch_name == r_sch_name:
         # If they point to exact same schedule name, and we verified one is 72 and other is setback...
         # Impossible unless logic above failed.
         # If they are same name, and we found it is 72, then Reference failed.
         pass
    elif t_sch_name and r_sch_name and t_sch_name != r_sch_name:
         score += 10
         feedback.append("New schedule object correctly assigned (+10).")

    passed = (score >= 60)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }