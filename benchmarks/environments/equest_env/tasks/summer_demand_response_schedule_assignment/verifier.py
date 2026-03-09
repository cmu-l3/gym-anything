#!/usr/bin/env python3
"""
Verifier for summer_demand_response_schedule_assignment task.

Checks:
1. New DAY-SCHEDULE-PD 'DR-Cooling-Day' exists.
2. 'DR-Cooling-Day' has correct hourly VALUES (75, 72, 80, 75 profile).
3. The WEEK-SCHEDULE-PD used by 'G.South Perim Spc' assigns 'DR-Cooling-Day' to Mon-Fri.
4. Simulation was run during the session.
"""

import os
import json
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

RESULT_JSON_PATH = "C:\\Users\\Docker\\task_result.json"
RESULT_INP_PATH = "C:\\Users\\Docker\\task_result.inp"

def verify_summer_demand_response_schedule_assignment(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Temp files for artifacts
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_inp = tempfile.NamedTemporaryFile(delete=False, suffix='.inp')
    
    try:
        # 1. Get JSON result
        copy_from_env(RESULT_JSON_PATH, temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
            
        # 2. Get INP file
        copy_from_env(RESULT_INP_PATH, temp_inp.name)
        with open(temp_inp.name, 'r', encoding='utf-8', errors='ignore') as f:
            inp_content = f.read()
            
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task artifacts: {str(e)}"}
    finally:
        if os.path.exists(temp_json.name): os.unlink(temp_json.name)
        if os.path.exists(temp_inp.name): os.unlink(temp_inp.name)

    score = 0
    feedback = []

    # --- Criterion 1: Simulation Run (10 pts) ---
    if result_data.get('sim_file_is_new'):
        score += 10
        feedback.append("Simulation ran successfully (+10).")
    else:
        feedback.append("Simulation NOT run during session (0/10).")

    # --- Criterion 2: Schedule Creation (20 pts) ---
    # Look for "DR-Cooling-Day" = DAY-SCHEDULE-PD
    day_sch_regex = re.compile(r'"DR-Cooling-Day"\s*=\s*DAY-SCHEDULE-PD', re.IGNORECASE)
    if day_sch_regex.search(inp_content):
        score += 20
        feedback.append("'DR-Cooling-Day' schedule created (+20).")
    else:
        return {"passed": False, "score": score, "feedback": "Fail: 'DR-Cooling-Day' schedule not found in project. " + " ".join(feedback)}

    # --- Criterion 3: Profile Accuracy (40 pts) ---
    # Extract VALUES = (...) block for DR-Cooling-Day
    # This is tricky with regex across lines. We find the definition and grab content until next definition.
    
    # 1. Find the start index
    match = day_sch_regex.search(inp_content)
    start_idx = match.end()
    
    # 2. Find the VALUES keyword after start_idx
    values_match = re.search(r'VALUES\s*=\s*\((.*?)\)', inp_content[start_idx:], re.DOTALL | re.IGNORECASE)
    
    profile_correct = False
    if values_match:
        values_str = values_match.group(1)
        # Clean up newlines and commas
        values_cleaned = re.sub(r'[\s,]+', ' ', values_str).strip()
        values_list = []
        try:
            values_list = [float(v) for v in values_cleaned.split()]
        except ValueError:
            pass

        # Expected profile:
        # Hours 1-12 (12 items): 75
        # Hours 13-16 (4 items): 72
        # Hours 17-20 (4 items): 80
        # Hours 21-24 (4 items): 75
        expected = [75]*12 + [72]*4 + [80]*4 + [75]*4
        
        if len(values_list) == 24:
            # Check with tolerance
            matches = [abs(v - e) < 0.1 for v, e in zip(values_list, expected)]
            if all(matches):
                score += 40
                feedback.append("Temperature profile values match exactly (+40).")
                profile_correct = True
            else:
                feedback.append(f"Profile values incorrect. Found: {values_list[:5]}... Expected: {expected[:5]}...")
        else:
            feedback.append(f"Profile length incorrect (found {len(values_list)}, expected 24).")
    else:
        feedback.append("Could not parse VALUES from DR-Cooling-Day.")

    # --- Criterion 4: Assignment (30 pts) ---
    # 1. Find G.South Perim Spc to get its Cool Schedule
    # "G.South Perim Spc" = SPACE ... COOL-TEMP-SCH = "Cool-C-Sch" (Example)
    zone_regex = re.compile(r'"G\.South Perim Spc"\s*=\s*SPACE', re.IGNORECASE)
    zone_match = zone_regex.search(inp_content)
    
    assignment_correct = False
    
    if zone_match:
        zone_start = zone_match.end()
        # Find next COOL-TEMP-SCH
        # Limit search to avoid jumping to next space
        next_space = re.search(r'\s*=\s*SPACE', inp_content[zone_start:], re.IGNORECASE)
        limit = next_space.start() if next_space else len(inp_content) - zone_start
        
        cool_sch_match = re.search(r'COOL-TEMP-SCH\s*=\s*"([^"]+)"', inp_content[zone_start:zone_start+limit], re.IGNORECASE)
        
        if cool_sch_match:
            annual_sch_name = cool_sch_match.group(1)
            
            # 2. Find Annual Schedule to get Week Schedule
            # "Cool-C-Sch" = SCHEDULE-PD ... WEEK-SCHEDULES = ( "Cool-Wk", ... )
            ann_regex = re.compile(f'"{re.escape(annual_sch_name)}"\s*=\s*SCHEDULE-PD', re.IGNORECASE)
            ann_match = ann_regex.search(inp_content)
            
            if ann_match:
                ann_start = ann_match.end()
                wk_sch_match = re.search(r'WEEK-SCHEDULES\s*=\s*\(\s*"([^"]+)"', inp_content[ann_start:], re.IGNORECASE)
                
                if wk_sch_match:
                    week_sch_name = wk_sch_match.group(1)
                    
                    # 3. Find Week Schedule to check assignments
                    # "Cool-Wk" = WEEK-SCHEDULE-PD ... DAY-SCHEDULES = ( "DR-Cooling-Day", "DR-Cooling-Day", ... )
                    wk_regex = re.compile(f'"{re.escape(week_sch_name)}"\s*=\s*WEEK-SCHEDULE-PD', re.IGNORECASE)
                    wk_match = wk_regex.search(inp_content)
                    
                    if wk_match:
                        wk_start = wk_match.end()
                        day_schs_match = re.search(r'DAY-SCHEDULES\s*=\s*\((.*?)\)', inp_content[wk_start:], re.DOTALL | re.IGNORECASE)
                        
                        if day_schs_match:
                            days_str = day_schs_match.group(1)
                            # Split by comma/whitespace and strip quotes
                            days = [d.strip().strip('"') for d in re.split(r'[\s,]+', days_str) if d.strip()]
                            
                            # Check Mon-Fri (indices 0-4)
                            if len(days) >= 5:
                                weekdays = days[0:5]
                                if all(d.lower() == "dr-cooling-day" for d in weekdays):
                                    score += 30
                                    feedback.append("Schedule correctly assigned to Mon-Fri (+30).")
                                    assignment_correct = True
                                else:
                                    feedback.append(f"Assignment incorrect. Mon-Fri set to: {weekdays}.")
                            else:
                                feedback.append("Week schedule definition incomplete.")
                        else:
                            feedback.append("Could not parse DAY-SCHEDULES in week schedule.")
                    else:
                        feedback.append(f"Week schedule '{week_sch_name}' definition not found.")
                else:
                    feedback.append("Could not find WEEK-SCHEDULES in annual schedule.")
            else:
                feedback.append(f"Annual schedule '{annual_sch_name}' definition not found.")
        else:
            feedback.append("COOL-TEMP-SCH not found for G.South Perim Spc.")
    else:
        feedback.append("Zone 'G.South Perim Spc' not found.")

    passed = (score >= 70) and assignment_correct and profile_correct

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }