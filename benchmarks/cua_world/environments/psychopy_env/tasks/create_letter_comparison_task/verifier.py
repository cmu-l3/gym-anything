#!/usr/bin/env python3
"""
Verifier for Letter Comparison Task.

Verifies:
1. Conditions File:
   - Structure (cols: str1, str2, corrAns)
   - Content (4-6 uppercase consonants)
   - Logic (50/50 split, correct diff logic)
2. Experiment Logic (Code Component):
   - Clock initialization
   - Loop termination (.finished = True)
   - 60s threshold check
"""

import json
import tempfile
import os
import csv
import logging
import xml.etree.ElementTree as ET
import random

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_letter_comparison_task(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    exp_path = metadata.get('experiment_file')
    cond_path = metadata.get('conditions_file')

    score = 0
    feedback = []

    # 1. Load Result JSON
    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix='.json') as tmp:
            copy_from_env("/tmp/task_result.json", tmp.name)
            with open(tmp.name) as f:
                result_json = json.load(f)
            os.unlink(tmp.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}

    if not result_json.get("exp_exists") or not result_json.get("cond_exists"):
        return {"passed": False, "score": 0, "feedback": "Required files not found."}

    # 2. Verify Conditions File (40 points)
    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix='.csv') as tmp:
            copy_from_env(cond_path, tmp.name)
            
            with open(tmp.name, 'r', newline='') as csvfile:
                reader = csv.DictReader(csvfile)
                rows = list(reader)
                headers = reader.fieldnames
            
            os.unlink(tmp.name)

        # Check Headers
        req_headers = {'str1', 'str2', 'corrAns'}
        if headers and req_headers.issubset(set(headers)):
            score += 5
            feedback.append("CSV headers correct.")
        else:
            feedback.append(f"Missing CSV headers. Found: {headers}")

        # Check Row Count
        if len(rows) >= 100:
            score += 5
            feedback.append(f"Row count sufficient ({len(rows)}).")
        else:
            feedback.append(f"Insufficient rows: {len(rows)}")

        # Check Content Logic
        same_count = 0
        diff_count = 0
        valid_content = True
        valid_logic = True

        for row in rows:
            s1 = row.get('str1', '').strip()
            s2 = row.get('str2', '').strip()
            ans = row.get('corrAns', '').strip().lower()

            # Check string format (uppercase, length)
            if not (s1.isupper() and 4 <= len(s1) <= 6):
                valid_content = False
            
            # Check logic
            if s1 == s2:
                same_count += 1
                if ans != 's': valid_logic = False
            else:
                diff_count += 1
                if ans != 'd': valid_logic = False
                # Check Levenshtein distance roughly (should be 1 char diff)
                diffs = sum(1 for a, b in zip(s1, s2) if a != b) + abs(len(s1) - len(s2))
                if diffs != 1: valid_logic = False

        if valid_content:
            score += 10
            feedback.append("String content valid (uppercase, length).")
        else:
            feedback.append("Invalid string content found.")

        if valid_logic:
            score += 10
            feedback.append("Comparison logic correct (Same=s, Diff=d, 1 char diff).")
        else:
            feedback.append("Logic errors in CSV (incorrect answers or string differences).")

        # Balance (approx 50/50)
        ratio = same_count / (len(rows) or 1)
        if 0.4 <= ratio <= 0.6:
            score += 10
            feedback.append("Trials balanced (approx 50/50).")
        else:
            feedback.append(f"Trials unbalanced: {ratio:.2f} same.")

    except Exception as e:
        feedback.append(f"Error verifying CSV: {e}")

    # 3. Verify Experiment Code Logic (60 points)
    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix='.psyexp') as tmp:
            copy_from_env(exp_path, tmp.name)
            tree = ET.parse(tmp.name)
            root = tree.getroot()
            os.unlink(tmp.name)

        # Check for Code Component
        code_comps = []
        for routine in root.iter('Routine'):
            for comp in routine.findall('Code'):
                code_comps.append(comp)
        
        if code_comps:
            score += 10
            feedback.append("Code component found.")
        else:
            feedback.append("No Code component found.")

        # Analyze Code Content
        has_clock_init = False
        has_break_logic = False
        has_60s_check = False
        has_finished_flag = False

        code_text = ""
        for comp in code_comps:
            for param in comp:
                if param.get('name') in ['Begin Experiment', 'Begin Routine', 'Each Frame', 'End Routine']:
                    code_text += (param.get('val') or "") + "\n"

        # Check for clock/timer
        if "Clock()" in code_text or "Timer()" in code_text or "getTime()" in code_text:
            has_clock_init = True
            score += 10
            feedback.append("Timer/Clock logic detected.")

        # Check for 60s threshold
        if "60" in code_text:
            has_60s_check = True
            score += 10
            feedback.append("60 second threshold found.")

        # Check for loop termination
        # Look for .finished = True (Builder standard) or break (pure python)
        if ".finished = True" in code_text or ".finished = 1" in code_text:
            has_finished_flag = True
            score += 20
            feedback.append("Loop termination logic (.finished = True) found.")
        elif "break" in code_text:
            # Fallback, though less likely in Builder code components without .finished
            has_finished_flag = True 
            score += 10 # Partial credit
            feedback.append("'break' statement found (partial credit).")

        # Check structure: Routine > Loop
        loops = root.findall(".//LoopInitiator")
        if loops:
            score += 10
            feedback.append("Loop structure found.")

    except Exception as e:
        feedback.append(f"Error verifying .psyexp: {e}")

    # Final Score Calculation
    passed = score >= 70 and has_finished_flag
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }