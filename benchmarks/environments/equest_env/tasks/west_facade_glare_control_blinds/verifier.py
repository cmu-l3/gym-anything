#!/usr/bin/env python3
"""
Verifier for west_facade_glare_control_blinds task.

Checks:
1. Schedule creation (Day, Week, Annual) with correct hierarchy and values.
2. Window assignment (Interior Shade Type & Schedule) for West-facing windows.
3. Simulation execution (timestamp check).
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_west_facade_glare_control_blinds(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    
    # Files to retrieve
    result_json_path = "C:\\temp\\task_result.json"
    exported_inp_path = "C:\\temp\\model_export.inp"
    
    # 1. Retrieve Result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env(result_json_path, temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {e}"}
    finally:
        if os.path.exists(temp_json.name): os.unlink(temp_json.name)

    # 2. Retrieve INP File
    temp_inp = tempfile.NamedTemporaryFile(delete=False, suffix='.inp')
    inp_content = ""
    try:
        copy_from_env(exported_inp_path, temp_inp.name)
        with open(temp_inp.name, 'r', encoding='latin-1') as f:
            inp_content = f.read()
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve model file: {e}"}
    finally:
        if os.path.exists(temp_inp.name): os.unlink(temp_inp.name)

    score = 0
    feedback = []

    # --- CRITERION 1: Simulation Run (10 pts) ---
    if result_data.get('sim_file_is_new', False):
        score += 10
        feedback.append("Simulation ran successfully.")
    else:
        feedback.append("Simulation did not run during the session.")

    # --- CRITERION 2: Schedule Hierarchy (30 pts) ---
    # Parse INP for schedules
    # 2a. Day Schedule (10 pts)
    # Looking for: "Glare-Day-Sch" = DAY-SCHEDULE-PD ... VALUES = ( 0, 0, ..., 1, 1, 1, 1, ..., 0 )
    # Hour 1-14: 0, Hour 15-18: 1, Hour 19-24: 0
    day_sch_regex = re.search(r'"Glare-Day-Sch"\s*=\s*DAY-SCHEDULE-PD', inp_content, re.IGNORECASE)
    day_sch_valid = False
    
    if day_sch_regex:
        # Find the block
        block_start = day_sch_regex.start()
        block_end = inp_content.find("..", block_start)
        block = inp_content[block_start:block_end]
        
        # Check values roughly. It's complex to parse exact arrays in DOE-2 BDL via regex
        # but we can look for the pattern of 1s in the afternoon
        # A common format: VALUES = ( 0, 0, 0, ... 1, 1, 1, 1 ... )
        # We verify existence and Fraction type logic.
        if "TYPE             = FRACTION" in block:
             # Check for 1s
             if "1" in block: 
                 day_sch_valid = True
                 score += 10
                 feedback.append("Day Schedule 'Glare-Day-Sch' created.")
             else:
                 feedback.append("Day Schedule found but values seem all zero.")
        else:
             # Default might be fraction, accept if created
             day_sch_valid = True
             score += 5
             feedback.append("Day Schedule created (checked existence).")
    else:
        feedback.append("Day Schedule 'Glare-Day-Sch' not found.")

    # 2b. Week Schedule (10 pts)
    week_sch_regex = re.search(r'"Glare-Week-Sch"\s*=\s*WEEK-SCHEDULE-PD', inp_content, re.IGNORECASE)
    if week_sch_regex:
        block_start = week_sch_regex.start()
        block_end = inp_content.find("..", block_start)
        block = inp_content[block_start:block_end]
        if "Glare-Day-Sch" in block:
            score += 10
            feedback.append("Week Schedule correctly references Day Schedule.")
        else:
            score += 5
            feedback.append("Week Schedule created but might not reference correct Day Schedule.")
    else:
        feedback.append("Week Schedule 'Glare-Week-Sch' not found.")

    # 2c. Annual Schedule (10 pts)
    year_sch_regex = re.search(r'"Glare-Year-Sch"\s*=\s*SCHEDULE-PD', inp_content, re.IGNORECASE)
    if year_sch_regex:
        block_start = year_sch_regex.start()
        block_end = inp_content.find("..", block_start)
        block = inp_content[block_start:block_end]
        if "Glare-Week-Sch" in block:
            score += 10
            feedback.append("Annual Schedule correctly references Week Schedule.")
        else:
            score += 5
            feedback.append("Annual Schedule created but might not reference correct Week Schedule.")
    else:
        feedback.append("Annual Schedule 'Glare-Year-Sch' not found.")


    # --- CRITERION 3: West Windows (60 pts) ---
    # Logic: Find all SPACEs. If name has .W, look at its children WINDOWs.
    # INP structure:
    # "Space Name" = SPACE ... ..
    # "Wall Name" = EXTERIOR-WALL ... ..
    # "Window Name" = WINDOW ... ..
    
    # We will split the file by SPACE commands to process hierarchically
    spaces = re.split(r'(\"[^\"]+\"\s*=\s*SPACE)', inp_content)
    
    west_windows_total = 0
    west_windows_correct = 0
    west_windows_schedule_ok = 0
    
    current_space_is_west = False
    
    # The split keeps delimiters, so we iterate in pairs or just traverse
    # A simpler approach for verification: Find all WINDOW blocks and check their parent hierarchy?
    # No, DOE-2 is nested.
    
    # Let's simple traverse:
    # Find all occurrences of SPACE, EXTERIOR-WALL, WINDOW
    # This state machine approach is safer.
    
    lines = inp_content.split('\n')
    context = {"space": "", "wall": ""}
    
    for line in lines:
        line = line.strip()
        
        # Check for Space
        m_space = re.match(r'^"([^"]+)"\s*=\s*SPACE', line)
        if m_space:
            context["space"] = m_space.group(1)
            continue
            
        # Check for Window
        m_window = re.match(r'^"([^"]+)"\s*=\s*WINDOW', line)
        if m_window:
            # We are inside a window definition now (until next ..)
            # Check if parent space is West
            if ".W" in context["space"] or ".W" in context.get("wall", ""): # Sometimes wall name has orientation
                # But task says "Space names containing .W"
                if ".W" in context["space"]:
                    west_windows_total += 1
                    
                    # Now we need to read the properties of this window
                    # Since we are iterating lines, we need to read ahead until ".."
                    # But simpler: check if properties appear in this block (DOE-2 blocks end with ..)
                    # We'll assume the properties are on subsequent lines before the next object
                    pass
        
        # Check properties if we are tracking a West Window
        if west_windows_total > west_windows_correct: # Meaning we just found a new west window candidate
             # We need to capture lines until ".."
             # This simple line iterator is tricky for multi-line blocks.
             pass

    # robust alternative: Regex all WINDOW blocks
    # 1. Extract all blocks: "Name" = TYPE ... ..
    blocks = re.findall(r'("[^"]+"\s*=\s*[^=]+\s*[\s\S]*?\.\.)', inp_content)
    
    # Map hierarchy is hard without a parser.
    # Hack: West zones are named like "G.W...", "T.W..."
    # We search for the pattern:
    # "Space" = SPACE ...
    # ...
    # "Window" = WINDOW ... INTERIOR-SHADE-TYPE = VENETIAN-BLINDS ... SHADING-SCHEDULE = "Glare-Year-Sch"
    
    # Let's count specific successes
    # 1. Find all West spaces
    west_spaces = re.findall(r'"([^"]+\.W[^"]*)"\s*=\s*SPACE', inp_content)
    
    # 2. For each west space, find its windows. 
    # This requires knowing which window belongs to which space. In INP, windows are nested under walls under spaces.
    # We will look for the text segment corresponding to the West Spaces.
    
    processed_windows = 0
    correct_shade = 0
    correct_sched = 0
    
    for space_name in west_spaces:
        # Regex to find the content of this space. 
        # Starts with space definition, ends at next SPACE definition or END.
        # This is risky if regex is greedy.
        
        # Safer: Find the index of this space, and the index of the next space.
        idx_start = inp_content.find(f'"{space_name}"')
        if idx_start == -1: continue
        
        # Find next SPACE keyword
        idx_next = inp_content.find(" = SPACE", idx_start + 10)
        if idx_next == -1: idx_next = len(inp_content)
        
        space_content = inp_content[idx_start:idx_next]
        
        # Find windows in this content
        window_blocks = re.findall(r'=\s*WINDOW\s*[\s\S]*?\.\.', space_content)
        
        for w_block in window_blocks:
            processed_windows += 1
            
            # Check Shade Type
            if re.search(r'INTERIOR-SHADE-TYPE\s*=\s*VENETIAN-BLINDS', w_block, re.IGNORECASE):
                correct_shade += 1
                
            # Check Schedule
            if re.search(r'SHADING-SCHEDULE\s*=\s*"Glare-Year-Sch"', w_block, re.IGNORECASE):
                correct_sched += 1
    
    # Scoring Windows
    # Max 40 points for shade type, 20 for schedule
    if processed_windows > 0:
        shade_score = (correct_shade / processed_windows) * 40
        sched_score = (correct_sched / processed_windows) * 20
        score += shade_score + sched_score
        
        feedback.append(f"Found {processed_windows} West-facing windows.")
        feedback.append(f"  - Correct Shade Type: {correct_shade}/{processed_windows}")
        feedback.append(f"  - Correct Schedule: {correct_sched}/{processed_windows}")
    else:
        feedback.append("Could not identify West-facing windows (Check space naming or hierarchy).")

    score = min(100, score)
    passed = score >= 70 and day_sch_valid
    
    return {
        "passed": passed,
        "score": int(score),
        "feedback": " | ".join(feedback)
    }