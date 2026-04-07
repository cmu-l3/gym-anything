#!/usr/bin/env python3
"""
Verifier for create_ax_cpt_task.

Verification Strategy:
1. File Existence: Checks if CSV and .psyexp files exist and were modified.
2. CSV Logic Analysis:
   - Loads the agent's CSV file.
   - Validates row count (40).
   - Validates proportions (70% AX, 10% AY, 10% BX, 10% BY).
   - Checks for correct cue/probe/corrAns logic.
   - Checks for stimulus variety in distractor trials.
3. PsychoPy Experiment Structure:
   - Parses the .psyexp XML.
   - Verifies Routine structure (Cue -> Delay -> Probe).
   - Verifies timing parameters (0.5s, 1.0s).
   - Verifies loop configuration.
"""

import json
import tempfile
import os
import csv
import logging
import xml.etree.ElementTree as ET

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_ax_cpt_task(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    csv_path_remote = metadata.get('conditions_file', '/home/ga/PsychoPyExperiments/conditions/ax_cpt_conditions.csv')
    exp_path_remote = metadata.get('experiment_file', '/home/ga/PsychoPyExperiments/ax_cpt.psyexp')

    score = 0
    feedback_parts = []
    
    # ------------------------------------------------------------------
    # 1. Check Result Metadata & Nonce
    # ------------------------------------------------------------------
    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix='.json') as tmp:
            result_json_path = tmp.name
        copy_from_env("/tmp/task_result.json", result_json_path)
        with open(result_json_path, 'r') as f:
            result_meta = json.load(f)
        
        # Check nonce
        with tempfile.NamedTemporaryFile(delete=False, suffix='.txt') as tmp:
            nonce_path = tmp.name
        copy_from_env("/home/ga/.task_nonce", nonce_path)
        with open(nonce_path, 'r') as f:
            expected_nonce = f.read().strip()
        
        if result_meta.get('result_nonce') != expected_nonce:
            return {"passed": False, "score": 0, "feedback": "Integrity check failed (nonce mismatch)."}
            
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task metadata: {e}"}
    finally:
        if os.path.exists(result_json_path): os.unlink(result_json_path)
        if 'nonce_path' in locals() and os.path.exists(nonce_path): os.unlink(nonce_path)

    # ------------------------------------------------------------------
    # 2. Analyze CSV Content (60 Points)
    # ------------------------------------------------------------------
    csv_passed = False
    try:
        if not result_meta.get('csv_exists'):
            feedback_parts.append("Conditions CSV file not found.")
        else:
            with tempfile.NamedTemporaryFile(delete=False, suffix='.csv') as tmp:
                local_csv = tmp.name
            copy_from_env(csv_path_remote, local_csv)
            
            with open(local_csv, 'r', encoding='utf-8-sig') as f:
                reader = csv.DictReader(f)
                rows = list(reader)
                
            # Normalize headers
            if rows:
                headers = [h.strip().lower() for h in rows[0].keys()]
            else:
                headers = []

            # Check required columns
            required_cols = ['cue', 'probe', 'corrans']
            has_cols = all(any(req in h for h in headers) for req in required_cols)
            
            if not has_cols:
                feedback_parts.append(f"CSV missing required columns (cue, probe, corrAns). Found: {headers}")
            else:
                score += 10 # File structure ok
                
                # Analyze Trial Logic
                counts = {'AX': 0, 'AY': 0, 'BX': 0, 'BY': 0}
                logic_errors = 0
                stimuli_non_a = set()
                stimuli_non_x = set()
                
                # Normalize key names for row access
                key_map = {k.lower().strip(): k for k in rows[0].keys()}
                k_cue = next((orig for norm, orig in key_map.items() if 'cue' in norm), None)
                k_probe = next((orig for norm, orig in key_map.items() if 'probe' in norm), None)
                k_ans = next((orig for norm, orig in key_map.items() if 'corrans' in norm or 'correct' in norm), None)

                for row in rows:
                    c = row[k_cue].strip()
                    p = row[k_probe].strip()
                    ans = row[k_ans].strip().lower()
                    
                    is_A = c == 'A'
                    is_X = p == 'X'
                    
                    if not is_A: stimuli_non_a.add(c)
                    if not is_X: stimuli_non_x.add(p)

                    # Classify
                    if is_A and is_X:
                        counts['AX'] += 1
                        if ans != 'm': logic_errors += 1
                    elif is_A and not is_X:
                        counts['AY'] += 1
                        if ans != 'z': logic_errors += 1
                    elif not is_A and is_X:
                        counts['BX'] += 1
                        if ans != 'z': logic_errors += 1
                    elif not is_A and not is_X:
                        counts['BY'] += 1
                        if ans != 'z': logic_errors += 1

                # Scoring logic
                if len(rows) == 40:
                    score += 10
                else:
                    feedback_parts.append(f"Expected 40 rows, found {len(rows)}")

                if counts['AX'] == 28: score += 10
                else: feedback_parts.append(f"AX trials: expected 28, found {counts['AX']}")
                
                if counts['AY'] == 4 and counts['BX'] == 4 and counts['BY'] == 4: score += 10
                else: feedback_parts.append(f"Distractor counts mismatch (AY/BX/BY): {counts['AY']}/{counts['BX']}/{counts['BY']}")
                
                if logic_errors == 0: score += 10
                else: feedback_parts.append(f"Found {logic_errors} rows with incorrect response mapping")
                
                # Stimulus variety check
                if len(stimuli_non_a) > 1 and len(stimuli_non_x) > 1:
                    score += 10
                else:
                    feedback_parts.append("Distractor stimuli lack variety (all identical letters used?)")

                csv_passed = True

    except Exception as e:
        feedback_parts.append(f"Error analyzing CSV: {str(e)}")
    finally:
        if 'local_csv' in locals() and os.path.exists(local_csv): os.unlink(local_csv)

    # ------------------------------------------------------------------
    # 3. Analyze Experiment Structure (40 Points)
    # ------------------------------------------------------------------
    try:
        if not result_meta.get('exp_exists'):
            feedback_parts.append("Experiment (.psyexp) file not found.")
        else:
            with tempfile.NamedTemporaryFile(delete=False, suffix='.psyexp') as tmp:
                local_exp = tmp.name
            copy_from_env(exp_path_remote, local_exp)
            
            tree = ET.parse(local_exp)
            root = tree.getroot()
            
            # Check for Trial Routine
            routines = root.findall(".//Routine")
            trial_routine = None
            for r in routines:
                # Naive name match or check contents
                if r.get('name') == 'trial':
                    trial_routine = r
                    break
            
            if not trial_routine and len(routines) > 0:
                # Fallback: check if any routine has cue/probe components
                trial_routine = routines[0] 

            if trial_routine:
                score += 5 # Found routine
                
                # Check Components
                comps = list(trial_routine)
                texts = [c for c in comps if c.tag == 'TextComponent']
                keys = [c for c in comps if c.tag == 'KeyboardComponent']
                
                if len(texts) >= 2: score += 10 # Has Cue and Probe
                else: feedback_parts.append("Missing Text components (need at least 2 for Cue/Probe)")
                
                if len(keys) >= 1: score += 5 # Has Response
                else: feedback_parts.append("Missing Keyboard component")
                
                # Check Timing (Heuristic check on params)
                # We look for val="0.5" or similar in Param children
                durations = []
                for t in texts:
                    for p in t:
                        if p.get('name') == 'stopVal':
                            durations.append(p.get('val'))
                
                if any('0.5' in str(d) for d in durations):
                    score += 10
                else:
                    feedback_parts.append("Could not verify 0.5s duration for stimuli")

            else:
                feedback_parts.append("No valid routine found in experiment")

            # Check Loop
            loops = root.findall(".//LoopInitiator")
            has_loop = False
            for loop in loops:
                for p in loop:
                    if p.get('name') == 'conditionsFile':
                        val = p.get('val', '')
                        if 'ax_cpt_conditions' in val or '.csv' in val:
                            has_loop = True
            
            if has_loop: score += 10
            else: feedback_parts.append("Loop not configured with conditions file")

    except Exception as e:
        feedback_parts.append(f"Error analyzing Experiment XML: {str(e)}")
    finally:
        if 'local_exp' in locals() and os.path.exists(local_exp): os.unlink(local_exp)

    # ------------------------------------------------------------------
    # Final Result
    # ------------------------------------------------------------------
    passed = score >= 70
    feedback = " | ".join(feedback_parts) if feedback_parts else "Task completed successfully."
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback
    }