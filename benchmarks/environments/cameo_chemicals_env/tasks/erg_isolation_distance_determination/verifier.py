#!/usr/bin/env python3
"""
Verifier for ERG Isolation Distance Determination Task.

Checks if the agent correctly identified Protective Action Distances
for three chemicals under specific scenario conditions (Night, Large Spill, Low Wind).

Scoring:
- File existence & validity: 10 pts
- Chlorine (Table 3 logic): 30 pts
- Acrolein (Table 1 logic): 30 pts
- Chlorine Trifluoride (Table 1 logic): 30 pts
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_erg_distances(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load metadata expectations
    metadata = task_info.get('metadata', {})
    expected_chemicals = metadata.get('expected_chemicals', [])
    output_file_path = metadata.get('output_file', "/home/ga/Documents/evacuation_zones.txt")

    score = 0
    max_score = 100
    feedback_parts = []
    
    # 1. Get Result JSON (metadata about file)
    task_result = {}
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # 2. Check File Existence and Anti-Gaming
    if not task_result.get('output_exists', False):
        return {"passed": False, "score": 0, "feedback": "Output file evacuation_zones.txt not found."}

    if not task_result.get('file_created_during_task', False):
        return {"passed": False, "score": 0, "feedback": "Output file was not created/modified during the task window (anti-gaming)."}

    score += 10
    feedback_parts.append("File created successfully")

    # 3. Get Content of Output File
    temp_txt = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env(output_file_path, temp_txt.name)
        with open(temp_txt.name, 'r') as f:
            content = f.read().lower() # Normalizing to lowercase for easier matching
            lines = content.split('\n')
    except Exception as e:
        return {"passed": False, "score": score, "feedback": f"Failed to read output file content: {e}"}
    finally:
        if os.path.exists(temp_txt.name):
            os.unlink(temp_txt.name)

    # 4. Verify Chemical Values
    # We look for lines containing the chemical identifier and the correct distance value
    
    # Helper to check a line
    def check_chemical(chem_name, un_num, target_dist, dist_regex):
        found = False
        value_correct = False
        
        # Look for the chemical in the file
        for line in lines:
            if (chem_name.lower() in line) or (un_num in line):
                found = True
                # Check for the correct distance (e.g., "6.0", "6", "6.0 miles")
                # We use regex to be robust against "6.0" vs "6" vs "6 miles"
                if re.search(dist_regex, line):
                    value_correct = True
                break
        return found, value_correct

    # Check Chlorine (UN 1017)
    # Expected: 6.0 miles (Table 3, Rail, Night, Low Wind)
    # Distractors: 5.6 (High Wind), 7.0 (Mod Wind), 3.0 (Day)
    found, correct = check_chemical("chlorine", "1017", "6.0", r"6\.0|6(\s|$)")
    
    # Logic to ensure we don't accidentally match "Chlorine Trifluoride" when looking for "Chlorine"
    # The simple check above might flag "Chlorine Trifluoride" as "Chlorine".
    # Let's refine: We look specifically for lines that DO contain Chlorine but DO NOT contain Trifluoride
    chlorine_lines = [l for l in lines if "chlorine" in l and "trifluoride" not in l]
    chlorine_correct = False
    for line in chlorine_lines:
        if re.search(r"6\.0|6(\s|$)", line):
            chlorine_correct = True
            break
            
    if chlorine_correct:
        score += 30
        feedback_parts.append("Chlorine: Correct (6.0 mi)")
    else:
        # Check for specific errors to give feedback
        feedback_parts.append("Chlorine: Incorrect or missing (Expected 6.0 mi for Table 3/Rail/Low Wind)")

    # Check Acrolein (UN 1092)
    # Expected: 6.9 miles (Table 1, Large Spill, Night)
    found, correct = check_chemical("acrolein", "1092", "6.9", r"6\.9")
    if correct:
        score += 30
        feedback_parts.append("Acrolein: Correct (6.9 mi)")
    else:
        feedback_parts.append("Acrolein: Incorrect or missing (Expected 6.9 mi)")

    # Check Chlorine Trifluoride (UN 1749)
    # Expected: 2.3 miles (Table 1, Large Spill, Night)
    found, correct = check_chemical("trifluoride", "1749", "2.3", r"2\.3")
    if correct:
        score += 30
        feedback_parts.append("Chlorine Trifluoride: Correct (2.3 mi)")
    else:
        feedback_parts.append("Chlorine Trifluoride: Incorrect or missing (Expected 2.3 mi)")

    # 5. Finalize
    passed = (score >= 100) # Task requires high precision for safety context
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }