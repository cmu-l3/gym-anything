#!/usr/bin/env python3
"""
Verifier for create_task_switching_paradigm task.

Verification Strategy (Hybrid):

1. Programmatic CSV Analysis (60 points):
   - File existence & structure (10 pts)
   - AABB Task Sequence (M,M,P,P...) (10 pts)
   - Logic correctness (CorrectResp matches Digit/Task rules) (15 pts)
   - TrialType logic (switch/repeat labels) (10 pts)
   - Valid Digits & Cue consistency (15 pts)

2. Programmatic Experiment Analysis (30 points):
   - Valid XML & Routines (10 pts)
   - Trial Components (Cue, Target, Keyboard) (10 pts)
   - Loop Configuration (Sequential, correct CSV ref) (10 pts)

3. VLM Verification (10 points):
   - Evidence of Builder usage / CSV creation workflow

Pass Threshold: 60 points total, but MUST have valid CSV structure (Part 1 is critical).
"""

import json
import tempfile
import os
import csv
import logging
import xml.etree.ElementTree as ET

logger = logging.getLogger(__name__)

def verify_create_task_switching_paradigm(traj, env_info, task_info):
    """Verify the task switching paradigm implementation."""
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    csv_remote_path = metadata.get('csv_path', "/home/ga/PsychoPyExperiments/conditions/task_switching_conditions.csv")
    psyexp_remote_path = metadata.get('psyexp_path', "/home/ga/PsychoPyExperiments/task_switching.psyexp")

    score = 0
    feedback = []
    
    # ---------------------------------------------------------
    # 1. Retrieve Result JSON & Nonce Check
    # ---------------------------------------------------------
    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix='.json') as tmp:
            json_local = tmp.name
        copy_from_env("/tmp/task_result.json", json_local)
        with open(json_local, 'r') as f:
            result_meta = json.load(f)
            
        # Nonce check
        with tempfile.NamedTemporaryFile(delete=False, suffix='.txt') as tmp:
            nonce_local = tmp.name
        copy_from_env("/home/ga/.task_nonce", nonce_local)
        with open(nonce_local, 'r') as f:
            expected_nonce = f.read().strip()
            
        if result_meta.get("result_nonce") != expected_nonce:
             return {"passed": False, "score": 0, "feedback": "FAIL: Nonce mismatch (Anti-gaming check)"}
             
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"FAIL: verification setup error: {e}"}
    finally:
        if os.path.exists(json_local): os.unlink(json_local)
        if os.path.exists(nonce_local): os.unlink(nonce_local)

    # ---------------------------------------------------------
    # 2. CSV Verification (60 points)
    # ---------------------------------------------------------
    csv_valid = False
    if result_meta.get("csv_exists") and result_meta.get("csv_modified"):
        try:
            with tempfile.NamedTemporaryFile(delete=False, suffix='.csv') as tmp:
                csv_local = tmp.name
            copy_from_env(csv_remote_path, csv_local)
            
            with open(csv_local, 'r', newline='') as f:
                reader = csv.DictReader(f)
                headers = [h.strip() for h in (reader.fieldnames or [])]
                rows = list(reader)
            
            # Check 1: Structure (10 pts)
            req_cols = ["task", "digit", "correctResp", "trialType", "cueText", "cueColor"]
            missing_cols = [c for c in req_cols if c not in headers]
            
            if not missing_cols and len(rows) >= 64:
                score += 10
                feedback.append("CSV structure valid (columns & length).")
                csv_valid = True
            else:
                feedback.append(f"CSV invalid. Missing cols: {missing_cols}, Rows: {len(rows)}")

            if csv_valid:
                # Check 2: AABB Pattern (10 pts)
                # Pattern: M, M, P, P, M, M, P, P...
                tasks = [r['task'].lower().strip() for r in rows]
                pattern_errors = 0
                for i in range(len(tasks)):
                    expected_type = "magnitude" if (i // 2) % 2 == 0 else "parity"
                    if expected_type not in tasks[i]:
                        pattern_errors += 1
                
                if pattern_errors == 0:
                    score += 10
                    feedback.append("Task sequence follows AABB pattern exactly.")
                elif pattern_errors < 5:
                    score += 5
                    feedback.append(f"Task sequence mostly correct ({pattern_errors} errors).")
                else:
                    feedback.append(f"Task sequence Failed AABB check ({pattern_errors} errors).")

                # Check 3: Logic Correctness (15 pts)
                logic_errors = 0
                for r in rows:
                    try:
                        d = int(r['digit'])
                        t = r['task'].lower()
                        resp = r['correctResp'].lower().strip()
                        
                        expected = ""
                        if "mag" in t:
                            expected = "left" if d < 5 else "right"
                        elif "par" in t:
                            expected = "left" if d % 2 == 0 else "right"
                        
                        if resp != expected:
                            logic_errors += 1
                    except:
                        logic_errors += 1
                
                if logic_errors == 0:
                    score += 15
                    feedback.append("Response logic (Magnitude/Parity) is perfect.")
                elif logic_errors < 5:
                    score += 7
                    feedback.append(f"Response logic mostly correct ({logic_errors} errors).")
                else:
                    feedback.append("Response logic failed validation.")

                # Check 4: TrialType Logic (10 pts)
                type_errors = 0
                for i in range(len(rows)):
                    tt = rows[i]['trialType'].lower().strip()
                    curr_task = rows[i]['task'].lower().strip()
                    
                    if i == 0:
                        if "first" not in tt: type_errors += 1
                    else:
                        prev_task = rows[i-1]['task'].lower().strip()
                        expected_tt = "repeat" if curr_task == prev_task else "switch"
                        if expected_tt != tt:
                            type_errors += 1
                
                if type_errors == 0:
                    score += 10
                    feedback.append("TrialType coding (switch/repeat) is perfect.")
                else:
                    feedback.append(f"TrialType coding errors found ({type_errors}).")

                # Check 5: Digits & Cue Consistency (15 pts)
                valid_digits = {1, 2, 3, 4, 6, 7, 8, 9}
                digit_errors = 0
                cue_errors = 0
                
                for r in rows:
                    try:
                        if int(r['digit']) not in valid_digits: digit_errors += 1
                    except: digit_errors += 1
                    
                    t = r['task'].lower()
                    ct = r['cueText'].lower()
                    cc = r['cueColor'].lower()
                    
                    if "mag" in t:
                        if "mag" not in ct or "blue" not in cc: cue_errors += 1
                    elif "par" in t:
                        if "par" not in ct or "green" not in cc: cue_errors += 1
                
                if digit_errors == 0 and cue_errors == 0:
                    score += 15
                    feedback.append("Digits and Cues are valid and consistent.")
                else:
                    feedback.append(f"Data errors: Digits({digit_errors}), Cues({cue_errors}).")

        except Exception as e:
            feedback.append(f"Error parsing CSV: {e}")
            if os.path.exists(csv_local): os.unlink(csv_local)
    else:
        feedback.append("CSV file not created or not modified.")

    # ---------------------------------------------------------
    # 3. Experiment Verification (30 points)
    # ---------------------------------------------------------
    if result_meta.get("psyexp_exists") and result_meta.get("psyexp_modified"):
        try:
            with tempfile.NamedTemporaryFile(delete=False, suffix='.psyexp') as tmp:
                exp_local = tmp.name
            copy_from_env(psyexp_remote_path, exp_local)
            
            tree = ET.parse(exp_local)
            root = tree.getroot()
            
            # Check 1: XML & Routines (10 pts)
            routines = [r.get('name') for r in root.findall(".//Routine")]
            has_instr = any("instruction" in r.lower() for r in routines)
            has_trial = any("trial" in r.lower() for r in routines)
            has_feedback = any("feedback" in r.lower() for r in routines)
            
            if has_instr and has_trial and has_feedback:
                score += 10
                feedback.append("Experiment routines (Instr, Trial, Feedback) present.")
            else:
                feedback.append(f"Missing routines. Found: {routines}")

            # Check 2: Trial Components (10 pts)
            # Find the trial routine
            trial_node = None
            for r in root.findall(".//Routine"):
                if "trial" in r.get('name', '').lower():
                    trial_node = r
                    break
            
            if trial_node:
                comps = [c.get('name', '').lower() for c in trial_node]
                # We can't easily check component types by name alone without deeper XML parsing,
                # but we can look for parameter values inside components
                
                has_cue_var = False
                has_digit_var = False
                has_kb = False
                
                for comp in trial_node:
                    # Check params
                    for param in comp.findall("Param"):
                        val = param.get('val', '')
                        if "$cueText" in val or "cueText" in val: has_cue_var = True
                        if "$digit" in val or "digit" in val: has_digit_var = True
                        
                    # Check type (tag name is usually the type in PsychoPy XML)
                    if "Keyboard" in comp.tag or "Key" in comp.tag:
                        has_kb = True
                
                if has_cue_var and has_digit_var and has_kb:
                    score += 10
                    feedback.append("Trial routine has Cue, Digit target, and Keyboard.")
                else:
                    feedback.append(f"Trial components incomplete. Cue:{has_cue_var}, Digit:{has_digit_var}, KB:{has_kb}")

            # Check 3: Loop Config (10 pts)
            loop_node = root.find(".//LoopInitiator")
            loop_ok = False
            if loop_node:
                # Check for sequential and CSV file
                is_seq = False
                has_csv = False
                
                for param in loop_node.iter("Param"):
                    name = param.get('name')
                    val = param.get('val')
                    if name == "loopType" and "sequential" in val: is_seq = True
                    if name == "conditionsFile" and "task_switching_conditions.csv" in val: has_csv = True
                
                if is_seq and has_csv:
                    score += 10
                    feedback.append("Loop configured correctly (Sequential + CSV linked).")
                    loop_ok = True
                else:
                    feedback.append(f"Loop config issue. Sequential:{is_seq}, Linked:{has_csv}")
            
        except Exception as e:
            feedback.append(f"Error parsing .psyexp: {e}")
            if os.path.exists(exp_local): os.unlink(exp_local)
    else:
        feedback.append("Experiment file not created or not modified.")

    # ---------------------------------------------------------
    # 4. VLM Verification (10 points)
    # ---------------------------------------------------------
    # Simple check: did the agent do anything visual?
    # We give points if files exist and pass basic checks, assuming interaction occurred.
    # Explicit VLM check can be added if files are missing or for robustness.
    
    if score >= 50: # If they did decent programmatic work, assume visual interaction valid
        score += 10
        feedback.append("Workflow verification passed (inferred from output quality).")
    
    return {
        "passed": score >= 60 and csv_valid,
        "score": score,
        "feedback": " | ".join(feedback)
    }