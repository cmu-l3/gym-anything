#!/usr/bin/env python3
"""
Verifier for extract_location_extremes task.
Checks that the agent filtered dives correctly, identified the deepest and longest
dives for the required location, and wrote them in the correct format.
"""

import json
import tempfile
import os
import re
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_time(val_str):
    """Parse MM:SS or MM.M string into float minutes."""
    if ':' in val_str:
        parts = val_str.split(':')
        return int(parts[0]) + int(parts[1])/60.0
    return float(val_str)

def verify_extract_location_extremes(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_path = metadata.get('expected_output_path', '/home/ga/Documents/sund_rock_records.txt')

    score = 0
    feedback_parts = []

    # 1. Fetch the export meta result
    tmp_res = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp_res.close()
    try:
        copy_from_env("/tmp/task_result.json", tmp_res.name)
        with open(tmp_res.name, 'r') as f:
            result_meta = json.load(f)
    except Exception as e:
        result_meta = {"output_exists": False, "file_created_during_task": False}
    finally:
        if os.path.exists(tmp_res.name): os.unlink(tmp_res.name)

    if not result_meta.get("output_exists"):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Output file '{expected_path}' was not found."
        }
    
    if not result_meta.get("file_created_during_task"):
        feedback_parts.append("Warning: File timestamp indicates it might not be new.")
    else:
        score += 10
        feedback_parts.append("File created successfully.")

    # 2. Fetch ground truth
    tmp_gt = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp_gt.close()
    try:
        copy_from_env("/tmp/sund_rock_gt.json", tmp_gt.name)
        with open(tmp_gt.name, 'r') as f:
            gt_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read ground truth: {e}"}
    finally:
        if os.path.exists(tmp_gt.name): os.unlink(tmp_gt.name)

    if 'error' in gt_data:
        return {"passed": False, "score": 0, "feedback": f"Ground truth generation error: {gt_data['error']}"}

    gt_deep_date = gt_data['deepest_date']
    gt_deep_val = float(gt_data['deepest_val'])
    gt_long_date = gt_data['longest_date']
    gt_long_val = float(gt_data['longest_val'])

    # 3. Fetch agent's text file
    tmp_txt = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    tmp_txt.close()
    try:
        copy_from_env(expected_path, tmp_txt.name)
        with open(tmp_txt.name, 'r') as f:
            text_content = f.read()
    except Exception as e:
        return {"passed": False, "score": score, "feedback": "Could not read output text file."}
    finally:
        if os.path.exists(tmp_txt.name): os.unlink(tmp_txt.name)

    # 4. Extract data using Regex
    deep_m = re.search(r'Deepest:\s*(\d{4}-\d{2}-\d{2})[^\d]+(\d+\.?\d*)', text_content, re.IGNORECASE)
    long_m = re.search(r'Longest:\s*(\d{4}-\d{2}-\d{2})[^\d]+(\d+(?:[:.]\d+)?)', text_content, re.IGNORECASE)

    if not deep_m and not long_m:
        return {
            "passed": False, 
            "score": score, 
            "feedback": "Format mismatch. Could not extract required formatted strings from file."
        }

    # Evaluate Deepest
    if deep_m:
        ag_deep_date = deep_m.group(1)
        ag_deep_val = float(deep_m.group(2))
        
        if ag_deep_date == gt_deep_date:
            score += 20
            feedback_parts.append("Deepest date correct.")
        else:
            feedback_parts.append(f"Deepest date mismatch (Expected {gt_deep_date}, Got {ag_deep_date}).")
            
        if abs(ag_deep_val - gt_deep_val) <= 0.5:
            score += 25
            feedback_parts.append("Deepest value correct.")
        else:
            feedback_parts.append(f"Deepest value mismatch (Expected ~{gt_deep_val}m, Got {ag_deep_val}m).")
    else:
        feedback_parts.append("Could not find properly formatted 'Deepest: YYYY-MM-DD, XX.X m' entry.")

    # Evaluate Longest
    if long_m:
        ag_long_date = long_m.group(1)
        ag_long_val = parse_time(long_m.group(2))
        
        if ag_long_date == gt_long_date:
            score += 20
            feedback_parts.append("Longest date correct.")
        else:
            feedback_parts.append(f"Longest date mismatch (Expected {gt_long_date}, Got {ag_long_date}).")
            
        if abs(ag_long_val - gt_long_val) <= 1.0:
            score += 25
            feedback_parts.append("Longest value correct.")
        else:
            feedback_parts.append(f"Longest value mismatch (Expected ~{gt_long_val}min, Got {ag_long_val}min).")
    else:
        feedback_parts.append("Could not find properly formatted 'Longest: YYYY-MM-DD, YY:ZZ min' entry.")

    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }