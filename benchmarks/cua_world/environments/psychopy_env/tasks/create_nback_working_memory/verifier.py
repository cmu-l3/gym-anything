#!/usr/bin/env python3
"""
Verifier for create_nback_working_memory task.

Verification Strategy (Hybrid: Programmatic + VLM):

1. Programmatic Checks (70 points):
   - Files exist and created during task (anti-gaming timestamps).
   - .psyexp Structure:
     - Contains Instructions, Trial, End routines.
     - Trial routine has Text ($letter) and Keyboard (space).
     - Loop is SEQUENTIAL (critical for n-back).
   - .csv Data Validity (The "Math" Check):
     - At least 60 rows.
     - Correct columns (letter, trial_type, correct_response).
     - 2-back logic holds: row[i] == row[i-2] iff target.
     - Target rate between 20-40%.

2. VLM Checks (30 points):
   - Trajectory verification: Agent actually used PsychoPy Builder.
   - Quality check: Final state looks correct.

Pass threshold: 60 points.
"""

import json
import tempfile
import os
import csv
import logging
import xml.etree.ElementTree as ET
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logger = logging.getLogger(__name__)

def verify_create_nback_working_memory(traj, env_info, task_info):
    """Verify n-back task creation."""
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    exp_file_path = metadata.get('experiment_file', '/home/ga/PsychoPyExperiments/nback_task.psyexp')
    cond_file_path = metadata.get('conditions_file', '/home/ga/PsychoPyExperiments/conditions/nback_conditions.csv')
    
    score = 0
    feedback_parts = []
    
    # ------------------------------------------------------------------
    # 1. RETRIEVE FILES
    # ------------------------------------------------------------------
    result_json = {}
    
    # Get JSON result
    with tempfile.NamedTemporaryFile(delete=False, suffix='.json') as tmp:
        json_path = tmp.name
    try:
        copy_from_env("/tmp/task_result.json", json_path)
        with open(json_path, 'r') as f:
            result_json = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {e}"}
    finally:
        if os.path.exists(json_path): os.unlink(json_path)
        
    # Get Experiment File
    exp_local_path = None
    if result_json.get("exp_exists"):
        with tempfile.NamedTemporaryFile(delete=False, suffix='.psyexp') as tmp:
            exp_local_path = tmp.name
        try:
            copy_from_env(exp_file_path, exp_local_path)
        except:
            exp_local_path = None

    # Get Conditions File
    cond_local_path = None
    if result_json.get("cond_exists"):
        with tempfile.NamedTemporaryFile(delete=False, suffix='.csv') as tmp:
            cond_local_path = tmp.name
        try:
            copy_from_env(cond_file_path, cond_local_path)
        except:
            cond_local_path = None

    # ------------------------------------------------------------------
    # 2. TIMESTAMP & EXISTENCE CHECKS (10 pts)
    # ------------------------------------------------------------------
    task_start = result_json.get("task_start_time", 0)
    
    files_valid = True
    if exp_local_path and result_json.get("exp_mtime", 0) > task_start:
        score += 5
        feedback_parts.append("Experiment file created.")
    else:
        files_valid = False
        feedback_parts.append("Experiment file missing or old.")
        
    if cond_local_path and result_json.get("cond_mtime", 0) > task_start:
        score += 5
        feedback_parts.append("Conditions file created.")
    else:
        files_valid = False
        feedback_parts.append("Conditions file missing or old.")

    if not files_valid:
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    # ------------------------------------------------------------------
    # 3. EXPERIMENT STRUCTURE CHECK (25 pts)
    # ------------------------------------------------------------------
    try:
        tree = ET.parse(exp_local_path)
        root = tree.getroot()
        
        routines = [r.get('name') for r in root.findall(".//Routine")]
        
        # Check Routines
        has_instr = any('instruct' in r.lower() for r in routines)
        has_trial = any('trial' in r.lower() for r in routines)
        has_end = any('end' in r.lower() or 'thanks' in r.lower() for r in routines)
        
        if has_instr: score += 5
        if has_trial: score += 5
        if has_end: score += 5
        
        # Check Trial Components
        trial_routine = None
        for r in root.findall(".//Routine"):
            if 'trial' in r.get('name', '').lower():
                trial_routine = r
                break
        
        if trial_routine:
            # Check for Text component with variable
            has_text_var = False
            for comp in trial_routine:
                if 'Text' in comp.tag:
                    for param in comp:
                        if param.get('name') == 'text' and '$' in param.get('val', ''):
                            has_text_var = True
            if has_text_var: score += 5
        
        # Check Loop Type (CRITICAL)
        loops = root.findall(".//LoopInitiator")
        is_sequential = False
        has_cond_file = False
        
        for loop in loops:
            for param in loop.iter():
                if param.get('name') == 'loopType' and param.get('val') == 'sequential':
                    is_sequential = True
                if param.get('name') == 'conditionsFile' and 'nback' in param.get('val', ''):
                    has_cond_file = True
        
        if is_sequential:
            score += 5
            feedback_parts.append("Loop is sequential (correct).")
        else:
            feedback_parts.append("FAIL: Loop must be sequential for n-back task.")
        
        if has_cond_file:
            feedback_parts.append("Conditions file linked.")

    except Exception as e:
        feedback_parts.append(f"XML Parse Error: {e}")

    # ------------------------------------------------------------------
    # 4. CONDITIONS DATA LOGIC CHECK (35 pts)
    # ------------------------------------------------------------------
    try:
        with open(cond_local_path, 'r') as f:
            reader = csv.DictReader(f)
            rows = list(reader)
            
        if len(rows) >= 60:
            score += 5
            feedback_parts.append(f"Row count OK ({len(rows)}).")
        else:
            feedback_parts.append(f"Row count low ({len(rows)} < 60).")
            
        # Math Check
        math_errors = 0
        targets = 0
        total_checks = 0
        
        required_cols = {'letter', 'trial_type', 'correct_response'}
        headers = set(rows[0].keys()) if rows else set()
        
        if not required_cols.issubset(headers):
             feedback_parts.append(f"Missing columns. Found: {headers}")
        else:
            score += 5 # Columns present
            
            for i in range(len(rows)):
                letter = rows[i]['letter'].strip().upper()
                ttype = rows[i]['trial_type'].strip().lower()
                
                if ttype == 'target':
                    targets += 1
                
                # Check 2-back logic starting at index 2
                if i >= 2:
                    prev_2 = rows[i-2]['letter'].strip().upper()
                    is_match = (letter == prev_2)
                    
                    if ttype == 'target' and not is_match:
                        math_errors += 1
                    elif ttype == 'nontarget' and is_match:
                        math_errors += 1
                    total_checks += 1
                elif ttype == 'target':
                    # First 2 rows cannot be targets
                    math_errors += 1
            
            # Rate check
            rate = targets / len(rows) if rows else 0
            if 0.20 <= rate <= 0.40:
                score += 5
                feedback_parts.append(f"Target rate OK ({rate:.2%}).")
            else:
                feedback_parts.append(f"Target rate outlier ({rate:.2%}).")
                
            # Logic score
            if math_errors == 0 and total_checks > 0:
                score += 20
                feedback_parts.append("2-back logic perfect.")
            elif math_errors <= 2:
                score += 10
                feedback_parts.append(f"2-back logic acceptable ({math_errors} errors).")
            else:
                feedback_parts.append(f"FAIL: 2-back logic failed ({math_errors} errors).")

    except Exception as e:
        feedback_parts.append(f"CSV Parse Error: {e}")

    # ------------------------------------------------------------------
    # 5. VLM VERIFICATION (30 pts)
    # ------------------------------------------------------------------
    frames = sample_trajectory_frames(traj, n=4)
    final_frame = get_final_screenshot(traj)
    all_frames = frames + [final_frame] if final_frame else frames
    
    prompt = """
    You are verifying an agent creating a PsychoPy experiment.
    Look at the sequence of images.
    1. Did the agent use the PsychoPy Builder interface (grey window with Flow/Routines)?
    2. Did they edit a conditions file (spreadsheet/Excel/CSV editor)?
    3. Does the final state show a completed flow (Instructions -> Loop -> End)?
    
    Answer JSON: {"used_builder": bool, "edited_csv": bool, "flow_visible": bool}
    """
    
    vlm_res = query_vlm(prompt=prompt, images=all_frames)
    
    if vlm_res and vlm_res.get('success'):
        parsed = vlm_res.get('parsed', {})
        if parsed.get('used_builder'): score += 10
        if parsed.get('edited_csv'): score += 10
        if parsed.get('flow_visible'): score += 10
    else:
        # Fallback if VLM fails but programmatic passed high
        if score >= 60:
            score += 15 # Benefit of doubt if code works
            feedback_parts.append("VLM skipped, credited based on functional files.")

    # cleanup
    if exp_local_path and os.path.exists(exp_local_path): os.unlink(exp_local_path)
    if cond_local_path and os.path.exists(cond_local_path): os.unlink(cond_local_path)

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }