#!/usr/bin/env python3
"""
Verifier for create_saved_case_filter task.

Verifies that:
1. The agent created the output file `urgent_cases.txt`.
2. The file contains the correct High Priority case numbers (Ground Truth).
3. The file does NOT contain Low Priority case numbers.
4. VLM verifies the "Saved Search" creation workflow.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_saved_case_filter(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. LOAD RESULT JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # 2. CHECK OUTPUT FILE EXISTENCE (15 pts)
    if not result.get('output_exists', False):
        return {"passed": False, "score": 0, "feedback": "Output file ~/urgent_cases.txt not found."}
    
    score += 15
    feedback.append("Output file created.")

    if result.get('file_created_during_task', False):
        score += 10
        feedback.append("File created during task window.")
    else:
        feedback.append("Warning: File timestamp indicates it might be stale.")

    # 3. VERIFY CONTENT (Accuracy & Precision) (45 pts)
    reported_raw = result.get('reported_content', "")
    gt_high_raw = result.get('ground_truth_high', "")
    gt_low_raw = result.get('ground_truth_low', "")

    # Normalize IDs (strip whitespace, split by comma or newline)
    def normalize_ids(raw_str):
        if not raw_str: return set()
        # Replace commas with spaces, then split
        tokens = raw_str.replace(',', ' ').split()
        return {t.strip() for t in tokens if t.strip()}

    reported_ids = normalize_ids(reported_raw)
    expected_ids = normalize_ids(gt_high_raw)
    forbidden_ids = normalize_ids(gt_low_raw)

    # Check for High Priority IDs (Accuracy)
    found_expected = reported_ids.intersection(expected_ids)
    missing_expected = expected_ids - reported_ids
    
    if len(expected_ids) > 0:
        accuracy_ratio = len(found_expected) / len(expected_ids)
        points_earned = int(30 * accuracy_ratio)
        score += points_earned
        if len(missing_expected) == 0:
            feedback.append(f"Correctly identified all {len(expected_ids)} High Priority cases.")
        else:
            feedback.append(f"Missed {len(missing_expected)} High Priority cases.")
    
    # Check for Low Priority IDs (Precision)
    found_forbidden = reported_ids.intersection(forbidden_ids)
    if len(found_forbidden) == 0:
        score += 15
        feedback.append("Correctly excluded all Low Priority cases.")
    else:
        feedback.append(f"Incorrectly included {len(found_forbidden)} Low Priority cases (Filter logic likely wrong).")
        # Heavy penalty for including wrong items in a filter task
        score -= 10 

    # 4. VLM VERIFICATION (30 pts)
    # Check if they actually created a "Saved Search" named "Urgent Safety Queue"
    frames = sample_trajectory_frames(traj, n=6)
    
    vlm_prompt = """
    Review this sequence of screenshots from an ArkCase task.
    The user was supposed to:
    1. Open the search/filter panel in the Complaints module.
    2. Set Priority to 'High'.
    3. Click 'Save Search' (often a floppy disk icon or 'Save' button).
    4. Name the search "Urgent Safety Queue".
    5. View the results.

    Answer in JSON:
    {
        "search_panel_opened": true/false,
        "priority_set_high": true/false,
        "save_dialog_visible": true/false,
        "search_named_correctly": true/false,
        "confidence": "high/medium/low"
    }
    """
    
    vlm_result = query_vlm(images=frames, prompt=vlm_prompt)
    
    vlm_score = 0
    if vlm_result and vlm_result.get('success'):
        parsed = vlm_result.get('parsed', {})
        if parsed.get('search_panel_opened'): vlm_score += 5
        if parsed.get('priority_set_high'): vlm_score += 10
        if parsed.get('save_dialog_visible'): vlm_score += 5
        if parsed.get('search_named_correctly'): vlm_score += 10
        
        score += vlm_score
        feedback.append(f"VLM verified workflow steps ({vlm_score}/30 pts).")
    else:
        feedback.append("VLM verification failed to process.")

    # Final logic
    # To pass, must have output file AND found all expected cases AND no forbidden cases
    passed = (len(missing_expected) == 0) and (len(found_forbidden) == 0) and (score >= 70)

    return {
        "passed": passed,
        "score": max(0, min(100, score)),
        "feedback": " ".join(feedback)
    }