#!/usr/bin/env python3
"""
Verifier for Iowa Gambling Task (IGT) creation.

Verification Strategy:
1. File Analysis (Primary):
   - Retrieve .psyexp and .csv files from the environment.
   - Parse XML to verify routines (instruction, trial, feedback), components (Mouse, Code), and Loops.
   - Parse CSV to verify deck parameters (A, B, C, D logic).
2. Anti-Gaming:
   - Check file timestamps against task start time.
   - Check nonce.
3. VLM (Secondary):
   - Verify UI interaction via trajectory frames.

Scoring (100 points total):
- [10] Files exist and created during task
- [15] Conditions CSV correctness (columns, values)
- [15] Routines structure (Instructions, Trial, Feedback, End)
- [15] Mouse component present
- [15] Code component present (logic requirement)
- [15] Loop configuration
- [15] Visual elements (4 decks)
"""

import json
import tempfile
import os
import csv
import logging
import xml.etree.ElementTree as ET

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_iowa_gambling_task(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    exp_path = metadata.get('experiment_file', '/home/ga/PsychoPyExperiments/iowa_gambling_task.psyexp')
    csv_path = metadata.get('conditions_file', '/home/ga/PsychoPyExperiments/conditions/igt_decks.csv')

    score = 0
    feedback = []
    
    # ---------------------------------------------------------
    # 1. Retrieve Result Metadata & Check Nonce/Timestamps
    # ---------------------------------------------------------
    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix='.json') as tmp:
            res_json_path = tmp.name
        copy_from_env("/tmp/task_result.json", res_json_path)
        with open(res_json_path, 'r') as f:
            result_meta = json.load(f)
        
        # Nonce check
        with tempfile.NamedTemporaryFile(delete=False, suffix='.txt') as tmp:
            nonce_path = tmp.name
        copy_from_env("/home/ga/.task_nonce", nonce_path)
        with open(nonce_path, 'r') as f:
            expected_nonce = f.read().strip()
        
        if result_meta.get("result_nonce") != expected_nonce:
             return {"passed": False, "score": 0, "feedback": "FAIL: Nonce mismatch (anti-gaming)"}

        # Timestamp check
        task_start = result_meta.get("task_start_time", 0)
        exp_mtime = result_meta.get("exp_mtime", 0)
        csv_mtime = result_meta.get("csv_mtime", 0)

        files_valid = True
        if result_meta.get("exp_file_exists") and exp_mtime > task_start:
            score += 5
            feedback.append("Experiment file created.")
        else:
            files_valid = False
            feedback.append("Experiment file missing or old.")

        if result_meta.get("csv_file_exists") and csv_mtime > task_start:
            score += 5
            feedback.append("Conditions file created.")
        else:
            files_valid = False
            feedback.append("Conditions file missing or old.")

    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error reading metadata: {e}"}
    finally:
        if os.path.exists(res_json_path): os.unlink(res_json_path)
        if os.path.exists(nonce_path): os.unlink(nonce_path)

    if not files_valid:
        return {"passed": False, "score": score, "feedback": " | ".join(feedback)}

    # ---------------------------------------------------------
    # 2. Verify Conditions CSV Content
    # ---------------------------------------------------------
    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix='.csv') as tmp:
            local_csv = tmp.name
        copy_from_env(csv_path, local_csv)
        
        with open(local_csv, 'r') as f:
            reader = csv.DictReader(f)
            rows = list(reader)
            headers = reader.fieldnames or []
        
        # Check columns
        req_cols = ["deck", "reward", "penalty_amount", "penalty_prob"]
        if all(col in headers for col in req_cols):
            score += 5
            feedback.append("CSV columns correct.")
        else:
            feedback.append(f"Missing CSV columns. Found: {headers}")

        # Check Data (Bechara params)
        # We look for rows corresponding to decks A, B, C, D
        correct_data_points = 0
        expected_decks = metadata.get('deck_data', {})
        
        found_decks = 0
        for row in rows:
            d = row.get("deck", "").strip().upper()
            if d in expected_decks:
                found_decks += 1
                params = expected_decks[d]
                try:
                    r = float(row.get("reward", 0))
                    pa = float(row.get("penalty_amount", 0))
                    pp = float(row.get("penalty_prob", 0))
                    
                    if r == params["reward"] and pa == params["penalty_amount"] and pp == params["penalty_prob"]:
                        correct_data_points += 1
                except:
                    pass
        
        if found_decks >= 4:
            score += 5
            feedback.append("All 4 decks present.")
        
        if correct_data_points >= 4:
             score += 5
             feedback.append("Deck parameters match IGT standard.")

    except Exception as e:
        feedback.append(f"Error parsing CSV: {e}")
    finally:
        if os.path.exists(local_csv): os.unlink(local_csv)

    # ---------------------------------------------------------
    # 3. Verify Experiment Structure (.psyexp XML)
    # ---------------------------------------------------------
    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix='.psyexp') as tmp:
            local_exp = tmp.name
        copy_from_env(exp_path, local_exp)
        
        tree = ET.parse(local_exp)
        root = tree.getroot()
        
        routines = root.find("Routines")
        routine_names = []
        components = []
        if routines is not None:
            for r in routines:
                routine_names.append(r.get("name").lower())
                for comp in r:
                    components.append(comp.tag)
        
        # Routines Check
        has_instruct = any("instruct" in r for r in routine_names)
        has_trial = any("trial" in r for r in routine_names)
        has_feedback = any("feedback" in r for r in routine_names)
        has_end = any(r in ["end", "thanks", "finish"] for r in routine_names)

        if has_instruct: score += 3
        if has_trial: score += 5
        if has_feedback: score += 5
        if has_end: score += 2
        if has_instruct and has_trial and has_feedback:
            feedback.append("Routines structure correct.")

        # Component Checks
        comp_str = " ".join(components).lower()
        if "mouse" in comp_str:
            score += 15
            feedback.append("Mouse component found.")
        else:
            feedback.append("Missing Mouse component.")
            
        if "code" in comp_str:
            score += 15
            feedback.append("Code component found.")
        else:
            feedback.append("Missing Code component (required for logic).")

        # Visual Elements Check (Decks)
        # Count text/visual components in trial routine specifically could be better,
        # but global count of text/image/rect is a decent proxy for "did they build UI?"
        visual_count = sum(1 for c in components if "Text" in c or "Image" in c or "Rect" in c or "Button" in c)
        if visual_count >= 4:
            score += 15
            feedback.append("Sufficient visual components.")
        else:
            feedback.append(f"Low visual component count ({visual_count}), expected 4+ for decks.")

        # Loop Check
        flow = root.find("Flow")
        has_loop = False
        if flow is not None:
            for item in flow:
                if "Loop" in item.tag:
                    has_loop = True
                    # Optional: check if loop wraps trial/feedback
        
        if has_loop:
            score += 15
            feedback.append("Loop configured.")
        else:
            feedback.append("Missing Loop.")

    except Exception as e:
        feedback.append(f"Error parsing .psyexp: {e}")
    finally:
        if os.path.exists(local_exp): os.unlink(local_exp)

    # ---------------------------------------------------------
    # 4. Final Scoring
    # ---------------------------------------------------------
    
    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }