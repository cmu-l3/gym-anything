#!/usr/bin/env python3
"""
Verifier for USDA Nutritional Analysis Task.
Checks:
1. Report file existence and creation time.
2. Content of report for correct nutrient values (Chicken Protein, Sweet Potato Carbs, Broccoli Vit C).
3. Existence of downloaded data file.
4. Browser history evidence of USDA site usage.
"""

import json
import os
import re
import tempfile
import logging

# Set up logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_usda_nutritional_analysis(traj, env_info, task_info):
    # 1. Setup and copy result from env
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Infrastructure error: copy_from_env not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result file: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Extract Data
    task_start = result.get('task_start_time', 0)
    report_exists = result.get('report_exists', False)
    report_content = result.get('report_content', "")
    report_mtime = result.get('report_mtime', 0)
    download_found = result.get('download_found', False)
    usda_visited = result.get('usda_visited', False)

    # 3. Define Expected Ranges from Metadata
    ranges = task_info.get('metadata', {}).get('ranges', {})
    chicken_range = ranges.get('chicken_protein_g', {'min': 20.0, 'max': 25.0})
    potato_range = ranges.get('sweet_potato_carbs_g', {'min': 18.0, 'max': 22.0})
    broccoli_range = ranges.get('broccoli_vit_c_mg', {'min': 80.0, 'max': 100.0})

    score = 0
    feedback = []

    # 4. Scoring Logic

    # Criterion A: Report Exists & Created during task (10 pts)
    if report_exists and report_mtime > task_start:
        score += 10
        feedback.append("Report created successfully.")
    elif report_exists:
        # File exists but timestamp is suspicious (unlikely with cleanup, but safe to handle)
        score += 5
        feedback.append("Report exists but timestamp is old (pre-task?).")
    else:
        feedback.append("Report file not found.")

    # Criterion B: Data Accuracy (60 pts total, 20 per item)
    # We use regex to find numbers associated with keywords in the report text
    
    # Helper to find value near keyword
    def check_value(text, keyword, val_range, unit_name):
        # Look for the keyword, then look for a floating point number nearby
        # Simple heuristic: Split text into lines, find line with keyword, extract numbers
        for line in text.split('\n'):
            if keyword.lower() in line.lower():
                # Extract all numbers
                numbers = re.findall(r"[-+]?\d*\.\d+|\d+", line)
                for num_str in numbers:
                    try:
                        val = float(num_str)
                        if val_range['min'] <= val <= val_range['max']:
                            return True, val
                    except ValueError:
                        continue
        return False, None

    # Check Chicken Protein
    c_ok, c_val = check_value(report_content, "Chicken", chicken_range, "Protein")
    if c_ok:
        score += 20
        feedback.append(f"Chicken Protein correct ({c_val}g).")
    else:
        # Try stricter search if line-based failed (e.g. if format is weird)
        # But for now, just give feedback
        feedback.append("Chicken Protein value missing or out of range (20-25g).")

    # Check Sweet Potato Carbs
    p_ok, p_val = check_value(report_content, "Potato", potato_range, "Carbs")
    if p_ok:
        score += 20
        feedback.append(f"Sweet Potato Carbs correct ({p_val}g).")
    else:
        feedback.append("Sweet Potato Carbs value missing or out of range (18-22g).")

    # Check Broccoli Vitamin C
    b_ok, b_val = check_value(report_content, "Broccoli", broccoli_range, "Vitamin C")
    if b_ok:
        score += 20
        feedback.append(f"Broccoli Vitamin C correct ({b_val}mg).")
    else:
        feedback.append("Broccoli Vitamin C value missing or out of range (80-100mg).")

    # Criterion C: Download Found (15 pts)
    if download_found:
        score += 15
        feedback.append("Data file download confirmed.")
    else:
        feedback.append("No downloaded data file found in ~/Downloads.")

    # Criterion D: USDA Visited (15 pts)
    if usda_visited:
        score += 15
        feedback.append("USDA website visit confirmed.")
    else:
        feedback.append("No history of visiting USDA website.")

    # Final Pass/Fail
    passed = (score >= 70)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }