#!/usr/bin/env python3
"""
Verifier for gym_dhw_schedule_implementation task.

Requirements:
1. Parse 4StoreyBuilding.inp.
2. Verify a new Day Schedule exists with peaks at 7-9 and 17-19 (values ~1.0) and base ~0.1.
3. Verify a Week Schedule exists that uses this day schedule.
4. Verify DHW Loop (CIRCULATION-LOOP, TYPE=DHW) has PROCESS-FLOW=5.0.
5. Verify DHW Loop uses the new Week Schedule.
6. Verify simulation ran during task.
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
    Parses the INP content to find DAY-SCHEDULE-PD and WEEK-SCHEDULE-PD blocks.
    Returns a dictionary of parsed schedules.
    """
    schedules = {
        "day": {},
        "week": {}
    }
    
    # Regex for finding blocks: "Name" = TYPE ... ..
    # This is a simplified parser.
    
    # 1. Find Day Schedules
    # Pattern: "Name" = DAY-SCHEDULE-PD
    # Capture values.
    day_pattern = re.compile(r'"([^"]+)"\s*=\s*DAY-SCHEDULE-PD', re.IGNORECASE)
    
    lines = inp_content.splitlines()
    current_block = None
    current_name = None
    
    # Iterate lines to handle multi-line values
    for i, line in enumerate(lines):
        line = line.strip()
        
        # Check for start of Day Schedule
        day_match = day_pattern.search(line)
        if day_match:
            current_name = day_match.group(1)
            current_block = "day"
            schedules["day"][current_name] = {"values": []}
            continue
            
        # Check for start of Week Schedule
        week_match = re.search(r'"([^"]+)"\s*=\s*WEEK-SCHEDULE-PD', line, re.IGNORECASE)
        if week_match:
            current_name = week_match.group(1)
            current_block = "week"
            schedules["week"][current_name] = {"days": []}
            continue
            
        if current_block == "day":
            # Look for VALUES = ( ... )
            if line.startswith("VALUES") or "VALUES" in line:
                # Extract numbers. Note: values might span lines or be comma separated
                # Simple extraction of all floats in the block until next keyword or empty line
                vals = re.findall(r"[-+]?\d*\.\d+|\d+", line)
                if vals:
                    schedules["day"][current_name]["values"].extend([float(v) for v in vals])
            elif line.startswith("TYPE"):
                pass # Ignore type for now
            elif "=" in line and "VALUES" not in line and "TYPE" not in line and ".." not in line:
                # Likely start of new command or property we don't care about, stop parsing this block
                current_block = None
                
        elif current_block == "week":
            # Look for DAY-SCHEDULES = ( "DayName", ... )
            if "DAY-SCHEDULES" in line:
                # Extract names in quotes
                refs = re.findall(r'"([^"]+)"', line)
                if refs:
                    schedules["week"][current_name]["days"].extend(refs)
            elif "=" in line and "DAY-SCHEDULES" not in line and ".." not in line:
                current_block = None

    return schedules

def parse_dhw_loop(inp_content):
    """
    Finds CIRCULATION-LOOPs with TYPE = DHW and extracts properties.
    """
    loops = []
    
    # Split by ".." which ends a command in DOE-2
    commands = inp_content.split("..")
    
    for cmd in commands:
        if "CIRCULATION-LOOP" in cmd and "TYPE             = DHW" in cmd:
            loop_data = {}
            # Extract Name
            name_match = re.search(r'"([^"]+)"\s*=\s*CIRCULATION-LOOP', cmd, re.IGNORECASE)
            if name_match:
                loop_data["name"] = name_match.group(1)
            
            # Extract Process Flow
            flow_match = re.search(r'PROCESS-FLOW\s*=\s*([\d\.]+)', cmd, re.IGNORECASE)
            if flow_match:
                loop_data["flow"] = float(flow_match.group(1))
            
            # Extract Schedule
            sch_match = re.search(r'PROCESS-FLOW-SCH\s*=\s*"([^"]+)"', cmd, re.IGNORECASE)
            if sch_match:
                loop_data["schedule"] = sch_match.group(1)
                
            loops.append(loop_data)
            
    return loops

def verify_gym_dhw_schedule_implementation(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    # 1. Retrieve Result JSON and INP File
    result_path = "C:\\Users\\Docker\\task_result.json"
    inp_path = "C:\\Users\\Docker\\Documents\\eQUEST 3-65 Projects\\4StoreyBuilding\\4StoreyBuilding.inp"
    
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_inp = tempfile.NamedTemporaryFile(delete=False, suffix='.inp')
    
    try:
        copy_from_env(result_path, temp_result.name)
        copy_from_env(inp_path, temp_inp.name)
        
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
            
        with open(temp_inp.name, 'r', encoding='latin-1') as f: # INP often not UTF-8
            inp_content = f.read()
            
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task files: {str(e)}"}
    finally:
        if os.path.exists(temp_result.name): os.unlink(temp_result.name)
        if os.path.exists(temp_inp.name): os.unlink(temp_inp.name)

    score = 0
    feedback = []

    # 2. Verify Simulation Run (10 pts)
    if result_data.get("sim_file_is_new"):
        score += 10
        feedback.append("Simulation ran successfully (+10).")
    else:
        feedback.append("Simulation did not run during task.")

    # 3. Parse INP
    schedules = parse_inp_schedules(inp_content)
    loops = parse_dhw_loop(inp_content)
    
    # 4. Find valid Gym Day Schedule (30 pts)
    # Target: 0.1 base, 1.0 at hours 7-9 (indices 6-8 approx) and 17-19 (indices 16-18)
    # DOE-2 hours are 1-24. Index 0 is Hour 1.
    # 7:00-8:00 is Hour 8 -> Index 7. 
    # Let's look for the pattern loosely.
    
    valid_day_sched = None
    for name, data in schedules["day"].items():
        vals = data.get("values", [])
        if len(vals) < 24: continue
        
        # Check peaks: Index 6,7,8 (7am-9am range) and 16,17,18 (5pm-7pm range)
        # We look for at least two '1.0' values in morning and two in evening
        morning_peak = any(v > 0.9 for v in vals[6:9])
        evening_peak = any(v > 0.9 for v in vals[16:19])
        
        # Check base: Most other values should be low
        # Count values < 0.2
        low_vals = sum(1 for v in vals if v < 0.2)
        
        if morning_peak and evening_peak and low_vals > 10:
            valid_day_sched = name
            break
            
    if valid_day_sched:
        score += 30
        feedback.append(f"Valid Gym Day Schedule found: '{valid_day_sched}' (+30).")
    else:
        feedback.append("No Day Schedule found matching the Morning/Evening peak profile.")

    # 5. Find valid Week Schedule (10 pts)
    valid_week_sched = None
    if valid_day_sched:
        for name, data in schedules["week"].items():
            days = data.get("days", [])
            # Check if it references our valid day schedule
            if any(valid_day_sched in d for d in days):
                valid_week_sched = name
                break
    
    if valid_week_sched:
        score += 10
        feedback.append(f"Valid Week Schedule found: '{valid_week_sched}' (+10).")
    else:
        feedback.append("No Week Schedule found linking to the Gym Day Schedule.")

    # 6. Check DHW Loop (20 pts Flow, 30 pts Assignment)
    dhw_loop = None
    if loops:
        dhw_loop = loops[0] # Assuming one DHW loop or taking first
    
    if dhw_loop:
        # Check Flow
        flow = dhw_loop.get("flow", 0)
        if 4.9 <= flow <= 5.1:
            score += 20
            feedback.append(f"DHW Loop Flow updated to {flow} GPM (+20).")
        else:
            feedback.append(f"DHW Loop Flow is {flow} GPM (Expected 5.0).")
            
        # Check Assignment
        assigned_sched = dhw_loop.get("schedule", "")
        # Remove quotes if present
        assigned_sched = assigned_sched.strip('"')
        
        if valid_week_sched and assigned_sched == valid_week_sched:
            score += 30
            feedback.append(f"Correct Week Schedule assigned to DHW Loop (+30).")
        elif assigned_sched:
             # Partial credit if they assigned *something* related to gym, but we enforce correctness
             feedback.append(f"DHW Loop has schedule '{assigned_sched}' assigned (Expected '{valid_week_sched}').")
        else:
             feedback.append("No schedule assigned to DHW Loop.")
    else:
        feedback.append("DHW Loop not found.")

    passed = (score >= 60) and result_data.get("sim_file_is_new")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }