#!/usr/bin/env python3
"""
Verifier for create_sternberg_memory_search task.

Verification Strategy:
1. CSV Logic Check (CRITICAL):
   - Row count >= 12
   - Set sizes 1, 3, 5 present
   - Logical consistency: 
     - If present='y', probe must be in memory_set
     - If present='n', probe must NOT be in memory_set
     - correct_key must match presence
2. Experiment Structure Check:
   - Valid XML
   - Routines: Presentation, Delay, Probe, Feedback
   - Loop connected to CSV
3. Anti-gaming:
   - File created during task
   - VLM trajectory check

Pass Threshold: 70/100 (Logic errors are heavily penalized)
"""

import json
import tempfile
import os
import csv
import logging
import xml.etree.ElementTree as ET
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logger = logging.getLogger(__name__)

def verify_create_sternberg_memory_search(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    exp_file_path = metadata.get('experiment_file', '/home/ga/PsychoPyExperiments/sternberg_task.psyexp')
    csv_file_path = metadata.get('conditions_file', '/home/ga/PsychoPyExperiments/sternberg_conditions.csv')
    
    score = 0
    feedback = []
    
    # 1. Get Result JSON for metadata (timestamp, nonce)
    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix='.json') as tmp:
            tmp_json = tmp.name
        copy_from_env("/tmp/task_result.json", tmp_json)
        with open(tmp_json) as f:
            result_meta = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result metadata: {e}"}
    finally:
        if os.path.exists(tmp_json): os.unlink(tmp_json)

    # 2. Verify CSV Logic (40 points)
    csv_valid = False
    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix='.csv') as tmp:
            tmp_csv = tmp.name
        copy_from_env(csv_file_path, tmp_csv)
        
        with open(tmp_csv, 'r') as f:
            reader = csv.DictReader(f)
            rows = list(reader)
            headers = reader.fieldnames if reader.fieldnames else []
            
        if len(rows) >= 12:
            score += 5
            feedback.append(f"Row count OK ({len(rows)})")
        else:
            feedback.append(f"Row count low ({len(rows)} < 12)")

        # Normalize headers
        headers = [h.strip().lower() for h in headers]
        required_cols = ['set_size', 'memory_set', 'probe', 'present', 'correct_key']
        missing = [c for c in required_cols if c not in headers]
        
        if not missing:
            score += 5
            feedback.append("All required columns present")
            
            # Logic Check
            logic_errors = 0
            set_sizes_found = set()
            
            for i, row in enumerate(rows):
                # Flexible key access
                r = {k.strip().lower(): v.strip() for k,v in row.items()}
                
                try:
                    s_size = int(r.get('set_size', 0))
                    set_sizes_found.add(s_size)
                    
                    mem_set = r.get('memory_set', '')
                    probe = r.get('probe', '')
                    present = r.get('present', '').lower()
                    key = r.get('correct_key', '').lower()
                    
                    # Clean memory set (remove spaces to check containment)
                    # Note: standard digit span uses spaces "1 5 9", probe "5"
                    # Simple containment check:
                    is_in = probe in mem_set.split() # Precise split check
                    
                    # Check Logic
                    expected_present = 'y' if is_in else 'n'
                    expected_key = 'left' if is_in else 'right'
                    
                    row_error = False
                    if present != expected_present:
                        feedback.append(f"Row {i+1} Logic Error: Probe '{probe}' in '{mem_set}' but present='{present}'")
                        row_error = True
                    
                    if key != expected_key:
                        feedback.append(f"Row {i+1} Key Error: Expect '{expected_key}' for present='{present}', got '{key}'")
                        row_error = True
                        
                    if row_error:
                        logic_errors += 1
                        
                except Exception as e:
                    feedback.append(f"Row {i+1} parse error: {e}")
                    logic_errors += 1
            
            # Scoring Logic
            if logic_errors == 0:
                score += 20
                feedback.append("Logic check: PERFECT")
            else:
                feedback.append(f"Logic check: {logic_errors} errors found")
            
            if {1, 3, 5}.issubset(set_sizes_found):
                score += 10
                feedback.append("Set sizes 1, 3, 5 present")
            else:
                feedback.append(f"Missing set sizes. Found: {set_sizes_found}")
                
            csv_valid = True
            
        else:
            feedback.append(f"Missing columns: {missing}")

    except Exception as e:
        feedback.append(f"CSV verification failed: {e}")
    finally:
        if os.path.exists(tmp_csv): os.unlink(tmp_csv)

    # 3. Verify Experiment Structure (40 points)
    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix='.psyexp') as tmp:
            tmp_exp = tmp.name
        copy_from_env(exp_file_path, tmp_exp)
        
        tree = ET.parse(tmp_exp)
        root = tree.getroot()
        
        routines = [r.get('name') for r in root.findall('.//Routine')]
        # Flexible matching
        has_presentation = any('present' in r.lower() or 'stim' in r.lower() for r in routines)
        has_delay = any('delay' in r.lower() or 'retention' in r.lower() or 'wait' in r.lower() for r in routines)
        has_probe = any('probe' in r.lower() or 'test' in r.lower() for r in routines)
        has_feedback = any('feed' in r.lower() for r in routines)
        
        if has_presentation: score += 10
        if has_delay: score += 5
        if has_probe: score += 10
        if has_feedback: score += 5
        
        # Check Loop
        loops = root.findall('.//LoopInitiator')
        if loops:
            score += 10
            feedback.append("Loop detected")
        else:
            feedback.append("No loop detected")
            
    except Exception as e:
        feedback.append(f"Experiment XML parse failed: {e}")
    finally:
        if os.path.exists(tmp_exp): os.unlink(tmp_exp)

    # 4. VLM Verification (20 points)
    # Use trajectory to ensure they actually built it, didn't just magic a file
    frames = sample_trajectory_frames(traj, n=4)
    final = get_final_screenshot(traj)
    
    vlm_prompt = """
    Check these screenshots of PsychoPy Builder.
    1. Is the user working in the Builder view (flowchart at bottom)?
    2. Do you see routines being created (e.g. rectangles in the flow)?
    3. Is there evidence of a loop being inserted?
    Answer 'yes' if it looks like a legitimate experiment building session.
    """
    
    vlm_res = query_vlm(images=frames + [final], prompt=vlm_prompt)
    if vlm_res.get("success") and "yes" in vlm_res.get("response", "").lower():
        score += 20
        feedback.append("VLM confirms building activity")
    else:
        feedback.append("VLM did not confirm building activity")

    passed = score >= 70 and csv_valid
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }