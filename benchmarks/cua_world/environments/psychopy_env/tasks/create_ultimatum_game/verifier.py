#!/usr/bin/env python3
"""
Verifier for create_ultimatum_game task.

Verification Strategy:
1. CSV Validation (20 pts): Exists, valid CSV, correct columns (offer, keep), correct sum (10).
2. Experiment Structure (30 pts): Valid XML, Loop exists, Links to correct CSV.
3. Component Logic (30 pts): Code component exists, contains 'earnings', 'if', 'feedback_msg'.
4. Stimulus/Feedback (20 pts): Text components use variables ($offer, $feedback_msg).
5. Anti-gaming: Files must be modified after task start.

Pass Threshold: 70 points.
"""

import json
import tempfile
import os
import logging
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_ultimatum_game(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result JSON from container
    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix='.json') as tmp:
            tmp_path = tmp.name
        copy_from_env("/tmp/create_ultimatum_game_result.json", tmp_path)
        with open(tmp_path, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(tmp_path):
            os.unlink(tmp_path)

    # ---------------------------------------------------------
    # NONCE CHECK (Anti-gaming)
    # ---------------------------------------------------------
    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix='.txt') as tmp:
            nonce_path = tmp.name
        copy_from_env("/home/ga/.task_nonce", nonce_path)
        with open(nonce_path, 'r') as f:
            expected_nonce = f.read().strip()
        
        result_nonce = result.get('result_nonce', '')
        if expected_nonce and result_nonce != expected_nonce:
             return {"passed": False, "score": 0, "feedback": "FAIL: Result nonce mismatch (anti-gaming check)."}
    except:
        pass # Ignore if nonce file missing in env (fallback)

    score = 0
    feedback = []

    # ---------------------------------------------------------
    # 1. CSV VALIDATION (20 pts)
    # ---------------------------------------------------------
    csv_score = 0
    if result.get("csv_exists") and result.get("csv_modified"):
        csv_score += 5
        cols = result.get("csv_columns", [])
        rows = result.get("csv_rows", [])
        
        # Check columns
        if "offer" in cols and "keep" in cols:
            csv_score += 5
        else:
            feedback.append("CSV missing required columns 'offer' or 'keep'")

        # Check rows (Sum to 10)
        valid_rows = 0
        for row in rows:
            try:
                offer = int(row.get('offer', 0))
                keep = int(row.get('keep', 0))
                if offer + keep == 10:
                    valid_rows += 1
            except:
                pass
        
        if len(rows) >= 5 and valid_rows >= 5:
            csv_score += 10
        elif valid_rows > 0:
            csv_score += 5
            feedback.append(f"CSV has {valid_rows} valid rows (expected 5)")
        else:
            feedback.append("CSV rows do not sum to 10 or are invalid")
    else:
        feedback.append("CSV file not found or not created during task")

    score += csv_score
    feedback.append(f"CSV Score: {csv_score}/20")

    # ---------------------------------------------------------
    # 2. EXPERIMENT STRUCTURE (30 pts)
    # ---------------------------------------------------------
    struct_score = 0
    if result.get("exp_exists") and result.get("exp_modified") and result.get("xml_valid"):
        struct_score += 10
        
        if result.get("has_loop"):
            struct_score += 10
            linked_csv = result.get("linked_csv", "")
            if "ug_conditions.csv" in linked_csv:
                struct_score += 10
            else:
                feedback.append(f"Loop linked to wrong file: {linked_csv}")
        else:
            feedback.append("Experiment missing Loop")
    else:
        feedback.append("Experiment file missing or invalid")

    score += struct_score
    feedback.append(f"Structure Score: {struct_score}/30")

    # ---------------------------------------------------------
    # 3. COMPONENT LOGIC (30 pts)
    # ---------------------------------------------------------
    logic_score = 0
    if result.get("has_code_component"):
        logic_score += 10
        content = result.get("code_content", "").lower()
        
        # Check for key elements in the code
        keywords_met = 0
        if "earnings" in content: keywords_met += 1
        if "feedback_msg" in content or "msg" in content: keywords_met += 1
        if "if" in content: keywords_met += 1
        
        if keywords_met >= 3:
            logic_score += 20
        elif keywords_met >= 1:
            logic_score += 10
            feedback.append("Code component missing some logic elements (earnings, feedback_msg, if)")
        else:
            feedback.append("Code component empty or missing logic")
    else:
        feedback.append("No Code Component found")

    score += logic_score
    feedback.append(f"Logic Score: {logic_score}/30")

    # ---------------------------------------------------------
    # 4. STIMULUS / FEEDBACK (20 pts)
    # ---------------------------------------------------------
    stim_score = 0
    text_content = result.get("text_stim_content", "")
    
    # Check for variables in text ($offer or $keep)
    if "$offer" in text_content or "$keep" in text_content:
        stim_score += 10
    
    # Check for feedback routine
    if result.get("has_feedback_routine"):
        stim_score += 5
        # Loose check for feedback variable usage in text content
        if "$feedback_msg" in text_content or "$msg" in text_content:
            stim_score += 5
    
    score += stim_score
    feedback.append(f"Stimulus Score: {stim_score}/20")

    # Final tally
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }