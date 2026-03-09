#!/usr/bin/env python3
"""
Verifier for compile_status_report task.
Compares the agent's generated JSON report against the live system state (ground truth).
"""

import json
import os
import tempfile
import logging
import math

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_compile_status_report(traj, env_info, task_info):
    """
    Verifies the Emoncms status report task.
    
    Scoring Criteria:
    1. File Existence & Validity (15 pts): JSON file exists and parses correctly.
    2. Anti-Gaming (15 pts): File created/modified during task session.
    3. Structure (10 pts): Required top-level keys present.
    4. Accuracy (60 pts):
       - Count matches (15 pts)
       - All IDs present (20 pts)
       - Metadata (names/tags/units) matches (15 pts)
       - Values plausible (10 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Retrieve the result manifest
    manifest = {}
    with tempfile.NamedTemporaryFile(delete=True) as tf:
        try:
            copy_from_env("/tmp/task_result.json", tf.name)
            tf.seek(0)
            manifest = json.load(tf)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {str(e)}"}

    # 2. Check basic file criteria
    if not manifest.get("report_exists", False):
        return {"passed": False, "score": 0, "feedback": "Report file not found at expected location."}
    
    if not manifest.get("file_created_during_task", False):
        return {"passed": False, "score": 0, "feedback": "Report file timestamp indicates it was not created during this task session."}

    if not manifest.get("report_valid_json", False):
        return {"passed": False, "score": 15, "feedback": "Report file exists but contains invalid JSON."}

    score = 30  # Base score for valid file created during task
    feedback_parts = ["File exists and is valid JSON."]

    # 3. Retrieve Agent Report and Ground Truth
    agent_report = {}
    ground_truth = []
    
    with tempfile.NamedTemporaryFile(delete=True) as tf_report, \
         tempfile.NamedTemporaryFile(delete=True) as tf_truth:
        try:
            # Copy agent report
            copy_from_env(manifest["report_path"], tf_report.name)
            tf_report.seek(0)
            agent_report = json.load(tf_report)
            
            # Copy ground truth
            copy_from_env(manifest["ground_truth_path"], tf_truth.name)
            tf_truth.seek(0)
            ground_truth = json.load(tf_truth)
        except Exception as e:
            return {"passed": False, "score": score, "feedback": f"Error retrieving data files: {str(e)}"}

    # 4. Structure Verification (10 pts)
    required_keys = ["report_title", "total_feeds", "feeds"]
    if all(k in agent_report for k in required_keys):
        score += 10
        feedback_parts.append("JSON structure is correct.")
    else:
        missing = [k for k in required_keys if k not in agent_report]
        feedback_parts.append(f"Missing top-level keys: {missing}")
        # If structure is wrong, we might not be able to proceed with deep verification
        if "feeds" not in agent_report:
            return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    # 5. Accuracy Verification (60 pts)
    
    # Prepare data for comparison
    # Ground truth is a list of dicts from Emoncms API
    # Agent report should be a dict with a "feeds" list
    
    gt_feeds = {int(f['id']): f for f in ground_truth}
    gt_count = len(gt_feeds)
    
    agent_feeds_list = agent_report.get("feeds", [])
    if not isinstance(agent_feeds_list, list):
        feedback_parts.append("'feeds' is not a list.")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    # Helper to safe cast keys
    agent_feeds = {}
    for f in agent_feeds_list:
        fid = f.get('id')
        if fid is not None:
            try:
                agent_feeds[int(fid)] = f
            except ValueError:
                pass

    agent_count = agent_report.get("total_feeds")
    
    # A. Count Matches (15 pts)
    if agent_count == gt_count and len(agent_feeds) == gt_count:
        score += 15
        feedback_parts.append(f"Feed count correct ({gt_count}).")
    else:
        feedback_parts.append(f"Feed count mismatch (Expected: {gt_count}, Got: {agent_count}/{len(agent_feeds)}).")

    # B. All IDs Present (20 pts)
    gt_ids = set(gt_feeds.keys())
    agent_ids = set(agent_feeds.keys())
    
    missing_ids = gt_ids - agent_ids
    extra_ids = agent_ids - gt_ids
    
    if not missing_ids and not extra_ids:
        score += 20
        feedback_parts.append("All feed IDs present.")
    else:
        # Partial credit
        overlap = len(gt_ids.intersection(agent_ids))
        if len(gt_ids) > 0:
            partial = int(20 * (overlap / len(gt_ids)))
            score += partial
            feedback_parts.append(f"Feed IDs match partially ({overlap}/{len(gt_ids)}).")

    # C. Metadata Accuracy (15 pts)
    # Check Name, Tag, Unit for intersection
    meta_correct = 0
    total_checks = 0
    
    for fid in gt_ids.intersection(agent_ids):
        gt = gt_feeds[fid]
        ag = agent_feeds[fid]
        
        # Name
        if str(gt.get('name', '')).strip() == str(ag.get('name', '')).strip():
            meta_correct += 1
        total_checks += 1
        
        # Tag
        if str(gt.get('tag', '')).strip() == str(ag.get('tag', '')).strip():
            meta_correct += 1
        total_checks += 1
        
        # Unit (Note: API usually returns unit in 'unit' field, sometimes empty)
        # We'll be lenient on unit if source is empty
        gt_unit = str(gt.get('unit', '')).strip()
        ag_unit = str(ag.get('unit', '')).strip()
        if gt_unit == ag_unit:
            meta_correct += 1
        total_checks += 1

    if total_checks > 0:
        meta_score = int(15 * (meta_correct / total_checks))
        score += meta_score
        if meta_score == 15:
            feedback_parts.append("Metadata perfectly matches.")
        else:
            feedback_parts.append(f"Metadata matches {int((meta_correct/total_checks)*100)}%.")
    else:
        score += 15 # No feeds to check?

    # D. Values Plausible (10 pts)
    # Values change, so we check if they are "close" or identical if static
    # or just if they are non-null when they should be.
    value_matches = 0
    total_val_checks = 0
    
    for fid in gt_ids.intersection(agent_ids):
        gt_val = gt_feeds[fid].get('value')
        ag_val = agent_feeds[fid].get('value')
        total_val_checks += 1
        
        try:
            g_v = float(gt_val) if gt_val is not None else None
            a_v = float(ag_val) if ag_val is not None else None
            
            if g_v is None and a_v is None:
                value_matches += 1
            elif g_v is not None and a_v is not None:
                # Allow 10% drift or 0.1 absolute difference
                if abs(g_v - a_v) < 0.1 or abs(g_v - a_v) / (abs(g_v) + 0.0001) < 0.1:
                    value_matches += 1
        except (ValueError, TypeError):
            # If string values match exactly
            if str(gt_val) == str(ag_val):
                value_matches += 1

    if total_val_checks > 0:
        val_score = int(10 * (value_matches / total_val_checks))
        score += val_score
        feedback_parts.append(f"Value accuracy: {int((value_matches/total_val_checks)*100)}%.")

    # 6. Final Result
    # Pass threshold: 60 points + valid file
    passed = (score >= 60)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }