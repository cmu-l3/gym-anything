#!/usr/bin/env python3
"""Verifier for sync_req_status_with_tests task.

Checks that the agent correctly updated SRS requirement statuses based on linked Test Cases.
Logic:
- Any Linked Test Rejected -> SRS Rejected
- All Linked Tests Approved -> SRS Approved
- Else -> SRS Draft
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_sync_status(traj, env_info, task_info):
    """Verify that SRS statuses match the ground truth logic."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    # 1. Retrieve files from the environment
    # We need: task_result.json, srs_result.json, ground_truth.json
    
    files_to_fetch = {
        "result": "/tmp/task_result.json",
        "srs": "/tmp/srs_result.json",
        "truth": "/tmp/ground_truth.json"
    }
    
    data = {}
    temp_files = []
    
    try:
        for key, path in files_to_fetch.items():
            tf = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
            temp_files.append(tf.name)
            try:
                copy_from_env(path, tf.name)
                with open(tf.name, 'r') as f:
                    data[key] = json.load(f)
            except Exception as e:
                logger.warning(f"Could not load {key}: {e}")
                data[key] = None
    finally:
        for tf_name in temp_files:
            if os.path.exists(tf_name):
                os.unlink(tf_name)

    # 2. Check if files were loaded
    if not data.get("result") or not data.get("srs") or not data.get("truth"):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Failed to retrieve verification data from environment."
        }

    task_res = data["result"]
    srs_json = data["srs"]
    ground_truth = data["truth"] # Map: ID -> Expected Status

    score = 0
    feedback_parts = []
    
    # 3. Anti-Gaming: Check if file was modified
    if task_res.get("file_modified", False):
        score += 10
        feedback_parts.append("Project saved (+10)")
    else:
        feedback_parts.append("Project NOT saved (no timestamp change)")
        # We continue checking, but max score will be limited if not saved
    
    # 4. Logic Verification
    # Parse SRS to get actual statuses
    actual_statuses = {}
    
    def extract_statuses(items):
        for item in items:
            if 'id' in item:
                actual_statuses[item['id']] = item.get('status', 'Draft')
            if 'children' in item:
                extract_statuses(item['children'])
    
    extract_statuses(srs_json.get('data', []))
    
    total_items = 0
    correct_items = 0
    
    # Categories for detailed feedback
    cat_stats = {
        "Approved": {"total": 0, "correct": 0},
        "Rejected": {"total": 0, "correct": 0},
        "Draft": {"total": 0, "correct": 0}
    }
    
    for req_id, expected in ground_truth.items():
        # Only verify items that exist in the SRS
        if req_id not in actual_statuses:
            continue
            
        actual = actual_statuses[req_id]
        total_items += 1
        
        # Track stats
        if expected not in cat_stats:
            cat_stats[expected] = {"total": 0, "correct": 0} # Safety
        cat_stats[expected]["total"] += 1
        
        if actual == expected:
            correct_items += 1
            cat_stats[expected]["correct"] += 1
    
    # Calculate Score
    # Logic is worth 90 points (10 points already for saving)
    if total_items > 0:
        logic_score = (correct_items / total_items) * 90
        score += logic_score
    else:
        feedback_parts.append("No requirements found to verify")
    
    # Generate detailed feedback
    feedback_parts.append(f"Accuracy: {correct_items}/{total_items} ({int(logic_score) if total_items else 0}/90 pts)")
    
    for status, stats in cat_stats.items():
        if stats["total"] > 0:
            feedback_parts.append(f"{status}: {stats['correct']}/{stats['total']}")

    # Pass criteria: Score >= 80 AND Logic Accuracy >= 80% AND File Modified
    accuracy = (correct_items / total_items) if total_items > 0 else 0
    passed = (score >= 80) and (accuracy >= 0.8) and task_res.get("file_modified", False)
    
    return {
        "passed": passed,
        "score": int(score),
        "feedback": " | ".join(feedback_parts),
        "details": {
            "accuracy": accuracy,
            "category_stats": cat_stats
        }
    }