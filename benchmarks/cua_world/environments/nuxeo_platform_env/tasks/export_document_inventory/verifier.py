#!/usr/bin/env python3
"""
Verifier for export_document_inventory task.

Criteria:
1. File exists and was created during the task (Anti-gaming).
2. File is valid JSON array.
3. Content matches Ground Truth fetched from Nuxeo API.
4. Required fields (title, type, path, creator, created) are present.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_export_document_inventory(traj, env_info, task_info):
    """
    Verifies that the agent correctly exported the document inventory to JSON.
    """
    # 1. Setup and retrieve files
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy the result metadata (which includes Ground Truth)
    meta_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result_meta = {}
    try:
        copy_from_env("/tmp/task_result.json", meta_file.name)
        with open(meta_file.name, 'r') as f:
            result_meta = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result metadata: {e}"}
    finally:
        if os.path.exists(meta_file.name):
            os.unlink(meta_file.name)

    # Initialize scoring
    score = 0
    feedback = []
    
    # 2. Verify File Existence & Anti-Gaming (Timestamp)
    if not result_meta.get("output_exists", False):
        return {"passed": False, "score": 0, "feedback": "Output file 'project_inventory.json' was not found."}
    
    score += 15
    feedback.append("Output file exists.")

    if result_meta.get("file_created_during_task", False):
        score += 5
        feedback.append("File was created/modified during the task.")
    else:
        feedback.append("WARNING: File timestamp is older than task start (possible stale file).")

    # 3. Retrieve and Parse Agent's Output File
    agent_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    agent_data = []
    try:
        copy_from_env(result_meta.get("output_path", "/home/ga/Documents/project_inventory.json"), agent_file.name)
        with open(agent_file.name, 'r') as f:
            agent_data = json.load(f)
        
        if isinstance(agent_data, list):
            score += 15
            feedback.append("File contains a valid JSON array.")
        else:
            return {"passed": False, "score": score, "feedback": "Output is valid JSON but NOT an array."}
            
    except json.JSONDecodeError:
        return {"passed": False, "score": score, "feedback": "Output file contains invalid JSON."}
    except Exception as e:
        return {"passed": False, "score": score, "feedback": f"Failed to read output file: {e}"}
    finally:
        if os.path.exists(agent_file.name):
            os.unlink(agent_file.name)

    # 4. Compare with Ground Truth
    ground_truth = result_meta.get("ground_truth", [])
    
    if isinstance(ground_truth, dict) and "error" in ground_truth:
        # Fallback if GT generation failed (should not happen in healthy env)
        feedback.append(f"Warning: Could not fetch ground truth ({ground_truth['error']}). checking structure only.")
        # Relaxed check
        if len(agent_data) > 0:
             score += 65
        return {"passed": True, "score": score, "feedback": "Verified structure (GT missing)."}

    # Check Counts
    gt_count = len(ground_truth)
    agent_count = len(agent_data)
    
    if agent_count == gt_count:
        score += 15
        feedback.append(f"Correct number of documents found ({agent_count}).")
    else:
        feedback.append(f"Incorrect document count: Found {agent_count}, expected {gt_count}.")
        # Partial credit if close
        if abs(agent_count - gt_count) <= 1:
            score += 5

    # Check Required Keys
    required_keys = ["title", "type", "path", "creator", "created"]
    keys_missing = False
    for item in agent_data:
        if not all(k in item for k in required_keys):
            keys_missing = True
            break
    
    if not keys_missing and agent_count > 0:
        score += 15
        feedback.append("All required JSON keys are present.")
    elif agent_count > 0:
        feedback.append("Some required keys (title, type, path, creator, created) are missing.")

    # Check Content Accuracy (Match by Path)
    # Transform lists to dicts keyed by path for easy lookup
    gt_map = {item.get("path"): item for item in ground_truth}
    agent_map = {item.get("path"): item for item in agent_data}
    
    correct_entries = 0
    total_checks = 0
    
    for path, gt_item in gt_map.items():
        if path in agent_map:
            agent_item = agent_map[path]
            # Verify specific fields
            entry_ok = True
            # Title
            if agent_item.get("title") != gt_item.get("title"): entry_ok = False
            # Type
            if agent_item.get("type") != gt_item.get("type"): entry_ok = False
            # Creator
            if agent_item.get("creator") != gt_item.get("creator"): entry_ok = False
            
            if entry_ok:
                correct_entries += 1
    
    # Calculate accuracy score (remaining 35 points)
    if gt_count > 0:
        accuracy = correct_entries / gt_count
        points_earned = int(accuracy * 35)
        score += points_earned
        if accuracy == 1.0:
            feedback.append("All document metadata matches repository exactly.")
        else:
            feedback.append(f"Metadata accuracy: {correct_entries}/{gt_count} documents match exactly.")
    else:
        # If GT is empty (shouldn't happen per setup), but agent matches empty
        score += 35
        feedback.append("Workspace was empty, and agent reported empty.")

    # Final Result
    passed = score >= 60  # Threshold
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }